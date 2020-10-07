UPDATE $schema.repos
SET status = 'Empty'
WHERE commits = 0 OR branch IS null;
