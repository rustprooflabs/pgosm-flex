-- Revert pgosm-flex:002 from pg

BEGIN;


DROP PROCEDURE osm.append_data_start();
DROP PROCEDURE osm.append_data_finish(BOOLEAN);

DROP TABLE osm.pgosm_flex;

COMMIT;
