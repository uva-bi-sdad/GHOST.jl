"""
    GHOSS

This is a module for collecting GitHub data about open source repositories and contributors.
"""
module GHOSS

using Base.Iterators: flatten
using DataFrames: DataFrames, AbstractDataFrame, DataFrame, order
using Diana: Diana, HTTP, Client, GraphQLClient,
             # HTTP
             HTTP.request
using Distributed: addprocs, @everywhere, fetch, @spawnat, workers, remotecall, remotecall_eval, Future, @sync, @distributed
using JSON3: JSON3
using LibPQ: LibPQ, Connection, execute, load!,
             # Intervals
             Intervals, Interval, superset,
             # TimeZones
             TimeZones, TimeZone, ZonedDateTime, TimeZones.utc_tz,
             # Dates
             Dates, DateTime, Second, Year, Dates.format, now, unix2datetime, Day, Date, Hour, year, Minute,
             # Tables
             Tables, rowtable
using Parameters: Parameters, @unpack
import Base: show, summary, isless
# Constants
"""
    GITHUB_REST_ENDPOINT::String = "https://api.github.com"
        
GitHub API v3 RESTful root endpoint.
"""
const GITHUB_REST_ENDPOINT = "https://api.github.com"
"""
    GITHUB_GRAPHQL_ENDPOINT::String = "https://api.github.com/graphql"
        
GitHub API v4 GraphQL API endpoint.
"""
const GITHUB_GRAPHQL_ENDPOINT = "https://api.github.com/graphql"
"""
    GH_FIRST_REPO_TS::ZonedDateTime = 2007-10-29T14:37:16+00:00
        
Timestamp when the earliest public GitHub repository was created (id: "MDEwOlJlcG9zaXRvcnkx", nameWithOwner: "mojombo/grit")
"""
const GH_FIRST_REPO_TS = ZonedDateTime("2007-10-29T14:37:16+00", "yyyy-mm-ddTHH:MM:SSz")

# for (root, dirs, files) in walkdir(joinpath(@__DIR__, "src"))
for (root, dirs, files) in walkdir(joinpath(@__DIR__))
    for file in files
        if occursin("assets", root) || isequal("GHOSS.jl", file)
        else
            include(joinpath(root, file))
        end
    end
end

mutable struct ParallelEnabler
    pat::GitHubPersonalAccessToken
    spdx::String
    ParallelEnabler() = new()
    function ParallelEnabler(pat::GitHubPersonalAccessToken)
        output = new()
        output.pat = pat
        output
    end
end

const READY = Ref(Future[])
const PARALLELENABLER = Ref(ParallelEnabler())

function setup_parallel(pats::AbstractVector{GitHubPersonalAccessToken})
    npats = length(pats)
    addprocs(npats, exeflags = `--proj`)
    remotecall_eval(Main, workers(), :(using GHOSS))
    GHOSS.READY.x = Vector{Future}(undef, npats)
    for proc ∈ workers()
        GHOSS.READY.x[proc - 1] = GHOSS.@spawnat proc nothing
        pat = pats[proc - 1]
        expr = :(GHOSS.PARALLELENABLER.x.pat = $pat;)
        remotecall_eval(Main, proc, expr)
    end
end

export GitHubPersonalAccessToken, queries, setup_parallel
end
