SELECT branch
FROM schema.repos
WHERE (status = 'Init' OR status = 'In progress') AND (commits > min_lim) AND (commits <= max_lim)
ORDER BY commits
;
