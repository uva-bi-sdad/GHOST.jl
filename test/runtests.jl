using Test, Documenter, OSSGH
using OSSGH.BaseUtils: Opt, setup
using OSSGH: Licenses.upload_licenses
using OSSGH: execute
DocMeta.setdocmeta!(OSSGH, :DocTestSetup, :(using OSSGH), recursive = true)

ENV["POSTGIS_HOST"] = get(ENV, "POSTGIS_HOST", "host.docker.internal")
ENV["POSTGIS_PORT"] = get(ENV, "POSTGIS_PORT", "5432")
ENV["GITHUB_TOKEN"] = get(ENV, "GITHUB_TOKEN", "edc41012de6017200512a98ddd0fb5464d4d6f9d")

obj = Opt("Nosferican",
          ENV["GITHUB_TOKEN"],
          db_usr = "postgres",
          db_pwd = "postgres",
          host = ENV["POSTGIS_HOST"],
          port = parse(Int, ENV["POSTGIS_PORT"]),
          dbname = "postgres",
          schema = "github_api_2007_",
          role = "ncses_oss"
          )
execute(obj.conn, "DROP SCHEMA IF EXISTS $(obj.schema) CASCADE;")

@testset "Set Up" begin
    @test isa(setup(obj), Nothing)
end
@testset "Licenses" begin
    @test isa(upload_licenses(obj), Nothing)
end
