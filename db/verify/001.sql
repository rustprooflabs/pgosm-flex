-- Verify pgosm-flex:001 on pg

BEGIN;

SELECT id, maxspeed, maxspeed_mph
	FROM pgosm.road
	WHERE False
;

ROLLBACK;
