SELECT *
    FROM osm.pgosm_flex
;


CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE SCHEMA IF NOT EXISTS routing;


SELECT postgis_full_version(), pgr_version();



CREATE TABLE routing.road_line AS
WITH a AS (
-- Remove as many multi-linestrings as possible with ST_LineMerge() 
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        ST_LineMerge(geom) AS geom
    FROM osm.road_line
), extra_cleanup AS (
-- Pull out those that are still multi, use ST_Dump() to pull out parts
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        (ST_Dump(geom)).geom AS geom
    FROM a 
    WHERE ST_GeometryType(geom) = 'ST_MultiLineString'
), combined AS (
-- Combine two sources
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        geom
    FROM a
    WHERE ST_GeometryType(geom) != 'ST_MultiLineString'
UNION
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        geom
    FROM extra_cleanup
    -- Some data may be lost here if multi-linestring somehow
    -- persists through the extra_cleanup query
    WHERE ST_GeometryType(geom) != 'ST_MultiLineString'
)
-- Calculate a new surrogate ID for key
SELECT ROW_NUMBER() OVER (ORDER BY geom) AS id, *
    FROM combined
    ORDER BY geom
;



COMMENT ON COLUMN routing.road_line.id IS 'Surrogate ID, cannot rely on osm_id being unique after converting multi-linestrings to linestrings.';
ALTER TABLE routing.road_line
    ADD CONSTRAINT pk_routing_road_line PRIMARY KEY (id)
;
CREATE INDEX ix_routing_road_line_osm_id
    ON routing.road_line (osm_id)
;


SELECT COUNT(*) FROM routing.road_line WHERE route_motor


--SELECT pgr_nodeNetwork('routing.road_line', 0.1, 'id', 'geom');
/*
 * Seperate Crossing splits at intersections with actual crossings where both lines
 * extend to the other side.
 * It does NOT split long lines at intersections where one section extends past
 * another section.  AKA - T-Intersections. 
 * Unless Routing functions have become more flexible, this will NOT work with
 * most common traffic routing use cases.
 * 
 * The ID comes through the new table with a new sub_id value.
 * Only creates records where splitting was done.
 * 
 * Fort Collins sub-region took ~30 seconds
 */
DROP TABLE IF EXISTS routing.road_separate_crossing;
--started at 8:20:30
CREATE TABLE routing.road_separate_crossing AS
SELECT *
FROM pgr_separateCrossing('SELECT id, geom FROM routing.road_line WHERE route_motor', dryrun => false)
;

/*
 * Takes much longer than pgr_separateCrossing
 * 
 * Seperate Crossing splits at touch points where two lines intersect
 * This DOES split long lines at intersections where one section intersects another
 * in the middle, AKA t-intesections
 * 
 * The ID comes through the new table with a new sub_id value.
 * Only creates records where splitting was done. Will need to merge with
 * unsplit lines from source table.
 * 
 * Fort Collins sub-region took 9 minutes (25k inputs, 21k outputs)
 * 
 * NOTE: Only seq, id, sub_id, and geom columns make it to final table. Does not help
 * to pass in SELECT * thinking you'll get all the columns in the final table.
 * (I tried to be lazier in later steps)
 */
DROP TABLE IF EXISTS routing.road_separate_touching;
CREATE TABLE routing.road_separate_touching AS
SELECT *
FROM pgr_separateTouching('SELECT id, geom FROM routing.road_line WHERE route_motor', dryrun => false)
;



SELECT * FROM routing.road_line
;
SELECT * FROM routing.road_separate_touching
;

DROP TABLE IF EXISTS routing.road_motor_edges;
CREATE TABLE routing.road_motor_edges AS
WITH split_lines AS (
SELECT r.id AS parent_id, spl.sub_id, r.osm_id, r.osm_type, r.maxspeed, r.oneway, r.layer
        , r.access, spl.geom
    FROM routing.road_line r
    INNER JOIN routing.road_separate_touching spl
        ON r.id = spl.id
    WHERE route_motor
), unsplit_lines AS (
SELECT r.id AS parent_id, 1::INT AS sub_id, r.osm_id, r.osm_type, r.maxspeed, r.oneway, r.layer
        , r.access, r.geom
    FROM routing.road_line r
    LEFT JOIN routing.road_separate_touching spl
        ON r.id = spl.id
    WHERE spl.id IS NULL
        AND r.route_motor
)
SELECT *
    FROM split_lines
UNION
SELECT *
    FROM unsplit_lines
;

COMMENT ON TABLE routing.road_motor_edges IS 'OSM road data setup for edges for routing for motorized travel';
ALTER TABLE routing.road_motor_edges
    ADD edge_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY;
ALTER TABLE routing.road_motor_edges
    ADD source BIGINT;
ALTER TABLE routing.road_motor_edges
    ADD target BIGINT;
;
ALTER TABLE routing.road_motor_edges
    ADD CONSTRAINT uq_routing_road_motor_edges_parent_id_sub_id
    UNIQUE (parent_id, sub_id)
;


-----------------------------------------------------------------------
-- SELECT pgr_createTopology('routing.road_line_noded', 0.1, 'geom');
-----------------------------------------------------------------------
DROP TABLE IF EXISTS routing.road_motor_vertices;
CREATE TABLE routing.road_motor_vertices AS
SELECT  * FROM pgr_extractVertices(
  'SELECT edge_id AS id, geom FROM routing.road_motor_edges')
;




SELECT * 
FROM routing.road_motor_vertices
WHERE in_edges IS NOT NULL
    OR out_edges IS NOT NULL
;



-------------------------------------------------
--SELECT pgr_analyzeGraph('routing.road_line_noded', 0.1, 'geom');

--  Update source column from out_edges

WITH outgoing AS (
    SELECT id AS source
        , unnest(out_edges) AS edge_id
        --, x, y
  FROM routing.road_motor_vertices
)
UPDATE routing.road_motor_edges e
SET source = o.source--, x1 = x, y1 = y
FROM outgoing o
WHERE e.edge_id = o.edge_id
    AND e.source IS NULL
;

-- Update target colum from in_edges
WITH incoming AS (
    SELECT id AS target
        , unnest(in_edges) AS edge_id
        --, x, y
  FROM routing.road_motor_vertices
)
UPDATE routing.road_motor_edges e
SET target = i.target--, x1 = x, y1 = y
FROM incoming i
WHERE e.edge_id = i.edge_id
    AND e.target IS NULL
;


SELECT *
    FROM routing.road_motor_edges
;



---------------------- 
-- TRYING TO CONTINUE HERE!
ALTER TABLE routing.road_motor_edges
    ADD cost_length DOUBLE PRECISION NOT NULL
    GENERATED ALWAYS AS (ST_Length(geom))
    STORED;


/*
 * v_start: 12181
*  v_end: 10402
 */


SELECT * FROM routing.road_motor_edges;
SELECT * FROM routing.road_motor_vertices;


SELECT d.*, n.geom AS node_geom, e.geom AS edge_geom
    FROM pgr_dijkstra(
        'SELECT edge_id AS id, source, target, cost_length AS cost,
                geom
            FROM routing.road_motor_edges
            ',
            :start_id, :end_id, directed := False
        ) d
    INNER JOIN routing.road_motor_vertices n ON d.node = n.id
    LEFT JOIN routing.road_motor_edges e ON d.edge = e.edge_id
;



