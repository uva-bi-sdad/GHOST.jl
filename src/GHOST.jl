"""
    GHOST

This is a module for collecting GitHub data about open source repositories and contributors.
"""
module GHOST

# using Base.Iterators: flatten
using DataFrames: DataFrames, AbstractDataFrame, DataFrame, order, groupby
using Diana: Diana, HTTP, Client, GraphQLClient, Result,
             # HTTP
             HTTP.request, HTTP.ExceptionRequest.StatusError
using Distributed: addprocs, @everywhere, fetch, @spawnat, workers, remotecall, remotecall_eval, Future, @sync, @distributed
using JSON3: JSON3
using LibPQ: LibPQ, Connection, execute, load!,
             # Intervals
             Intervals, Interval, superset, Closed, Open,
             # TimeZones
             TimeZones, TimeZone, ZonedDateTime, UTC, TimeZones.utc_tz,
             # Dates
             Dates, DateTime, Dates.CompoundPeriod, Dates.canonicalize, Second, Year, Month, Week, Dates.format, now, unix2datetime, Day, Date, Hour, year, Minute,
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
    GH_FIRST_REPO_TS::DateTime = 2007-10-29T14:37:16
        
Timestamp when the earliest public GitHub repository was created (id: "MDEwOlJlcG9zaXRvcnkx", nameWithOwner: "mojombo/grit")
"""
const GH_FIRST_REPO_TS = DateTime("2007-10-29T14:37:16")

# for (root, dirs, files) in walkdir(joinpath(@__DIR__, "src"))
for (root, dirs, files) in walkdir(joinpath(@__DIR__))
    for file in files
        if occursin("assets", root) || isequal("GHOST.jl", file)
        else
            include(joinpath(root, file))
        end
    end
end

mutable struct ParallelEnabler
    pat::GitHubPersonalAccessToken
    conn::Connection
    schema::String
    spdx::String
    ParallelEnabler() = new()
end

const READY = Ref(Future[])
const PARALLELENABLER = ParallelEnabler()

export GitHubPersonalAccessToken, queries, setup, setup_parallel,
       Connection, execute, DataFrame, Interval, ZonedDateTime, utc_tz,
       generate_search_query, graphql, JSON3, @sync, @distributed,
       licenses, find_queries, find_repos, query_commits_simple, query_commits,
       now, CompoundPeriod, canonicalize,
       groupby,
       @unpack
end
