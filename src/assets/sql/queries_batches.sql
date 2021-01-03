WITH A AS (
    SELECT spdx,
        created,
        CEIL(count::real / 10) queries
    FROM gh_2007_2020.queries
    WHERE NOT done
    ORDER BY queries DESC,
        spdx
),
B AS (
    SELECT spdx,
        created,
        queries::smallint,
        CEIL(
            ROW_NUMBER() OVER (
                PARTITION BY queries
                ORDER BY queries DESC,
                    spdx,
                    created
            )::real / 10
        )::smallint AS query_group
    FROM A
)
SELECT *
FROM B
ORDER BY queries DESC,
    query_group;
