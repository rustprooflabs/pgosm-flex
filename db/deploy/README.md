# PgOSM Flex SQL deploy scripts

The scripts in this folder are executed during PgOSM Flex initialization via
the `prepare_osm_schema()` function in `docker/db.py`.
New or removed files in this folder must be adjusted in that function
as appropriate.
