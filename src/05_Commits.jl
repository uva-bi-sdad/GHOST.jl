"""
    parse_author(node)::NamedTuple

This parses the email, name, and ID of the author node.
"""
parse_author(node) = (email = node.email, name = node.name, id = isnothing(node.user) ? missing : node.user.id)
"""
    parse_commit(branch, node)::NamedTuple

This parses a commit node and adds the branch it queried.
"""
function parse_commit(branch, node)
    authors = parse_author.(getproperty.(node.authors.edges, :node))
    emails = [ isa(elem, AbstractString) ? replace(elem, r"(\{|\}|\")" => s"\\\1}") : missing for elem in getproperty.(authors, :email) ]
    names = [ isa(elem, AbstractString) ? replace(elem, r"(\{|\}|\")" => s"\\\1}") : missing for elem in getproperty.(authors, :name) ]
    users = [ isa(elem, AbstractString) ? replace(elem, r"(\{|\}|\")" => s"\\\1}") : missing for elem in getproperty.(authors, :authors) ]
    (branch = branch,
     id = node.id,
     sha1 = node.oid,
     committed_ts = replace(node.committedDate, "Z" => ""),
     emails = emails,
     names = names,
     users = users,
     additions = node.additions,
     deletions = node.deletions)
end
"""
    query_commits_repos_1_10(branches::AbstractVector{<:AbstractString})::Nothing
"""
function query_commits_repos_1_10(branches::AbstractVector{<:AbstractString})::Nothing
    @unpack conn, schema = PARALLELENABLER
    output = DataFrame(vcat(fill(String, 4), fill(Vector{Union{Missing,String}}, 3), fill(Int, 2)),
                       [:branch, :id, :sha1, :committed_ts, :emails, :names, :users, :additions, :deletions],
                       0)
    query = String(read(joinpath(dirname(pathof(GHOSS)), "assets", "graphql", "03_commits.graphql"))) |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        (obj -> replace(obj, r"\s+(\{|\}|\:)\s*" => s"\1")) |>
        (obj -> replace(obj, r"(:|,|\.{3})\s*" => s"\1")) |>
        strip |>
        string
    vars = Dict("until" => "2020-01-01T00:00:00Z",
                "nodes" => branches,
                "first" => 10)
    result = graphql(query, vars = vars)
    json = try
        JSON3.read(result.Data)
    catch err
        println(result)
        println(typeof(result))
        println(propertynames(result))
        println(branches)
        JSON3.read(result.Data)
    end
    for (branch, nodes) in zip(branches, values(json.data.nodes))
        if isnothing(nodes)
            println(branch)
            execute(conn, "UPDATE $schema.repos SET status = 'NOT_FOUND' WHERE branch = '$branch';")
        else
            for edge in nodes.target.history.edges
                for node in values(edge)
                    push!(output, parse_commit(branch, node))
                end
            end
        end
    end
    execute(conn, "BEGIN;")
    load!(output,
          conn,
          string("INSERT INTO $schema.commits VALUES (",
                 join(("\$$i" for i in 1:size(output, 2)), ','),
                 ") ON CONFLICT ON CONSTRAINT commits_pkey DO NOTHING;"))
    execute(conn, "COMMIT;")
    execute(conn,
            """
            UPDATE $schema.repos
            SET status = 'Done'
            WHERE branch = ANY('{$(join(unique(output.branch), ','))}'::text[])
            ;
            """)
    nothing
end
