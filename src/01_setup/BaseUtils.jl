"""
    BaseUtils

Module that provides the base utilities for OSSGH.
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
    GITHUB_REST_ENDPOINT
        
GitHub RESTful API v3 root endpoint.
"""
const GITHUB_REST_ENDPOINT = "https://api.github.com"
"""
    GITHUB_GRAPHQL_ENDPOINT
        
GitHub GraphQL API v4 endpoint.
"""
const GITHUB_GRAPHQL_ENDPOINT = "https://api.github.com/graphql"
"""
    GITHUB_API_QUERY

GitHub GraphQL query.
"""
const GITHUB_API_QUERY =
"""
query Search(\$license_created: String!) {
    search(query: \$license_created, type: REPOSITORY) {
        repositoryCount
    }
}

query Commits(\$owner: String!, \$name: String!, \$until: GitTimestamp!) {
    repository(owner: \$owner, name: \$name) {
        defaultBranchRef {
            target {
                ... on Commit {
                    history(first: 15, until: \$until) {
                        ...CommitData
                    }
                }
            }
        }
    }
}

query CommitsContinue(\$owner: String!, \$name: String!, \$until: GitTimestamp!, \$cursor: String!) {
    repository(owner: \$owner, name: \$name) {
        defaultBranchRef {
            target {
                ... on Commit {
                    history(first: 15, until: \$until, after: \$cursor) {
                        ...CommitData
                    }
                }
            }
        }
    }
}

query CommitsVerify(\$owner: String!, \$name: String!, \$until: GitTimestamp!) {
    repository(owner: \$owner, name: \$name) {
        defaultBranchRef {
            target {
                ... on Commit {
                    history(until: \$until) {
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
"""
mutable struct Limits
    remaining::Int
    reset::DateTime
end
"""
    GitHubPersonalAccessToken

A GitHub Personal Access Token
"""
struct GitHubPersonalAccessToken
    login::String
    token::String
    client::Client
    limits::Limits
    function GitHubPersonalAccessToken(login::AbstractString, token::AbstractString)
        response = request("GET",
                           "$GITHUB_REST_ENDPOINT/rate_limit",
                           ["Accept" => "application/vnd.github.v3+json",
                            "User-Agent" => login,
                            "Authorization" => "token $token"])
        client = GraphQLClient(GITHUB_GRAPHQL_ENDPOINT,
                               auth = "bearer $token",
                               headers = Dict("User-Agent" => login))
        json = JSON3.read(response.body).resources.graphql
        limits = Limits(json.remaining, unix2datetime(json.reset))
        new(login, token, client, limits)
    end
end
summary(io::IO, obj::GitHubPersonalAccessToken) = println(io, "GitHub Personal Access Token")
function show(io::IO, obj::GitHubPersonalAccessToken)
    print(io, summary(obj))
    println(io, "  login: $(obj.login)")
    println(io, "  remaining: $(obj.limits.remaining)")
    println(io, "  reset: $(obj.limits.reset)")
end
function update!(obj::GitHubPersonalAccessToken)
    response = request("GET",
                       "$GITHUB_REST_ENDPOINT/rate_limit",
                       ["Accept" => "application/vnd.github.v3+json",
                        "User-Agent" => login,
                        "Authorization" => "token $token"])
    json = JSON3.read(response.body).resources.graphql
    obj.limits.remaining = json.remaining
    obj.limits.reset = unix2datetime(json.reset)
    obj
end
"""
    graphql(obj::GitHubPersonalAccessToken,
            operationName::AbstractString,
            vars::Dict{String})

Return JSON 
"""
function graphql(obj::GitHubPersonalAccessToken,
                 operationName::AbstractString,
                 vars::Dict{String})
    if iszero(obj.limits.remaining)
        sleep(max(obj.limits.reset - now(), 0))
        obj.limits.remaining = 5_000
    end
    result = obj.client.Query(GITHUB_API_QUERY,
                              operationName = operationName,
                              vars = vars)
    obj.limits.remaining = parse(Int, result.Info["X-RateLimit-Remaining"])
    obj.limits.reset = unix2datetime(parse(Int, result.Info["X-RateLimit-Reset"]))
    json = JSON3.read(result.Data)
    if haskey(json, :errors)
        # if any(x.type == "NOT_FOUND" for x ∈ json.errors)
        # end
    end
end
"""
    OPT(login::AbstractString,
        token::AbstractString;
        db_usr::AbstractString = "postgres",
        db_pwd::AbstractString = "postgres",
        host::AbstractString = "postgres",
        port::Integer = 5432,
        dbname::AbstractString = "postgres",
        schema::AbstractString = "github_api_2007_",
        role::AbstractString = "postgres")

Structure for passing arguments to functions.
"""
struct Opt
    conn::Connection
    schema::String
    role::String
    pat::GitHubPersonalAccessToken
    function Opt(login::AbstractString,
                 token::AbstractString;
                 db_usr::AbstractString = "postgres",
                 db_pwd::AbstractString = "postgres",
                 schema::AbstractString = "github_api_2007_",
                 role::AbstractString = "postgres",
                 host::AbstractString = "postgres",
                 port::Integer = 5432,
                 dbname::AbstractString = "postgres")
        conn = Connection("host = $host port = $port dbname = $dbname user = $db_usr password = $db_pwd")
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
    setup(obj::Opt)

Sets up your PostgreSQL database for the project.
The default role value will be the connection's `current_user` if empty.
"""
function setup(obj::Opt)
    @unpack conn, schema, role = obj
    getproperty.(execute(conn, "SELECT COUNT(*) = 1 AS check FROM information_schema.schemata WHERE schema_name = '$schema';"),
                 :check)[1] && return
    getproperty.(execute(conn, "SELECT COUNT(*) = 1 AS check FROM pg_roles WHERE rolname = '$role';"),
                 :check)[1] || execute(conn, "CREATE ROLE $role;")
    execute(conn, "CREATE SCHEMA IF NOT EXISTS $schema AUTHORIZATION $role;")
    execute(conn, """CREATE TABLE IF NOT EXISTS $schema.licenses (
                       name text NOT NULL,
                       spdx text NOT NULL,
                       CONSTRAINT licenses_pkey PRIMARY KEY (spdx)
                     );
                     ALTER TABLE $schema.licenses OWNER TO $role;
                  """)
    execute(conn, """CREATE TABLE IF NOT EXISTS $schema.spdx_queries (
                       spdx text NOT NULL,
                       dtinterval text NOT NULL,
                       count integer NOT NULL,
                       status text NOT NULL,
                       as_of timestamp with time zone NOT NULL,
                       CONSTRAINT spdx_query UNIQUE (spdx, dtinterval)
                     );
                     ALTER TABLE $schema.spdx_queries OWNER TO $role;
                     COMMENT ON TABLE $schema.spdx_queries
                      IS 'This table is a tracker for queries';
                    COMMENT ON COLUMN $schema.spdx_queries.spdx
                      IS 'The SPDX license ID';
                    COMMENT ON COLUMN $schema.spdx_queries.dtinterval
                      IS 'The time interval for the query';
                    COMMENT ON COLUMN $schema.spdx_queries.count
                      IS 'How many results for the query';
                    COMMENT ON COLUMN $schema.spdx_queries.status
                      IS 'Status of the query';
                    COMMENT ON CONSTRAINT spdx_query ON $schema.spdx_queries
                      IS 'No duplicate for queries';
                    CREATE INDEX spdx_queries_interval ON $schema.spdx_queries (dtinterval);
                    CREATE INDEX spdx_queries_spdx ON $schema.spdx_queries (spdx);
                    CREATE INDEX spdx_queries_spdx_interval ON $schema.spdx_queries (spdx, dtinterval);
                    CREATE INDEX spdx_queries_status ON $schema.spdx_queries (status);
                 """)
    execute(conn, """CREATE TABLE IF NOT EXISTS $schema.repos (
                       slug text NOT NULL,
                       id integer NOT NULL,
                       spdx text NOT NULL,
                       created timestamp without time zone NOT NULL,
                       as_of timestamp without time zone NOT NULL,
                       dtinterval text NOT NULL,
                       status text NOT NULL,
                       CONSTRAINT repos_pkey PRIMARY KEY (slug)
                     );
                     ALTER TABLE $schema.repos OWNER TO $role;
                     COMMENT ON TABLE $schema.repos IS 'Basic information about the repositories';
                     CREATE INDEX repos_interval ON $schema.repos (dtinterval);
                     CREATE INDEX repos_spdx ON $schema.repos (spdx);
                     CREATE INDEX repos_spdx_interval ON $schema.repos (spdx, dtinterval);
                  """)
    execute(conn, """CREATE TABLE IF NOT EXISTS $schema.commits (
                       slug text NOT NULL,
                       hash text NOT NULL,
                       datetime timestamp without time zone NOT NULL,
                       login text,
                       additions integer NOT NULL,
                       deletions integer NOT NULL,
                       as_of timestamp without time zone NOT NULL,
                       CONSTRAINT commits_pkey PRIMARY KEY (slug, hash)
                     );
                     ALTER TABLE $schema.commits OWNER TO $role;
                     CREATE INDEX commits_login ON $schema.commits (login);
                 """)
    nothing
end
end
