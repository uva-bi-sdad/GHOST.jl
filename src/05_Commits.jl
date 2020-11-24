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
    if isnothing(node)
        println(branch)
        throw(ErrorException("Weird thing going on"))
    end
    authors = parse_author.(getproperty.(node.authors.edges, :node))
    emails = getproperty.(authors, :email)
    names = getproperty.(authors, :name)
    users = [ isa(elem, AbstractString) ? escape_string(elem) : elem for elem in getproperty.(authors, :id) ]
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
    query_commits_simple(branches::AbstractVector{<:AbstractString}, batch_size::Integer)::Nothing
"""
function query_commits_simple(branches::AbstractVector{<:AbstractString}, batch_size::Integer)::Nothing
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
                "first" => batch_size)
    result = graphql(query, vars = vars)
    json = try
        json = JSON3.read(result.Data)
        json.data
    catch err
        if length(branches) == 1
            execute(conn, "UPDATE $schema.repos SET status = 'FOR_LATER' WHERE branch = '$(only(branches))';")
        else
            query_commits_simple(view(branches, 1:length(branches) ÷ 2), batch_size)
            query_commits_simple(view(branches, length(branches) ÷ 2 + 1:lastindex(branches)), batch_size)
        end
        return
    end
    for (branch, nodes) in zip(branches, values(json.nodes))
        if isnothing(nodes)
            execute(conn, "UPDATE $schema.repos SET status = 'NOT_FOUND' WHERE branch = '$branch';")
        else
            for edge in nodes.target.history.edges
                nodes = values(edge)
                if any(isnothing, nodes)
                    execute(conn, "UPDATE $schema.repos SET status = 'SERVICE_UNAVAILABLE' WHERE branch = '$branch';")
                else
                    for node in nodes
                        push!(output, parse_commit(branch, node))
                    end
                end
            end
        end
    end
    try
        execute(conn, "BEGIN;")
        load!(output,
              conn,
              string("INSERT INTO $schema.commits VALUES (",
                     join(("\$$i" for i in 1:size(output, 2)), ','),
                     ") ON CONFLICT ON CONSTRAINT commits_pkey DO NOTHING;"))
        execute(conn, "COMMIT;")
    catch err
        println(branches)
        throw(err)
    end
    execute(conn,
            """
            UPDATE $schema.repos
            SET status = 'Done'
            WHERE branch = ANY('{$(join(unique(output.branch), ','))}'::text[])
            ;
            """)
    nothing
end
