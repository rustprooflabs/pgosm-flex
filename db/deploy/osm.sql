/*
    Creating the PostGIS extension is intended for entirely in-Docker use only.

    If you are using an external database with a non-superuser role (RECOMMENDED)
    this will fail.  This is not a bug.
    See the Permissions section in the user guide for more:
        https://pgosm-flex.com/postgres-permissions.html
*/
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS osm;
COMMENT ON SCHEMA osm IS 'Schema populated by PgOSM Flex.  SELECT * FROM osm.pgosm_flex; for details.';
