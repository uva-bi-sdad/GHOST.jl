CREATE TABLE IF NOT EXISTS schema.commits (
    branch text NOT NULL,
    id text PRIMARY KEY,
    oid text NOT NULL,
    committedat timestamp NOT NULL,
    author_email text NOT NULL,
    author_name text NOT NULL,
    author_id text,
    message text NOT NULL,
    additions bigint,
    deletions bigint,
    lastupdated timestamp NOT NULL
);
COMMENT ON TABLE schema.commits IS 'Commits Information';
COMMENT ON COLUMN schema.commits.branch IS 'Base Branch ID (foreign key)';
COMMENT ON COLUMN schema.commits.id IS 'Commit ID';
COMMENT ON COLUMN schema.commits.oid IS 'Git Object ID (SHA1)';
COMMENT ON COLUMN schema.commits.committedat IS 'When was it committed?';
COMMENT ON COLUMN schema.commits.author_email IS 'The email in the Git commit.';
COMMENT ON COLUMN schema.commits.author_name IS 'The name in the Git commit.';
COMMENT ON COLUMN schema.commits.author_id IS 'GitHub Author';
COMMENT ON COLUMN schema.commits.message IS 'Git message (co-authorship information)';
COMMENT ON COLUMN schema.commits.additions IS 'The number of additions in this commit.';
COMMENT ON COLUMN schema.commits.deletions IS 'The number of deletions in this commit.';
COMMENT ON COLUMN schema.commits.lastupdated IS 'When was GitHub queried.';
