CREATE TABLE IF NOT EXISTS schema.pats (
    login text,
    token text NOT NULL,
    CONSTRAINT pats_pkey PRIMARY KEY (login)
);
