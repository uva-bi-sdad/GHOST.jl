# Manual

## Introduction

This tool can be used for collecting information useful for estimating the scope and impact of open source software.

The following data is collected for the analysis.

- Commit data for repositories
  - Commit ID (hash)
  - Timestamp (datetime)
  - Repository (slug)
  - Author (login)
  - Lines added (Integer)
  - Lines deleted (Integer)
  - As of (datetime of when information was queried)
- Repository data
  - Slug (owner/name)
  - Creation Date
  - License (SPDX)

Additional data such as user information can be obtained from the [GHTorrent](http://ghtorrent.org/) project.

## Licenses

The official list of Open Source Initiative (OSI) approved licenses is hosted at their [website](https://opensource.org/licenses/alphabetical).

On the OSI licenses database:

- 12 are superseded
- 5 are retired
- 78 are active OSI approved

GitHub uses the Ruby Gem [Licensee](https://licensee.github.io/licensee/) for systematically detecting the license of repositories (GitHub [documentation](https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository#detecting-a-license)). It detects among 38 different [licenses](https://github.com/github/choosealicense.com/tree/gh-pages/_licenses) out of which 29 are OSI-approved licenses (28 active licenses and 1 superseded). These licenses include the most commonly used ones.

The following licenses are both GitHub/Licensee detectable and OSI-approved.

const licenses = 

**Name**|**SPDX**
:-----:|:-----:
BSD Zero Clause License|0BSD
Academic Free License v3.0|AFL-3.0
GNU Affero General Public License v3.0|AGPL-3.0
Apache License 2.0|Apache-2.0
Artistic License 2.0|Artistic-2.0
BSD 2-Clause "Simplified" License|BSD-2-Clause
BSD 3-Clause "New" or "Revised" License|BSD-3-Clause
Boost Software License 1.0|BSL-1.0
CeCILL Free Software License Agreement v2.1|CECILL-2.1
Educational Community License v2.0|ECL-2.0
Eclipse Public License 1.0|EPL-1.0
Eclipse Public License 2.0|EPL-2.0
European Union Public License 1.2|EUPL-1.2
GNU General Public License v2.0 only|GPL-2.0
GNU General Public License v3.0 only|GPL-3.0
ISC License|ISC
GNU Lesser General Public License v2.1 only|LGPL-2.1
GNU Lesser General Public License v3.0 only|LGPL-3.0
LaTeX Project Public License v1.3c|LPPL-1.3c
MIT License|MIT
Mozilla Public License 2.0|MPL-2.0
Microsoft Public License|MS-PL
Microsoft Reciprocal License|MS-RL
University of Illinois/NCSA Open Source License|NCSA
SIL Open Font License 1.1|OFL-1.1
Open Software License 3.0|OSL-3.0
PostgreSQL License|PostgreSQL
Universal Permissive License v1.0|UPL-1.0
zlib License|Zlib

The `license` table contains this data.

## Collection Strategy

### Repositories

We are interested in finding every repository on GitHub that fits the following criteria:

- Is public
- Has a machine detectable OSI-approved license
- Is not a fork
- Is not a mirror
- Is not archived
- Was created on GitHub during `[1970-01-01, 2020-01-01)`

In order to perform such a query with the GitHub API we most first identify *search* queries which yield fewer than 1,000 results (the maximum number of results any query will return). The way we achieve the task is through searching for every public, non-fork, non-mirror, non-archived, public repository with `X` license where `X` is a machine-detectable OSI-approved license. In addition, the code will limit results based on when the repository was created (a persistent value) and shorten the interval until fewer than 1,000 results are returned.

We store the query parameters and perform the iterative process for each license of interest.

The `queries` table contains is used to store the queries and track their status.

For each query, we obtain each of the resulting repositories and their associated data.

The `repos` table contains this data and is used to track the status of the commit data for each repository.

### Commits

For each repository, we query the commit data based on the time coverage of the data collection.

The `commits` table contains this data and is used to update the status of the repository commit data at the `repos` table.

!!! note

    Commit users may show with a `NULL` login which indicates that the commit email does not match those associated with any GitHub account.