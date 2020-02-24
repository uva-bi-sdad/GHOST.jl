"""
    BaseUtils

Module that provides the base utilities for GHOSS.
"""
module BaseUtils
using Dates: DateTime, unix2datetime
using Diana: Client, GraphQLClient
using JSON3: JSON3
using HTTP: request
using LibPQ: Connection, execute
using Parameters: @unpack
import Base: show, summary
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
    GITHUB_API_QUERY

GitHub GraphQL query.
"""
const GITHUB_API_QUERY = """
                         query Search(\$license_created: String!) {
                             search(query: \$license_created, type: REPOSITORY) {
                                 repositoryCount
                             }
                         }

                         query Repo(\$license_created: String!) {
                             search(query: \$license_created, type: REPOSITORY, first: 100) {
                                 ...SearchLogic
                             }
                         }

                         query RepoContinue(\$license_created: String!, \$cursor: String!) {
                             search(query: \$license_created, type: REPOSITORY, first: 100, after: \$cursor) {
                                 ...SearchLogic
                             }
                         }

                         fragment SearchLogic on SearchResultItemConnection {
                             pageInfo {
                                 endCursor
                             }
                             nodes {
                                 ... on Repository {
                                     nameWithOwner
                                     createdAt
                                 }
                             }
                         }

                         query RepoVerify(\$license_created: String!) {
                             search(query: \$license_created, type: REPOSITORY) {
                                 repositoryCount
                             }
                         }

                         query Commits(\$owner: String!, \$name: String!, \$since: GitTimestamp!, \$until: GitTimestamp!, \$first: Int!) {
                             repository(owner: \$owner, name: \$name) {
                                 defaultBranchRef {
                                     target {
                                         ... on Commit {
                                             history(since: \$since, until: \$until, first: \$first) {
                                                 ...CommitData
                                             }
                                         }
                                     }
                                 }
                             }
                         }

                         query CommitsContinue(\$owner: String!, \$name: String!, \$since: GitTimestamp!, \$until: GitTimestamp!, \$cursor: String!, \$first: Int!) {
                             repository(owner: \$owner, name: \$name) {
                                 defaultBranchRef {
                                     target {
                                         ... on Commit {
                                             history(since: \$since, until: \$until, after: \$cursor, first: \$first) {
                                                 ...CommitData
                                             }
                                         }
                                     }
                                 }
                             }
                         }

                         query CommitsVerify(\$owner: String!, \$name: String!, \$since: GitTimestamp!, \$until: GitTimestamp!) {
                             repository(owner: \$owner, name: \$name) {
                                 defaultBranchRef {
                                     target {
                                         ... on Commit {
                                             history(since: \$since, until: \$until) {
                                                 totalCount
                                             }
                                         }
                                     }
                                 }
                             }
                         }

                         fragment CommitData on CommitHistoryConnection {
                             pageInfo {
                                 endCursor
                                 hasNextPage
                             }
                             nodes {
                                 author {
                                     user {
                                         login
                                     }
                                 }
                                 oid
                                 committedDate
                                 additions
                                 deletions
                             }
                         }
                         """
# Structs
"""
    Limits

GitHub API v4 GraphQL limits for a PersonalAccessToken.

It includes how many remaining queries are available for the current time period and when it resets.

# Fields
- `remaining::Int`
- `reset::DateTime`
"""
mutable struct Limits
    remaining::Int
    reset::DateTime
end
"""
    GitHubPersonalAccessToken(login::AbstractString,
                              token::AbstractString
                              )::GitHubPersonalAccessToken

A GitHub Personal Access Token

# Fields

- `login::String`
- `token::String`
- `client::Client`
- `limits::Limits`
"""
struct GitHubPersonalAccessToken
    login::String
    token::String
    client::Client
    limits::Limits
    function GitHubPersonalAccessToken(login::AbstractString, token::AbstractString)
        response = request(
            "GET",
            "$GITHUB_REST_ENDPOINT/rate_limit",
            [
                "Accept" => "application/vnd.github.v3+json",
                "User-Agent" => login,
                "Authorization" => "token $token",
            ],
        )
        client = GraphQLClient(
            GITHUB_GRAPHQL_ENDPOINT,
            auth = "bearer $token",
            headers = Dict("User-Agent" => login),
        )
        json = JSON3.read(response.body).resources.graphql
        limits = Limits(json.remaining, unix2datetime(json.reset))
        new(login, token, client, limits)
    end
end
summary(io::IO, obj::GitHubPersonalAccessToken) =
    println(io, "GitHub Personal Access Token")
function show(io::IO, obj::GitHubPersonalAccessToken)
    print(io, summary(obj))
    println(io, "  login: $(obj.login)")
    println(io, "  remaining: $(obj.limits.remaining)")
    println(io, "  reset: $(obj.limits.reset)")
end
function update!(obj::GitHubPersonalAccessToken)
    response = request(
        "GET",
        "$GITHUB_REST_ENDPOINT/rate_limit",
        [
            "Accept" => "application/vnd.github.v3+json",
            "User-Agent" => login,
            "Authorization" => "token $token",
        ],
    )
    json = JSON3.read(response.body).resources.graphql
    obj.limits.remaining = json.remaining
    obj.limits.reset = unix2datetime(json.reset)
    obj
end
"""
    graphql(obj::GitHubPersonalAccessToken,
            operationName::AbstractString,
            vars::Dict{String})

Return JSON of the GraphQL query.
"""
function graphql(
    obj::GitHubPersonalAccessToken,
    operationName::AbstractString,
    vars::Dict{String},
)
    if iszero(obj.limits.remaining)
        sleep(max(obj.limits.reset - now(), 0))
        obj.limits.remaining = 5_000
    end
    result = try
        obj.client.Query(GITHUB_API_QUERY, operationName = operationName, vars = vars)
    catch err
        if isone(obj.limits.remaining)
            sleep(max(obj.limits.reset - now(), 0))
            obj.limits.remaining = 5_000
        else
            sleep(0.5)
            println("$vars: graphql")
        end
        try
            obj.client.Query(GITHUB_API_QUERY, operationName = operationName, vars = vars)
        catch err
            return err
        end
    end
    obj.limits.remaining = parse(Int, result.Info["X-RateLimit-Remaining"])
    obj.limits.reset = unix2datetime(parse(Int, result.Info["X-RateLimit-Reset"]))
    sleep(1)
    result
end
"""
    Opt(login::AbstractString,
        token::AbstractString;
        db_usr::AbstractString = "postgres",
        db_pwd::AbstractString = "postgres",
        host::AbstractString = "postgres",
        port::Integer = 5432,
        dbname::AbstractString = "postgres",
        schema::AbstractString = "github_api_2007_",
        role::AbstractString = "postgres"
        )::Opt

Structure for passing arguments to functions.

# Fields
- `conn::Connection`
- `schema::String`
- `role::String`
- `pat::GitHubPersonalAccessToken`

# Example
```julia-repl
julia> opt = Opt("Nosferican",
                 ENV["GITHUB_TOKEN"],
                 host = ENV["POSTGIS_HOST"],
                 port = parse(Int, ENV["POSTGIS_PORT"]));

```
"""
struct Opt
    conn::Connection
    schema::String
    role::String
    pat::GitHubPersonalAccessToken
    function Opt(
        login::AbstractString,
        token::AbstractString;
        db_usr::AbstractString = "postgres",
        db_pwd::AbstractString = "postgres",
        schema::AbstractString = "github_api_2007_",
        role::AbstractString = "postgres",
        host::AbstractString = "postgres",
        port::Integer = 5432,
        dbname::AbstractString = "postgres",
    )
        conn =
            Connection("host = $host port = $port dbname = $dbname user = $db_usr password = $db_pwd")
        pat = GitHubPersonalAccessToken(login, token)
        new(conn, schema, role, pat)
    end
end
summary(io::IO, obj::Opt) = println(io, "Options for functions")
function show(io::IO, obj::Opt)
    print(io, summary(obj))
    println(io, replace(replace(string(obj.conn), r"^" => "  "), r"\n[^$]" => "\n  "))
    println(io, "  Schema: $(obj.schema)")
    println(io, "  Role: $(obj.role)")
    print(io, replace(replace(string(obj.pat), r"^" => "  "), r"\n[^$]" => "\n  "))
end
"""
    setup(opt::Opt)

Sets up your PostgreSQL database for the project based on the options passed through the `Opt`.

# Example

```julia-repl
julia> setup(opt)

```
"""
function setup(opt::Opt)
    @unpack conn, schema, role = opt
    execute(conn, "CREATE EXTENSION IF NOT EXISTS btree_gist;")
    getproperty.(
        execute(
            conn,
            "SELECT COUNT(*) = 1 AS check FROM pg_roles WHERE rolname = '$role';",
        ),
        :check,
    )[1] || execute(conn, "CREATE ROLE $role;")
    execute(conn, "CREATE SCHEMA IF NOT EXISTS $schema AUTHORIZATION $role;")
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.licenses (
             name text NOT NULL,
             spdx text NOT NULL,
             CONSTRAINT licenses_pkey PRIMARY KEY (spdx)
           );
           ALTER TABLE $schema.licenses OWNER TO $role;
        """,
    )
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.spdx_queries (
             spdx text NOT NULL,
             created_query tsrange NOT NULL,
             count integer NOT NULL,
             status text NOT NULL,
             as_of timestamp with time zone NOT NULL,
             CONSTRAINT spdx_query UNIQUE (spdx, created_query)
           );
           ALTER TABLE $schema.spdx_queries OWNER TO $role;
           COMMENT ON TABLE $schema.spdx_queries
            IS 'This table is a tracker for queries';
          COMMENT ON COLUMN $schema.spdx_queries.spdx
            IS 'The SPDX license ID';
          COMMENT ON COLUMN $schema.spdx_queries.created_query
            IS 'The time interval for the query';
          COMMENT ON COLUMN $schema.spdx_queries.count
            IS 'How many results for the query';
          COMMENT ON COLUMN $schema.spdx_queries.status
            IS 'Status of the query';
          COMMENT ON CONSTRAINT spdx_query ON $schema.spdx_queries
            IS 'No duplicate for queries';
          CREATE INDEX spdx_queries_interval ON $schema.spdx_queries USING GIST (created_query);
          CREATE INDEX spdx_queries_spdx ON $schema.spdx_queries (spdx);
          CREATE INDEX spdx_queries_spdx_interval ON $schema.spdx_queries USING GIST (spdx, created_query);
          CREATE INDEX spdx_queries_status ON $schema.spdx_queries (status);
       """,
    )
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.repos (
             slug text NOT NULL,
             spdx text NOT NULL,
             created timestamp with time zone NOT NULL,
             as_of timestamp with time zone NOT NULL,
             created_query tsrange NOT NULL,
             status text NOT NULL,
             CONSTRAINT repos_pkey PRIMARY KEY (slug)
           );
           ALTER TABLE $schema.repos OWNER TO $role;
           COMMENT ON TABLE $schema.repos IS 'Basic information about the repositories';
           COMMENT ON COLUMN $schema.repos.created
            IS 'When was the repository created';
           COMMENT ON COLUMN $schema.repos.created_query
            IS 'The time interval for the query';
           CREATE INDEX repos_created ON $schema.repos (created);
           CREATE INDEX repos_spdx ON $schema.repos (spdx);
           CREATE INDEX repos_spdx_interval ON $schema.repos USING GIST (spdx, created_query);
        """,
    )
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.commits (
             slug text NOT NULL,
             hash text NOT NULL,
             committed_date timestamp with time zone NOT NULL,
             login text,
             additions integer NOT NULL,
             deletions integer NOT NULL,
             as_of timestamp with time zone NOT NULL,
             CONSTRAINT commits_pkey PRIMARY KEY (slug, hash)
           );
           ALTER TABLE $schema.commits OWNER TO $role;
           CREATE INDEX commits_login ON $schema.commits (login);
       """,
    )
    nothing
end
abstract type GH_ERROR <: Exception end
struct NOT_FOUND <: GH_ERROR
    slug::String
end
struct TIMEOUT <: GH_ERROR
    slug::String
    vars::Dict{String}
end
struct SERVICE_UNAVAILABLE <: GH_ERROR
    slug::String
end
struct UNKNOWN{T} <: GH_ERROR
    er::T
    slug::String
    vars::Dict{String}
end
function gh_errors(result, pat, operationName, vars)
    json = JSON3.read(result.Data)
    if haskey(json, :errors)
        er = json.errors[1]
        slug = "$(vars["owner"])/$(vars["name"])"
        if startswith(er.message, "Something went wrong while executing your query.")
            new_bulk_size = vars["first"] ÷ 2
            while true
                result =
                    graphql(pat, operationName, merge(vars, Dict("first" => new_bulk_size)))
                json = JSON3.read(result.Data)
                haskey(json, :errors) || break
                if new_bulk_size == 1
                    println("$slug: TIMEOUT")
                    TIMEOUT(slug, vars)
                end
                new_bulk_size ÷= 2
            end
        elseif er.type == "NOT_FOUND"
            return NOT_FOUND(slug)
        elseif er.type == "SERVICE_UNAVAILABLE"
            return SERVICE_UNAVAILABLE(slug)
        else
            println("$slug: UNKNOWN")
            UNKNOWN(er, slug, vars)
        end
    end
    json
end
gh_errors(result::Exception, pat, operationName, vars) = result
handle_errors(opt::Opt, obj) = false
function handle_errors(opt::Opt, obj::Exception)
    println(obj)
    true
end
function handle_errors(opt::Opt, obj::GH_ERROR)
    execute(
        opt.conn,
        "UPDATE $(opt.schema).repos SET status = '$(typeof(obj))' WHERE slug = '$(obj.slug)';",
    )
    true
end
end
