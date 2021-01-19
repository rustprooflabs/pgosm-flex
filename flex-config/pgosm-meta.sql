COMMENT ON SCHEMA osm IS 'Schema populated by PgOSM-Flex.  SELECT * FROM osm.pgosm_flex; for details.';
COMMENT ON TABLE osm.pgosm_flex IS 'Provides meta information on the PgOSM-Flex project including version and SRID used during the import.';

ALTER TABLE osm.pgosm_flex ADD COLUMN ts TIMESTAMPTZ DEFAULT NOW();

COMMENT ON COLUMN osm.pgosm_flex.ts IS 'Indicates when the post-processing SQL script was ran, NOT necessarily when the source file is from.';

