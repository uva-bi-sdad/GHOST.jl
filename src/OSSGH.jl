"""
    OSSGH

This is a module for collecting GitHub data about open source repositories and contributors.
"""
module OSSGH
for (root, dirs, files) ∈ walkdir(joinpath(@__DIR__))
    for dir ∈ dirs
        files = readdir(joinpath(root, dir))
        for file ∈ files
            include(joinpath(root, dir, file))
        end
    end
end
using .BaseUtils: Opt, setup, execute
using .Licenses: upload_licenses
export
    Opt, setup, execute,
    upload_licenses
end
