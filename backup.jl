
run(`ijob -A biocomplexity -p bii -t 0-04:00:00 -c 30 --mem=256GB`)
julia --proj

filter!(isequal(joinpath(homedir(), ".julia")), DEPOT_PATH)

using GHOSS

conn = Connection("""
                  host = $(get(ENV, "PGHOST", ""))
                  dbname = sdad
                  user = $(get(ENV, "DB_USR", ""))
                  password = $(get(ENV, "DB_PWD", ""))
                  """);
pats = execute(conn, "SELECT * FROM gh.pat ORDER BY login;", not_null = true) |>
    DataFrame |>
    (data -> [ GitHubPersonalAccessToken(row.login, row.pat) for row in eachrow(data) ])
pat = pats[18]
pat.login
findfirst(pat -> isequal("Nosferican", pat.login), pats)
setup_parallel(pats)
schema = "gh_2007_2019"
querydata = execute(conn,
                    """
                    SELECT spdx, created, count
                    FROM gh_2007_2019.queries
                    ORDER BY count DESC
                    ;
                    """,
                    not_null = true) |>
    DataFrame
querydata.created = Interval.(ZonedDateTime.(getproperty.(querydata.created, :first), utc_tz), ZonedDateTime.(getproperty.(querydata.created, :last), utc_tz))
data = querydata[11:20,:]
data = querydata[21:30,:]
sum(data.count)

function branches(pat::GitHubPersonalAccessToken, query::AbstractString, bulk_size::Integer = 50, waittime::Real = 0.5)
    vars = Dict("first" => bulk_size)
    result = graphql(pat, query = query, operationName = "Search", vars = vars)
    if isa(result, StatusError)
        if result.status == 502
            # Timeout
            sleep(waittime)
            output = branches(pat, query, vars["first"] ÷ 2, waittime)
        elseif result.status == 403
            # documentation_url: https://developer.github.com/v3/#abuse-rate-limits
            # message: You have triggered an abuse detection mechanism. Please wait a few minutes before you try again.
            println("ABUSE!!!")
            sleep(parse(Int, Dict(result.response.headers)["Retry-After"]))
            output = branches(pat, query, vars["first"], waittime)
        else
            output = result
        end
    else
        output = result
    end
    output
end


function branches(pat::GitHubPersonalAccessToken, data::AbstractDataFrame, bulk_size::Integer = 50, waittime::Real = 1)
    log_of_requests = DataFrame([String, Int, Union{Diana.Result,StatusError}], [:query, :first, :result], 0)
    bulk_size = 50
    waittime = 1
    # insert_order = 0
    output = DataFrame()
    data[!,:cursor] .= ""
    subquery = join((generate_search_query(row, idx) for (idx, row) in enumerate(eachrow(data))), ',')
    query = string(String(read(joinpath(@__DIR__, "src", "assets", "branches.graphql"))), "query Search(\$first: Int!){$subquery}") |>
            (obj -> replace(obj, r"\s+" => " ")) |>
            strip |>
            string;
    vars = Dict("first" => bulk_size)
    result = graphql(pat, query = query, operationName = "Search", vars = vars)
    push!(log_of_requests, (query = query, first = vars["first"], result = result))
    while isa(result, StatusError)
        if result.status == 502
            # Timeout
            sleep(waittime)
            vars["first"] = vars["first"] ÷ 2
            result = graphql(pat, query = query, operationName = "Search", vars = vars)
            push!(log_of_requests, (query = query, first = vars["first"], result = result))
        elseif result.status == 403
            # documentation_url: https://developer.github.com/v3/#abuse-rate-limits
            # message: You have triggered an abuse detection mechanism. Please wait a few minutes before you try again.
            println("ABUSE!!!")
            sleep(parse(Int, Dict(result.response.headers)["Retry-After"]))
            result = graphql(pat, query = query, operationName = "Search", vars = vars)
            push!(log_of_requests, (query = query, first = vars["first"], result = result))
        else
            return result
        end
    end
    # println(result)
    json = JSON3.read(result.Data).data
    println(vars["first"])
    for (idx, elem) in enumerate(values(json))
        # global insert_order
        data.cursor[idx] = something(elem.pageInfo.endCursor)
        # insert_order += 1
        # println("insert_order: $insert_order idx: $idx ($(length(elem.edges)))")
        append!(output, (id = elem.node.id, branch = elem.node.defaultBranchRef.id, query = query, count = vars["first"]) for elem in elem.edges)
        # append!(output, (id = elem.node.id, branch = elem.node.defaultBranchRef.id) for elem in elem.edges)
    end
    # "MDEwOlJlcG9zaXRvcnkyMTAyMjQzOTM=" ∈ output.id
    while any(!isempty, data.cursor)
        timestamp = now()
        vars["first"] = bulk_size
        filter!(row -> !isempty(row.cursor), data)
        subquery = join((generate_search_query(row, idx) for (idx, row) in enumerate(eachrow(data))), ',')
        query = string(String(read(joinpath(@__DIR__, "src", "assets", "branches.graphql"))), "query Search(\$first: Int!){$subquery}") |>
            (obj -> replace(obj, r"\s+" => " ")) |>
            strip |>
            string;
        sleep(waittime)
        result = graphql(pat, query = query, operationName = "Search",  vars = vars);
        push!(log_of_requests, (query = query, first = vars["first"], result = result))
        while isa(result, StatusError)
            # global insert_order
            if result.status == 502
                # Timeout
                sleep(waittime)
                vars["first"] = vars["first"] ÷ 2
                result = graphql(pat, query = query, operationName = "Search", vars = vars)
                push!(log_of_requests, (query = query, first = vars["first"], result = result))
            elseif result.status == 403
                # documentation_url: https://developer.github.com/v3/#abuse-rate-limits
                # message: You have triggered an abuse detection mechanism. Please wait a few minutes before you try again.
                println("ABUSE!!!")
                sleep(parse(Int, Dict(result.response.headers)["Retry-After"]))
                result = graphql(pat, query = query, operationName = "Search", vars = vars)
                push!(log_of_requests, (query = query, first = vars["first"], result = result))
            else
                return result
            end
        end
        if (:Data ∉ propertynames(result)) || (:data ∈ propertynames(result.Data))
            return result
        end
        json = JSON3.read(result.Data).data
        println(vars["first"])
        for (idx, elem) in enumerate(values(json))
            # global insert_order
            data.cursor[idx] = something(elem.pageInfo.endCursor, "")
            # insert_order += 1
            # println("insert_order: $insert_order idx: $idx ($(length(elem.edges)))")
            append!(output, (id = elem.node.id, branch = elem.node.defaultBranchRef.id, query = query, count = vars["first"]) for elem in elem.edges)
            # append!(output, (id = elem.node.id, branch = elem.node.defaultBranchRef.id) for elem in elem.edges)
            # @assert "MDEwOlJlcG9zaXRvcnkyMTAyMjQzOTM=" ∉ output.id
        end
        # output[output.id .== "MDEwOlJlcG9zaXRvcnkyMTAyMjg1NzM=",:]
        # findall(output.id .== "MDEwOlJlcG9zaXRvcnkyMTAyMjg1NzM=")
        # output[end - 1:end,:]
        
        # size(output, 1) == size(unique(output), 1)
        # x = DataFrames.combine(x -> size(x, 1), DataFrames.groupby(output, :id))
        # x = x[x.x1 .> 1,:]
        # filter!(:x1 > 1)
        # println(Dates.canonicalize(Dates.CompoundPeriod(now() - timestamp)))
    end
    (output, log_of_requests)
end
time_start = now()
# result[result.id .== "MDEwOlJlcG9zaXRvcnkyMTAyMjQzOTM=",:]
result = branches(querydata[1:10,:], 50)
result2, log_responses2 = branches(data)
result3, log_responses3 = branches(data)

sum(data.count)
size(result3, 1)
size(unique(result3), 1)

sum(data.count)
size(result2, 1)

using CSV, JSONTables
length(log_responses2.query)
log_responses2.query[1:2]

io = mkpath("queries.txt")
touch("queries.txt")
io = open("queries.txt", write = true)
typeof(io)
for elem in log_responses3.query
    println(io, elem)
end
close(io)

result[!,[:query, :count, :id]]
result.query
result.count
using DataFrames
chk = combine(groupby(result, :id), x -> size(x, 1))
length(unique(result.id))
size(result, 1)




result[!,:asof] .= round(now(utc_tz), Second)
result[!,:status] .= "Ready"
result
load!(result, conn, "INSERT INTO $schema.repos VALUES(\$1, \$2, \$3, \$4);")
load!(result[!,1:2], conn, "INSERT INTO $schema.repos VALUES(\$1, \$2, '$(round(now(utc_tz), Second))', 'Ready');")
unique(result)
time_end = now()
println(Dates.canonicalize(Dates.CompoundPeriod(time_end - time_start)))

result = chk
pat = pats[2]
typeof(JSON3.read(chk.Data).data)

    while isa(result, StatusError) && result.status == 502
        global first_count, result
        first_count = first_count ÷ 2
        result = graphql(pat, query = query, operationName = "Search", vars = Dict("first" => first_count))
    end


data = querydata[1:10,:]
data[!,:cursor] .= ""
output = DataFrame()
subquery = join((generate_search_query(row, idx) for (idx, row) in enumerate(eachrow(data))), ',')
query = string(String(read(joinpath(@__DIR__, "src", "assets", "branches.graphql"))), "query Search(\$first: Int!){$subquery}") |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        strip |>
        string;
first_count = 100
result = graphql(pat, query = query, operationName = "Search", vars = Dict("first" => first_count))
# Status Code 502 means: Timeout
while isa(result, StatusError) && result.status == 502
    global first_count, result
    first_count = first_count ÷ 2
    result = graphql(pat, query = query, operationName = "Search", vars = Dict("first" => first_count))
end

json = JSON3.read(result.Data).data
for (idx, elem) in enumerate(values(json))
    data.cursor[idx] = something(elem.pageInfo.endCursor)
    append!(output, (id = elem.node.id, branch = elem.node.defaultBranchRef.id) for elem in elem.edges)
end
while any(!isempty, data.cursor)
    filter!(row -> !isempty(row.cursor), data)
    subquery = join((generate_search_query(row, idx) for (idx, row) in enumerate(eachrow(data))), ',')
    query = string(String(read(joinpath(@__DIR__, "src", "assets", "branches.graphql"))), "query Search{$subquery}") |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        strip |>
        string;
    # sleep(rand(0.25:0.75))
    result = graphql(pat, query = query, operationName = "Search", vars = Dict{String,Any}())
    json = JSON3.read(result.Data).data
    for (idx, elem) in enumerate(values(json))
        data.cursor[idx] = something(elem.pageInfo.endCursor, "")
        append!(output, (id = elem.node.id, branch = elem.node.defaultBranchRef.id) for elem in elem.edges)
    end
    data
end
output

query = """
fragment A on SearchResultItemConnection {
  pageInfo {
    endCursor
  }
  edges {
    node {
      ... on Repository {
        id
        defaultBranchRef {
          id
        }
      }
    }
  }
}

query Search {
  _1: search(query: "is:public fork:false mirror:false archived:false license:mit created:2019-12-07T16:00:00+00..2019-12-08T00:00:00+00", type: REPOSITORY, first: 100, after: "Y3Vyc29yOjkwMA==") {
    ...A
  }
  _2: search(query: "is:public fork:false mirror:false archived:false license:mit created:2019-12-02T14:24:00+00..2019-12-02T19:12:00+00", type: REPOSITORY, first: 100, after: "Y3Vyc29yOjkwMA==") {
    ...A
  }
  _3: search(query: "is:public fork:false mirror:false archived:false license:mit created:2016-10-28T12:00:00+00..2016-10-29T00:00:00+00", type: REPOSITORY, first: 100, after: "Y3Vyc29yOjkwMA==") {
    ...A
  }
}
"""
json[Symbol("_1")].pageInfo.endCursor
[ (id = elem.node.id, branch = elem.node.defaultBranchRef.id) for elem in json[Symbol("_2")].edges ]

json[Symbol("_2")].edges[1].node
