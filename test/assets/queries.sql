-- We first check that the intervals start and end as we expect
WITH A AS (
  SELECT
    spdx,
    MIN(LOWER(created)) = '2007-10-29'
    AND MAX(UPPER(created)) = date_trunc('year', CURRENT_DATE) :: timestamp AS valid
  FROM gh_2007_2019.queries
  GROUP BY
    spdx
  ORDER BY
    spdx ASC
),
B AS (
  SELECT
    true = ALL(
      SELECT
        valid
      FROM A
    ) AS valid
),
-- Next we verify that intervals are non-overlaping consecutive intervals
C AS (
  SELECT
    spdx,
    created,
    UPPER(
      LAG(created) OVER (
        PARTITION BY spdx
        ORDER BY
          created ASC
      )
    ) = LOWER(created) AS valid
  FROM gh_2007_2019.queries
),
D AS (
  SELECT
    true = ALL(
      SELECT
        valid
      FROM C
      WHERE
        valid IS NOT NULL
    ) AS valid
)
SELECT
  true = (
    SELECT
      valid
    FROM B
  )
  AND (
    SELECT
      valid
    FROM D
  ) AS valid;
