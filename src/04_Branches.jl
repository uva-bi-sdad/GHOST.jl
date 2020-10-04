"""
    parse_branch_node(node, spdx::AbstractString)::NamedTuple

Parses a node and returns a suitable `NamedTuple` for the table.
"""
function parse_branch_node(node, spdx::AbstractString)
    @unpack id, createdAt, nameWithOwner, description, primaryLanguage, defaultBranchRef = node
    (id = id,
     spdx = spdx,
     slug = nameWithOwner,
     createdat = DateTime(replace(createdAt, "Z" => "")),
     description = something(description, missing),
     primarylanguage = isnothing(primaryLanguage) ? missing : primaryLanguage.name,
     branch = isnothing(primaryLanguage) ? missing : defaultBranchRef.id)
end
"""
    find_repos(batch::AbstractDataFrame)::Nothing

Takes a batch of 10 spdx/createdat and puts the data in the database.
"""
function find_repos(batch::AbstractDataFrame)
    @unpack conn, schema = GHOSS.PARALLELENABLER
    output = DataFrame(vcat(fill(String, 3), DateTime, fill(Union{Missing, String}, 3)),
                       [:id, :spdx, :slug, :createdat, :description, :primarylanguage, :branch],
                       0)
    subsquery = join([ string("_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$(batch.spdx[idx]) created:",
                     format(batch.created[idx].first, "yyyy-mm-ddTHH:MM:SS\\Z"),
                     "..",
                     format(batch.created[idx].last, "yyyy-mm-ddTHH:MM:SS\\Z"),
                     "\",type:REPOSITORY, first:10, after:\$cursor_$idx){...A}") for idx in 1:size(batch, 1)]);
    query = string(String(read(joinpath(@__DIR__, "assets", "graphql", "branches.graphql"))),
                          "query Search(\$until:String!,",
                          join((("\$cursor_$idx:String") for idx in 1:size(batch, 1)), ','),
                          "){$subsquery}") |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        strip |>
        string;
    vars = Dict("until" => "$(parse(Int, match(r"\d{4}$", schema).match) + 1)-01-01T00:00:00Z")
    while true
        sleep(1)
        result = graphql(query, vars = vars)
        :Data ∈ propertynames(result) || return result
        json = JSON3.read(result.Data)
        append!(output,
                reduce(vcat,
                       DataFrame(parse_branch_node(node.node, spdx) for node in elem.edges)
                       for (elem, spdx) in zip(values(json.data), batch[:spdx])))
        json.data[:_1].pageInfo.hasNextPage || break
        all(elem -> !elem.pageInfo.hasNextPage, values(json.data)) || break
        for idx in eachindex(json.data)
            if !isnothing(json.data[idx].pageInfo.endCursor)
                push!(vars, "cursor$idx" => json.data[idx].pageInfo.endCursor)
            end
        end
    end
    execute(conn, "BEGIN;")
    load!(output,
          conn,
          string("INSERT INTO $schema.repos VALUES(",
                 join(("\$$i" for i in 1:size(output, 2)), ','),
                 ") ON CONFLICT DO NOTHING;"))
    execute(conn, "COMMIT;")
    for row in eachrow(batch)
        execute(conn,
                """
                UPDATE $schema.queries
                SET done = true
                WHERE spdx = '$(row.spdx)' AND '$(row.created.first)'::timestamp <@ created
                ;
                """)
    end
end
