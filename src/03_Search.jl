"""
    Search

Module for performing the repository search.
"""
module Search
using ..BaseUtils: Opt, graphql
using Dates: DateTime, now, Year, Second, CompoundPeriod
using HTTP: request
using JSON3: JSON3
using LibPQ: Connection, Statement, execute, prepare
using Parameters: @unpack
"""
    search(opt::Opt,
           spdx::AbstractString,
           since::DateTime,
           until::DateTime)
    
Uploads the repository queries.

# Example

```julia-repl
julia> data = execute(opt.conn, "SELECT spdx FROM \$(opt.schema).licenses ORDER BY spdx DESC LIMIT 1;") |>
              rowtable;

julia> foreach(row -> search(opt, row...), data)

```
"""
function search(opt::Opt,
                spdx::AbstractString,
                since::DateTime = DateTime("2007-10-29T14:37:16"),
                until::DateTime = floor(now(), Year),
                total::Union{Missing,Integer} = missing,
                insert_stmt::Union{Missing,Statement} = missing)
    @unpack conn, pat, schema = opt
    if ismissing(insert_stmt)
        insert_stmt = prepare(conn,
                              """INSERT INTO $schema.spdx_queries VALUES(\$1, \$2, \$3, \$4, \$5)
                                 ON CONFLICT ON CONSTRAINT spdx_query DO NOTHING;
                              """)
    end
    if ismissing(total)
        result = graphql(pat,
                         "Search",
                         Dict("license_created" => """is:public fork:false mirror:false archived:false
                                                      license:$spdx
                                                      created:$since..$until
                                                   """))
        json = JSON3.read(result.Data)
        total = json.data.search.repositoryCount
    end
    step_value = ceil((until - since) ÷ ceil(Int, total / 1_000), Second)
    current_since = since
    current_until = min(since + step_value, until)
    while total > 0
        result = graphql(pat,
                         "Search",
                         Dict("license_created" => """is:public fork:false mirror:false archived:false
                                                      license:$spdx
                                                      created:$current_since..$current_until
                                                   """))
        as_of = DateTime(first(x[2] for x ∈ values(result.Info.headers) if x[1] == "Date")[1:end - 4],
                         "e, dd u Y HH:MM:SS")
        json = JSON3.read(result.Data)
        current_total = json.data.search.repositoryCount
        if current_total ≤ 1_000
            current_status = iszero(current_total) ? "Done" : "Initiated"
            execute(insert_stmt, (spdx, "[$current_since, $current_until)", current_total, current_status, as_of))
        else
            search(opt, spdx, current_since, current_until, current_total, insert_stmt)
            step_value = ceil((until - current_until) ÷ ceil(Int, (total - current_total) / 1_000), Second)
        end
        current_since = current_until
        current_until = min(current_since + step_value, until)
        total -= current_total
    end
end
end