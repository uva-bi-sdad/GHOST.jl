CREATE TABLE IF NOT EXISTS schema.licenses (
    spdx character varying(12) PRIMARY KEY,
    name character varying(47) NOT NULL
);
COMMENT ON TABLE schema.licenses IS 'OSI-approved machine detectable licenses';
COMMENT ON COLUMN schema.licenses.spdx IS 'SPDX license ID';
COMMENT ON COLUMN schema.licenses.name IS 'Name of the license';
