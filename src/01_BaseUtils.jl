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
const GITHUB_API_QUERY =
    """
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

Return JSON of the GraphQL query.
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
    setup(opt::Opt)

Sets up your PostgreSQL database for the project based on the options passed through the `Opt`.

# Example

```julia-repl
julia> setup(opt)

```
"""
function setup(opt::Opt)
    @unpack conn, schema, role = opt
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
                       created_query tsrange NOT NULL,
                       count integer NOT NULL,
                       status text NOT NULL,
                       as_of timestamp without time zone NOT NULL,
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
                    CREATE INDEX spdx_queries_interval ON $schema.spdx_queries (created_query);
                    CREATE INDEX spdx_queries_spdx ON $schema.spdx_queries (spdx);
                    CREATE INDEX spdx_queries_spdx_interval ON $schema.spdx_queries (spdx, created_query);
                    CREATE INDEX spdx_queries_status ON $schema.spdx_queries (status);
                 """)
    execute(conn, """CREATE TABLE IF NOT EXISTS $schema.repos (
                       slug text NOT NULL,
                       spdx text NOT NULL,
                       created timestamp without time zone NOT NULL,
                       as_of timestamp without time zone NOT NULL,
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
                     CREATE INDEX repos_spdx_interval ON $schema.repos (spdx, created_query);
                  """)
    execute(conn, """CREATE TABLE IF NOT EXISTS $schema.commits (
                       slug text NOT NULL,
                       hash text NOT NULL,
                       committed_date timestamp without time zone NOT NULL,
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
