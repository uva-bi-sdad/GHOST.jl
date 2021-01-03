"""
    parse_author(node)::NamedTuple

This parses the email, name, and ID of the author node.
"""
parse_author(node) = (email = escape_string(node.email),
                      name = escape_string(node.name),
                      id = isnothing(node.user) ? missing : escape_string(node.user.id))
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
    users = getproperty.(authors, :id)
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
    query_commits(branch::AbstractString)::Nothing
"""
function query_commits(branch::AbstractString)::Nothing
    @unpack conn, schema = GHOST.PARALLELENABLER
    since = execute(conn, "SELECT MIN(committedat) AS since FROM gh_2007_2020.commits WHERE branch = '$branch';") |>
        (obj -> only(getproperty.(obj, :since)))
    since = coalesce(since, GHOST.GH_FIRST_REPO_TS)
    output = DataFrame(vcat(fill(String, 4), fill(Vector{Union{Missing,String}}, 3), fill(Int, 2)),
                       [:branch, :id, :sha1, :committed_ts, :emails, :names, :users, :additions, :deletions],
                       0)
    query = String(read(joinpath(pkgdir(GHOST), "src", "assets", "graphql", "04_commits_single.graphql"))) |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        (obj -> replace(obj, r"\s+(\{|\}|\:)\s*" => s"\1")) |>
        (obj -> replace(obj, r"(:|,|\.{3})\s*" => s"\1")) |>
        strip |>
        string
    vars = Dict("since" => string(since, "Z"),
                "until" => "2020-01-01T00:00:00Z",
                "node" => branch,
                "first" => 64,
                )
    success = false
    json = try
        while !success
            result = graphql(query, vars = vars, max_retries = 1)
            json = JSON3.read(result.Data)
            if haskey(json, :errors)
                if first(json.errors).type == "NOT_FOUND"
                    execute(conn, "UPDATE $schema.repos SET status = 'NOT_FOUND' WHERE branch = '$branch';")
                    return
                end
            end
            try
                json = json.data.node.target.history
                success = !isempty(json.edges)
            catch err
                vars["first"] == 1 && throw(ErrorException("$branch is not playing nice."))
                vars["first"] ÷= 2
                sleep(0.25)
            end
        end
        json
    catch err
        throw(ErrorException("$branch is not playing nice ($first)."))
    end
    for edge in json.edges
        push!(output, GHOST.parse_commit(branch, edge.node))
    end
    execute(conn, "BEGIN;")
    load!(output,
          conn,
          string("INSERT INTO $schema.commits VALUES (",
                 join(("\$$i" for i in 1:size(output, 2)), ','),
                 ") ON CONFLICT ON CONSTRAINT commits_pkey DO NOTHING;"))
    execute(conn, "COMMIT;")
    while json.pageInfo.hasNextPage
        sleep(0.25)
        vars["until"] = string(DateTime(output[end,:committed_ts]), "Z")
        vars["first"] = 64
        success = false
        json = try
            while !success
                result = graphql(query, vars = vars, max_retries = 1)
                json = JSON3.read(result.Data)
                if haskey(json, :errors)
                    if first(json.errors).type == "NOT_FOUND"
                        execute(conn, "UPDATE $schema.repos SET status = 'NOT_FOUND' WHERE branch = '$branch';")
                        return
                    end
                end
                try
                    json = json.data.node.target.history
                    success = !isempty(json.edges)
                catch err
                    vars["first"] == 1 && throw(ErrorException("$branch is not playing nice."))
                    vars["first"] ÷= 2
                    sleep(0.25)
                end
            end
            json
        catch err
            throw(ErrorException("$branch is not playing nice ($first)."))
        end
        output = DataFrame(vcat(fill(String, 4), fill(Vector{Union{Missing,String}}, 3), fill(Int, 2)),
                       [:branch, :id, :sha1, :committed_ts, :emails, :names, :users, :additions, :deletions],
                       0)
        for edge in json.edges
            push!(output, GHOST.parse_commit(branch, edge.node))
        end
        execute(conn, "BEGIN;")
        load!(output,
              conn,
              string("INSERT INTO $schema.commits VALUES (",
                     join(("\$$i" for i in 1:size(output, 2)), ','),
                     ") ON CONFLICT ON CONSTRAINT commits_pkey DO NOTHING;"))
        execute(conn, "COMMIT;")
    end
    execute(conn,
            """
            UPDATE $schema.repos
            SET status = 'Done'
            WHERE branch = '$branch'
            ;
            """)
    println("$branch done at $(now())")
    nothing
end
"""
    query_commits_simple(branches::AbstractVector{<:AbstractString}, batch_size::Integer)::Nothing
"""
function query_commits_simple(branches::AbstractVector{<:AbstractString}, batch_size::Integer)::Nothing
    @unpack conn, schema = PARALLELENABLER
    output = DataFrame(vcat(fill(String, 4), fill(Vector{Union{Missing,String}}, 3), fill(Int, 2)),
                       [:branch, :id, :sha1, :committed_ts, :emails, :names, :users, :additions, :deletions],
                       0)
    query = String(read(joinpath(dirname(pathof(GHOST)), "assets", "graphql", "03_commits.graphql"))) |>
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
