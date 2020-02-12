"""
    Licenses

Application for uploading OSI-approved non-retired licenses name and SPDX to the database.
"""
module Licenses
using ..BaseUtils: Opt
using LibPQ: Connection, execute, load!, status, reset!
using Parameters: @unpack
"""
    OSI_MACHINE_DETECTABLE_LICENSES::Vector{NamedTuple{(:name, :spdx),Tuple{String,String}}}
"""
const OSI_MACHINE_DETECTABLE_LICENSES = [
    (name = "BSD Zero Clause License", spdx = "0BSD"),
    (name = "Academic Free License v3.0", spdx = "AFL-3.0"),
    (name = "GNU Affero General Public License v3.0", spdx = "AGPL-3.0"),
    (name = "Apache License 2.0", spdx = "Apache-2.0"),
    (name = "Artistic License 2.0", spdx = "Artistic-2.0"),
    (name = "BSD 2-Clause \"Simplified\" License", spdx = "BSD-2-Clause"),
    (name = "BSD 3-Clause \"New\" or \"Revised\" License", spdx = "BSD-3-Clause"),
    (name = "Boost Software License 1.0", spdx = "BSL-1.0"),
    (name = "CeCILL Free Software License Agreement v2.1", spdx = "CECILL-2.1"),
    (name = "Educational Community License v2.0", spdx = "ECL-2.0"),
    (name = "Eclipse Public License 1.0", spdx = "EPL-1.0"),
    (name = "Eclipse Public License 2.0", spdx = "EPL-2.0"),
    (name = "European Union Public License 1.2", spdx = "EUPL-1.2"),
    (name = "GNU General Public License v2.0 only", spdx = "GPL-2.0"),
    (name = "GNU General Public License v3.0 only", spdx = "GPL-3.0"),
    (name = "ISC License", spdx = "ISC"),
    (name = "GNU Lesser General Public License v2.1 only", spdx = "LGPL-2.1"),
    (name = "GNU Lesser General Public License v3.0 only", spdx = "LGPL-3.0"),
    (name = "LaTeX Project Public License v1.3c", spdx = "LPPL-1.3c"),
    (name = "MIT License", spdx = "MIT"),
    (name = "Mozilla Public License 2.0", spdx = "MPL-2.0"),
    (name = "Microsoft Public License", spdx = "MS-PL"),
    (name = "Microsoft Reciprocal License", spdx = "MS-RL"),
    (name = "University of Illinois/NCSA Open Source License", spdx = "NCSA"),
    (name = "SIL Open Font License 1.1", spdx = "OFL-1.1"),
    (name = "Open Software License 3.0", spdx = "OSL-3.0"),
    (name = "PostgreSQL License", spdx = "PostgreSQL"),
    (name = "Universal Permissive License v1.0", spdx = "UPL-1.0"),
    (name = "zlib License", spdx = "Zlib")
]
"""
    licenses(opt::Opt)

Creates the licenses table in the database.

The table metadata is recorded.

# Example

```jldoctest
julia> licenses(opt)
PostgreSQL result

julia> execute(opt.conn,
               "SELECT COUNT(*) = 29 as verify FROM \$(opt.schema).licenses;") |>
       rowtable |>
       (data -> data[1].verify)
true

julia> execute(opt.conn,
               string("SELECT name, spdx FROM ", opt.schema, ".licenses;"),
               not_null = true) |>
           DataFrame
29×2 DataFrames.DataFrame
│ Row │ name                                            │ spdx         │
│     │ String                                          │ String       │
├─────┼─────────────────────────────────────────────────┼──────────────┤
│ 1   │ BSD Zero Clause License                         │ 0BSD         │
│ 2   │ Academic Free License v3.0                      │ AFL-3.0      │
│ 3   │ GNU Affero General Public License v3.0          │ AGPL-3.0     │
│ 4   │ Apache License 2.0                              │ Apache-2.0   │
│ 5   │ Artistic License 2.0                            │ Artistic-2.0 │
│ 6   │ BSD 2-Clause "Simplified" License               │ BSD-2-Clause │
│ 7   │ BSD 3-Clause "New" or "Revised" License         │ BSD-3-Clause │
⋮
│ 22  │ Microsoft Public License                        │ MS-PL        │
│ 23  │ Microsoft Reciprocal License                    │ MS-RL        │
│ 24  │ University of Illinois/NCSA Open Source License │ NCSA         │
│ 25  │ SIL Open Font License 1.1                       │ OFL-1.1      │
│ 26  │ Open Software License 3.0                       │ OSL-3.0      │
│ 27  │ PostgreSQL License                              │ PostgreSQL   │
│ 28  │ Universal Permissive License v1.0               │ UPL-1.0      │
│ 29  │ zlib License                                    │ Zlib         │

julia> execute(opt.conn,
               @sprintf("SELECT obj_description('%s.licenses'::regclass);", opt.schema)) |>
           (obj -> getproperty.(obj, :obj_description)[1]) |>
           println
OSI-approved machine detectable licenses (i.e., Licensee).
The official list of Open Source Initiative (OSI) approved licenses is hosted at their website.
GitHub uses the Ruby Gem Licensee for systematically detecting the license of repositories.
                 
References:
- https://opensource.org/licenses/alphabetical
- https://licensee.github.io/licensee/
- https://github.com/github/choosealicense.com/tree/gh-pages/_licenses (b509f7fa1f69213669f4b7e7c83d7037be8f55dd)
- https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json (v3.7-21-g958f9ac)
- https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository#detecting-a-license
    
As of: 2020-02-07

julia> execute(opt.conn,
               @sprintf(\"\"\"SELECT column_name, data_type, col_description('%s.licenses'::regclass, ordinal_position)
                        FROM information_schema.columns
                        WHERE table_schema = '%s' AND table_name = 'licenses';
                        \"\"\",
                        opt.schema, opt.schema),
               not_null = true) |>
           DataFrame
2×3 DataFrames.DataFrame
│ Row │ column_name │ data_type │ col_description                           │
│     │ String      │ String    │ String                                    │
├─────┼─────────────┼───────────┼───────────────────────────────────────────┤
│ 1   │ name        │ text      │ Name of the license.                      │
│ 2   │ spdx        │ text      │ Software Package Data Exchange License ID │

```
"""
function licenses(opt::Opt)
    @unpack conn, schema, role = opt
    isone(Int(status(conn))) && reset!(conn)
    # Create table if needed
    execute(conn,
            """
            COMMENT ON TABLE $schema.licenses IS
            'OSI-approved machine detectable licenses (i.e., Licensee).
            The official list of Open Source Initiative (OSI) approved licenses is hosted at their website.
            GitHub uses the Ruby Gem Licensee for systematically detecting the license of repositories.
                             
            References:
            - https://opensource.org/licenses/alphabetical
            - https://licensee.github.io/licensee/
            - https://github.com/github/choosealicense.com/tree/gh-pages/_licenses (b509f7fa1f69213669f4b7e7c83d7037be8f55dd)
            - https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json (v3.7-21-g958f9ac)
            - https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository#detecting-a-license
                
            As of: 2020-02-07';
            COMMENT ON COLUMN $schema.licenses.name IS 'Name of the license.';
            COMMENT ON COLUMN $schema.licenses.spdx IS 'Software Package Data Exchange License ID';
            ALTER TABLE $schema.licenses OWNER to $role;
            """)
    execute(conn, "TRUNCATE $schema.licenses;")
    execute(conn, "BEGIN;")
    load!(OSI_MACHINE_DETECTABLE_LICENSES,
          conn,
          "INSERT INTO $schema.licenses (name, spdx) VALUES (\$1, \$2) ON CONFLICT DO NOTHING;")
    execute(conn, "COMMIT;")
end
end
