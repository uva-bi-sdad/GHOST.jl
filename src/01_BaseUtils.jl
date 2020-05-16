# Structs
"""
    Limits

GitHub API limits.

It includes how many remaining queries are available for the current time period and when it resets.

# Fields
- `limit::Int`
- `remaining::Int`
- `reset::ZonedDateTime`
"""
mutable struct Limits
    limit::Int
    remaining::Int
    reset::ZonedDateTime
end
"""
    API_Limits

GitHub API limits for a PersonalAccessToken.

# Fields
- core::Limits
- search::Limits
- graphql::Limits
"""
mutable struct API_Limits
    core::Limits
    search::Limits
    graphql::Limits
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
    limits::API_Limits
    function GitHubPersonalAccessToken(login::AbstractString, token::AbstractString)
        client = GraphQLClient(
            GITHUB_GRAPHQL_ENDPOINT,
            auth = "bearer $token",
            headers = Dict("User-Agent" => login),
        )
        # Dummy values
        limits = API_Limits(Limits(0, 0, now(TimeZone("UTC"))),
                            Limits(0, 0, now(TimeZone("UTC"))),
                            Limits(0, 0, now(TimeZone("UTC"))))
        output = new(login, token, client, limits)
        # Update dummy values for actual ones
        update!(output)
    end
end
summary(io::IO, obj::GitHubPersonalAccessToken) =
    println(io, "GitHub Personal Access Token")
function show(io::IO, obj::GitHubPersonalAccessToken)
    print(io, summary(obj))
    println(io, "  login: $(obj.login)")
    println(io, "  core remaining: $(obj.limits.core.remaining)")
    println(io, "  core reset: $(obj.limits.core.reset)")
    println(io, "  graphql remaining: $(obj.limits.graphql.remaining)")
    println(io, "  graphql reset: $(obj.limits.graphql.reset)")
end
function update!(obj::GitHubPersonalAccessToken)
    response = request(
        "GET",
        "$GITHUB_REST_ENDPOINT/rate_limit",
        [
            "Accept" => "application/vnd.github.v3+json",
            "User-Agent" => obj.login,
            "Authorization" => "token $(obj.token)",
        ],
    )
    json = JSON3.read(response.body).resources
    obj.limits.core.remaining = json.core.remaining
    obj.limits.core.reset = ZonedDateTime(unix2datetime(json.core.reset), TimeZone("UTC"))
    obj.limits.search.remaining = json.search.remaining
    obj.limits.search.reset = ZonedDateTime(unix2datetime(json.search.reset), TimeZone("UTC"))
    obj.limits.graphql.remaining = json.graphql.remaining
    obj.limits.graphql.reset = ZonedDateTime(unix2datetime(json.graphql.reset), TimeZone("UTC"))
    obj
end

"""
    graphql(obj::GitHubPersonalAccessToken,
            operationName::AbstractString,
            vars::Dict{String})

Return JSON of the GraphQL query.
"""
function graphql(
    obj::GitHubPersonalAccessToken;
    query::AbstractString,
    operationName::AbstractString,
    vars::Dict{String},
    )
    update!(obj)
    if iszero(obj.limits.graphql.remaining)
        w = obj.limits.graphql.reset - now(utc_tz)
        sleep(max(w, zero(w)))
        obj.limits.graphql.remaining = obj.limits.graphql.limit
    end
    result = try
        result = obj.client.Query(query, operationName = operationName, vars = vars)
        @assert result.Info.status == 200
        # If the cost is higher than the current remaining, it will return a 200 with the API rate limit message
        if result.Data == "{\"errors\":[{\"type\":\"RATE_LIMITED\",\"message\":\"API rate limit exceeded\"}]}"
            w = obj.limits.graphql.reset - now(utc_tz)
            sleep(max(w, zero(w)))
            result = obj.client.Query(query, operationName = operationName, vars = vars)
            @assert result.Info.status == 200
        end
        result
    catch err
        # If the query triggered an abuse behavior it will check for a retry_after
        retry_after = (x[2] for x ∈ values(err.response.headers) if x[1] == "Retry-After")
        isempty(retry_after) || sleep(parse(Int, first(retry_after)) + 1)
        # The other case is when it timeout. We try once more just in case.
        try
            obj.client.Query(query, operationName = operationName, vars = vars)
        catch err
            return err
        end
    end
    update!(obj)
    if isa(result, Exception)
        println(result)
    end
    result
end
# """
#     Opt(pats::AbstractVector{<:GitHubPersonalAccessToken},
#         db_usr::AbstractString = "postgres",
#         db_pwd::AbstractString = "postgres",
#         host::AbstractString = "postgres",
#         port::Integer = 5432,
#         dbname::AbstractString = "postgres",
#         schema::AbstractString = "github_api_2007_\$(year(floor(now(), Year) - Day(1)))",
#         role::AbstractString = "postgres"
#         )::Opt

# Structure for passing arguments to functions.

# # Fields
# - `conn::Connection`
# - `schema::String`
# - `role::String`
# - `pat::GitHubPersonalAccessToken`

# # Example
# ```julia-repl
# julia> opt = Opt("Nosferican",
#                  ENV["GITHUB_TOKEN"],
#                  host = ENV["POSTGIS_HOST"],
#                  port = parse(Int, ENV["POSTGIS_PORT"]));

# ```
# """
# struct Opt
#     conn::Connection
#     schema::String
#     pat::GitHubPersonalAccessToken
#     function Opt(conn::Connection,
#                  pat::GitHubPersonalAccessToken,
#                  schema = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))")
#         new(conn, schema, pat)
#     end
# end
# summary(io::IO, obj::Opt) = println(io, "Options for functions")
# function show(io::IO, obj::Opt)
#     print(io, summary(obj))
#     println(io, replace(replace(string(obj.conn), r"^" => "  "), r"\n[^$]" => "\n  "))
#     println(io, "  Schema: $(obj.schema)")
#     print(io, replace(replace(string(obj.pat), r"^" => "  "), r"\n[^$]" => "\n  "))
# end
"""
    setup(conn::Connection, schema::AbstractString = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))")

Sets up your PostgreSQL database for the project based on the options passed through the `Opt`.

# Example

```julia-repl
julia> setup(opt)

```
"""
function setup(conn::Connection, schema::AbstractString = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))")
    execute(conn, "CREATE EXTENSION IF NOT EXISTS btree_gist;")
    execute(conn, "CREATE SCHEMA IF NOT EXISTS $schema;")
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.licenses (
             spdx text NOT NULL,
             name text NOT NULL,
             CONSTRAINT spdxid UNIQUE (spdx)
           );
           COMMENT ON TABLE $schema.licenses
            IS 'OSI-approved machine detectable licenses';
           COMMENT ON COLUMN $schema.licenses.spdx
            IS 'SPDX license ID';
           COMMENT ON COLUMN $schema.licenses.name
            IS 'Name of the license';
        """,
    )
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.queries (
             spdx text NOT NULL,
             created tsrange NOT NULL,
             count smallint NOT NULL,
             asof timestamp NOT NULL,
             done bool NOT NULL,
             CONSTRAINT query UNIQUE (spdx, created)
           );
           COMMENT ON TABLE $schema.queries
            IS 'This table is a tracker for queries';
           COMMENT ON COLUMN $schema.queries.spdx
            IS 'The SPDX license ID';
           COMMENT ON COLUMN $schema.queries.created
            IS 'The time interval for the query';
           COMMENT ON COLUMN $schema.queries.count
            IS 'How many results for the query';
           COMMENT ON COLUMN $schema.queries.asof
            IS 'When was GitHub queried about the information.';
           COMMENT ON COLUMN $schema.queries.done
            IS 'Has the repositories been collected?';
           COMMENT ON CONSTRAINT query ON $schema.queries
            IS 'No duplicate for queries';
       """,
    )
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.repos (
             repoid text NOT NULL,
             basebranchid text NOT NULL,
             asof timestamp NOT NULL,
             status text NOT NULL,
             CONSTRAINT repoid_idx UNIQUE (repoid)
           );
           COMMENT ON TABLE $schema.repos IS 'Repository ID and base branch ID';
           COMMENT ON COLUMN $schema.repos.repoid
            IS 'Repository ID';
           COMMENT ON COLUMN $schema.repos.basebranchid
            IS 'Base branch ID';
           COMMENT ON COLUMN $schema.repos.status
            IS 'Status of collection effort';
           COMMENT ON COLUMN $schema.repos.asof
            IS 'When was GitHub queried about the information.';
        """,
    )
    execute(
        conn,
        """CREATE TABLE IF NOT EXISTS $schema.commits (
             basebranchid text NOT NULL,
             commitid text NOT NULL,
             committed_date timestamp NOT NULL,
             authorid text,
             authoremail text,
             additions integer NOT NULL,
             deletions integer NOT NULL,
             asof timestamp NOT NULL,
             CONSTRAINT commits_id UNIQUE (commitid)
           );
       """,
    )
    nothing
end
