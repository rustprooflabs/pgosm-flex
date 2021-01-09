/*
  Quality control queries to identify features not pulled into feature tables
  with run-all.lua.
*/
DROP TABLE IF EXISTS osm_missing;

CREATE TEMP TABLE osm_missing AS
SELECT geom_type, osm_id
    FROM osm.tags
;

CREATE INDEX ix_osm_missing ON osm_missing (osm_id);



--------------------------------------------
-- Remove matches in POINT (node) tables
--------------------------------------------
DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.amenity_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);


DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.building_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.indoor_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.infrastructure_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.natural_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.place_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.shop_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.traffic_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.water_point i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'N'
);




--------------------------------------------
-- Remove matches in Line/Polygon (way) tables
--------------------------------------------

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.amenity_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.amenity_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);


DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.building_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);


DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.indoor_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.natural_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.natural_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.place_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.place_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.road_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.road_major i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.shop_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.traffic_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.traffic_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.water_line i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);

DELETE FROM osm_missing m
    WHERE EXISTS (
        SELECT 1
            FROM osm.water_polygon i
            WHERE m.osm_id = i.osm_id AND m.geom_type = 'W'
);


WITH missing_tags AS (
SELECT t.*
    FROM osm_missing m 
    INNER JOIN osm.tags t ON m.geom_type = t.geom_type AND m.osm_id = t.osm_id
)
SELECT jsonb_object_keys(tags), COUNT(*)
    FROM missing_tags
    GROUP BY  jsonb_object_keys(tags)
    ORDER BY COUNT(*) DESC
;

