"""
    licenses(conn::Connection,
             pat::GitHubPersonalAccessToken,
             schema::AbstractString = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))",
             )::Nothing

Uploads the licenses table to the database.
It includes every OSI-approved license that is machine readable with Licensee.
"""
function licenses(conn::Connection,
                  pat::GitHubPersonalAccessToken,
                  schema::AbstractString = "gh_2007_$(Dates.year(floor(now(), Year) - Day(1)))")
    # Obtain all licences used by the Ruby gem: `licensee`.
    licensee = graphql(pat,
                       query = string(strip(replace(String(read(joinpath(@__DIR__, "assets", "licensee.graphql"))), r"[\n\s]+" => " "))),
                       operationName = "licensee",
                       # The repository is https://github.com/licensee/licensee
                       vars = Dict("id" => "MDEwOlJlcG9zaXRvcnkyMzAyMjM3Nw==",
                                   # Path is https://github.com/licensee/licensee/tree/master/vendor/choosealicense.com/_licenses
                                   "expression" => "master:vendor/choosealicense.com/_licenses")) |>
        (obj -> JSON3.read(obj.Data).data.node.object) |>
        (obj -> (sha1 = obj.oid, spdx = [ uppercase(elem.name[1:end - 4]) for elem in obj.entries ]))
    # Queries the SPDX licenses (ID and whether OSI approved)
    spdx = request("GET",
                   "https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json") |>
        (obj -> JSON3.read(obj.body)) |>
        (obj -> (version = obj.licenseListVersion,
                 release_date = obj.releaseDate,
                 spdx = [ (spdx = license.licenseId,
                           name = license.name)
                           # Keep only OSI-approved licences
                           for license in obj.licenses if license.isOsiApproved ]))
    # Keep only licenses that are machine detectable with Licensee
    filter!(license -> uppercase(license.spdx) ∈ licensee.spdx, spdx.spdx)
    execute(conn, "BEGIN;")
    load!(spdx.spdx, conn, "INSERT INTO $schema).licenses VALUES ($(join(("\$$i" for i in 1:2), ',')));")
    execute(conn, "COMMIT;")
    # Add the source data metadata
    execute(conn,
        """
        COMMENT ON TABLE $schema.licenses IS
        'OSI-approved machine detectable licenses (i.e., Licensee).
        The official list of Open Source Initiative (OSI) approved licenses is hosted at their website.
        For programmatic access we first obtain all licences from the SPDX data files.
        We filter the licenses based on whether it is OSI-approved.
        GitHub uses the Ruby Gem Licensee for systematically detecting the license of repositories.
                         
        References:
        - https://spdx.org
        - https://licensee.github.io/licensee
        - https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository#detecting-a-license
            
        SPDX data version: $(spdx.version)
        Licensee data version: $(licensee.sha1)';
        COMMENT ON COLUMN $schema.licenses.spdx IS 'Software Package Data Exchange License ID';
        COMMENT ON COLUMN $schema.licenses.name IS 'Name of the license';
        """)
    nothing
end
