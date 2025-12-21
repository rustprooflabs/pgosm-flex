
CREATE OR REPLACE PROCEDURE {schema_name}.routing_prepare_roads_for_routing()
LANGUAGE plpgsql
AS $$

BEGIN

    DROP TABLE IF EXISTS edges_table;
    CREATE TEMP TABLE edges_table AS
    WITH a AS (
    -- Remove as many multi-linestrings as possible with ST_LineMerge() 
    SELECT r.osm_id, r.osm_type, r.maxspeed, r.oneway, r.layer,
            r.route_foot, r.route_cycle, r.route_motor, r.access,
            ST_LineMerge(r.geom) AS geom
        FROM osm.road_line r
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
    SELECT ROW_NUMBER() OVER (ORDER BY geom) AS id
            , *
            -- Compute start/end points here instead of making this part of an expensive JOIN
            -- in the intersection code later.
            , ST_StartPoint(geom) AS geom_start
            , ST_EndPoint(geom) AS geom_end
        FROM combined
        ORDER BY geom
    ;

    CREATE INDEX gix_routing_osm_road_intermediate_geom
        ON edges_table
        USING GIST (geom)
    ;
    CREATE INDEX gix_routing_osm_road_intermediate_geom_start
        ON edges_table
        USING GIST (geom_start)
    ;
    CREATE INDEX gix_routing_osm_road_intermediate_geom_end
        ON edges_table
        USING GIST (geom_end)
    ;
    CREATE UNIQUE INDEX gix_tmp_edges_id
        ON edges_table (id)
    ;
    ANALYZE edges_table;

    RAISE NOTICE 'Edge table table created';



    ------------------------------------------------------------------
    -- Split long lines where there are route-able intersections
    -- Based on `pgr_separateTouching()` from pgRouting 4.0 
    DROP TABLE IF EXISTS initial_intersection;
    CREATE TEMP TABLE initial_intersection AS
    SELECT e1.id AS id1, e2.id AS id2
            , e1.osm_id AS osm_id1, e2.osm_id AS osm_id2
            , e1.geom AS geom1
            , e2.geom AS geom2
            , e1.geom_start AS geom_start1
            , e1.geom_end AS geom_end1
            -- The intersection point is the blade
            , ST_Intersection(e1.geom, e2.geom) AS blade
        FROM edges_table e1
            , edges_table e2
        WHERE
            -- Find all combinations of mismatches.
            e1.id > e2.id
            -- This tolerance should be same (??? should it???) as snap tolerance above
            AND ST_DWithin(e1.geom, e2.geom, 0.1)
            -- They don't share start/end points. If they do, this step doesn't matter.
            AND NOT (
                e1.geom_start = e2.geom_start OR  e1.geom_start = e2.geom_end
                OR e1.geom_end = e2.geom_start OR e1.geom_end = e2.geom_end
            )
    ;

    CREATE INDEX gix_initial_intersection_geom1 ON initial_intersection USING GIST (geom1);
    CREATE INDEX gix_initial_intersection_geom2 ON initial_intersection USING GIST (geom2);
    CREATE INDEX gix_initial_intersection_blade ON initial_intersection USING GIST (blade);

    RAISE NOTICE 'Intersections table created';


    DROP TABLE IF EXISTS split_edges;
    CREATE TEMP TABLE split_edges AS
    WITH stacked AS (
    SELECT i.id1 AS id, i.osm_id1 AS osm_id
            , split.path[1]::BIGINT AS sub_id
            , split.geom
        FROM initial_intersection i
        CROSS JOIN LATERAL st_dump(st_split(st_snap(geom1, blade, 0.1), blade)) split
        WHERE NOT ST_Relate(st_snap(geom1, blade, 0.1), blade, '1********')
           -- AND osm_id1 IN (1171245820, 758283788)
           -- AND osm_id2 IN (1171245820, 758283788)
    UNION
    SELECT i.id2 AS id, i.osm_id2 AS osm_id
            , split.path[1]::BIGINT AS sub_id
            , split.geom
        FROM initial_intersection i
        CROSS JOIN LATERAL st_dump(st_split(st_snap(geom2, blade, 0.1), blade)) split
        WHERE NOT ST_Relate(st_snap(geom2, blade, 0.1), blade, '1********')
           -- AND osm_id1 IN (1171245820, 758283788)
           -- AND osm_id2 IN (1171245820, 758283788)
    )
    SELECT DISTINCT
            row_number() over()::BIGINT AS seq
            , *
        FROM stacked
    ;


    -------------------------------------------------------
    -- Combine the Split edges with the un-split edges
    -- This is the production "edge" table for routing.
    -------------------------------------------------------
    DROP TABLE IF EXISTS {schema_name}.routing_road_edge;
    CREATE TABLE {schema_name}.routing_road_edge AS
    WITH split_lines AS (
    SELECT r.id AS parent_id, spl.sub_id, r.osm_id, r.osm_type, r.maxspeed, r.oneway, r.layer
            , route_foot, route_cycle, route_motor
            , r.access, spl.geom
        FROM edges_table r
        INNER JOIN split_edges spl
            ON r.id = spl.id
    ), unsplit_lines AS (
    SELECT r.id AS parent_id, 1::INT AS sub_id, r.osm_id, r.osm_type, r.maxspeed, r.oneway, r.layer
            , route_foot, route_cycle, route_motor
            , r.access, r.geom
        FROM edges_table r
    LEFT JOIN split_edges spl
        ON r.id = spl.id
    WHERE spl.id IS NULL
    )
    SELECT *
        FROM split_lines
    UNION
    SELECT *
        FROM unsplit_lines
    ;

    COMMENT ON TABLE {schema_name}.routing_road_edge IS 'OSM road data setup for edges for routing for motorized travel';
    ALTER TABLE {schema_name}.routing_road_edge
        ADD edge_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY;
    ALTER TABLE {schema_name}.routing_road_edge
        ADD source BIGINT;
    ALTER TABLE {schema_name}.routing_road_edge
        ADD target BIGINT;

    /*
    ALTER TABLE {schema_name}.routing_road_edge
        ADD CONSTRAINT uq_routing_road_edges_parent_id_sub_id
        UNIQUE (parent_id, sub_id)
    ;
    */
    RAISE NOTICE 'routing_osm_road_edge table created';
    RAISE WARNING 'Not adding a unique constraint that should exist... data cleanup needed.';


    DROP TABLE IF EXISTS {schema_name}.routing_road_vertex;
    CREATE TABLE {schema_name}.routing_road_vertex AS
    SELECT  * FROM pgr_extractVertices(
    'SELECT edge_id AS id, geom FROM {schema_name}.routing_road_edge')
    ;
    RAISE NOTICE 'routing_osm_road_vertex table created';

    --  Update source column from out_edges
    WITH outgoing AS (
        SELECT id AS source
            , unnest(out_edges) AS edge_id
    FROM {schema_name}.routing_road_vertex
    )
    UPDATE {schema_name}.routing_road_edge e
    SET source = o.source
    FROM outgoing o
    WHERE e.edge_id = o.edge_id
        AND e.source IS NULL
    ;

    -- Update target column from in_edges
    WITH incoming AS (
        SELECT id AS target
            , unnest(in_edges) AS edge_id
    FROM {schema_name}.routing_road_vertex
    )
    UPDATE {schema_name}.routing_road_edge e
    SET target = i.target
    FROM incoming i
    WHERE e.edge_id = i.edge_id
        AND e.target IS NULL
    ;
    
    ANALYZE {schema_name}.routing_road_vertex;
    ANALYZE {schema_name}.routing_road_edge;

END $$;

