"""
    OSSGH

This is a module for collecting GitHub data about open source repositories and contributors.
"""
module OSSGH
using HTTP: Response, request
using Cascadia: nodeText, parsehtml, Selector
using ConfParser: ConfParse, parse_conf!, retrieve
using Dates: unix2datetime, DateTime, now, canonicalize, CompoundPeriod, DateFormat, format, today
using Diana: Client, GraphQLClient
using JSON3: JSON3
using Tables: rowtable
using TimeZones: ZonedDateTime, TimeZone
using LibPQ: Connection, execute, prepare
using Parameters: @unpack
import Base: isless, show, summary
    
for (root, dirs, files) ∈ walkdir(joinpath(@__DIR__))
    for dir ∈ dirs
        files = readdir(joinpath(root, dir))
        for file ∈ files
            include(joinpath(root, dir, file))
            println(joinpath(root, dir, file))
        end
    end
end

# include(joinpath(@__DIR__, "BaseUtils.jl"))
# include(joinpath(@__DIR__, "Licenses.jl"))

export
    setup!,
    load_licenses,
    load_queries,
    load_repos,
    load_commits
end
