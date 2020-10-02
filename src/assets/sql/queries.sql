CREATE TABLE IF NOT EXISTS schema.queries (
    spdx text NOT NULL,
    created tsrange NOT NULL,
    count smallint NOT NULL,
    asof timestamp NOT NULL DEFAULT date_trunc('second', current_timestamp AT TIME ZONE 'UTC')::timestamp,
    done bool NOT NULL DEFAULT false,
    CONSTRAINT nonoverlappingqueries EXCLUDE USING gist (created WITH &&, spdx WITH =)
);
COMMENT ON TABLE schema.queries IS 'This table is a tracker for queries';
COMMENT ON COLUMN schema.queries.spdx IS 'The SPDX license ID';
COMMENT ON COLUMN schema.queries.created IS 'The time interval for the query';
COMMENT ON COLUMN schema.queries.count IS 'How many results for the query';
COMMENT ON COLUMN schema.queries.asof IS 'When was GitHub queried about the information.';
COMMENT ON COLUMN schema.queries.done IS 'Has the repositories been collected?';
COMMENT ON CONSTRAINT nonoverlappingqueries ON schema.queries IS 'No duplicate for queries';
