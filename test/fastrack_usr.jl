0
# run(`ijob -A biocomplexity -p bii -t 0-04:00:00 -c 30 --mem=256GB`)
run(`ijob -A biocomplexity -p bii -t 0-04:00:00 -c 8 --mem=256GB`)
julia --proj

filter!(isequal(joinpath(homedir(), ".julia")), DEPOT_PATH)
using GHOSS
conn = Connection("""
                  host = $(get(ENV, "PGHOST", ""))
                  dbname = sdad
                  user = $(get(ENV, "DB_USR", ""))
                  password = $(get(ENV, "DB_PWD", ""))
                  """);
logins = execute(conn,
                 """
                 SELECT DISTINCT login
                 FROM gh.ctrs_raw
                 WHERE login NOT IN (SELECT id FROM gh.usr_email)
                 ORDER BY login ASC;
                 """,
                 not_null = true) |>
    (obj -> getproperty.(obj, :login))
ranges = [ logins[start:stop] for (start, stop) in zip((1:1_500:length(logins))[1:end - 1], (1:1_500:length(logins))[2:end] .- 1) ];

pats = execute(conn, "SELECT * FROM gh.pat ORDER BY login;", not_null = true) |>
    DataFrame |>
    (obj -> [ GHOSS.GitHubPersonalAccessToken(row.login, row.pat) for row in eachrow(obj) ] )
auths = DataFrame()
for pat in pats
    json = graphql(pat,
                   query = "query ID{viewer{login}}",
                   operationName = "ID",
                   vars = Dict{String,String}())
    auth = Dict(json.Info.headers)["X-OAuth-Scopes"]
    push!(auths, (login = JSON3.read(json.Data).data.viewer.login, auth = auth))
end
pats = pats[occursin.("user", auths.auth)]
pat = pats[1]
GHOSS.setup_parallel(conn, pats)
using Distributed
conn = Connection("""
                  host = $(get(ENV, "PGHOST", ""))
                  dbname = sdad
                  user = $(get(ENV, "DB_USR", ""))
                  password = $(get(ENV, "DB_PWD", ""))
                  """);
@everywhere GHOSS.PARALLELENABLER.x.conn = Connection("""
                                                      host = $(get(ENV, "PGHOST", ""))
                                                      dbname = sdad
                                                      user = $(get(ENV, "DB_USR", ""))
                                                      password = $(get(ENV, "DB_PWD", ""))
                                                      """);
errors = []
@everywhere function magic(conn, login)
    # println(0)
    pat = GHOSS.PARALLELENABLER.x.pat
    conn = GHOSS.PARALLELENABLER.x.conn
    # println(myid())
    idx = length(login)
    subquery = join("_$idx:user(login:\$u$idx){...useremail}" for idx in 1:idx);
    query = string("fragment useremail on User{id email}",
                   "query useremails($(join(("\$u$idx:String!" for idx in 1:idx), ','))){$subquery}");
    try
        result = GHOSS.graphql(pat,
                               query = query,
                               operationName = "useremails",
                               vars = Dict{String,String}(zip(("u$idx" for idx in 1:idx), login)))
    json = JSON3.read(result.Data).data
    output = DataFrame(login = login,
                       id = Vector{Union{Missing,String}}(undef, idx),
                       email = Vector{Union{Missing,String}}(undef, idx))
    for (i, val) in enumerate(values(json))
        if isnothing(val)
            output.id[i] = missing
            output.email[i] = missing
        else
            output.id[i] = val.id
            output.email[i] = isempty(val.email) ? missing : val.email
        end
    end
        GHOSS.load!(output,
                    conn,
                    "INSERT INTO gh.usr_email VALUES(\$1,\$2,\$3) ON CONFLICT ON CONSTRAINT usr_email_login_key DO NOTHING;")
    catch err
        err
    end
end
@sync @distributed for login in ranges
    magic(conn, login)
    sleep(1)
end
for proc ∈ workers()
    GHOSS.READY.x[proc - 1] = GHOSS.@spawnat proc nothing
    pat = pats[proc - 1]
    expr = :(GHOSS.PARALLELENABLER.x.pat = $pat; GHOSS.PARALLELENABLER.x.conn = $conn)
    remotecall_eval(Main, proc, :(magic($(ranges[1]))))
    x = Distributed.remotecall_eval(Main, 2, :(magic($(ranges[1]))))
end

fetch(@spawnat 3 magic(conn, ranges[1]))
idx = 1_500
subquery = join("_$idx:user(login:\$u$idx){...useremail}" for idx in 1:idx)
query = string("fragment useremail on User{id email}",
               "query useremails($(join(("\$u$idx:String!" for idx in 1:idx), ','))){$subquery}")
# subquery = join("_$idx:user(login:\$u$idx){...useremail}" for idx in 0:idx)
# query = string("fragment useremail on User{id email}",
#                "query useremails($(join(("\$u$idx:String!" for idx in 0:idx), ','))){$subquery}")
pat = pats[1]
json = graphql(pat,
               query = query,
               operationName = "useremails",
               vars = Dict{String,String}(zip(("u$idx" for idx in 1:idx), logins[1:idx])))




pats = execute(conn, "SELECT * FROM gh.pat ORDER BY login;", not_null = true) |>
    DataFrame |>
    (obj -> [ GHOSS.GitHubPersonalAccessToken(row.login, row.pat) for row in eachrow(obj) ] )
auths = DataFrame()
for pat in pats
    json = graphql(pat,
                   query = "query ID{viewer{login}}",
                   operationName = "ID",
                   vars = Dict{String,String}())
    auth = Dict(json.Info.headers)["X-OAuth-Scopes"]
    push!(auths, (login = JSON3.read(json.Data).data.viewer.login, auth = auth))
end
pats = pats[occursin.("user", auths.auth)]


# json = graphql(pat,
#                query = query,
#                operationName = "useremails",
#                vars = Dict{String,String}(zip(("u$idx" for idx in 0:idx), logins)))

really_good = falses(length(auths.login[occursin.("user", auths.auth)]))
login = logins
for (idx, pat) in enumerate(pats[occursin.("user", auths.auth)])
    try
        idx = l
        json = graphql(pat,
               query = query,
               operationName = "useremails",
               vars = Dict{String,String}(zip(("u$idx" for idx in 0:idx), login)))
        good_pats[idx] = true



json = graphql(pat,
    query = "query ID{viewer{login}}",
    operationName = "ID",
    vars = Dict{String,String}())
Dict(json.Info.headers)["X-OAuth-Scopes"]
    
json = graphql(pat,
               query = query,
               operationName = "useremails",
               vars = Dict{String,String}(zip(("u$idx" for idx in 0:idx), logins)))

propertynakes(json)
