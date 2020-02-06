"""
    Licenses

Application for uploading OSI-approved non-retired licences name and SPDX to the database.
"""
module Licenses
using ..BaseUtils: Opt
using Cascadia: nodeText, parsehtml, Selector
using HTTP: request
using JSON3: JSON3
using LibPQ: Connection, execute, prepare
using Parameters: @unpack
"""
    SPDX_CORRECTIONS

Manual fixes to the SPDX for which the OSI website had wrong based on the SPDX data.
"""
const SPDX_CORRECTIONS = ("LiliQ-P" => "LiLiQ-P-1.1",
                          "LiliQ-R" => "LiLiQ-R-1.1", 
                          "LiliQ-R+" => "LiLiQ-Rplus-1.1",
                          "UPL" => "UPL-1.0",
                          "WXwindows" => "wxWindows")
"""
    SELECTOR_LI

CSS Selector for list items in the unordered list inside the field-item class.
"""
const SELECTOR_LI = Selector(".field-item > ul > li");
"""
    SELECTOR_LI

CSS Selector for the anchor tag.
"""
const SELECTOR_A = Selector("a");
"""
    parse_license(node)

Return the name and SPDX for an OSI license that has SPDX and has not been retired.
If the license does not have a SPDX or it has been retired, returns `Nothing`.
"""
function parse_license(node)
    text = nodeText(node)
    # We only use licenses that have an SPDX which means it needs to detect a parentheses
    # We do not want to include licenses that have been retired
    if !occursin("(", text) || occursin(r"\(retired\)$", text)
        output = nothing
    else
        matches = eachmatch(SELECTOR_A, node)
        if length(matches) ≠ 1
            output = nothing
        else
            text = strip(nodeText(first(eachmatch(SELECTOR_A, node))))
            name = match(r"^.*?(?= \()", text).match
            spdx = match(r"(?<=\()[^\s]*?(?=\)$)", text).match
            output = (name = name, spdx = spdx)
        end
    end
end
"""
    manual_fix_spdx!(spdx, wrong, correct)

Modifies `spdx` by fixing wrong SPDX codes with the correct ones.
"""
function manual_fix_spdx!(spdx, wrong, correct)
    idx = findfirst(x -> isequal(wrong, last(x)), spdx)
    name = spdx[findfirst(x -> isequal(wrong, last(x)), spdx)][1]
    deleteat!(spdx, idx)
    push!(spdx, (name = name, spdx = correct))
    spdx
end
"""
    osi_licenses()::Tuple{Vector{NamedTuple{(:name, :spdx),
                                            Tuple{SubString{String},SubString{String}}}},
                          SubString{String}}

Return non-retired OSI approved licences and the date when the data was last queried.
"""
@inline function osi_licenses()::Tuple{Vector{NamedTuple{(:name, :spdx),
                                                         Tuple{SubString{String},SubString{String}}}},
                                       SubString{String}}
    response = request("GET", "https://opensource.org/licenses/alphabetical");
    html = parsehtml(String(response.body));
    licenses = eachmatch(SELECTOR_LI, html.root);
    spdx = collect(Iterators.filter(!isnothing, parse_license(node) for node ∈ licenses))
    response_date = last(response.headers[findfirst(isequal("Date"), first.(response.headers))])
    spdx, response_date
end
"""
    sdpx_data()::Tuple{Vector{String},String}

Return a list of all SPDX and the date/version of the data release.
"""
@inline function sdpx_data()::Tuple{Vector{String},String}
    spdx_data = request("GET", "https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json");
    json = JSON3.read(spdx_data.body);
    spdx_id = get.(json.licenses, "licenseId", nothing)
    spdx_date = json.releaseDate
    spdx_id, spdx_date
end
"""
    upload_licenses(obj::Opt)

Creates the licences table in the database.

It first obtains the name and license code for all approved non-retired licenses by Open Source Initiative on the [website](https://opensource.org/licenses/alphabetical).
It validates the license codes with the latest published Software Package Data Exchange (SPDX) [data](https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json).
It corrects errors by applying the following corrections:

$SPDX_CORRECTIONS

It refreshes the data if data has been previously collected.
The table metadata is recorded.

# Example

```jldoctest; filter = r"On: \\w{3}, \\d{2} \\w{3} \\d{4} \\d{2}:\\d{2}:\\d{2} GMT"
julia> setup(opt)

julia> upload_licenses(opt)


julia> execute(opt.conn,
               string("SELECT COUNT(*) > 0 as chk FROM ", opt.schema, ".licenses;")) |>
           (obj -> getproperty.(obj, :chk)[1])
true

julia> execute(opt.conn,
               @sprintf("SELECT obj_description('%s.licenses'::regclass);", opt.schema)) |>
           (obj -> getproperty.(obj, :obj_description)[1] |>
           println
License name and SPDX based on non-retired OSI-approved licenses.
      Based on data at: https://opensource.org/licenses/alphabetical
      On: Thu, 06 Feb 2020 03:32:51 GMT
      Using SPDX codes from release date: 2020-01-30

julia> execute(opt.conn,
               @sprintf(\"\"\"SELECT column_name, data_type, col_description('%s.licenses'::regclass, ordinal_position)
                           FROM information_schema.columns
                           WHERE table_schema = '%s' AND table_name = 'licenses';
                        \"\"\",
                        opt.schema, opt.schema)) |>
           DataFrame
2×3 DataFrames.DataFrame
│ Row │ column_name │ data_type │ col_description                           │
│     │ String⍰     │ String⍰   │ Union{Missing, String}                    │
├─────┼─────────────┼───────────┼───────────────────────────────────────────┤
│ 1   │ name        │ text      │ Name of the license.                      │
│ 2   │ spdx        │ text      │ Software Package Data Exchange License ID │

```

"""
function upload_licenses(obj::Opt)
    @unpack conn, schema, role = obj
    # Obtaining OSI licenses from the Open Source Initiative Website
    # Verify SPDX with SPDX ID data
    spdx, response_date = osi_licenses()
    spdx_id, spdx_date = sdpx_data()
    foreach(wc -> manual_fix_spdx!(spdx, wc...), SPDX_CORRECTIONS)
    @assert isempty(setdiff(last.(spdx), spdx_id))
    @assert length(unique(spdx)) == length(spdx)
    sort!(spdx, by = (x -> x.spdx))
    # Create table if needed
    execute(conn, """COMMENT ON TABLE $schema.licenses IS
                       'License name and SPDX based on non-retired OSI-approved licenses.
                        Based on data at: https://opensource.org/licenses/alphabetical
                        On: $response_date
                        Using SPDX codes from release date: $spdx_date';
                     COMMENT ON COLUMN $schema.licenses.name IS 'Name of the license.';
                     COMMENT ON COLUMN $schema.licenses.spdx IS 'Software Package Data Exchange License ID';
                     ALTER TABLE $schema.licenses OWNER to $role;
                  """)
    stmt = prepare(conn, "INSERT INTO $schema.licenses (name, spdx) VALUES (\$1, \$2) ON CONFLICT DO NOTHING;")
    execute(conn, "TRUNCATE $schema.licenses;")
    foreach(row -> execute(stmt, collect(row)), spdx)
end
end
