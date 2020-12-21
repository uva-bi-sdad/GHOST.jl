"""
    query_intervals(spdx::AbstractString, created::AbstractVector{<:Interval{ZonedDateTime}})

Return count of search results based on the license for each created interval.
"""
function query_intervals(created::Vector{Interval{DateTime,Closed,Open}})
    @unpack pat, spdx = PARALLELENABLER
    subsquery = join([ string("_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$spdx created:",
                       format(created[idx].first, "yyyy-mm-ddTHH:MM:SS\\Z"),
                       "..",
                       format(created[idx].last, "yyyy-mm-ddTHH:MM:SS\\Z"),
                       "\",type:REPOSITORY){...A}") for idx in eachindex(created)]);
    query = "fragment A on SearchResultItemConnection{repositoryCount} query Search{$subsquery}" |>
        (obj -> replace(obj, r"\s+" => " ")) |>
        strip |>
        string;
    result = graphql(query)
    json = JSON3.read(result.Data)
    data = json.data
    DataFrame(created = created, count = getproperty.(values(data), :repositoryCount))
end
"""
    query_intervals(created::AbstractVector{<:AbstractVector{Interval{ZonedDateTime}}})::DataFrame

Returns a 
"""
function query_intervals(created::Vector{Vector{Interval{DateTime,Closed,Open}}})
    output = DataFrame()
    graphqlremaining =
        ( fetch(@spawnat(
            w,
            (proc = w,
             remaining = GHOST.PARALLELENABLER.pat.limits.graphql.remaining,
             resetat = GHOST.PARALLELENABLER.pat.limits.graphql.reset)
            )) for w in workers()
        ) |>
        DataFrame
    maptovalidprocs = sort!(graphqlremaining, (order(2, rev = true), 3))[!,1][1:min(length(READY.x), length(created))] .- 1
    for w in maptovalidprocs
        READY.x[w] = remotecall(GHOST.query_intervals, w + 1, popfirst!(created))
    end
    while !isempty(created)
        # local w
        w = findfirst(isready, @view(READY.x[maptovalidprocs]))
        if isnothing(w)
            sleep(3)
        else
            append!(output, fetch(READY.x[maptovalidprocs][w]))
            READY.x[maptovalidprocs[w]] = remotecall(GHOST.query_intervals, maptovalidprocs[w] + 1, popfirst!(created))
        end
    end
    while any(!isready, READY.x)
        sleep(3)
    end
    for f in @view(READY.x[maptovalidprocs][isready.(READY.x[maptovalidprocs])])
        append!(output, fetch(f))
    end
    sort!(output)
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
format_tsrange(obj::Interval{DateTime}) = replace(string(obj), " .." => ",")
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
function queries(spdx::AbstractString)
    # spdx = "mit"
    # schema = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))"
    @unpack conn, schema = PARALLELENABLER
    @everywhere GHOST.PARALLELENABLER.spdx = $spdx
    calendaryear = parse(Int, schema[end - 3:end])
    created = vcat(floor(GH_FIRST_REPO_TS, Day),
                   DateTime("2009-01-01"):Month(6):DateTime("2010-01-01"),
                   DateTime("2010-01-01"):Month(3):DateTime("2011-01-01"),
                   DateTime("2011-01-01"):Month(2):DateTime("2012-01-01"),
                   DateTime("2012-01-01"):Month(1):DateTime("2013-01-01"),
                   DateTime("2013-01-01"):Week(1):DateTime("2013-12-30"),
                   DateTime("2013-12-30"):Day(1):DateTime(floor(now(utc_tz), Year), UTC)) |>
        unique
    created = [ Interval(start, stop, true, false) for (start, stop) in zip(@view(created[1:end - 1]), @view(created[2:end])) ]
    created = [ created[start:stop] for (start, stop) in zip(1:185:length(created), vcat((0:185:length(created))[2:end], length(created))) ]
    data = GHOST.query_intervals(created)
    data = GHOST.prune(data)
    data = reduce(vcat, cleanintervals(row) for row in eachrow(data))
    toreplace = ismissing.(data.count)
    created = data.created[toreplace]
    while !isempty(created)
        created = [ created[start:stop] for (start, stop) in zip(1:185:length(created), vcat((0:185:length(created))[2:end], length(created))) ]
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
    sort!(data, :created)
    execute(conn, "BEGIN;")
    load!(data[!,[:spdx,:created,:count]],
          conn,
          """
          INSERT INTO $schema.queries (spdx, created, count) VALUES ($(join(("\$$i" for i in 1:3), ',')))
          ON CONFLICT ON CONSTRAINT nonoverlappingqueries DO NOTHING;
          """,
          )
    execute(conn, "COMMIT;")
    nothing
end
"""
    find_repo_count_for_intervals(spdx::AbstractString, created::AbstractVector{<:Interval{DateTime}})
"""
function find_repo_count_for_intervals(spdx::AbstractString, created::AbstractVector{<:Interval{DateTime}})
    repositoryCount = zeros(UInt32, length(created))
    indices = range(firstindex(created), lastindex(created), step = 286)
    for idx₀ in indices
        vals = idx₀:min(idx₀ + step(indices) - 1, lastindex(created))
        subsquery = join([ string("_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$spdx created:",
                                  format(created[idx].first, "yyyy-mm-ddTHH:MM:SS+00"),
                                  "..",
                                  format(created[idx].last, "yyyy-mm-ddTHH:MM:SS+00"),
                                  "\",type:REPOSITORY){...A}") for idx in vals
                         ]);
        query = "fragment A on SearchResultItemConnection{repositoryCount} query Search{$subsquery}" |>
            (obj -> replace(obj, r"\s+" => " ")) |>
            strip |>
            string;
        try
            sleep(0.75)
            result = graphql(query)
            json = JSON3.read(result.Data)
            repositoryCount[vals] .= getproperty.(values(json.data), :repositoryCount)
        catch err
            println(vals)
            println(result)
            println(err)
        end
    end
    data = DataFrame(created = created, count = repositoryCount)
    pruned = prune(data)
    cleaned_prune = reduce(vcat, cleanintervals(row) for row in eachrow(pruned))
end
"""
    fill_missing_intervals(spdx::AbstractString, data::AbstractDataFrame)
"""
function fill_missing_intervals(spdx::AbstractString, data::AbstractDataFrame)
    new_data = find_repo_count_for_intervals(spdx, data.created[ismissing.(data.count)])
    new_data = join(data, new_data, on = :created, makeunique = true)
    new_data[!,:count] .= coalesce.(new_data.count_1, new_data.count)
    pruned = prune(new_data[!,[:created, :count]])
    cleaned_prune = reduce(vcat, cleanintervals(row) for row in eachrow(pruned))
end
"""
    find_queries(spdx::AbstractString)
"""
function find_queries(spdx::AbstractString)
    created = vcat(DateTime("2009-01-01") - GH_FIRST_REPO_TS,
                   fill(Month(6), 2),
                   fill(Month(4), 3),
                   fill(Month(2), 6),
                   fill(Month(1), 12),
                   fill(Day(5), 73))
    created = vcat(GH_FIRST_REPO_TS, GH_FIRST_REPO_TS .+ cumsum(created))
    created = vcat(created, created[end]:Day(1):DateTime(year(floor(now(utc_tz), Year))))
    created = Interval.(created[begin:end - 1], created[nextind(created, firstindex(created)):end], true, false)
    data = find_repo_count_for_intervals(spdx, created)
    while any(ismissing, data.count)
        data = fill_missing_intervals(spdx, data)
    end
    data[!,:spdx] .= spdx
    data[!,[:spdx, :created, :count]]
end
