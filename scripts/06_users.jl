using GHOST
setup()
@unpack conn, schema, pat = GHOST.PARALLELENABLER

users = execute(conn,
                """
                SELECT author
                FROM $schema.usr_to_get_login_full A
                LEFT JOIN $schema.test_usr B
                ON A.author = B.id
                WHERE B.id is null
                ;
                """) |>
    (obj -> getproperty.(obj, :author))
users = [ data[i:min(i + 4_999, lastindex(users))] for i in 1:5_000:length(users) ]

function query_users(users::AbstractVector{<:AbstractString})
    nodes = [ users[i:min(i + 99, lastindex(users))] for i in 1:100:length(users) ]
    vars = Dict(zip(string.("x", eachindex(nodes)), nodes))
    query = string("fragment a on Node {id __typename",
                   "...on User{login} ",
                   "...on Organization {login} ",
                   "...on Bot {login}}",
                   "query A(",
                   join(("\$x$i:[ID!]!" for i in eachindex(nodes)), ','),
                   "){",
                   join(("_$i:nodes(ids:\$x$i){...a}" for i in eachindex(nodes)), ' '),
                   "}")
    result = graphql(query, vars = vars, max_retries = 2)
    json = JSON3.read(result.Data)
    output = reduce(vcat, DataFrame(r for r in values(elem) if ~isnothing(r)) for elem in values(json.data))
    execute(conn, "BEGIN;")
    GHOST.load!(output, conn, "INSERT INTO $schema.test_usr VALUES(\$1,\$2,\$3) ON CONFLICT DO NOTHING;")
    execute(conn, "COMMIT;")
    nothing
end

for i in 1:lastindex(users)
    println(i)
    query_users(users[i])
    sleep(0.25)
end
