using GHOST
using GHOST: @unpack, @everywhere, READY, remotecall, load!
setup()
time_start = now()
println(time_start)
setup_parallel()

@unpack conn, schema, pat = GHOST.PARALLELENABLER
data = execute(conn,
               "SELECT branch FROM $(schema).repos WHERE status = 'Init' ORDER BY commits;",
               not_null = true) |>
    (obj -> getproperty.(obj, :branch))
data = [ @view(data[i:min(i + 99, lastindex(data))]) for i in 1:100:length(data) ]
function magic(nodes::AbstractVector)
    query = "fragment X on Ref { id target { ... on Commit { history(until: \$until) { totalCount } } } } query Commits(\$x:[ID!]!, \$until:GitTimestamp!){nodes(ids:\$x){...X}}"
    vars = Dict("x" => nodes, "until" => "2020-01-01T00:00:00Z")
    result = graphql(query, vars = vars)
    json = JSON3.read(result.Data)
    try
        if :data ∈ propertynames(json)
            x = DataFrame((;x.id, x.target.history.totalCount) for x in (x for x in json.data.nodes if !isnothing(x)))
            load!(x, GHOST.PARALLELENABLER.conn, "INSERT INTO gh_2007_2020.repos_chk VALUES(\$1,\$2) ON CONFLICT DO NOTHING;")
        end
        if :errors ∈ propertynames(json)
            y = [ (branch = SubString(x.message, 52, length(x.message) - 2), commits = 0) for x in values(json.errors) ]
            load!(y, GHOST.PARALLELENABLER.conn, "INSERT INTO gh_2007_2020.repos_chk VALUES(\$1,\$2) ON CONFLICT DO NOTHING;")
        end
    catch err
        println("Error in: $nodes")
    end
    nothing
end
magic(data[2])
@sync @distributed for idx in eachindex(data)
    magic(data[idx])
    println(idx)
end