# Manual

## Introduction

This tool can be used for collecting information useful for measuring the scope and impact of open source software.

## Licenses

GitHub can recognize certain licenses for repositories per their [documentation](https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository). We filter out the machine-detectable licenses that are approved by the Open Source Initiative based on the SPDX Working Group SPDX License [List](https://raw.githubusercontent.com/spdx/license-list-data/master/json/licenses.json) data.

!!! info

    SPDX stands for Software Package Data Exchange open standard for communicating software bill of material
    information (including components, licenses, copyrights, and security references).

The following licenses are machine-detectable OSI-approved licenses.

|**SPDX**|**Name**|
|:------:|:------:|
|0BSD | BSD Zero Clause License|
|AFL-3.0 | Academic Free License v3.0|
|AGPL-3.0 | GNU Affero General Public License v3.0|
|Apache-2.0 | Apache License 2.0|
|Artistic-2.0 | Artistic License 2.0|
|BSD-2-Clause | BSD 2-Clause Simplified License|
|BSD-3-Clause | BSD 3-Clause New or Revised License|
|BSL-1.0 | Boost Software License 1.0|
|CECILL-2.1 | CeCILL Free Software License Agreement v2.1|
|ECL-2.0 | Educational Community License v2.0|
|EPL-1.0 | Eclipse Public License 1.0|
|EPL-2.0 | Eclipse Public License 2.0|
|EUPL-1.1 | European Union Public License 1.1|
|EUPL-1.2 | European Union Public License 1.2|
|GPL-2.0 | GNU General Public License v2.0 only|
|GPL-3.0 | GNU General Public License v3.0 only|
|ISC | ISC License|
|LGPL-2.1 | GNU Lesser General Public License v2.1 only|
|LGPL-3.0 | GNU Lesser General Public License v3.0 only|
|LPPL-1.3c | LaTeX Project Public License v1.3c|
|MIT | MIT License|
|MPL-2.0 | Mozilla Public License 2.0|
|MS-PL | Microsoft Public License|
|MS-RL | Microsoft Reciprocal License|
|NCSA | University of Illinois/NCSA Open Source License|
|OFL-1.1 | SIL Open Font License 1.1|
|OSL-3.0 | Open Software License 3.0|
|PostgreSQL | PostgreSQL License|
|UPL-1.0 | Universal Permissive License v1.0|
|Zlib | zlib License|

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

!!! Warning

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

    This is table `gh_2007_2020.queries`.

The `queries` table is used to store the queries and track their status. Once all the records have been obtained for the `repos` table their `done` status becomes `TRUE`.

### Repository base branch

The commit data for a Git repository is dependent on the base branch.

The `repos` table contains the GitHub repository global node ID and the global node ID for the base branch of the repository.

| repoid                           | basebranchid                     | asof                   | status |
|----------------------------------|----------------------------------|------------------------|--------|
| MDEwOlJlcG9zaXRvcnkyMzgzNTcxMTI= | MDM6UmVmMjM4MzU3MTEyOm1hc3Rlcg== | 2020-05-14 19:49:10+00 | Ready  |

!!! info

    This is table `gh_2007_2020.repos`.

The various `status` values include:

- `Ready`: We will commence collecting commit data from it.
- `Unavailable`: Repository is not accessible (e.g., deleted of made private `NOT_FOUND`, DMCA takedown)
- `Error`: Something weird happened such as someone Git force pushing and changing the history during scrape.

### Commits

For each repository, we query the commit data based on the time coverage of the data collection.

The `commits` table contains this data and is used to update the status of the repository commit data at the `repos` table.

!!! note

    Commit users may show with a `NULL` login which indicates that the commit email does not match those associated with any GitHub account.

!!! note

    Commit timestamps sometimes may have have strange dates dating back before the creation of version control (usually the Epoch time). For those commits, we replace the value with the earliest commit date in that repository that seems valid.

## How To Use

In order to use this package, refer to the example in the [test suite](https://github.com/uva-bi-sdad/GHOST.jl/blob/main/test/runtests.jl) and the [CI script](https://github.com/uva-bi-sdad/GHOST.jl/blob/main/.github/workflows/ci.yml). The prefered solution is through a containerized application such as the CI using Docker but any environment with the required components will do.

### Components

- GitHub Personal Access Tokens with `read_org` access
- Julia v1 (current release v1.5.3)
- A PostgreSQL database connection (tested with v11 and v12)
