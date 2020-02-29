"""
    Commits

Module for performing the commit data collection.
"""
module Commits
using ..BaseUtils: Opt, graphql, gh_errors, handle_errors
using Dates: now, Year, Second
using HTTP: request
using JSON3: JSON3, Object
using LibPQ: Connection, Statement, execute, prepare, Intervals.Interval, load!, status
using LibPQ.TimeZones: ZonedDateTime, TimeZone
using Parameters: @unpack
using Tables: rowtable
"""
    parse_repo(node::Object,
               slug::AbstractString,
               as_of::ZonedDateTime)

Return iterator for insertion into database.
"""
function parse_repo(node::Object, slug::AbstractString, as_of::ZonedDateTime)
    # node = json.data.repository.defaultBranchRef.target.history.nodes[1]
    @unpack author, oid, committedDate, additions, deletions = node
    (
        slug = slug,
        hash = oid,
        committed_date = committedDate,
        login = isnothing(author.user) ? missing : author.user.login,
        additions = additions,
        deletions = deletions,
        as_of = as_of,
    )
end
"""
    commits(opt::Opt,
            slug::AbstractString,
            since::ZonedDateTime = ZonedDateTime("1970-01-01T00:00:00.000+00:00"),
            until::ZonedDateTime = floor(now(TimeZone("UTC")), Year),
            bulk_size::Integer = 16)

Uploads the repository queries.

# Example

```julia-repl
julia> data = rowtable(execute(opt.conn, "SELECT slug FROM \$(opt.schema).repos ORDER BY slug ASC LIMIT 1;"));

julia> foreach(row -> commits(opt, row...), data)

julia> execute(opt.conn,
               "SELECT COUNT(*) FROM \$(opt.schema).repos WHERE status = 'Done';") |>
       rowtable |>
       (obj -> isone(obj[1].count))
true
```
"""
function commits(
    opt::Opt,
    slug::AbstractString,
    since::ZonedDateTime = ZonedDateTime("1970-01-01T00:00:00.000+00:00"),
    until::ZonedDateTime = floor(now(TimeZone("UTC")), Year),
    bulk_size::Integer = 32,
)
    @unpack conn, pat, schema = opt
    # bulk_size = 100
    owner, name = split(slug, '/')
    # since = ZonedDateTime("1970-01-01T00:00:00.000+00:00")
    # until = floor(now(TimeZone("UTC")), Year)
    vars = Dict(
        "owner" => owner,
        "name" => name,
        "since" => since,
        "until" => until,
        "first" => bulk_size,
    )
    data =
        execute(
            conn,
            """SELECT hash, committed_date FROM $(opt.schema).commits
               WHERE slug = '$slug'
               ORDER BY committed_date ASC
               LIMIT 1
               ;
            """,
            not_null = true,
        ) |> rowtable
    if !isempty(data)
        data = data[1]
        result = graphql(
            pat,
            "Commits",
            merge(
                vars,
                Dict("since" => data.committed_date, "until" => data.committed_date),
            ),
        )
        json = gh_errors(result, pat, "Commits", vars)
        handle_errors(opt, json) && return
        if any(
            x.oid == data.hash
            for x in json.data.repository.defaultBranchRef.target.history.nodes
        )
            vars["until"] =
                first(
                    node.committedDate
                    for node ∈ json.data.repository.defaultBranchRef.target.history.nodes if node.oid == data.hash
                ) |> (
                    obj -> ZonedDateTime(
                        replace(obj, r"(?<=\d)Z$" => "UTC"),
                        "yyyy-mm-ddTHH:MM:SSZZZ",
                    )
                )
        end
    end
    result = graphql(pat, "Commits", vars)
    println("$(opt.login): $slug $(now()) $(pat.limits.remaining)")
    json = gh_errors(result, pat, "Commits", vars)
    handle_errors(opt, json) && return
    as_of = ZonedDateTime(
        first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date"),
        "e, dd u Y HH:MM:SS ZZZ",
    )
    execute(conn, "BEGIN;")
    load!(
        (
            parse_repo(node, slug, as_of)
            for node in json.data.repository.defaultBranchRef.target.history.nodes
        ),
        conn,
        "INSERT INTO $schema.commits VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7) ON CONFLICT DO NOTHING;",
    )
    execute(conn, "COMMIT;")
    while !isnothing(json.data.repository.defaultBranchRef.target.history.pageInfo.endCursor)
        vars = Dict(
            "owner" => owner,
            "name" => name,
            "since" => since,
            "until" => until,
            "cursor" =>
                    json.data.repository.defaultBranchRef.target.history.pageInfo.endCursor,
            "first" => bulk_size,
        )
        result = graphql(pat, "CommitsContinue", vars)
        println("$(opt.login): $slug $(now())")
        json = gh_errors(result, pat, "CommitsContinue", vars)
        handle_errors(opt, json) && return
        if isnothing(json)
            execute(
                conn,
                """UPDATE $schema.repos
                   SET status = 'NOT_FOUND'
                   WHERE slug = '$slug'
                   ;
                """,
            )
            return
        end
        as_of = ZonedDateTime(
            first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date"),
            "e, dd u Y HH:MM:SS ZZZ",
        )
        execute(conn, "BEGIN;")
        load!(
            (
                parse_repo(node, slug, as_of)
                for node in json.data.repository.defaultBranchRef.target.history.nodes
            ),
            conn,
            "INSERT INTO $schema.commits VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7) ON CONFLICT DO NOTHING;",
        )
        execute(conn, "COMMIT;")
    end
    result = graphql(
        pat,
        "CommitsVerify",
        Dict("owner" => owner, "name" => name, "since" => since, "until" => until),
    )
    json = gh_errors(result, pat, "CommitsVerify", vars)
    handle_errors(opt, json) && return
    total = json.data.repository.defaultBranchRef.target.history.totalCount
    collected = getproperty.(execute(
        conn,
        """SELECT COUNT(*) FROM $schema.commits
           WHERE slug = '$slug'
           ;
        """,
    ), :count)[1]
    execute(
        conn,
        """UPDATE $schema.repos
           SET status = '$(collected ≥ total ? "Done" : "Error")'
           WHERE slug = '$slug'
           ;
        """,
    )
end
end
