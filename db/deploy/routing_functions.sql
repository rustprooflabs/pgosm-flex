CREATE OR REPLACE PROCEDURE {schema_name}.pgrouting_version_check()
LANGUAGE plpgsql
AS $$
    DECLARE pgr_ver TEXT;
BEGIN
        -- Ensure pgRouting extension exists with at least pgRouting 4.0
        IF NOT EXISTS (
            SELECT 1 FROM pg_extension WHERE extname = 'pgrouting'
        ) THEN
            RAISE EXCEPTION
                'pgRouting extension is not installed. Version >= 4.0 required.';
        END IF;

        -- Get pgRouting version
        SELECT pgr_version() INTO pgr_ver;

        -- Enforce minimum version
        IF string_to_array(pgr_ver, '.')::INT[] < ARRAY[4,0] THEN
            RAISE EXCEPTION
                'pgRouting version % detected. Version >= 4.0 required.',
                pgr_ver;
        END IF;

END $$;


COMMENT ON PROCEDURE {schema_name}.pgrouting_version_check IS 'Ensures appropriate pgRouting extension is installed with an appropriate version.';



CREATE OR REPLACE PROCEDURE {schema_name}.routing_prepare_edge_network()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Requires `route_edge_input` temp table with columns:
    --   osm_id, layer, geom


    DROP TABLE IF EXISTS edges_table;
    CREATE TEMP TABLE edges_table AS
    WITH a AS (
    -- Remove as many multi-linestrings as possible with ST_LineMerge() 
    SELECT r.osm_id, r.layer
            , ST_LineMerge(r.geom) AS geom
        FROM route_edge_input r
    ), extra_cleanup AS (
    -- Pull out those that are still multi, use ST_Dump() to pull out parts
    SELECT osm_id, layer
            , (ST_Dump(geom)).geom AS geom
        FROM a 
        WHERE ST_GeometryType(geom) = 'ST_MultiLineString'
    ), combined AS (
    -- Combine two sources
    SELECT osm_id, layer
            , geom
        FROM a
        WHERE ST_GeometryType(geom) != 'ST_MultiLineString'
    UNION
    SELECT osm_id, layer
            , geom
        FROM extra_cleanup
        -- Some data may be lost here if multi-linestring somehow
        -- persists through the extra_cleanup query
        WHERE ST_GeometryType(geom) != 'ST_MultiLineString'
    )
    -- Calculate a new surrogate ID for key
    SELECT ROW_NUMBER() OVER (ORDER BY geom) AS id
            , osm_id, layer, geom
            -- Compute start/end points here instead of making this part of an expensive JOIN
            -- in the intersection code later.
            , ST_StartPoint(geom) AS geom_start
            , ST_EndPoint(geom) AS geom_end
        FROM combined
        ORDER BY geom
    ;

    CREATE INDEX gix_tmp_edges_table_geom
        ON edges_table
        USING GIST (geom)
    ;
    CREATE INDEX gix_tmp_edges_table_geom_start
        ON edges_table
        USING GIST (geom_start)
    ;
    CREATE INDEX gix_tmp_edges_table_geom_end
        ON edges_table
        USING GIST (geom_end)
    ;
    CREATE UNIQUE INDEX gix_tmp_edges_table_id
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
            , e1.layer AS layer1, e2.layer AS layer2
            , e1.geom AS geom1
            , e2.geom AS geom2
            , e1.geom_start AS geom_start1
            , e1.geom_end AS geom_end1
            , e2.geom_start AS geom_start2
            , e2.geom_end AS geom_end2
            -- The intersection point is the blade
            , ST_Intersection(e1.geom, e2.geom) AS blade
        FROM edges_table e1
            , edges_table e2
        WHERE
            -- Find all combinations of mismatches.
            e1.id != e2.id
            -- This tolerance finds general proximity, later refined.
            -- Probably can speed up by switching to simple && bbox query.
            AND e1.geom && e2.geom
            --AND ST_DWithin(e1.geom, e2.geom, 0.1)
            -- Don't split line if not on same layer
            AND e1.layer = e2.layer
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


    -- Create the combination of lines to be split with all points to use for blades.
    -- Looking at both directions for id1/id2 pairs.
    DROP TABLE IF EXISTS geom_with_blade;
    CREATE TABLE geom_with_blade AS 
    SELECT id1 AS id, osm_id1 AS osm_id, geom1 AS geom
            , ST_UnaryUnion(ST_Collect(ST_PointOnSurface(blade))) AS blades
        FROM initial_intersection
        -- Exclude blades same as start/end points
        WHERE blade NOT IN (geom_start1, geom_end1)
        GROUP BY id1, osm_id1, geom1
    UNION
    SELECT id2 AS id, osm_id2 AS osm_id, geom2 AS geom
            , ST_UnaryUnion(ST_Collect(ST_PointOnSurface(blade))) AS blades
        FROM initial_intersection
        -- Exclude blades same as start/end points
        WHERE blade NOT IN (geom_start2, geom_end2)
        GROUP BY id2, osm_id2, geom2
    ;

    -- Split lines using blades. Assign new `seq` ID (legacy reasons, try to improve this...)
    -- Splitting no longer uses snapping. OpenStreetMap edge data should be properly
    -- connected with shared nodes if there is a true path. Missing nodes in
    -- data should be fixed in OpenStreetMap data directly instead of trying
    -- to make that step happen here.
    DROP TABLE IF EXISTS split_edges;
    CREATE TEMP TABLE split_edges AS
    WITH splits AS (
    SELECT i.id, i.osm_id
            , split.path[1]::BIGINT AS sub_id
            , split.geom
        FROM geom_with_blade i
        CROSS JOIN LATERAL st_dump(st_split(i.geom, blades)) split
        WHERE NOT ST_Relate(i.geom, blades, '1********')
            AND split.geom <> i.geom -- Exclude any unchanged records
            AND NOT ST_IsEmpty(blades) -- Exclude any blades that ended up empty
    )
    SELECT row_number() over()::BIGINT AS seq
            , *
        FROM splits
    ;

    -------------------------------------------------------
    -- Combine the Split edges with the un-split edges
    -- This is the initial production edge table for routing.
    -------------------------------------------------------
    DROP TABLE IF EXISTS route_edges_output;
    CREATE TEMP TABLE route_edges_output AS
    WITH split_lines AS (
    SELECT r.id AS parent_id
            , spl.sub_id
            , r.osm_id, r.layer
            , spl.geom
        FROM edges_table r
        INNER JOIN split_edges spl
            ON r.id = spl.id
    ), unsplit_lines AS (
    SELECT r.id AS parent_id
            , 1::INT AS sub_id
            , r.osm_id, r.layer
            , r.geom
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

    RAISE NOTICE 'Edge data in route_edges_output temp table. Persist the output to save it.';
    -- Outputs:  `route_edges_output` temp table.
END $$;

COMMENT ON PROCEDURE {schema_name}.routing_prepare_edge_network() IS 'Requires `route_edge_input` temp table as input, creates `route_edges_output` temp table as output.';



CREATE OR REPLACE PROCEDURE {schema_name}.routing_prepare_road_network()
LANGUAGE plpgsql
AS $$
BEGIN

    CALL {schema_name}.pgrouting_version_check();

    --Create edges table for input to routing_prepare_edge_network procedure
    DROP TABLE IF EXISTS route_edge_input;
    CREATE TEMP TABLE route_edge_input AS
    SELECT osm_id, layer, geom
        FROM {schema_name}.road_line
    ;

    -- Creates the `route_edges_output` table.
    CALL {schema_name}.routing_prepare_edge_network();


    DROP TABLE IF EXISTS {schema_name}.routing_road_edge;
    CREATE TABLE {schema_name}.routing_road_edge
    (
        edge_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY
        , osm_id BIGINT NOT NULL
        , sub_id BIGINT NOT NULL
        , vertex_id_source BIGINT
        , vertex_id_target BIGINT
        , layer INT
        , major BOOLEAN
        , route_foot BOOLEAN
        , route_cycle BOOLEAN
        , route_motor BOOLEAN
        , osm_type TEXT NOT NULL
        , name TEXT
        , ref TEXT
        , maxspeed NUMERIC
        , oneway INT2
        , tunnel TEXT
        , bridge TEXT
        , access TEXT
        , geom GEOMETRY(LINESTRING)
        --, UNIQUE (osm_id, sub_id) -- Currently not enforceable... dups exist...
    );

    INSERT INTO {schema_name}.routing_road_edge (
        osm_id, sub_id, osm_type, name, ref, maxspeed, oneway, layer, tunnel, bridge, major
        , route_foot, route_cycle, route_motor, access
        , geom
    )
    SELECT re.osm_id, re.sub_id
            , r.osm_type, r.name, r.ref, r.maxspeed
            , r.oneway, re.layer, r.tunnel, r.bridge, r.major
            , r.route_foot, r.route_cycle, r.route_motor, r.access
            , re.geom
        FROM route_edges_output re
        INNER JOIN {schema_name}.road_line r ON re.osm_id = r.osm_id
        ORDER BY re.geom
    ;

    CREATE INDEX gix_{schema_name}_routing_road_edge
        ON {schema_name}.routing_road_edge
        USING GIST (geom)
    ;

    RAISE NOTICE 'Created table {schema_name}.routing_road_edge with edge data';


    ALTER TABLE {schema_name}.routing_road_edge
        ADD cost_length DOUBLE PRECISION NULL;

    UPDATE {schema_name}.routing_road_edge
        SET cost_length = ST_Length(ST_Transform(geom, 4326)::GEOGRAPHY)
    ;

    COMMENT ON COLUMN {schema_name}.routing_road_edge.cost_length IS 'Length based cost calculated using GEOGRAPHY for accurate length.';


    -- Add forward cost column, enforcing oneway restrictions
    ALTER TABLE {schema_name}.routing_road_edge
        ADD cost_length_forward NUMERIC
        GENERATED ALWAYS AS (
            CASE WHEN oneway IN (0, 1) OR oneway IS NULL
                    THEN cost_length
                WHEN oneway = -1
                    THEN -1 * cost_length
                END
        )
        STORED
    ;

    -- Add reverse cost column, enforcing oneway restrictions
    ALTER TABLE {schema_name}.routing_road_edge
        ADD cost_length_reverse NUMERIC
        GENERATED ALWAYS AS (
            CASE WHEN oneway IN (0, -1) OR oneway IS NULL
                    THEN cost_length
                WHEN oneway = 1
                    THEN -1 * cost_length
                END
        )
        STORED
    ;

    COMMENT ON COLUMN {schema_name}.routing_road_edge.cost_length_forward IS 'Length based cost for forward travel with directed routing. Based on cost_length value.';
    COMMENT ON COLUMN {schema_name}.routing_road_edge.cost_length_reverse IS 'Length based cost for reverse travel with directed routing. Based on cost_length value.';


    DROP TABLE IF EXISTS {schema_name}.routing_road_vertex;
    CREATE TABLE {schema_name}.routing_road_vertex AS
    SELECT  * FROM pgr_extractVertices(
    'SELECT edge_id AS id, geom FROM {schema_name}.routing_road_edge')
    ;
    RAISE NOTICE 'Created table {schema_name}.routing_road_vertex from edges.';

    CREATE INDEX gix_{schema_name}_routing_road_vertex
        ON {schema_name}.routing_road_vertex
        USING GIST (geom)
    ;

    --  Update source column from out_edges
    WITH outgoing AS (
        SELECT id AS vertex_id_source
            , unnest(out_edges) AS edge_id
    FROM {schema_name}.routing_road_vertex
    )
    UPDATE {schema_name}.routing_road_edge e
    SET vertex_id_source = o.vertex_id_source
    FROM outgoing o
    WHERE e.edge_id = o.edge_id
        AND e.vertex_id_source IS NULL
    ;

    -- Update target column from in_edges
    WITH incoming AS (
        SELECT id AS vertex_id_target
            , unnest(in_edges) AS edge_id
    FROM {schema_name}.routing_road_vertex
    )
    UPDATE {schema_name}.routing_road_edge e
    SET vertex_id_target = i.vertex_id_target
    FROM incoming i
    WHERE e.edge_id = i.edge_id
        AND e.vertex_id_target IS NULL
    ;
    

    ANALYZE {schema_name}.routing_road_edge;
    ANALYZE {schema_name}.routing_road_vertex;

    COMMENT ON TABLE {schema_name}.routing_road_vertex IS 'Routing vertex data. These points can be used as the start/end points for routing the edge network in {schema_name}.routing_road_edge..';

END $$;


COMMENT ON PROCEDURE {schema_name}.routing_prepare_road_network IS 'Creates the {schema_name}.routing_road_edge and {schema_name}.routing_road_vertex from the {schema_name}.road_line input data';



--------------------------------------------------
-- Waterway routing prep
--------------------------------------------------


CREATE OR REPLACE PROCEDURE {schema_name}.routing_prepare_water_network()
LANGUAGE plpgsql
AS $$
BEGIN

    CALL {schema_name}.pgrouting_version_check();

    --Create edges table for input to routing_prepare_edge_network procedure
    DROP TABLE IF EXISTS route_edge_input;
    CREATE TEMP TABLE route_edge_input AS
    SELECT osm_id, layer, geom
        FROM {schema_name}.water_line
    ;

    -- Creates the `route_edges_output` table.
    CALL {schema_name}.routing_prepare_edge_network();


    DROP TABLE IF EXISTS {schema_name}.routing_water_edge;
    CREATE TABLE {schema_name}.routing_water_edge
    (
        edge_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY
        , osm_id BIGINT NOT NULL
        , sub_id BIGINT NOT NULL
        , vertex_id_source BIGINT
        , vertex_id_target BIGINT
        , layer INT
        , osm_type TEXT NOT NULL
        , name TEXT
        , tunnel TEXT
        , bridge TEXT
        , geom GEOMETRY(LINESTRING)
    );

    INSERT INTO {schema_name}.routing_water_edge (
        osm_id, sub_id, osm_type, name, layer, tunnel, bridge
        , geom
    )
    SELECT re.osm_id, re.sub_id
            , r.osm_type, r.name
            , re.layer, r.tunnel, r.bridge
            , re.geom
        FROM route_edges_output re
        INNER JOIN {schema_name}.water_line r ON re.osm_id = r.osm_id
        ORDER BY re.geom
    ;

    CREATE INDEX gix_{schema_name}_routing_water_edge
        ON {schema_name}.routing_water_edge
        USING GIST (geom)
    ;

    RAISE NOTICE 'Created table {schema_name}.routing_water_edge with edge data';


    ALTER TABLE {schema_name}.routing_water_edge
        ADD cost_length DOUBLE PRECISION NULL;

    UPDATE {schema_name}.routing_water_edge
        SET cost_length = ST_Length(ST_Transform(geom, 4326)::GEOGRAPHY)
    ;

    COMMENT ON COLUMN {schema_name}.routing_water_edge.cost_length IS 'Length based cost calculated using GEOGRAPHY for accurate length.';


    -- Add forward cost column, enforcing oneway restrictions
    ALTER TABLE {schema_name}.routing_water_edge
        ADD cost_length_forward NUMERIC
        GENERATED ALWAYS AS (cost_length)
        STORED
    ;

    -- Add reverse cost column, enforcing oneway restrictions
    ALTER TABLE {schema_name}.routing_water_edge
        ADD cost_length_reverse NUMERIC
        GENERATED ALWAYS AS (-1 * cost_length)
        STORED
    ;

    COMMENT ON COLUMN {schema_name}.routing_water_edge.cost_length_forward IS 'Length based cost for forward travel with directed routing. Based on cost_length value.';
    COMMENT ON COLUMN {schema_name}.routing_water_edge.cost_length_reverse IS 'Length based cost for reverse travel with directed routing. Based on cost_length value.';


    DROP TABLE IF EXISTS {schema_name}.routing_water_vertex;
    CREATE TABLE {schema_name}.routing_water_vertex AS
    SELECT  * FROM pgr_extractVertices(
    'SELECT edge_id AS id, geom FROM {schema_name}.routing_water_edge')
    ;
    RAISE NOTICE 'Created table {schema_name}.routing_water_vertex from edges.';

    CREATE INDEX gix_{schema_name}_routing_water_vertex
        ON {schema_name}.routing_water_vertex
        USING GIST (geom)
    ;

    --  Update source column from out_edges
    WITH outgoing AS (
        SELECT id AS vertex_id_source
            , unnest(out_edges) AS edge_id
    FROM {schema_name}.routing_water_vertex
    )
    UPDATE {schema_name}.routing_water_edge e
    SET vertex_id_source = o.vertex_id_source
    FROM outgoing o
    WHERE e.edge_id = o.edge_id
        AND e.vertex_id_source IS NULL
    ;

    -- Update target column from in_edges
    WITH incoming AS (
        SELECT id AS vertex_id_target
            , unnest(in_edges) AS edge_id
    FROM {schema_name}.routing_water_vertex
    )
    UPDATE {schema_name}.routing_water_edge e
    SET vertex_id_target = i.vertex_id_target
    FROM incoming i
    WHERE e.edge_id = i.edge_id
        AND e.vertex_id_target IS NULL
    ;


    ANALYZE {schema_name}.routing_water_edge;
    ANALYZE {schema_name}.routing_water_vertex;

    COMMENT ON TABLE {schema_name}.routing_water_vertex IS 'Routing vertex data. These points can be used as the start/end points for routing the edge network in {schema_name}.routing_water_edge..';


END $$;


COMMENT ON PROCEDURE {schema_name}.routing_prepare_water_network IS 'Creates the {schema_name}.routing_water_edge and {schema_name}.routing_water_vertex from the {schema_name}.water_line input data';
