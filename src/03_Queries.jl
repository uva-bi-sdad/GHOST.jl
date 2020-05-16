"""
    generate_search_query(obj, idx::Integer)

Return the named item query based on the ID, SPDX, created, and cursor.
"""
function generate_search_query(obj, idx::Integer)
    spdx = obj.spdx
    created = obj.created
    created = string(format(created.first, "yyyy-mm-ddTHH:MM:SSzz")[1:end - 3], "..", format(created.last, "yyyy-mm-ddTHH:MM:SSzz")[1:end - 3])
    cursor = isempty(obj.cursor) ? "" : ", after: \"$(obj.cursor)\""
    "_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$spdx created:$created\", type: REPOSITORY, first: 100$cursor){...A}"
end

"""
    query_intervals(spdx::AbstractString, created::AbstractVector{<:Interval{ZonedDateTime}})

Return count of search results based on the license for each created interval.
"""
function query_intervals(created::AbstractVector{<:Interval{ZonedDateTime}})
    pat = PARALLELENABLER.x.pat
    spdx = PARALLELENABLER.x.spdx
    subsquery = join([ string("_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$spdx created:",
                       format(created[idx].first, "yyyy-mm-ddTHH:MM:SSzz")[1:end - 3],
                       "..",
                       format(created[idx].last, "yyyy-mm-ddTHH:MM:SSzz")[1:end - 3],
                       "\",type:REPOSITORY){...A}") for idx in eachindex(created)]);
    query = "fragment A on SearchResultItemConnection{repositoryCount} query Search{$subsquery}" |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        strip |>
        string;
    result = graphql(pat, query = query, operationName = "Search", vars = Dict{String,Any}())
    json = JSON3.read(result.Data)
    data = json.data
    DataFrame(created = created, count = getproperty.(values(data), :repositoryCount))
end
"""
    query_intervals(created::AbstractVector{<:AbstractVector{Interval{ZonedDateTime}}})::DataFrame

Returns a 
"""
function query_intervals(created::AbstractVector{<:AbstractVector{Interval{ZonedDateTime}}})
    output = DataFrame()
    graphqlremaining =
        DataFrame(
            fetch(
                @spawnat w (w, GHOSS.PARALLELENABLER.x.pat.limits.graphql.remaining, GHOSS.PARALLELENABLER.x.pat.limits.graphql.reset)) for w in workers()
                )
    maptovalidprocs = sort!(graphqlremaining, (order(2, rev = true), 3))[!,1][1:min(length(READY.x), length(created))] .- 1
    for w in maptovalidprocs
        READY.x[w] = remotecall(GHOSS.query_intervals, w + 1, popfirst!(created))
    end
    while !isempty(created)
        w = findfirst(isready, @view(READY.x[maptovalidprocs]))
        if isnothing(w)
            sleep(5)
        else
            append!(output, fetch(READY.x[maptovalidprocs][w]))
            READY.x[maptovalidprocs][w] = remotecall(GHOSS.query_intervals, w + 1, popfirst!(created))
        end
    end
    while any(!isready, READY.x)
        sleep(5)
    end
    for f in @view(READY.x[maptovalidprocs][isready.(READY.x[maptovalidprocs])])
        append!(output, fetch(f))
    end
    output
end

"""
    cleanintervals(row)

Returns the input if the count is 1,000 records or fewer.
If there are more than a 1,000 it splits them based on the ratio of the count.
"""
function cleanintervals(row)
    created = row.created
    cnt = row.count
    if ismissing(cnt) || cnt ≤ 1_000
        DataFrame(row)
    else
        new_step = ceil((created.last - created.first) ÷ (cnt ÷ 1_000 + 1), Second)
        new_date_period = range(created.first, created.last, step = new_step)
        DataFrame([ (created = Interval(ds, de, true, false), count = missing) for (ds, de) in zip(new_date_period[1:end - 1], new_date_period[2:end]) ])
    end
end
"""
    prune(data)

Prune the intervals based on the created and count values.
"""
function prune(data)
    isempty(data) && return data
    created = data.created
    cnt = data.count
    output = similar(data, 0)
    running_cnt = 0
    date_start = first(created).first
    for (created, cnt) in zip(created, cnt)
        if (running_cnt + cnt) ≥ 1_000
            push!(output, (created = Interval(date_start, created.first, true, false), count = running_cnt))
            date_start = created.first
            running_cnt = cnt
        else
            running_cnt += cnt
        end
    end
    push!(output, (created = Interval(date_start, created[end].last, true, false), count = running_cnt))
    output
end

"""
    format_tsrange(obj::Interval{ZonedDateTime})

Return the Postgres compatible form.
"""
format_tsrange(obj::Interval{ZonedDateTime}) = replace(string(obj), ".." => ",")

"""
    queries(conn::Connection,
            spdx::AbstractString,
            schema::AbstractString = "gh_2007_\$(Dates.year(floor(now(), Year) - Day(1)))")

This will upload the queries to the database with:
- spdx::text NOT NULL
- created::tsrange NOT NULL
- count::smallint NOT NULL
- asof::time
- done::bool NOT NULL
"""
function queries(conn::Connection,
                 spdx::AbstractString,
                 schema::AbstractString = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))")
    # spdx = "mit"
    # schema = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))"
    calendaryear = parse(Int, schema[end - 3:end])
    created = floor(GH_FIRST_REPO_TS, Day):Day(1):floor(now(utc_tz), Year)
    created = [ Interval(start, stop, true, false) for (start, stop) in zip(created[1:end - 1], created[2:end]) ]
    created = [ created[start:stop] for (start, stop) in zip((1:185:length(created))[1:end], (vcat((0:185:length(created))[2:end], length(created)))) ]
    @everywhere GHOSS.PARALLELENABLER.x.spdx = $spdx
    data = query_intervals(created)
    data = prune(data)
    data = reduce(vcat, cleanintervals(row) for row in eachrow(data))
    toreplace = ismissing.(data.count)
    created = data.created[toreplace]
    while !isempty(created)
        created = [ created[start:stop] for (start, stop) in zip((1:185:length(created))[1:end], (vcat((0:185:length(created))[2:end], length(created)))) ]
        vals = query_intervals(created)
        data.count[toreplace] .= get.(Ref(Dict(zip(vals.created, vals.count))), data.created[toreplace], missing)
        data = reduce(vcat, cleanintervals(row) for row in eachrow(data))
        toreplace = ismissing.(data.count)
        created = data.created[toreplace]
    end
    data = prune(data)
    # Dates.canonicalize(Dates.CompoundPeriod(minimum(elem.last - elem.first for elem in data.created)))
    data[!,:created] .= format_tsrange.(data.created)
    data[!,:spdx] .= spdx
    data[!,:asof] .= round(now(utc_tz), Second)
    data[!,:done] .= iszero.(data.count)
    sort!(data, :created)
    execute(conn, "BEGIN;")
    load!(data[!,[:spdx,:created,:count,:asof,:done]],
          conn,
          """
          INSERT INTO $schema.queries VALUES ($(join(("\$$i" for i in 1:5), ',')))
          ON CONFLICT ON CONSTRAINT query DO UPDATE SET
          count = EXCLUDED.count, done = EXCLUDED.done, asof = EXCLUDED.asof;
          """,
          )
    execute(conn, "COMMIT;")
    nothing
end
