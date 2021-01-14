CREATE TABLE IF NOT EXISTS schema.repos (
    id text PRIMARY KEY,
    spdx character varying(12) NOT NULL,
    slug text NOT NULL,
    createdat timestamp NOT NULL,
    description text,
    primarylanguage text,
    branch text,
    commits bigint NOT NULL,
    asof timestamp NOT NULL DEFAULT date_trunc('second', current_timestamp AT TIME ZONE 'UTC')::timestamp,
    status text NOT NULL DEFAULT 'Init',
    CONSTRAINT repos_branch UNIQUE (branch)
);
COMMENT ON TABLE schema.repos IS 'Repository ID and base branch ID';
COMMENT ON COLUMN schema.repos.id IS 'Repository ID';
COMMENT ON COLUMN schema.repos.spdx IS 'SPDX license ID';
COMMENT ON COLUMN schema.repos.slug IS 'Location of the respository';
COMMENT ON COLUMN schema.repos.createdat IS 'When was the repository created on GitHub?';
COMMENT ON COLUMN schema.repos.description IS 'Description of the respository';
COMMENT ON COLUMN schema.repos.primarylanguage IS 'Primary language of the respository';
COMMENT ON COLUMN schema.repos.branch IS 'Base branch ID';
COMMENT ON COLUMN schema.repos.commits IS 'Number of commits in the branch until the end of the observation period';
COMMENT ON COLUMN schema.repos.asof IS 'When was GitHub queried?';
COMMENT ON COLUMN schema.repos.status IS 'Status of collection effort';
