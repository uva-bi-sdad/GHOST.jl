"""
    Commits

Module for performing the commit data collection.
"""
module Commits
using ..BaseUtils: Opt, graphql
using Dates: DateTime, now, Year, Second, CompoundPeriod
using HTTP: request
using JSON3: JSON3, Object
using LibPQ: Connection, Statement, execute, prepare, Intervals.Interval, load!, status
using Parameters: @unpack
"""
    parse_repo(node::Object,
               slug::AbstractString,
               as_of::DateTime)

Return iterator for insertion into database.
"""
function parse_repo(node::Object,
                    slug::AbstractString,
                    as_of::DateTime)
   # node = json.data.repository.defaultBranchRef.target.history.nodes[1]
   @unpack author, oid, committedDate, additions, deletions = node
   (slug = slug,
    hash = oid,
    committed_date = committedDate,
    login = isnothing(author.user) ? missing : author.user.login,
    additions = additions,
    deletions = deletions,
    as_of = as_of)
end
"""
    commits(opt::Opt,
            slug::AbstractString)

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
function commits(opt::Opt,
                 slug::AbstractString,
                 since::DateTime = DateTime("1970-01-01T00:00:00"),
                 until::DateTime = floor(now(), Year),
                 bulk_size::Integer = 100)
    @unpack conn, pat, schema = opt
    owner, name = split(slug, '/')
    since = DateTime("1970-01-01T00:00:00")
    until = floor(now(), Year)
    result = graphql(pat,
                     "Commits",
                     Dict("owner" => owner,
                          "name" => name,
                          "since" => since,
                          "until" => until,
                          "first" => bulk_size))
    json = JSON3.read(result.Data)
    if haskey(json, :errors)
        for er ∈ json.errors
            if startswith(er.message, "Something went wrong while executing your query.")
                new_bulk_size = bulk_size ÷ 2
                while true
                    result = graphql(pat,
                                     "Commits",
                                     Dict("owner" => owner,
                                          "name" => name,
                                          "since" => since,
                                          "until" => until,
                                          "first" => new_bulk_size))
                    json = JSON3.read(result.Data)
                    haskey(json, :errors) || break
                    bulk_size == 1 || throw(Error("Kept timing out!: $slug: $since..$until"))
                end
            end
        end
    end
    as_of = DateTime(first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date")[1:end - 4],
                     "e, dd u Y HH:MM:SS")
    execute(conn, "BEGIN;")
    load!((parse_repo(node, slug, as_of) for node ∈ json.data.repository.defaultBranchRef.target.history.nodes),
           conn,
           "INSERT INTO $schema.commits VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7) ON CONFLICT DO NOTHING;")
    execute(conn, "COMMIT;")
    while !isnothing(json.data.repository.defaultBranchRef.target.history.pageInfo.endCursor)
        result = graphql(pat,
                         "CommitsContinue",
                         Dict("owner" => owner,
                              "name" => name,
                              "since" => since,
                              "until" => until,
                              "cursor" => json.data.repository.defaultBranchRef.target.history.pageInfo.endCursor,
                              "first" => bulk_size))
        json = JSON3.read(result.Data)
        as_of = DateTime(first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date")[1:end - 4],
                         "e, dd u Y HH:MM:SS")
        execute(conn, "BEGIN;")
        load!((parse_repo(node, slug, as_of) for node ∈ json.data.repository.defaultBranchRef.target.history.nodes),
              conn,
              "INSERT INTO $schema.commits VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7) ON CONFLICT DO NOTHING;")
        execute(conn, "COMMIT;")
    end
    result = graphql(pat,
                     "CommitsVerify",
                     Dict("owner" => owner,
                          "name" => name,
                          "since" => since,
                          "until" => until))
    json = JSON3.read(result.Data)
    total = json.data.repository.defaultBranchRef.target.history.totalCount
    collected = getproperty.(execute(conn,
                                    """SELECT COUNT(*) FROM $schema.commits
                                       WHERE slug = '$slug'
                                       ;
                                    """),
                            :count)[1]
    execute(conn,
            """UPDATE $schema.repos
               SET status = '$(collected ≥ total ? "Done" : "Error")'
               WHERE slug = '$slug'
               ;
            """)
end
end
