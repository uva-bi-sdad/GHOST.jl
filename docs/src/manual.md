# Manual

## Getting Started

GHOST.jl can be installed from the repository through:

```julia
using Pkg
Pkg.add(url = "https://github.com/uva-bi-sdad/GHOST.jl")
```

to load the package, use

```julia
using GHOST
```

## Licenses

GitHub can recognize certain licenses for repositories per their [documentation](https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository). We filter out the machine-detectable licenses that are approved by the Open Source Initiative based on the SPDX Working Group SPDX License [List](https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json) data.

!!! info

    SPDX stands for Software Package Data Exchange open standard for communicating software bill of material
    information (including components, licenses, copyrights, and security references).

The following licenses are machine-detectable OSI-approved licenses.

|   **SPDX**   |                    **Name**                     |
|:------------:|:-----------------------------------------------:|
|     0BSD     |             BSD Zero Clause License             |
|    AFL-3.0   |            Academic Free License v3.0           |
|   AGPL-3.0   |      GNU Affero General Public License v3.0     |
|  Apache-2.0  |                Apache License 2.0               |
| Artistic-2.0 |               Artistic License 2.0              |
| BSD-2-Clause |        BSD 2-Clause "Simplified" License        |
| BSD-3-Clause |     BSD 3-Clause "New" or "Revised" License     |
|    BSL-1.0   |            Boost Software License 1.0           |
|  CECILL-2.1  |   CeCILL Free Software License Agreement v2.1   |
|    ECL-2.0   |        Educational Community License v2.0       |
|    EPL-1.0   |            Eclipse Public License 1.0           |
|    EPL-2.0   |            Eclipse Public License 2.0           |
|   EUPL-1.1   |        European Union Public License 1.1        |
|   EUPL-1.2   |        European Union Public License 1.2        |
|    GPL-2.0   |       GNU General Public License v2.0 only      |
|    GPL-3.0   |       GNU General Public License v3.0 only      |
|      ISC     |                   ISC License                   |
|   LGPL-2.1   |   GNU Lesser General Public License v2.1 only   |
|   LGPL-3.0   |   GNU Lesser General Public License v3.0 only   |
|   LPPL-1.3c  |        LaTeX Project Public License v1.3c       |
|      MIT     |                   MIT License                   |
|    MPL-2.0   |            Mozilla Public License 2.0           |
|     MS-PL    |             Microsoft Public License            |
|     MS-RL    |           Microsoft Reciprocal License          |
|     NCSA     | University of Illinois/NCSA Open Source License |
|    OFL-1.1   |            SIL Open Font License 1.1            |
|    OSL-3.0   |            Open Software License 3.0            |
|  PostgreSQL  |                PostgreSQL License               |
|    UPL-1.0   |        Universal Permissive License v1.0        |
|   Unlicense  |                  The Unlicense                  |
|     Zlib     |                   zlib License                  |

## Collection Strategy

### Universe

We are interested in finding every repository on GitHub that fits the following criteria:

- Is public
- Has a machine detectable OSI-approved license
- Is not a fork
- Is not a mirror
- Is not archived

!!! info

    The oldest repository by creation time on GitHub dates back to 2007-10-29T14:37:16+00.

In the GitHub [search syntax](https://help.github.com/en/github/searching-for-information-on-github/understanding-the-search-syntax) the following criteria is denoted by

```
{
  search(query: "is:public fork:false mirror:false archived:false license:$spdx created:2007-10-29T14:37:16+00..2020-01-01T00:00:00+00", type: REPOSITORY) {
    repositoryCount
  }
}
```

where `$spdx` a license keyword (e.g., `mit`).

!!! warning

    GitHub only allows to query up to 1,000 results per search connection result.
    If a query returns over 1,000 results, only the first 1,000 are accessible.
    In order to be able to collect every repository of interest we query based on:
        - license (e.g., `spdx:mit`)
        - when it was created (e.g., `created:2010-01-01T00:00:00+00..2010-02-01T00:00:00+00`)
    We shrink intervals until the result count is 1,000 or fewer.

```
created:2010-01-01T00:00:00+00..2010-01-01T12:00:00+00 1,850

created:2010-01-01T00:00:00+00..2010-01-01T12:00:00+00 998
created:2010-01-01T12:00:00+00..2010-01-02T00:00:00+00 952
```

We then prune intervals to obtain the least amount of valid intervals that cover the full time period.

For example,

| spdx |                    created                    | count |         asof        | done  |
|:----:|:---------------------------------------------:|:-----:|:-------------------:|-------|
| zlib | ["2007-10-29 00:00:00","2014-09-04 00:00:00") |  999  | 2020-05-14 18:48:03 | FALSE |
| zlib | ["2014-09-04 00:00:00","2016-12-09 00:00:00") |  998  | 2020-05-14 18:48:03 | FALSE |
| zlib | ["2016-12-09 00:00:00","2018-12-21 00:00:00") |  998  | 2020-05-14 18:48:03 | FALSE |
| zlib | ["2018-12-21 00:00:00","2020-01-01 00:00:00") |  562  | 2020-05-14 18:48:03 | FALSE |

!!! info

    This is table `gh_2007_2021.queries`.

The `queries` table is used to store the queries and track their status. Once all the records have been obtained for the `repos` table their `done` status becomes `TRUE`.

### Repository base branch

The commit data for a Git repository is dependent on the base branch.

The `repos` table contains the GitHub repository global node ID and the global node ID for the base branch of the repository.

| id                           | basebranchid                     | asof                   | status |
|----------------------------------|----------------------------------|------------------------|--------|
| MDEwOlJlcG9zaXRvcnkyMzgzNTcxMTI= | MDM6UmVmMjM4MzU3MTEyOm1hc3Rlcg== | 2020-05-14 19:49:10+00 | Ready  |

!!! info

    This is table `gh_2007_2021.repos`.

The various `status` values include:

- `Ready`: We will commence collecting commit data from it.
- `Unavailable`: Repository is not accessible (e.g., deleted of made private `NOT_FOUND`, DMCA takedown)
- `Error`: Something weird happened such as someone Git force pushing and changing the history during the scrape process.

### Commits

For each repository, we query the commit data based on the time coverage of the data collection.

The `commits` table contains this data and is used to update the status of the repository commit data at the `repos` table.

!!! note

    Commit users may show with a `NULL` login which indicates that the commit email does not match those associated with any GitHub account.

!!! note

    Commit timestamps sometimes may have have strange dates dating back before the creation of version control (usually the Epoch time). For those commits, we replace the value with the earliest commit date in that repository that seems valid.

## Relational Database

|   Table  |      Column     |                               Description                               |
|:--------:|:---------------:|:-----------------------------------------------------------------------:|
| licenses |       spdx      |                Software Package Data Exchange License ID                |
| licenses |       name      |                           Name of the license                           |
|  queries |       spdx      |                           The SPDX license ID                           |
|  queries |     created     |                     The time interval for the query                     |
|  queries |      count      |                      How many results for the query                     |
|  queries |       asof      |              When was GitHub queried about the information.             |
|  queries |       done      |                   Has the repositories been collected?                  |
|   repos  |        id       |                              Repository ID                              |
|   repos  |       spdx      |                             SPDX license ID                             |
|   repos  |       slug      |                       Location of the repository                       |
|   repos  |    createdat    |                When was the repository created on GitHub?               |
|   repos  |   description   |                      Description of the repository                     |
|   repos  | primarylanguage |                   Primary language of the repository                   |
|   repos  |      branch     |                              Base branch ID                             |
|   repos  |     commits     | Number of commits in the branch until the end of the observation period |
|   repos  |       asof      |                         When was GitHub queried?                        |
|   repos  |      status     |                       Status of collection effort                       |
|  commits |      branch     |                       Base Branch ID (foreign key)                      |
|  commits |        id       |                                Commit ID                                |
|  commits |       oid       |                           Git Object ID (SHA1)                          |
|  commits |   committedat   |                          When was it committed?                         |
|  commits |  authors_email  |                       The email in the Git commit.                      |
|  commits |   authors_name  |                       The name in the Git commit.                       |
|  commits |    authors_id   |                              GitHub Author                              |
|  commits |    additions    |                 The number of additions in this commit.                 |
|  commits |    deletions    |                 The number of deletions in this commit.                 |
|  commits |       asof      |                         When was GitHub queried.                        |

## How To Use

In order to use this package, refer to API section in the documentation, the examples in the [test suite](https://github.com/uva-bi-sdad/GHOST.jl/blob/main/test/runtests.jl), the [CI](https://github.com/uva-bi-sdad/GHOST.jl/blob/main/.github/workflows/ci.yml) and [pipeline](https://github.com/uva-bi-sdad/GHOST.jl/tree/main/scripts) scripts.

!!! info

    Additional documentation is forthcoming once the API interface is stabilized.

### Requirements

- GitHub Personal Access Tokens with public access
- Julia v1 (current release v1.5.3)
- A PostgreSQL database connection (tested with v11-v13)
