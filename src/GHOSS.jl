"""
    GHOSS

This is a module for collecting GitHub data about open source repositories and contributors.
"""
module GHOSS
for (root, dirs, files) in walkdir(joinpath(@__DIR__))
    for file in files
        isequal("GHOSS.jl", file) || include(joinpath(root, file))
    end
end
using ..BaseUtils: Opt, setup
using ..Licenses: licenses
using ..Search: search
using ..Repos: repos
using ..Commits: commits, repo_exists

using ..BaseUtils: GITHUB_REST_ENDPOINT, GITHUB_GRAPHQL_ENDPOINT, GITHUB_API_QUERY, GitHubPersonalAccessToken
using ..Licenses: licenses
using ..Search: search
using ..Repos: repos
using ..Commits: commits

using LibPQ: execute, Dates.DateTime, Intervals.Interval
using Tables: rowtable
export Opt, setup, licenses, search, repos, commits, execute, DateTime, Interval, rowtable,
       GITHUB_REST_ENDPOINT, GITHUB_GRAPHQL_ENDPOINT, GITHUB_API_QUERY, GitHubPersonalAccessToken,
       repo_exists
end
