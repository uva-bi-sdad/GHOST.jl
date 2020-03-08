"""
    Repos

Module for performing the repository data collection.
"""
module Repos
using ..BaseUtils: Opt, graphql
using Dates: DateTime, now, Year, Second, CompoundPeriod
using TimeZones: ZonedDateTime
using HTTP: request
using JSON3: JSON3, Object
using LibPQ: Connection, Statement, execute, prepare, Intervals.Interval, load!
using Parameters: @unpack
"""
    parse_repo(node::Object,
               spdx::AbstractString,
               created_query::Interval,
               as_of::DateTime)

Return iterator for insertion into database.
"""
function parse_repo(
    node::Object,
    spdx::AbstractString,
    created_query::Interval{ZonedDateTime},
    as_of::ZonedDateTime,
)
    @unpack nameWithOwner, createdAt = node
    (
        slug = nameWithOwner,
        spdx = spdx,
        created = createdAt,
        as_of = as_of,
        created_query = "[$(created_query.first), $(created_query.last))",
        status = "Initiated",
    )
end
"""
    repos(opt::Opt,
          spdx::AbstractString,
          created_query::Interval{DateTime})

Uploads the repository queries.

# Example

```julia-repl
julia> data = execute(opt.conn,
                      "SELECT spdx, created_query FROM \$(opt.schema).spdx_queries ORDER BY spdx ASC, created_query ASC;") |>
              rowtable;

julia> foreach(row -> repos(opt, row...), data)

julia> execute(opt.conn,
               "SELECT COUNT(*) FROM \$(opt.schema).spdx_queries WHERE status != 'Done';") |>
       rowtable |>
       (obj -> iszero(obj[1].count))
true
```
"""
function repos(opt::Opt, spdx::AbstractString, created_query::Interval{ZonedDateTime})
    @unpack conn, pat, schema = opt
    @assert created_query.inclusivity.first && !created_query.inclusivity.last
    result = graphql(
        pat,
        "Repo",
        Dict("license_created" => """is:public fork:false mirror:false archived:false
                                     license:$spdx
                                     created:$(created_query.first)..$(created_query.last)
                                  """),
    )
    json = JSON3.read(result.Data)
    as_of = DateTime(
        first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date")[1:end-4],
        "e, dd u Y HH:MM:SS",
    )
    execute(conn, "BEGIN;")
    load!(
        (parse_repo(node, spdx, created_query, as_of) for node in json.data.search.nodes),
        conn,
        "INSERT INTO $schema.repos VALUES (\$1, \$2, \$3, \$4, \$5, \$6) ON CONFLICT DO NOTHING;",
    )
    execute(conn, "COMMIT;")
    while !isnothing(json.data.search.pageInfo.endCursor)
        result = graphql(
            pat,
            "RepoContinue",
            Dict(
                "license_created" =>
                        """is:public fork:false mirror:false archived:false
                           license:$spdx
                           created:$(created_query.first)..$(created_query.last)
                        """,
                "cursor" => json.data.search.pageInfo.endCursor,
            ),
        )
        json = JSON3.read(result.Data)
        as_of = DateTime(
            first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date")[1:end-4],
            "e, dd u Y HH:MM:SS",
        )
        execute(conn, "BEGIN;")
        load!(
            (
                parse_repo(node, spdx, created_query, as_of)
                for node in json.data.search.nodes
            ),
            conn,
            "INSERT INTO $schema.repos VALUES (\$1, \$2, \$3, \$4, \$5, \$6) ON CONFLICT DO NOTHING;",
        )
        execute(conn, "COMMIT;")
    end
    result = graphql(
        pat,
        "RepoVerify",
        Dict("license_created" => """is:public fork:false mirror:false archived:false
                                     license:$spdx
                                     created:$(created_query.first)..$(created_query.last)
                                  """),
    )
    json = JSON3.read(result.Data)
    total = json.data.search.repositoryCount
    collected = getproperty.(
        execute(
            conn,
            """SELECT COUNT(*) FROM $schema.repos
               WHERE spdx = '$spdx'
               AND created_query = '[$(created_query.first), $(created_query.last))'
            """,
        ),
        :count,
    )[1]
    if collected ≥ total
        execute(
            conn,
            """UPDATE $schema.spdx_queries
               SET status = 'Done'
               WHERE spdx = '$spdx'
               AND created_query = '[$(created_query.first), $(created_query.last))'
            """,
        )
    else
        execute(
            conn,
            """UPDATE $schema.spdx_queries
               SET status = 'In Progress'
               WHERE spdx = '$spdx'
               AND created_query = '[$(created_query.first), $(created_query.last))'
            """,
        )
    end
end
end
