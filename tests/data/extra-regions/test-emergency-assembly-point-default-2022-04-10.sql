--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2 (Debian 14.2-1.pgdg110+1)
-- Dumped by pg_dump version 14.2 (Debian 14.2-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: osm; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA osm;


ALTER SCHEMA osm OWNER TO postgres;

--
-- Name: SCHEMA osm; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA osm IS 'Schema populated by PgOSM-Flex.  SELECT * FROM osm.pgosm_flex; for details.';


--
-- Name: pgosm; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA pgosm;


ALTER SCHEMA pgosm OWNER TO postgres;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA IF NOT EXISTS public;


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: append_data_finish(boolean); Type: PROCEDURE; Schema: osm; Owner: postgres
--

CREATE PROCEDURE osm.append_data_finish(IN skip_nested boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $_$
 BEGIN

    REFRESH MATERIALIZED VIEW osm.vplace_polygon;
    REFRESH MATERIALIZED VIEW osm.vplace_polygon_subdivide;
    REFRESH MATERIALIZED VIEW osm.vpoi_all;

    IF $1 = False THEN
        RAISE NOTICE 'Populating nested place table';
        CALL osm.populate_place_polygon_nested();
        RAISE NOTICE 'Calculating nesting of place polygons';
        CALL osm.build_nested_admin_polygons();

    END IF;


END $_$;


ALTER PROCEDURE osm.append_data_finish(IN skip_nested boolean) OWNER TO postgres;

--
-- Name: PROCEDURE append_data_finish(IN skip_nested boolean); Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON PROCEDURE osm.append_data_finish(IN skip_nested boolean) IS 'Finalizes PgOSM Flex after osm2pgsql-replication.  Refreshes materialized view and (optionally) processes the place_polygon_nested data.';


--
-- Name: append_data_start(); Type: PROCEDURE; Schema: osm; Owner: postgres
--

CREATE PROCEDURE osm.append_data_start()
    LANGUAGE plpgsql
    AS $$

 BEGIN

    RAISE NOTICE 'Truncating table osm.place_polygon_nested;';
    TRUNCATE TABLE osm.place_polygon_nested;

END $$;


ALTER PROCEDURE osm.append_data_start() OWNER TO postgres;

--
-- Name: PROCEDURE append_data_start(); Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON PROCEDURE osm.append_data_start() IS 'Prepares PgOSM Flex database for running osm2pgsql in append mode.  Removes records from place_polygon_nested if they existed.';


--
-- Name: build_nested_admin_polygons(bigint); Type: PROCEDURE; Schema: osm; Owner: postgres
--

CREATE PROCEDURE osm.build_nested_admin_polygons(IN batch_row_limit bigint DEFAULT 100)
    LANGUAGE plpgsql
    AS $_$
 DECLARE
     rows_to_update BIGINT;
 BEGIN

 SELECT  COUNT(*) INTO rows_to_update
     FROM osm.place_polygon_nested r
     WHERE nest_level IS NULL
 ;
 RAISE NOTICE 'Rows to update: %', rows_to_update;
 RAISE NOTICE 'Updating in batches of % rows', $1;

 FOR counter IN 1..rows_to_update by $1 LOOP

    DROP TABLE IF EXISTS places_for_nesting;
    CREATE TEMP TABLE places_for_nesting AS
    SELECT p.osm_id
        FROM osm.place_polygon_nested p
        WHERE p.name IS NOT NULL
            AND (admin_level IS NOT NULL
                OR osm_type IN ('boundary', 'admin_level', 'suburb',
                             'neighbourhood')
                )
    ;
    CREATE UNIQUE INDEX tmp_ix_places_for_nesting
        ON places_for_nesting (osm_id);


    DROP TABLE IF EXISTS place_batch;
    CREATE TEMP TABLE place_batch AS
    SELECT p.osm_id, t.nest_level, t.name_path, t.osm_id_path, t.admin_level_path
        FROM osm.vplace_polygon p
        INNER JOIN LATERAL (
            SELECT COUNT(i.osm_id) AS nest_level,
                    ARRAY_AGG(i.name ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS name_path,
                    ARRAY_AGG(i.osm_id ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS osm_id_path,
                    ARRAY_AGG(COALESCE(i.admin_level::INT, 99::INT) ORDER BY i.admin_level ASC) AS admin_level_path
                FROM osm.vplace_polygon i
                WHERE ST_Within(p.geom, i.geom)
                    AND EXISTS (
                            SELECT 1 FROM places_for_nesting include
                                WHERE i.osm_id = include.osm_id
                        )
                    AND i.name IS NOT NULL
               ) t ON True
        WHERE EXISTS (
                SELECT 1 FROM osm.place_polygon_nested miss
                    WHERE miss.nest_level IS NULL
                    AND p.osm_id = miss.osm_id
        )
        AND EXISTS (
                SELECT 1 FROM places_for_nesting include
                    WHERE p.osm_id = include.osm_id
            )
    LIMIT $1
    ;

    UPDATE osm.place_polygon_nested n 
        SET nest_level = t.nest_level,
            name_path = t.name_path,
            osm_id_path = t.osm_id_path,
            admin_level_path = t.admin_level_path
        FROM place_batch t
        WHERE n.osm_id = t.osm_id
        ;
    COMMIT;
    END LOOP;

    DROP TABLE IF EXISTS place_batch;
    DROP TABLE IF EXISTS places_for_nesting;

    -- With all nested paths calculated the innermost value can be determined.
    WITH calc_inner AS (
    SELECT a.osm_id
        FROM osm.place_polygon_nested a
        WHERE a.row_innermost -- Start with per row check...
            -- If an osm_id is found in any other path, cannot be innermost
            AND NOT EXISTS (
            SELECT 1
                FROM osm.place_polygon_nested i
                WHERE a.osm_id <> i.osm_id
                    AND a.osm_id = ANY(osm_id_path)
        )
    )
    UPDATE osm.place_polygon_nested n
        SET innermost = True
        FROM calc_inner i
        WHERE n.osm_id = i.osm_id
    ;
END $_$;


ALTER PROCEDURE osm.build_nested_admin_polygons(IN batch_row_limit bigint) OWNER TO postgres;

--
-- Name: PROCEDURE build_nested_admin_polygons(IN batch_row_limit bigint); Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON PROCEDURE osm.build_nested_admin_polygons(IN batch_row_limit bigint) IS 'Warning: Expensive procedure!  Use to populate the osm.place_polygon_nested table. This procedure is not ran as part of SQL script automatically due to excessive run time on large regions.';


--
-- Name: populate_place_polygon_nested(); Type: PROCEDURE; Schema: osm; Owner: postgres
--

CREATE PROCEDURE osm.populate_place_polygon_nested()
    LANGUAGE sql
    AS $$


    INSERT INTO osm.place_polygon_nested (osm_id, name, osm_type, admin_level, geom)
    SELECT p.osm_id, p.name, p.osm_type,
            COALESCE(p.admin_level::INT, 99) AS admin_level,
            geom
        FROM osm.vplace_polygon p
        WHERE (p.boundary = 'administrative'
                OR p.osm_type IN   ('neighborhood', 'city', 'suburb', 'town', 'admin_level', 'locality')
           )
            AND p.name IS NOT NULL
            AND NOT EXISTS (
                SELECT osm_id
                    FROM osm.place_polygon_nested n
                    WHERE n.osm_id = p.osm_id
                )
    ;

$$;


ALTER PROCEDURE osm.populate_place_polygon_nested() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: amenity_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.amenity_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.amenity_line OWNER TO postgres;

--
-- Name: TABLE amenity_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.amenity_line IS 'OpenStreetMap amenity lines - all lines with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_line.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_line.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_line.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_line.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_line.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_line.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_line.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.amenity_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.amenity_point OWNER TO postgres;

--
-- Name: TABLE amenity_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.amenity_point IS 'OpenStreetMap amenity points - all points with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_point.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_point.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_point.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_point.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_point.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_point.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.amenity_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.amenity_polygon OWNER TO postgres;

--
-- Name: TABLE amenity_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.amenity_polygon IS 'OpenStreetMap amenity polygons - all polygons with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_polygon.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_polygon.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_polygon.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_polygon.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_polygon.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_polygon.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.amenity_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: building_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.building_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    levels integer,
    height numeric,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.building_point OWNER TO postgres;

--
-- Name: TABLE building_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.building_point IS 'OpenStreetMap building points - all points with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';


--
-- Name: COLUMN building_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN building_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building.lua';


--
-- Name: COLUMN building_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN building_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN building_point.levels; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN building_point.height; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN building_point.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN building_point.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN building_point.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN building_point.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN building_point.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN building_point.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN building_point.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN building_point.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN building_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: building_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.building_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    levels integer,
    height numeric,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.building_polygon OWNER TO postgres;

--
-- Name: TABLE building_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.building_polygon IS 'OpenStreetMap building polygons - all polygons with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';


--
-- Name: COLUMN building_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN building_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building.lua';


--
-- Name: COLUMN building_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN building_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN building_polygon.levels; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN building_polygon.height; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN building_polygon.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN building_polygon.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN building_polygon.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN building_polygon.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN building_polygon.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN building_polygon.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN building_polygon.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN building_polygon.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN building_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.building_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.indoor_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.indoor_line OWNER TO postgres;

--
-- Name: TABLE indoor_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.indoor_line IS 'OpenStreetMap indoor related lines. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_line.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_line.level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.room; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.entrance; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.door; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.capacity; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.highway; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.indoor_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.indoor_point OWNER TO postgres;

--
-- Name: TABLE indoor_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.indoor_point IS 'OpenStreetMap indoor related points. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_point.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_point.level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.room; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.entrance; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.door; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.capacity; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.highway; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.indoor_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.indoor_polygon OWNER TO postgres;

--
-- Name: TABLE indoor_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.indoor_polygon IS 'OpenStreetMap indoor related polygons. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_polygon.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_polygon.level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.room; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.entrance; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.door; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.capacity; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.highway; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.indoor_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: infrastructure_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.infrastructure_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.infrastructure_line OWNER TO postgres;

--
-- Name: COLUMN infrastructure_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_line.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: infrastructure_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.infrastructure_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.infrastructure_point OWNER TO postgres;

--
-- Name: TABLE infrastructure_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.infrastructure_point IS 'OpenStreetMap infrastructure layer.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/infrasturcture.lua';


--
-- Name: COLUMN infrastructure_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN infrastructure_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN infrastructure_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN infrastructure_point.ele; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN infrastructure_point.height; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.height IS 'Object height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN infrastructure_point.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN infrastructure_point.material; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.material IS 'Describes the main material of a physical feature.  https://wiki.openstreetmap.org/wiki/Key:material';


--
-- Name: COLUMN infrastructure_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: infrastructure_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.infrastructure_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.infrastructure_polygon OWNER TO postgres;

--
-- Name: COLUMN infrastructure_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.infrastructure_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: landuse_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.landuse_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.landuse_point OWNER TO postgres;

--
-- Name: TABLE landuse_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.landuse_point IS 'OpenStreetMap landuse points - all points with a landuse tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/landuse.lua';


--
-- Name: COLUMN landuse_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN landuse_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN landuse_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN landuse_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: landuse_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.landuse_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.landuse_polygon OWNER TO postgres;

--
-- Name: TABLE landuse_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.landuse_polygon IS 'OpenStreetMap landuse polygons - all polygons with a landuse tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/landuse.lua';


--
-- Name: COLUMN landuse_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN landuse_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN landuse_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN landuse_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.landuse_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: leisure_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.leisure_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.leisure_point OWNER TO postgres;

--
-- Name: TABLE leisure_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.leisure_point IS 'OpenStreetMap leisure points - all points with a leisure tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/leisure.lua';


--
-- Name: COLUMN leisure_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN leisure_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN leisure_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN leisure_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: leisure_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.leisure_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.leisure_polygon OWNER TO postgres;

--
-- Name: TABLE leisure_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.leisure_polygon IS 'OpenStreetMap leisure polygons - all polygons with a leisure tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/leisure.lua';


--
-- Name: COLUMN leisure_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN leisure_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN leisure_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN leisure_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.leisure_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.natural_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.natural_line OWNER TO postgres;

--
-- Name: TABLE natural_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.natural_line IS 'OpenStreetMap natural lines, e.g. cliffs, tree row, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_line.ele; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_line.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.natural_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.natural_point OWNER TO postgres;

--
-- Name: TABLE natural_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.natural_point IS 'OpenStreetMap natural points, e.g. trees, peaks, etc..  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_point.ele; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.natural_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.natural_polygon OWNER TO postgres;

--
-- Name: TABLE natural_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.natural_polygon IS 'OpenStreetMap natural polygons, e.g. woods, grass, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_polygon.ele; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_polygon.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.natural_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: pgosm_flex; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.pgosm_flex (
    id bigint NOT NULL,
    imported timestamp with time zone DEFAULT now() NOT NULL,
    osm_date date NOT NULL,
    default_date boolean NOT NULL,
    region text NOT NULL,
    pgosm_flex_version text NOT NULL,
    srid text NOT NULL,
    project_url text NOT NULL,
    osm2pgsql_version text NOT NULL,
    language text NOT NULL,
    osm2pgsql_mode text DEFAULT 'create'::text NOT NULL
);


ALTER TABLE osm.pgosm_flex OWNER TO postgres;

--
-- Name: TABLE pgosm_flex; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.pgosm_flex IS 'Provides meta information on the PgOSM-Flex project including version and SRID used during the import. One row per import.';


--
-- Name: COLUMN pgosm_flex.imported; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.imported IS 'Indicates when the import was ran.';


--
-- Name: COLUMN pgosm_flex.osm_date; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.osm_date IS 'Indicates the date of the OpenStreetMap data loaded.  Recommended to set PGOSM_DATE env var at runtime, otherwise defaults to the date PgOSM-Flex was run.';


--
-- Name: COLUMN pgosm_flex.default_date; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.default_date IS 'If true, the value in osm_date represents the date PgOSM-Flex was ran.  If False, the date was set via env var and should indicate the date the OpenStreetMap data is from.';


--
-- Name: COLUMN pgosm_flex.region; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.region IS 'Region specified at run time via env var PGOSM_REGION.';


--
-- Name: COLUMN pgosm_flex.pgosm_flex_version; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.pgosm_flex_version IS 'Version of PgOSM-Flex used to generate schema.';


--
-- Name: COLUMN pgosm_flex.srid; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.srid IS 'SRID of imported data.';


--
-- Name: COLUMN pgosm_flex.project_url; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.project_url IS 'PgOSM-Flex project URL.';


--
-- Name: COLUMN pgosm_flex.osm2pgsql_version; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.osm2pgsql_version IS 'Version of osm2pgsql used to load data.';


--
-- Name: COLUMN pgosm_flex.language; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.language IS 'Preferred language specified at run time via env var PGOSM_LANGUAGE.  Empty string when not defined.';


--
-- Name: COLUMN pgosm_flex.osm2pgsql_mode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.pgosm_flex.osm2pgsql_mode IS 'Indicates which osm2pgsql mode was used, create or append.';


--
-- Name: pgosm_flex_id_seq; Type: SEQUENCE; Schema: osm; Owner: postgres
--

ALTER TABLE osm.pgosm_flex ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME osm.pgosm_flex_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: place_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.place_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.place_line OWNER TO postgres;

--
-- Name: TABLE place_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.place_line IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_line.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_line.boundary; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_line.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_line.admin_level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_line.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.place_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.place_point OWNER TO postgres;

--
-- Name: TABLE place_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.place_point IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_point.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_point.boundary; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_point.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_point.admin_level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_point.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.place_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.place_polygon OWNER TO postgres;

--
-- Name: TABLE place_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.place_polygon IS 'See view: osm.vplace_polgyon for improved data.  OpenStreetMap named places and administrative boundaries.  Contains relations and the polygon parts making up the relations. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon.boundary; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_polygon.admin_level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon.member_ids; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.  Used to create improved osm.vplace_polygon.';


--
-- Name: COLUMN place_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon_nested; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.place_polygon_nested (
    osm_id bigint NOT NULL,
    name text NOT NULL,
    osm_type text NOT NULL,
    admin_level integer NOT NULL,
    nest_level bigint,
    name_path text[],
    osm_id_path bigint[],
    admin_level_path integer[],
    row_innermost boolean GENERATED ALWAYS AS (
CASE
    WHEN (osm_id_path[array_length(osm_id_path, 1)] = osm_id) THEN true
    ELSE false
END) STORED NOT NULL,
    innermost boolean DEFAULT false NOT NULL,
    geom public.geometry NOT NULL
);


ALTER TABLE osm.place_polygon_nested OWNER TO postgres;

--
-- Name: TABLE place_polygon_nested; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.place_polygon_nested IS 'Provides hierarchy of administrative polygons.  Built on top of osm.vplace_polygon. Artifact of PgOSM-Flex (place.sql).';


--
-- Name: COLUMN place_polygon_nested.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon_nested.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon_nested.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon_nested.admin_level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.admin_level IS 'Value from admin_level if it exists.  Defaults to 99 if not.';


--
-- Name: COLUMN place_polygon_nested.nest_level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.nest_level IS 'How many polygons is the current polygon nested within.  1 indicates polygon with no containing polygon.';


--
-- Name: COLUMN place_polygon_nested.name_path; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.name_path IS 'Array of names of the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.osm_id_path; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.osm_id_path IS 'Array of osm_id for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.admin_level_path; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.admin_level_path IS 'Array of admin_level values for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.row_innermost; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.row_innermost IS 'Indicates if the osm_id is the most inner ID of the current row.  Used to calculated innermost after all nesting paths have been calculated.';


--
-- Name: COLUMN place_polygon_nested.innermost; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.innermost IS 'Indiciates this row is the innermost admin level of the current data set and does **not** itself contain another admin polygon.  Calculated by procedure osm.build_nested_admin_polygons() defined in pgosm-flex/flex-config/place.sql.';


--
-- Name: COLUMN place_polygon_nested.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.place_polygon_nested.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: places_in_relations; Type: VIEW; Schema: osm; Owner: postgres
--

CREATE VIEW osm.places_in_relations AS
 SELECT p_no_rel.osm_id
   FROM osm.place_polygon p_no_rel
  WHERE ((p_no_rel.osm_id > 0) AND (EXISTS ( SELECT rel.relation_id,
            rel.member_id
           FROM ( SELECT i.osm_id AS relation_id,
                    (jsonb_array_elements_text(i.member_ids))::bigint AS member_id
                   FROM osm.place_polygon i
                  WHERE (i.osm_id < 0)) rel
          WHERE (rel.member_id = p_no_rel.osm_id))));


ALTER TABLE osm.places_in_relations OWNER TO postgres;

--
-- Name: VIEW places_in_relations; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON VIEW osm.places_in_relations IS 'Lists all osm_id values included in a relation''s member_ids list.  Technically could contain duplicates, but not a concern with current expected use of this view.';


--
-- Name: COLUMN places_in_relations.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.places_in_relations.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: poi_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.poi_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.poi_line OWNER TO postgres;

--
-- Name: TABLE poi_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.poi_line IS 'OpenStreetMap Points of Interest (POI) (lines).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_line.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_line.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_line.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_line.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_line.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_line.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_line.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.poi_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.poi_point OWNER TO postgres;

--
-- Name: TABLE poi_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.poi_point IS 'OpenStreetMap Points of Interest (POI) (points).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_point.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_point.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_point.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_point.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_point.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_point.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.poi_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.poi_polygon OWNER TO postgres;

--
-- Name: TABLE poi_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.poi_polygon IS 'OpenStreetMap Points of Interest (POI) (polygons).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_polygon.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_polygon.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_polygon.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_polygon.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_polygon.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_polygon.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_polygon.member_ids; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.';


--
-- Name: COLUMN poi_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.poi_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.public_transport_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.public_transport_line OWNER TO postgres;

--
-- Name: TABLE public_transport_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.public_transport_line IS 'OpenStreetMap public transport lines - all lines with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_line.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_line.public_transport; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_line.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_line.ref; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_line.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_line.network; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_line.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.public_transport_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.public_transport_point OWNER TO postgres;

--
-- Name: TABLE public_transport_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.public_transport_point IS 'OpenStreetMap public transport points - all points with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_point.public_transport; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_point.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_point.ref; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_point.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_point.network; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_point.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.public_transport_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.public_transport_polygon OWNER TO postgres;

--
-- Name: TABLE public_transport_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.public_transport_polygon IS 'OpenStreetMap public transport polygons - all polygons with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_polygon.public_transport; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_polygon.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_polygon.ref; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_polygon.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_polygon.network; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_polygon.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.public_transport_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.road_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    oneway smallint,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.road_line OWNER TO postgres;

--
-- Name: TABLE road_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.road_line IS 'OpenStreetMap roads, full layer.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road.lua';


--
-- Name: COLUMN road_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_line.ref; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_line.maxspeed; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_line.oneway; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.oneway IS 'Used for calculating costs for routing with one-way controls.  0 indicates 2-way traffic is allowed (or assumed).  1 indicates travel is allowed forward only, -1 indicates travel is allowed reverse only. Values reversible and alternating result in NULL.  See https://wiki.openstreetmap.org/wiki/Key:oneway';


--
-- Name: COLUMN road_line.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_line.tunnel; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_line.bridge; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_line.major; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.major IS 'Indicates feature is a "major" road, classification handled by helpers.major_road().';


--
-- Name: COLUMN road_line.route_foot; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.route_foot IS 'Best guess if the segment is routable for foot traffic. If access is no or private, set to false. WARNING: This does not indicte that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.route_cycle; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.route_cycle IS 'Best guess if the segment is routable for bicycle traffic. If access is no or private, set to false. WARNING: This does not indicte that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.route_motor; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.route_motor IS 'Best guess if the segment is routable for motorized traffic. If access is no or private, set to false. WARNING: This does not indicte that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.road_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    oneway smallint,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    access text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.road_point OWNER TO postgres;

--
-- Name: TABLE road_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.road_point IS 'OpenStreetMap road points.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road.lua';


--
-- Name: COLUMN road_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_point.ref; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_point.maxspeed; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_point.oneway; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.oneway IS 'Used for calculating costs for routing with one-way controls.  0 indicates 2-way traffic is allowed (or assumed).  1 indicates travel is allowed forward only, -1 indicates travel is allowed reverse only. Values reversible and alternating result in NULL.  See https://wiki.openstreetmap.org/wiki/Key:oneway';


--
-- Name: COLUMN road_point.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_point.tunnel; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_point.bridge; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.road_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.road_polygon OWNER TO postgres;

--
-- Name: COLUMN road_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_polygon.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_polygon.ref; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.road_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: shop_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.shop_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    phone text,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    brand text,
    website text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.shop_point OWNER TO postgres;

--
-- Name: TABLE shop_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.shop_point IS 'OpenStreetMap shop related points.   Generated by osm2pgsql Flex output using pgosm-flex/flex-config/shop.lua';


--
-- Name: COLUMN shop_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN shop_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN shop_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN shop_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN shop_point.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN shop_point.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN shop_point.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN shop_point.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN shop_point.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN shop_point.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN shop_point.phone; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN shop_point.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN shop_point.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN shop_point.brand; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN shop_point.website; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN shop_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: shop_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.shop_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    phone text,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    brand text,
    website text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.shop_polygon OWNER TO postgres;

--
-- Name: TABLE shop_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.shop_polygon IS 'OpenStreetMap shop related polygons. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/shop.lua';


--
-- Name: COLUMN shop_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN shop_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN shop_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN shop_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN shop_polygon.housenumber; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN shop_polygon.street; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN shop_polygon.city; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN shop_polygon.state; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN shop_polygon.postcode; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN shop_polygon.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN shop_polygon.phone; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN shop_polygon.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN shop_polygon.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN shop_polygon.brand; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN shop_polygon.website; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN shop_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.shop_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: tags; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.tags (
    geom_type character(1) NOT NULL,
    osm_id bigint NOT NULL,
    tags jsonb,
    osm_url text GENERATED ALWAYS AS (((('https://www.openstreetmap.org/'::text ||
CASE
    WHEN (geom_type = 'N'::bpchar) THEN 'node'::text
    WHEN (geom_type = 'W'::bpchar) THEN 'way'::text
    ELSE 'relation'::text
END) || '/'::text) || (osm_id)::text)) STORED NOT NULL
);


ALTER TABLE osm.tags OWNER TO postgres;

--
-- Name: TABLE tags; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.tags IS 'OpenStreetMap tag data for all objects in source file.  Key/value data stored in tags column in JSONB format.';


--
-- Name: COLUMN tags.geom_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.tags.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';


--
-- Name: COLUMN tags.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.tags.osm_id IS 'OpenStreetMap ID. Unique along with geometry type (geom_type).';


--
-- Name: COLUMN tags.tags; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.tags.tags IS 'Stores unaltered key/value pairs from OpenStreetMap.  A few tags are dropped by Lua script though most are preserved.';


--
-- Name: COLUMN tags.osm_url; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.tags.osm_url IS 'Calculated URL to object in OpenStreetMap.org.  Paths are split based on N(ode), W(ay) and R(elation).  See definition of generated column for full details.';


--
-- Name: traffic_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.traffic_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.traffic_line OWNER TO postgres;

--
-- Name: TABLE traffic_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.traffic_line IS 'OpenStreetMap traffic related lines.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_line.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_line.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_line.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';


--
-- Name: COLUMN traffic_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: traffic_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.traffic_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.traffic_point OWNER TO postgres;

--
-- Name: TABLE traffic_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.traffic_point IS 'OpenStreetMap traffic related points.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_point.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_point.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';


--
-- Name: COLUMN traffic_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: traffic_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.traffic_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.traffic_polygon OWNER TO postgres;

--
-- Name: TABLE traffic_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.traffic_polygon IS 'OpenStreetMap traffic related polygons.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_polygon.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_polygon.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway".';


--
-- Name: COLUMN traffic_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.traffic_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vbuilding_all; Type: VIEW; Schema: osm; Owner: postgres
--

CREATE VIEW osm.vbuilding_all AS
 SELECT building_point.osm_id,
    'N'::text AS geom_type,
    building_point.osm_type,
    building_point.osm_subtype,
    building_point.name,
    building_point.levels,
    building_point.height,
    building_point.operator,
    building_point.wheelchair,
    building_point.wheelchair_desc,
    building_point.address,
    building_point.geom
   FROM osm.building_point
UNION
 SELECT building_polygon.osm_id,
    'W'::text AS geom_type,
    building_polygon.osm_type,
    building_polygon.osm_subtype,
    building_polygon.name,
    building_polygon.levels,
    building_polygon.height,
    building_polygon.operator,
    building_polygon.wheelchair,
    building_polygon.wheelchair_desc,
    building_polygon.address,
    public.st_centroid(building_polygon.geom) AS geom
   FROM osm.building_polygon;


ALTER TABLE osm.vbuilding_all OWNER TO postgres;

--
-- Name: VIEW vbuilding_all; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON VIEW osm.vbuilding_all IS 'Converts polygon buildings to point with ST_Centroid(), combines with source points using UNION.';


--
-- Name: COLUMN vbuilding_all.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN vbuilding_all.geom_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';


--
-- Name: COLUMN vbuilding_all.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building.lua';


--
-- Name: COLUMN vbuilding_all.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN vbuilding_all.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN vbuilding_all.levels; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN vbuilding_all.height; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.height IS 'Object height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN vbuilding_all.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN vbuilding_all.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.wheelchair IS 'Indicates if building is wheelchair accessible.';


--
-- Name: COLUMN vbuilding_all.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN vbuilding_all.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vbuilding_all.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vplace_polygon; Type: MATERIALIZED VIEW; Schema: osm; Owner: postgres
--

CREATE MATERIALIZED VIEW osm.vplace_polygon AS
 SELECT p.osm_id,
    p.osm_type,
    p.boundary,
    p.admin_level,
    p.name,
    p.member_ids,
    p.geom
   FROM osm.place_polygon p
  WHERE (NOT (EXISTS ( SELECT 1
           FROM osm.places_in_relations pir
          WHERE (p.osm_id = pir.osm_id))))
  WITH NO DATA;


ALTER TABLE osm.vplace_polygon OWNER TO postgres;

--
-- Name: MATERIALIZED VIEW vplace_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON MATERIALIZED VIEW osm.vplace_polygon IS 'Simplified polygon layer removing non-relation geometries when a relation contains it in the member_ids column.';


--
-- Name: COLUMN vplace_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN vplace_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN vplace_polygon.boundary; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN vplace_polygon.admin_level; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.admin_level IS 'Value from admin_level if it exists.';


--
-- Name: COLUMN vplace_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN vplace_polygon.member_ids; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.  Used to create improved osm.vplace_polygon.';


--
-- Name: COLUMN vplace_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vplace_polygon_subdivide; Type: MATERIALIZED VIEW; Schema: osm; Owner: postgres
--

CREATE MATERIALIZED VIEW osm.vplace_polygon_subdivide AS
 SELECT vplace_polygon.osm_id,
    public.st_subdivide(vplace_polygon.geom) AS geom
   FROM osm.vplace_polygon
  WITH NO DATA;


ALTER TABLE osm.vplace_polygon_subdivide OWNER TO postgres;

--
-- Name: MATERIALIZED VIEW vplace_polygon_subdivide; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON MATERIALIZED VIEW osm.vplace_polygon_subdivide IS 'Subdivided geometry from osm.vplace_polygon.  Multiple rows per osm_id, one for each subdivided geometry.';


--
-- Name: COLUMN vplace_polygon_subdivide.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon_subdivide.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.  Duplicated in this view!';


--
-- Name: COLUMN vplace_polygon_subdivide.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vplace_polygon_subdivide.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vpoi_all; Type: MATERIALIZED VIEW; Schema: osm; Owner: postgres
--

CREATE MATERIALIZED VIEW osm.vpoi_all AS
 SELECT poi_point.osm_id,
    'N'::text AS geom_type,
    poi_point.osm_type,
    poi_point.osm_subtype,
    poi_point.name,
    poi_point.address,
    poi_point.operator,
    poi_point.geom
   FROM osm.poi_point
UNION
 SELECT poi_line.osm_id,
    'L'::text AS geom_type,
    poi_line.osm_type,
    poi_line.osm_subtype,
    poi_line.name,
    poi_line.address,
    poi_line.operator,
    public.st_centroid(poi_line.geom) AS geom
   FROM osm.poi_line
UNION
 SELECT poi_polygon.osm_id,
    'W'::text AS geom_type,
    poi_polygon.osm_type,
    poi_polygon.osm_subtype,
    poi_polygon.name,
    poi_polygon.address,
    poi_polygon.operator,
    public.st_centroid(poi_polygon.geom) AS geom
   FROM osm.poi_polygon
  WITH NO DATA;


ALTER TABLE osm.vpoi_all OWNER TO postgres;

--
-- Name: MATERIALIZED VIEW vpoi_all; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON MATERIALIZED VIEW osm.vpoi_all IS 'Cobmined POI view. Converts lines and polygons to point with ST_Centroid(), stacks using UNION';


--
-- Name: COLUMN vpoi_all.geom_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vpoi_all.geom_type IS 'Indicates source table, N (point) L (line) W (polygon).  Using L for line differs from how osm2pgsql classifies lines ("W") in order to provide a direct link to which table the data comes from.';


--
-- Name: COLUMN vpoi_all.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vpoi_all.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN vpoi_all.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vpoi_all.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN vpoi_all.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vpoi_all.address IS 'Address combined from address parts in helpers.get_address(). See base tables for individual address parts';


--
-- Name: vshop_all; Type: VIEW; Schema: osm; Owner: postgres
--

CREATE VIEW osm.vshop_all AS
 SELECT shop_point.osm_id,
    'N'::text AS geom_type,
    shop_point.osm_type,
    shop_point.osm_subtype,
    shop_point.name,
    shop_point.address,
    shop_point.phone,
    shop_point.wheelchair,
    shop_point.wheelchair_desc,
    shop_point.operator,
    shop_point.brand,
    shop_point.website,
    shop_point.geom
   FROM osm.shop_point
UNION
 SELECT shop_polygon.osm_id,
    'W'::text AS geom_type,
    shop_polygon.osm_type,
    shop_polygon.osm_subtype,
    shop_polygon.name,
    shop_polygon.address,
    shop_polygon.phone,
    shop_polygon.wheelchair,
    shop_polygon.wheelchair_desc,
    shop_polygon.operator,
    shop_polygon.brand,
    shop_polygon.website,
    public.st_centroid(shop_polygon.geom) AS geom
   FROM osm.shop_polygon;


ALTER TABLE osm.vshop_all OWNER TO postgres;

--
-- Name: VIEW vshop_all; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON VIEW osm.vshop_all IS 'Converts polygon shops to point with ST_Centroid(), combines with source points using UNION.';


--
-- Name: COLUMN vshop_all.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN vshop_all.geom_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';


--
-- Name: COLUMN vshop_all.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN vshop_all.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN vshop_all.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN vshop_all.address; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN vshop_all.phone; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN vshop_all.wheelchair; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN vshop_all.operator; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN vshop_all.brand; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN vshop_all.website; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN vshop_all.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.vshop_all.geom IS 'Geometry, mix of points loaded by osm2pgsql and points calculated from the ST_Centroid() of the polygons loaded by osm2pgsql.';


--
-- Name: water_line; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.water_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    geom public.geometry(LineString,3857)
);


ALTER TABLE osm.water_line OWNER TO postgres;

--
-- Name: TABLE water_line; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.water_line IS 'OpenStreetMap water / waterway related lines.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_line.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_line.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_line.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_line.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_line.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_line.tunnel; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_line.bridge; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_line.boat; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_line.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_point; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.water_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    geom public.geometry(Point,3857)
);


ALTER TABLE osm.water_point OWNER TO postgres;

--
-- Name: TABLE water_point; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.water_point IS 'OpenStreetMap water / waterway related points.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_point.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_point.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_point.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_point.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_point.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_point.tunnel; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_point.bridge; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_point.boat; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_point.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_polygon; Type: TABLE; Schema: osm; Owner: postgres
--

CREATE TABLE osm.water_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE osm.water_polygon OWNER TO postgres;

--
-- Name: TABLE water_polygon; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON TABLE osm.water_polygon IS 'OpenStreetMap water / waterway related polygons.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_polygon.osm_id; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_polygon.osm_type; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_polygon.osm_subtype; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_polygon.name; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_polygon.layer; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_polygon.tunnel; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_polygon.bridge; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_polygon.boat; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_polygon.geom; Type: COMMENT; Schema: osm; Owner: postgres
--

COMMENT ON COLUMN osm.water_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road; Type: TABLE; Schema: pgosm; Owner: postgres
--

CREATE TABLE pgosm.road (
    id bigint NOT NULL,
    region text DEFAULT 'United States'::text NOT NULL,
    osm_type text NOT NULL,
    route_motor boolean DEFAULT true,
    route_foot boolean DEFAULT true,
    route_cycle boolean DEFAULT true,
    maxspeed numeric(6,2) NOT NULL,
    maxspeed_mph numeric(6,2) GENERATED ALWAYS AS ((maxspeed / 1.609344)) STORED NOT NULL
);


ALTER TABLE pgosm.road OWNER TO postgres;

--
-- Name: TABLE road; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON TABLE pgosm.road IS 'Provides lookup information for road layers, generally related to routing use cases.';


--
-- Name: COLUMN road.region; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.region IS 'Allows defining different definitions based on region.  Can be custom defined.';


--
-- Name: COLUMN road.osm_type; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.osm_type IS 'Value from highway tags.';


--
-- Name: COLUMN road.route_motor; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.route_motor IS 'Used to filter for classifications that typically allow motorized traffic.';


--
-- Name: COLUMN road.route_foot; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.route_foot IS 'Used to filter for classifications that typically allow foot traffic.';


--
-- Name: COLUMN road.route_cycle; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.route_cycle IS 'Used to filter for classifications that typically allow bicycle traffic.';


--
-- Name: COLUMN road.maxspeed; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.maxspeed IS 'Maxspeed in km/hr';


--
-- Name: COLUMN road.maxspeed_mph; Type: COMMENT; Schema: pgosm; Owner: postgres
--

COMMENT ON COLUMN pgosm.road.maxspeed_mph IS 'Maxspeed in mph';


--
-- Name: road_id_seq; Type: SEQUENCE; Schema: pgosm; Owner: postgres
--

ALTER TABLE pgosm.road ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME pgosm.road_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: layer_styles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.layer_styles (
    id integer NOT NULL,
    f_table_catalog character varying(256),
    f_table_schema character varying(256),
    f_table_name character varying(256),
    f_geometry_column character varying(256),
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now(),
    type character varying
);


ALTER TABLE public.layer_styles OWNER TO postgres;

--
-- Name: layer_styles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.layer_styles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.layer_styles_id_seq OWNER TO postgres;

--
-- Name: layer_styles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.layer_styles_id_seq OWNED BY public.layer_styles.id;


--
-- Name: layer_styles_staging; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.layer_styles_staging (
    id integer NOT NULL,
    f_table_catalog character varying(256),
    f_table_schema character varying(256),
    f_table_name character varying(256),
    f_geometry_column character varying(256),
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now(),
    type character varying
);


ALTER TABLE public.layer_styles_staging OWNER TO postgres;

--
-- Name: TABLE layer_styles_staging; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.layer_styles_staging IS 'Staging table to load QGIS Layer Styles.  Similar to QGIS-created table, no primary key.';


--
-- Name: layer_styles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.layer_styles ALTER COLUMN id SET DEFAULT nextval('public.layer_styles_id_seq'::regclass);


--
-- Data for Name: amenity_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.amenity_line (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, wheelchair, wheelchair_desc, geom) FROM stdin;
\.


--
-- Data for Name: amenity_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.amenity_point (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, wheelchair, wheelchair_desc, geom) FROM stdin;
281652616	pub	\N	The Wooden Nickel	1900	Folsom Street	\N	\N	\N	1900 Folsom Street	yes	\N	0101000020110F000030940EC2EDFD69C136AC2600FB575141
3940894710	veterinary	\N	San Francisco SPCA Veterinary Hospital - Mission Campus	201	Alabama Street	San Francisco	CA	94103	201 Alabama Street, San Francisco, CA, 94103	\N	\N	0101000020110F00007884F730C1FD69C1C3DF94E308585141
3940887840	animal_shelter	\N	Animal Care & Control	1200	15th Street	San Francisco	CA	94103	1200 15th Street, San Francisco, CA, 94103	\N	\N	0101000020110F0000BAA5B6EAC8FD69C1EDD6393B04585141
1409407314	car_sharing	\N	15th & Folsom (UCSF)	\N	\N	\N	\N	\N		\N	\N	0101000020110F0000B70C3912DAFD69C17CC48A2603585141
4628752984	cafe	\N		\N	\N	\N	\N	\N		\N	\N	0101000020110F0000375B5014D1FD69C11024501926585141
5089298921	restaurant	italian_pizza	Pink Onion	\N	\N	\N	\N	94103	94103	\N	\N	0101000020110F0000187434D8E2FD69C1777B8E043D585141
1243846554	bar	\N	Nihon	1779	Folsom Street	\N	\N	94103	1779 Folsom Street, 94103	\N	\N	0101000020110F000062BF43DAEAFD69C168C25EAB3B585141
281652606	post_box	\N		\N	\N	\N	\N	\N		\N	\N	0101000020110F0000B507F5A2EFFD69C1AF6E266539585141
2049063016	post_box	\N	USPS	\N	\N	\N	\N	\N		\N	\N	0101000020110F00004A389EB7EFFD69C1A7D3840834585141
368168766	library	\N	Far West Library for Educational Research and Development	\N	\N	\N	CA	\N	CA	\N	\N	0101000020110F000083169787E4FD69C133332C0D06585141
5757635621	restaurant	japanese	Rintaro	\N	\N	\N	\N	\N		\N	\N	0101000020110F000009C1ED6BE5FD69C1F5160D7F3F585141
1803661677	restaurant	french	Chez Spencer	82 	14th St, San Francisco 	\N	\N	94103	82  14th St, San Francisco , 94103	\N	\N	0101000020110F00004CFD3F8EE6FD69C17D1D2C473F585141
2000101334	post_box	\N	USPS	\N	\N	\N	\N	\N		\N	\N	0101000020110F0000988938040AFE69C184023E5F2F585141
4307902891	restaurant	\N	Doña Margo	\N	\N	\N	\N	\N		\N	\N	0101000020110F0000E25DBB7509FE69C1A4E094A52E585141
4013644509	restaurant	\N	Walzwerk	\N	\N	\N	\N	\N		\N	\N	0101000020110F00001A3BE40708FE69C14BFED49709585141
2411576667	restaurant	\N	Mission Public SF	233	14th Street	San Francisco	\N	94103	233 14th Street, San Francisco, 94103	\N	\N	0101000020110F0000F2F0ED0F18FE69C156D0194F2D585141
9419035931	bicycle_parking	\N		\N	\N	\N	\N	\N		\N	\N	0101000020110F0000A694046722FE69C1AE9FB47E31585141
4516187333	bar	\N	The Armory Club	\N	\N	\N	\N	\N		\N	\N	0101000020110F0000FFCE883C27FE69C19E0D845B32585141
3345049955	car_sharing	\N	14th & Mission (on-street)	\N	\N	\N	\N	\N		\N	\N	0101000020110F0000E185A83C28FE69C1A311D3992F585141
420508633	post_box	\N	USPS	\N	\N	\N	\N	\N		\N	\N	0101000020110F0000FA282BFA28FE69C1CDA658B832585141
\.


--
-- Data for Name: amenity_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.amenity_polygon (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, wheelchair, wheelchair_desc, geom) FROM stdin;
132605501	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F0000010000000103000000010000000900000068C627C5C1FD69C19F1809771158514100E4E582C1FD69C122BE828809585141D7AD6D25BDFD69C196DFC23C0A585141CC9BC697BDFD69C10CD30E2C15585141ACC60E86B8FD69C14EE6682816585141D4695AB2B9FD69C12C8EAA4635585141AB23D8EBBDFD69C1A6DE95C22A585141AA3D9B16C1FD69C1FA6A455E1B58514168C627C5C1FD69C19F18097711585141
688747551	marketplace	\N	SoMa StrEat Food Park	428	11th Street	\N	\N	\N	428 11th Street	yes	\N	0106000020110F0000010000000103000000010000001200000058752B28BFFD69C1FC788B36625851413DA4A7F6BEFD69C158143795615851419969B9ABBDFD69C1680F09585E585141AB184FECBBFD69C1F1209A405E585141A8980D12B9FD69C1481034FB5D58514198833FDCB5FD69C1B1D7186A5D585141D1A26171B5FD69C11392FF6A5D5851414451A012B5FD69C1277785C15D585141078A06CBB4FD69C13E19B17F5E5851417EE92BAEB4FD69C17DF364545F585141DAF5F4C9B4FD69C1C1891520605851414B7632F7B4FD69C167DCC199605851412F331D93B7FD69C1A53166ED65585141F2F433B5B9FD69C19AF849486A5851419BD68C7ABAFD69C1E1C132AD6B5851411D63294EBEFD69C17DE80FE8635851416F1C5F11BFFD69C12B411A5F6258514158752B28BFFD69C1FC788B3662585141
132605458	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F00000100000001030000000100000008000000EB908664DDFD69C1EC2AD2564E58514195BF2432D6FD69C16D1AAAA14D585141E8739C91D6FD69C1744EF76D3E585141795A6797D1FD69C19D379B433E5851418CC91D45D1FD69C1978B81D94E585141AECF7ABED3FD69C19D51DDF85358514103AC65F0DCFD69C1CBC44A9954585141EB908664DDFD69C1EC2AD2564E585141
132605487	parking	\N	Best Buy Parking	\N	\N	\N	\N	\N		\N	\N	0106000020110F0000010000000103000000010000001A000000E513AC83CDFD69C11AC1BFEF3E5851418707E367CDFD69C1451A86FC3A585141CA01FF8CC2FD69C1D09BF8803C585141CEE8489AC0FD69C1E76E447E3C585141C1DA5238C0FD69C1610A92F23B585141258AD5A2C0FD69C115E7BB033B58514118F32ED7BDFD69C1F4014E3736585141499C8B59BBFD69C1621A93203B585141799ACC35BAFD69C1DDCCE8B73D585141D7E3D0F0BAFD69C17C348DF13E5851417EC9DAE1BAFD69C1CB67526A3F585141DB52BE2FBAFD69C11B85C48A3F58514129564F4DBAFD69C126D91F7247585141642B1688BAFD69C1B160C5F44858514128249DADBBFD69C179257F194F5851411F4A735BBCFD69C128AC6A9A4E585141A1898D2CBDFD69C1C925D99E5058514191127527BFFD69C16B213D374F58514157C093BABFFD69C195F05C484F5851419BEDABB1BFFD69C1E06684CF50585141087D6004CCFD69C11A5374BD515851411A786B0FCCFD69C12D72DF954F5851419D2B3183CCFD69C1F070C99F4F585141BEA8DD92CCFD69C15A4D9F224C585141A93EE548CDFD69C15A4D9F224C585141E513AC83CDFD69C11AC1BFEF3E585141
132605510	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F00000100000001030000000100000005000000CDAC572DCCFD69C1C069514020585141EAB44B62CBFD69C1B73F98740B585141A85D29DDC5FD69C196B0B24E0C58514132263AD2C3FD69C1512DD56821585141CDAC572DCCFD69C1C069514020585141
132605518	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F000001000000010300000001000000050000008FC6B64BDEFD69C1B3C7000F1A5851417E07DAA7DDFD69C1D898E72B045851410072914ACFFD69C1F3BF2F5F06585141DB440B31D0FD69C18EA4BB191C5851418FC6B64BDEFD69C1B3C7000F1A585141
261095625	animal_boarding	\N	Wag Hotels	25	14th Street	San Francisco	CA	94103	25 14th Street, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000050000000A95C96DDDFD69C1A713CD7B365851418F3E131ADDFD69C123CF80262E585141DF8EE93FD5FD69C190865A672F585141E7B83988D5FD69C11C0A84A2375851410A95C96DDDFD69C1A713CD7B36585141
104597417	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F00000100000001030000000100000005000000C9B8E14DFBFD69C196E759E6315851413250BBFDFAFD69C10E550102235851419293B722EFFD69C18AABF51C2558514125C91E9BEFFD69C1F25E94EC33585141C9B8E14DFBFD69C196E759E631585141
25821948	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F00000100000001030000000100000008000000B291F295E2FD69C1C17522E1435851418192A481E2FD69C102E8CDDB41585141CE5DB863E2FD69C10DFBA3303F585141D309E141E2FD69C1399EE70A3C585141D290773BE2FD69C1D347616B3B58514140C43266DFFD69C1AAE3F3E53B58514135F377A3DFFD69C191E9B15244585141B291F295E2FD69C1C17522E143585141
586782486	social_facility	\N	Division Circle Navigation Center	224	South Van Ness Avenue	San Francisco	CA	94103	224 South Van Ness Avenue, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000160000001671C1C71BFE69C1463C25B75158514127EEA4681BFE69C1C84648AE4D5851412825156C1AFE69C196CA2D154A58514121FAB7EB18FE69C19372AA48475851418074610E17FE69C161E0BE914558514135D1830415FE69C1B181941C455851417C6C7C0213FE69C16ABBE2F44558514128714D3C11FE69C14935080548585141D6F345E00FFE69C1B943D8174B58514147ABF3100FFE69C1CD731CDD4E585141D72AB6E30EFE69C138707EF35258514120C30AEE0EFE69C130D197E7575851416578C61610FE69C13DB6CF5A5C585141728B7ADC10FE69C1B4CEC36C5E58514143101FCE12FE69C137C4B0515F585141164F199114FE69C1F67BAD485F5851412FB2BCBB16FE69C17BF1BA9A5E5851417A559AC518FE69C153A5D1EC5C585141433785681AFE69C1627FD7F659585141D2C0C3021BFE69C1EBFBB9B85758514139E9AF731BFE69C16740D413565851411671C1C71BFE69C1463C25B751585141
260973315	nightclub	\N	Public Works	161	Erie Street	San Francisco	CA	94103	161 Erie Street, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000060000006C4223FA22FE69C15C0DEA8548585141A5DAAE9522FE69C1F94EEB773D585141470FD24422FE69C187BCA2833D5851415EDC21961DFE69C16DCFF92D3E585141C1123BFA1DFE69C178C0F83B495851416C4223FA22FE69C15C0DEA8548585141
112593518	parking	\N		\N	\N	\N	\N	\N		\N	\N	0106000020110F0000010000000103000000010000000C0000002FCFE38828FE69C1EBA894BE4B58514153521E3A1FFE69C1EB7042CA4C585141C487F3D41EFE69C1092055DA5058514116401C601EFE69C1AF1062F3555851414192345E1DFE69C13590CF6D5A585141123DF5B71AFE69C1393F48DD62585141F3D1A97B1FFE69C1D6D8331D65585141A2DD528920FE69C16F08D39F4E585141AD574C7C27FE69C1D93DBDC44F5851414D18C48827FE69C18ABF8DB44E585141BE1BE78328FE69C1F6A1D0DF4E5851412FCFE38828FE69C1EBA894BE4B585141
\.


--
-- Data for Name: building_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.building_point (osm_id, osm_type, osm_subtype, name, levels, height, housenumber, street, city, state, postcode, address, wheelchair, wheelchair_desc, operator, geom) FROM stdin;
1209228821	address	\N		\N	\N	165	Erie Street	\N	\N	\N	165 Erie Street	\N	\N	\N	0101000020110F000045D7540922FE69C1DA5FA61148585141
6441756876	address	\N	Lyon-Martin Health Services	\N	\N	1735	Mission Street	San Francisco	CA	94103	1735 Mission Street, San Francisco, CA, 94103	\N	\N	\N	0101000020110F0000AAE85E3D28FE69C10A618F4E52585141
6441756875	address	\N	Lee Woodward Counseling Center for Women	\N	\N	1735	Mission Street	San Francisco	CA	94103	1735 Mission Street, San Francisco, CA, 94103	\N	\N	\N	0101000020110F000099A7A90328FE69C14A234A5857585141
6441756877	address	\N	Women's Community Clinic	\N	\N	1735	Mission Street	San Francisco	CA	94103	1735 Mission Street, San Francisco, CA, 94103	\N	\N	\N	0101000020110F0000DF15AEC527FE69C11B8905625C585141
\.


--
-- Data for Name: building_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.building_polygon (osm_id, osm_type, osm_subtype, name, levels, height, housenumber, street, city, state, postcode, address, wheelchair, wheelchair_desc, operator, geom) FROM stdin;
260998412	building	yes	Impact Hub San Francisco	\N	11	1899	Mission Street	San Francisco	\N	94103	1899 Mission Street, San Francisco, 94103	\N	\N	\N	0106000020110F000001000000010300000001000000060000009C986FD826FE69C18333B1C10058514118A4BD9926FE69C122E5088BF95751419B5B343926FE69C18F04D903F9575141E78D504E21FE69C1DBA915AFF957514141675A9221FE69C1540E8C79015851419C986FD826FE69C18333B1C100585141
261007318	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000002300000034C1799B1DFE69C15B717AB00258514151D3E9971DFE69C16253D5FF01585141F14DB7751DFE69C107B07CDE01585141719182721DFE69C198F9758301585141E9AFBB8A1DFE69C1E104B55C01585141A3093A8D1DFE69C12A8F68CD005851417D21516A1DFE69C128A66E960058514196BA57601DFE69C1D332A379FF5751419D9EFD791DFE69C12FFA403DFF575141FF56EF731DFE69C128E7ABB9FE575141DBE76F571DFE69C1BECEAE79FE575141F6F9DF531DFE69C1909C3C10FE57514126F92D681DFE69C100CD58CFFD575141B44531631DFE69C118640C40FD5751419E58534B1DFE69C1BC2B321AFD5751418FD6B1461DFE69C1CB1F9D96FC575141BFD5FF5A1DFE69C1CBC85D74FC575141301093591DFE69C16CA3DBDDFB575141FE97DB3E1DFE69C10FABCBB0FB5751415247953A1DFE69C105656C34FB57514158B2D14D1DFE69C1831CF401FB575141CAEC644C1DFE69C131B0E082FA57514160D763321DFE69C10888CD4CFA575141D2CB4C021DFE69C13314CAFAF9575141CD1A66C01CFE69C1D76D8106FA575141728706AB1CFE69C13A376547FA575141E1891C6E1CFE69C1E6CFE64BFA575141A08FC34E1CFE69C181C73812FA57514145B6B90A1CFE69C14FD9D61EFA57514120473AEE1BFE69C16A324C91FA575141E725FEE819FE69C18E4D98D7FA575141A5A9CC331AFE69C1E269F3740358514126707DFE1AFE69C1AECFE95903585141D8B4B07F1DFE69C12BF77D020358514134C1799B1DFE69C15B717AB002585141
261007303	building	yes		\N	\N	1540;1542	15th Street	\N	\N	\N	1540;1542 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C000000E7D9881E18FE69C122250A2C0158514176E0E1EA17FE69C1C602C555FB5751416C83D2CA17FE69C192C23CF6FA57514131AE0B9017FE69C1EA3B59FEFA57514102AFBD7B17FE69C1D55C7C61FB5751416A8C415A17FE69C1C8ADE466FB5751419B45E53F17FE69C1B6DD2909FB575141C0AFA6F816FE69C15EC71313FB575141D36407D516FE69C1A14ADE54FB5751417C828E0117FE69C1E912452100585141294C3E0C17FE69C15C61E45101585141E7D9881E18FE69C122250A2C01585141
261007310	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000100000007C828E0117FE69C1E912452100585141D36407D516FE69C1A14ADE54FB575141D0EB9DCE16FE69C1380F2D12FB575141F2A936A916FE69C11F9A88F3FA575141A460FB5C16FE69C19DCB8BFCFA575141A41A512E16FE69C12D1D5335FB5751418949CDFC15FE69C17B8D2037FB5751418F6E5FE115FE69C1857FFA13FB575141ECFC009315FE69C1CE497F21FB575141B4190D6515FE69C14F853064FB5751416A40CC8F15FE69C1EE61BD5300585141F6D279B915FE69C14E10554E00585141E8C941BB15FE69C1E80D657B005851416790F28516FE69C172BD745F00585141D9CA858416FE69C1FABF6432005851417C828E0117FE69C1E912452100585141
261089757	building	yes		\N	\N	1520	15th Street	\N	\N	\N	1520 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A00000024C6319612FE69C1AC0B70E9FE57514133CF699412FE69C1ED2EC5B8FE575141E644427D12FE69C13831F525FC57514176FB745311FE69C18E015150FC5751411AAEBF6C11FE69C13497B214FF575141B5C20E9B11FE69C146D57C0DFF575141710E60AA11FE69C146717BBA005851414B68708A12FE69C18B3FF09A00585141F34D7A7B12FE69C1A2EC0AEDFE57514124C6319612FE69C1AC0B70E9FE575141
256458227	building	yes		\N	11	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000290000007EE5A80E08FE69C1D7F4D880FF57514127441C0608FE69C12D9A3387FE575141ADAC79E707FE69C11A7BCE8AFE5751414702B5E007FE69C1742A88C4FD5751417BF3D50108FE69C1639106C0FD5751417A7A6CFB07FE69C101801209FD575141F352FBE407FE69C197A8C60BFD575141C8BEE9E307FE69C10E001FE4FC5751413607AAD507FE69C16F70ECE5FC575141A7413DD407FE69C16A3812C0FC57514152145C6E07FE69C172BB7DCEFC575141450B247007FE69C171BEDC01FD5751416A75E52807FE69C197A8C60BFD575141777E1D2707FE69C18EA567D8FC575141BAB4A4AD06FE69C10399A0E8FC5751410FDDC7AF06FE69C11CCE0225FD5751411FA0557F06FE69C180D7512BFD5751412CA98D7D06FE69C15DA2EFEEFC5751413642CB0406FE69C1DC9528FFFC575141EE9B490706FE69C1B18CC042FD57514118F31F6905FE69C188D16158FD5751415E99A16605FE69C190DAC914FD575141C43EA80905FE69C152ED6721FD5751417D98260C05FE69C1395E1C6DFD57514166F5A34E04FE69C1313C3F87FD575141AC9B254C04FE69C117CB8A3BFD575141F04A16D903FE69C18206DD4AFD5751410CD6EFDB03FE69C1F8C8F99BFD575141D082013703FE69C136C681B2FD575141E66FDF4E03FE69C18974E37600585141FE12620C04FE69C1E94CA75D00585141EF90C00704FE69C13117ADDDFF575141324B3A9405FE69C1BCE799A7FF57514123C9988F05FE69C15DF26920FF5751419973260506FE69C13DB61711FF575141A9F5C70906FE69C129F36097FF575141834A1A8606FE69C19BFE2787FF57514193CCBB8A06FE69C1F87A3B0600585141F352FBE407FE69C15F0D5ED7FF5751413AF97CE207FE69C19BFE2787FF5751417EE5A80E08FE69C1D7F4D880FF575141
256851488	building	yes		\N	9	1417;1419	15th Street	\N	\N	\N	1417;1419 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000700000007695C5EF6FD69C10C69091DFA575141C2368603F6FD69C165DF4044F05751413F7E022CF5FD69C12904CC63F057514122ED5D8DF3FD69C1506E479FF05751419C8400ACF3FD69C1D130DBF3F357514101EED8E7F3FD69C166562977FA57514107695C5EF6FD69C10C69091DFA575141
-3442900	building	yes		\N	\N	101;103;105;107;109;111;113;115;117;119	Shotwell Street	\N	\N	\N	101;103;105;107;109;111;113;115;117;119 Shotwell Street	\N	\N	\N	0106000020110F00000100000001030000000100000016000000A20B1A5AF9FD69C12FD128E5F9575141A7B74238F9FD69C12F86B3C6F5575141F3BE8481F8FD69C1063722DEF5575141800B887CF8FD69C177225141F5575141DB62B92AF9FD69C1032AC92AF557514139B06E11F9FD69C1B7719712F2575141DD583D63F8FD69C16B681F29F2575141CDD69B5EF8FD69C15851879CF1575141C4FC710CF9FD69C1F45AFF85F1575141243CFAFFF8FD69C1111F0EFDEF5751411181CE87F7FD69C1C5E9B82DF05751415AA0B98BF7FD69C18AE563A7F057514106AA4829F6FD69C163D173D4F0575141B5EC613AF6FD69C19327AEE3F25751418BD1B93FF6FD69C1766AD18FF357514158A46AB7F6FD69C1CB327F80F3575141E9E240BFF6FD69C12840D573F4575141CB52A958F6FD69C12F507380F45751415F83526DF6FD69C11F4ED704F75751416F05F471F6FD69C11196F003F75751413D4C508CF6FD69C14C2E1641FA575141A20B1A5AF9FD69C12FD128E5F9575141
256851470	building	yes		\N	\N	1405;1407;1409;1411;1413;1415	15th Street	\N	\N	\N	1405;1407;1409;1411;1413;1415 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000001000000083AA0DEBF3FD69C1FB6CFDD3FA57514101EED8E7F3FD69C166562977FA5751419C8400ACF3FD69C1D130DBF3F35751419EB7BF83F3FD69C1C28043F9F3575141D6DB9F7CF3FD69C11CEDE02AF35751412616A19DF2FD69C1315C8549F3575141B75477A5F2FD69C15BE02028F4575141C809D881F2FD69C15230892DF4575141C26BDC96F2FD69C1C2CE5E89F6575141669790B6F2FD69C18436DD84F6575141216A78BFF2FD69C16A1FB885F7575141190D699FF2FD69C1C6B7398AF75751411A86D2A5F2FD69C1D6AF2D41F857514112E8D6BAF2FD69C13C9552A3FA5751412E73B0BDF2FD69C1C58372FDFA57514183AA0DEBF3FD69C1FB6CFDD3FA575141
256851477	building	mixd_use		\N	11	1900;1902	Folsom Street	\N	\N	\N	1900;1902 Folsom Street	\N	\N	\N	0106000020110F0000010000000103000000010000001800000012E8D6BAF2FD69C13C9552A3FA5751411A86D2A5F2FD69C1D6AF2D41F85751416E70ADD0F0FD69C1FC7E6088F85751413BA6B54FEDFD69C1139D5A08F957514115BECC2CEDFD69C16684A345F9575141BE95A92AEDFD69C1D12AE0F0F9575141D7745A4FEDFD69C1172A3F24FA575141AE59B254EDFD69C140D47BCFFA5751417BE1FA39EDFD69C16ED06219FB575141FC9D2F3DEDFD69C1135A63ABFB5751415E15356CEDFD69C132C817F7FB57514175C126B9EDFD69C1A74EFBEEFB575141AA2BB1E0EDFD69C1A23E7698FB575141E346224AEEFD69C13274F18AFB575141FAAC6968EEFD69C13B4924D2FB57514165817EB7EEFD69C1625F3AC8FB575141C38D47D3EEFD69C10D6F1A6EFB575141F588E4BBEFFD69C1D7B15C50FB575141540E17DEEFFD69C1C1982DA4FB5751412314872DF0FD69C1CAF65C99FB57514101DD844CF0FD69C1A4450738FB5751410FA5D07FF0FD69C18F3CB831FB575141E410BF7EF0FD69C1F1D852ECFA57514112E8D6BAF2FD69C13C9552A3FA575141
25371853	building	transportation		3	13	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000009000000A0F97B8CE9FD69C11C8F241BFC575141A3675C93E7FD69C1AABEABE5C9575141A6F65DA4D5FD69C128264CD5CC5751411535A2CED4FD69C15D3F5E2DD2575141156AF861D1FD69C161BDCCF8D7575141607BB672D1FD69C1101A1F50DA57514168C771F7CDFD69C14997889BE057514129478F16CFFD69C13E784B3300585141A0F97B8CE9FD69C11C8F241BFC575141
132605488	building	yes		\N	14	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000009F2BF488C1FD69C1575829D508585141EAB40E68C0FD69C13623B3DDEB575141B2A4E903B7FD69C123CAD924ED57514172AB9D1CB8FD69C17760675B0A5851419F2BF488C1FD69C1575829D508585141
25371859	building	yes	OfficeMax	\N	7	1750	Harrison Street	San Francisco	\N	94103	1750 Harrison Street, San Francisco, 94103	\N	\N	\N	0106000020110F00000100000001030000000100000009000000A17659C4DDFD69C19C191F233F5851417BB48C09D9FD69C1865A27AC3E585141DA7AABF6D8FD69C1A9A646593D585141D938B2F3D7FD69C1D25C24883D58514123D106FED7FD69C1B05104923E585141E8739C91D6FD69C1744EF76D3E58514195BF2432D6FD69C16D1AAAA14D585141EB908664DDFD69C1EC2AD2564E585141A17659C4DDFD69C19C191F233F585141
25821942	building	yes	Best Buy	\N	8	1717	Harrison Street	\N	\N	94103	1717 Harrison Street, 94103	\N	\N	\N	0106000020110F0000010000000103000000010000000B000000B4145E6FCDFD69C10D58FECA39585141B15EB9C9CCFD69C1285C3FB4285851419D765C1BC2FD69C15E26D4522A585141A84CD541C2FD69C17D1BF64F2E5851419EA80EBBC0FD69C15CE2718B2E585141973CC56FBFFD69C1440FCA8F32585141183BF375C0FD69C181D1D760345851413DE6A0F9BFFD69C1F4180D833558514164516FEAC0FD69C18B47272F37585141E1DAE415C1FD69C12C4F91A93B585141B4145E6FCDFD69C10D58FECA39585141
132605510	building	parking		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000CDAC572DCCFD69C1C069514020585141EAB44B62CBFD69C1B73F98740B585141A85D29DDC5FD69C196B0B24E0C58514132263AD2C3FD69C1512DD56821585141CDAC572DCCFD69C1C069514020585141
132605486	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000EAB44B62CBFD69C1B73F98740B585141758327F3CAFD69C10EFC33B6FB575141B2C00399C7FD69C1615D2112FC575141A85D29DDC5FD69C196B0B24E0C585141EAB44B62CBFD69C1B73F98740B585141
261095636	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000070000008F3E131ADDFD69C123CF80262E585141A79F9CD4DCFD69C16BE5804D285851413DE72726D7FD69C13472DB49295851412FD36628D5FD69C179F076962958514150501338D5FD69C144A5A9092E585141DF8EE93FD5FD69C190865A672F5851418F3E131ADDFD69C123CF80262E585141
261095634	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000060000003DE72726D7FD69C13472DB49295851413AF096B5D6FD69C1BD1A210C1E585141547E14ACD4FD69C12FDA5D6E1E5851414C9F2CF6D4FD69C1BEA53F50275851412FD36628D5FD69C179F07696295851413DE72726D7FD69C13472DB4929585141
256472200	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000004C9F2CF6D4FD69C1BEA53F5027585141547E14ACD4FD69C12FDA5D6E1E58514115A16865D0FD69C17A47A4EB1E58514194E9F1C5D0FD69C1D4735721285851414C9F2CF6D4FD69C1BEA53F5027585141
261095632	building	yes		\N	11	1818;1820	Harrison Street	\N	\N	\N	1818;1820 Harrison Street	\N	\N	\N	0106000020110F0000010000000103000000010000000600000050501338D5FD69C144A5A9092E5851412FD36628D5FD69C179F07696295851414C9F2CF6D4FD69C1BEA53F502758514194E9F1C5D0FD69C1D47357212858514105E398F9D0FD69C1A3C70C8F2E58514150501338D5FD69C144A5A9092E585141
256472207	building	yes		\N	10	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000E7B83988D5FD69C11C0A84A237585141DF8EE93FD5FD69C190865A672F58514150501338D5FD69C144A5A9092E58514105E398F9D0FD69C1A3C70C8F2E58514148156F54D1FD69C1EE11073938585141E7B83988D5FD69C11C0A84A237585141
261095625	building	yes	Wag Hotels	\N	\N	25	14th Street	San Francisco	CA	94103	25 14th Street, San Francisco, CA, 94103	\N	\N	\N	0106000020110F000001000000010300000001000000050000000A95C96DDDFD69C1A713CD7B365851418F3E131ADDFD69C123CF80262E585141DF8EE93FD5FD69C190865A672F585141E7B83988D5FD69C11C0A84A2375851410A95C96DDDFD69C1A713CD7B36585141
256472212	building	yes		\N	8	41	14th Street	\N	\N	\N	41 14th Street	\N	\N	\N	0106000020110F000001000000010300000001000000060000004BABFF27E3FD69C124A14CA535585141A601249EE2FD69C152061A7627585141A79F9CD4DCFD69C16BE5804D285851418F3E131ADDFD69C123CF80262E5851410A95C96DDDFD69C1A713CD7B365851414BABFF27E3FD69C124A14CA535585141
397006689	building	yes		\N	\N	64	14th Street	\N	\N	94103	64 14th Street, 94103	\N	\N	\N	0106000020110F00000100000001030000000100000006000000F4CD44B8E3FD69C1486EF3B5415851416549C481E3FD69C18810A8E83B585141D309E141E2FD69C1399EE70A3C585141CE5DB863E2FD69C10DFBA3303F5851418192A481E2FD69C102E8CDDB41585141F4CD44B8E3FD69C1486EF3B541585141
397006819	building	yes		\N	\N	81	14th Street	\N	\N	\N	81 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000006000000FBFE6CD4E6FD69C1E21DAD06355851410908A5D2E6FD69C1776796C734585141588D0E86E6FD69C194B9F53E2B585141E4D80449E5FD69C165909D662B585141EC7BBE97E5FD69C177FE542E35585141FBFE6CD4E6FD69C1E21DAD0635585141
397006815	building	yes		\N	\N	77;85	14th Street	\N	\N	\N	77;85 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C00000071B37611E8FD69C132FABBA13458514180EF6DE7E7FD69C1C6D894093058514120F1D1BEE7FD69C1269C34182B585141588D0E86E6FD69C194B9F53E2B5851410908A5D2E6FD69C1776796C7345851414D7B67F8E6FD69C1C103480A3558514125983C39E7FD69C117C54401355851418EBB6A46E7FD69C1153BE2C43458514150310C9EE7FD69C1A71644B834585141669753BCE7FD69C10B5A8DF534585141BE7E8AF3E7FD69C1568E57EE3458514171B37611E8FD69C132FABBA134585141
397006688	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000AD9991E7EBFD69C17BB685B13F5851419B9E86DCEBFD69C1875A17643D5851415DBC1C32E7FD69C180E037BE3D5851416EB7273DE7FD69C1AD41A60B40585141AD9991E7EBFD69C17BB685B13F585141
397006687	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000009B9E86DCEBFD69C1875A17643D585141882A12CBEBFD69C127C1F68A3A585141212D0026E7FD69C1FBC0373F3B5851415DBC1C32E7FD69C180E037BE3D5851419B9E86DCEBFD69C1875A17643D585141
261095628	building	yes		\N	9	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000060000004ECEB496EBFD69C187369C9034585141CECBD564EBFD69C135D4CF902F58514180EF6DE7E7FD69C1C6D894093058514171B37611E8FD69C132FABBA13458514180351816E8FD69C17FAD021F355851414ECEB496EBFD69C187369C9034585141
261095626	building	yes		\N	7	1811	Folsom Street	\N	\N	\N	1811 Folsom Street	\N	\N	\N	0106000020110F00000100000001030000000100000005000000CECBD564EBFD69C135D4CF902F58514145B29141EBFD69C13E4F079A2A58514120F1D1BEE7FD69C1269C34182B58514180EF6DE7E7FD69C1C6D8940930585141CECBD564EBFD69C135D4CF902F585141
261095638	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000800000018E60205EBFD69C126848AAA23585141CB1531BFEAFD69C1556115CD1C585141C1558D9DE3FD69C122C346E61D585141F546AEBEE3FD69C10456505B21585141CF1DD9D0E3FD69C16161E5422358514162D518DFE3FD69C1A4CFA2C424585141D410B915E5FD69C16C0B11932458514118E60205EBFD69C126848AAA23585141
261095624	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000AD8F1520EBFD69C1E75099562658514118E60205EBFD69C126848AAA23585141D410B915E5FD69C16C0B11932458514110276C1BE5FD69C15A7C080A25585141F806CF2BE5FD69C18097941F27585141AD8F1520EBFD69C1E750995626585141
261095630	building	yes		\N	6	1825	Folsom Street	\N	\N	\N	1825 Folsom Street	\N	\N	\N	0106000020110F0000010000000103000000010000000700000045B29141EBFD69C13E4F079A2A585141AD8F1520EBFD69C1E750995626585141F806CF2BE5FD69C18097941F27585141E4D80449E5FD69C165909D662B585141588D0E86E6FD69C194B9F53E2B58514120F1D1BEE7FD69C1269C34182B58514145B29141EBFD69C13E4F079A2A585141
261095629	building	yes		\N	5	75	14th Street	\N	\N	\N	75 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000EC7BBE97E5FD69C177FE542E35585141E4D80449E5FD69C165909D662B585141F806CF2BE5FD69C18097941F27585141BAEE01B6E2FD69C1B0217F7227585141A601249EE2FD69C152061A76275851414BABFF27E3FD69C124A14CA535585141EC7BBE97E5FD69C177FE542E35585141
397006817	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000F806CF2BE5FD69C18097941F2758514110276C1BE5FD69C15A7C080A25585141ABF403E3E3FD69C172AF2E2D255851410AACE8A4E2FD69C1C39B3B5125585141BAEE01B6E2FD69C1B0217F7227585141F806CF2BE5FD69C18097941F27585141
397006818	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000008000000ABF403E3E3FD69C172AF2E2D2558514162D518DFE3FD69C1A4CFA2C424585141CF1DD9D0E3FD69C16161E54223585141CDA36292E2FD69C10C2D545A23585141430CF704E2FD69C1C4203E6423585141E1CC6E11E2FD69C1DC585B62255851410AACE8A4E2FD69C1C39B3B5125585141ABF403E3E3FD69C172AF2E2D25585141
397006816	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000CF1DD9D0E3FD69C16161E54223585141F546AEBEE3FD69C10456505B21585141D933318AE2FD69C193D9A57321585141CDA36292E2FD69C10C2D545A23585141CF1DD9D0E3FD69C16161E54223585141
261095627	building	yes		\N	24	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000002239965DEAFD69C1FE7BE8A11A585141A3B3D15DE9FD69C1EF4976CC015851413D554527E0FD69C1EB68E34703585141210C6527E1FD69C10F413D1E1C5851412239965DEAFD69C1FE7BE8A11A585141
25821952	building	retail	Foods Co	\N	\N	1800	Folsom Street	\N	\N	\N	1800 Folsom Street	\N	\N	\N	0106000020110F000001000000010300000001000000050000003250BBFDFAFD69C10E55010223585141F4C44F1DFAFD69C102274B1408585141CBA85DF0EDFD69C1900A6DDB095851419293B722EFFD69C18AABF51C255851413250BBFDFAFD69C10E55010223585141
261100106	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000F000000EE84EDD5F5FD69C138D311BB07585141317A8891F5FD69C133DE681601585141D9960286F4FD69C1BC9F2634015851411718F29EF4FD69C1840A3D44045851412ACD527BF4FD69C152A4BE4804585141CF39F365F4FD69C11B60F47E01585141890BCE36F3FD69C1C30D149001585141E3E4D77AF3FD69C1C59066410758514148D546B0F3FD69C1C685173B075851412CC3D6B3F3FD69C11C3A610A085851416A4E4294F4FD69C11BC60BF207585141A272228DF4FD69C18DC598F606585141BC8950EDF4FD69C18120C8EB06585141856570F4F4FD69C1C9203BE707585141EE84EDD5F5FD69C138D311BB07585141
261100109	building	yes		\N	11	1402;1404	15th Street	\N	\N	\N	1402;1404 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000900000034A2BE69F3FD69C12C209EB508585141890BCE36F3FD69C1C30D1490015851419DF79E16F2FD69C1932B89B901585141DD788E2FF2FD69C1FF9C0786045851410A405F08F2FD69C1D436898A045851414BC14E21F2FD69C13D96766E075851417C7FB06AF2FD69C196D5C87D075851413A446B80F2FD69C1C9B258CA0858514134A2BE69F3FD69C12C209EB508585141
261100108	building	yes		\N	6	1434	15th Street	\N	\N	\N	1434 15th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000DE129334F8FD69C1795B4E1D08585141843989F0F7FD69C17293487300585141DDCACE95F5FD69C14387099A00585141317A8891F5FD69C133DE681601585141EE84EDD5F5FD69C138D311BB07585141EE84EDD5F5FD69C1AF1C169F08585141DE129334F8FD69C1795B4E1D08585141
261100107	building	yes		\N	6	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000500000083C6EA85F9FD69C16D6BDCFC07585141667CFD4DF9FD69C1D8FD2E2B00585141843989F0F7FD69C17293487300585141DE129334F8FD69C1795B4E1D0858514183C6EA85F9FD69C16D6BDCFC07585141
256458242	building	yes		\N	7	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000060000000071FBAFFFFD69C1F552389F05585141A9CF6EA7FFFD69C19893409604585141D4A46C73FFFD69C11C20177FFE575141CF605900FCFD69C14CF659F3FE5751419AFB8C3CFCFD69C1003E7B13065851410071FBAFFFFD69C1F552389F05585141
256458216	building	yes		\N	7	1454;1456;1458;1460;1462;1464;1466;1468	15th Street	\N	\N	\N	1454;1456;1458;1460;1462;1464;1466;1468 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A00000022355F2601FE69C1C0DBD0A303585141F85AA3F600FE69C1F1F96B05FE57514123EAF69300FE69C138C5F012FE575141CEC1D39100FE69C1EB4675D7FD5751412854266FFFFD69C1323836FEFD575141D4A46C73FFFD69C11C20177FFE575141A9CF6EA7FFFD69C19893409604585141D172BAD300FE69C186E3986E04585141D0F950CD00FE69C13E3888AF0358514122355F2601FE69C1C0DBD0A303585141
256458251	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000008000000427B9B3202FE69C17A5DD5E00958514136A5220C02FE69C17475CC47055851410071FBAFFFFD69C1F552389F055851419AFB8C3CFCFD69C1003E7B1306585141D703134FFCFD69C123D6B362085851411E732449FDFD69C1FEDD7A520858514105538759FDFD69C17D0F48930A585141427B9B3202FE69C17A5DD5E009585141
256458218	building	yes		\N	7	74;76	Shotwell Street	\N	\N	\N	74;76 Shotwell Street	\N	\N	\N	0106000020110F0000010000000103000000010000000B000000246711C6FFFD69C12A71DEF10B585141679429BDFFFD69C18462B0980A5851417901C6FAFCFD69C1DBF1ECFA0A58514107C732FCFCFD69C12C074C2E0B585141F160EBDDFCFD69C1C2A1CD320B585141C74543E3FCFD69C1D33A9C0F0C5851417F6C020EFDFD69C19DE7330A0C585141C68BED11FDFD69C15CBB83A20C58514100EE15E2FEFD69C146391E5D0C585141ABC5F2DFFEFD69C1142F4D090C585141246711C6FFFD69C12A71DEF10B585141
256458232	building	yes		\N	10	58;60	Shotwell Street	\N	\N	\N	58;60 Shotwell Street	\N	\N	\N	0106000020110F0000010000000103000000010000000D0000008E40E47800FE69C160096E69135851416F3CA16F00FE69C12C630A52125851418DC2BC0E00FE69C1AE7CA85E12585141A8D42C0B00FE69C1098703F711585141022B5181FFFD69C176F4090912585141E59F777EFFFD69C14EB484B211585141ECFB7966FEFD69C148005FD811585141BD6FCABCFCFD69C18372261112585141FC7750CFFCFD69C16E276C3B14585141D45DB50CFEFD69C1973D101114585141A3643294FFFD69C11164CADC1358514186D95891FFFD69C157911288135851418E40E47800FE69C160096E6913585141
256458239	building	yes		\N	7	52;54	Shotwell Street	\N	\N	\N	52;54 Shotwell Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A000000A3AADCC2FFFD69C100C5754C16585141AB48D8ADFFFD69C135812FD913585141A3643294FFFD69C11164CADC13585141D45DB50CFEFD69C1973D101114585141C5547D0EFEFD69C17024A54B14585141ED6E18D1FCFD69C1880E01761458514148890EE0FCFD69C1D657362A16585141A1212C59FDFD69C1125AFD19165851414D72725DFDFD69C186BA929D16585141A3AADCC2FFFD69C100C5754C16585141
256458230	building	yes		\N	11	62;64;66	Shotwell Street	\N	\N	\N	62;64;66 Shotwell Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C0000003621300600FE69C153191BD2105851417A4E48FDFFFD69C12139D7CB0F585141F075F0A4FFFD69C136998ED70F5851415F371A9DFFFD69C1AF37A0E90E585141D8C22684FCFD69C1324FF9530F58514179FC0797FCFD69C128CD28881158514179487D61FEFD69C16BC0DF4A11585141ECFB7966FEFD69C148005FD811585141E59F777EFFFD69C14EB484B2115851419D3FA0AFFFFD69C1A8A735AC115851413895DBA8FFFD69C15B32B9DE105851413621300600FE69C153191BD210585141
256458231	building	yes		\N	10	42;44	Shotwell Street	\N	\N	\N	42;44 Shotwell Street	\N	\N	\N	0106000020110F000001000000010300000001000000050000000528AD8D01FE69C1E941C9D91A58514172F7037901FE69C184991D6A18585141BFA747F8FCFD69C15F0E3B041958514153D8F00CFDFD69C137C0E6731B5851410528AD8D01FE69C1E941C9D91A585141
256458229	building	yes		\N	7	48;50	Shotwell Street	\N	\N	\N	48;50 Shotwell Street	\N	\N	\N	0106000020110F0000010000000103000000010000000800000077E5255A02FE69C199C65F4C18585141AC17334602FE69C18E7BF0F515585141A3AADCC2FFFD69C100C5754C165851414D72725DFDFD69C186BA929D16585141F3D954E4FCFD69C180B8CBAD16585141BFA747F8FCFD69C15F0E3B041958514172F7037901FE69C184991D6A1858514177E5255A02FE69C199C65F4C18585141
256458238	building	yes		\N	5	36;40	Shotwell Street	\N	\N	\N	36;40 Shotwell Street	\N	\N	\N	0106000020110F00000100000001030000000100000008000000C479C93803FE69C1E9C677091D585141D082013703FE69C10045B0D01C585141937A7B2403FE69C1BAEDB5A31A5851410528AD8D01FE69C1E941C9D91A58514153D8F00CFDFD69C137C0E6731B585141E7089A21FDFD69C1F7A5A8D91D585141882B99F702FE69C121007B121D585141C479C93803FE69C1E9C677091D585141
256458240	building	yes		\N	6	32	Shotwell Street	\N	\N	\N	32 Shotwell Street	\N	\N	\N	0106000020110F000001000000010300000001000000060000001A5C420C03FE69C1C554A57D1F585141882B99F702FE69C121007B121D585141E7089A21FDFD69C1F7A5A8D91D5851417B394336FDFD69C1BA06D344205851414D468B5900FE69C1E10893D91F5851411A5C420C03FE69C1C554A57D1F585141
256458219	building	yes		\N	10	28;30	Shotwell Street	\N	\N	\N	28;30 Shotwell Street	\N	\N	\N	0106000020110F00000100000001030000000100000009000000AD49E5E500FE69C12BA4148B215851419B4EDADA00FE69C1CAA11B39205851419465765D00FE69C1B1A35449205851414D468B5900FE69C1E10893D91F5851417B394336FDFD69C1BA06D344205851414807364AFDFD69C1E8C18E9822585141422F266800FE69C1D276352E2258514133AD846300FE69C1AA181B9D21585141AD49E5E500FE69C12BA4148B21585141
261098422	building	yes		\N	9	18;20	Shotwell Street	\N	\N	\N	18;20 Shotwell Street	\N	\N	\N	0106000020110F0000010000000103000000010000000D000000E819EEBC00FE69C1228E22FF26585141F0B7E9A700FE69C1AB65B2A8245851418A7AF86FFDFD69C1CF9BA61625585141A805D272FDFD69C18931E06F255851417514B151FDFD69C119CF6174255851413DF0D058FDFD69C10268C5422658514180EA2978FDFD69C15BCA433E2658514101A75E7BFDFD69C1FAC4FB92265851415B7BAA5BFDFD69C1AC627D9726585141ECB98063FDFD69C179BF0077275851419C75037BFDFD69C1D8DA657327585141BA898DE7FFFD69C10C6CE01C27585141E819EEBC00FE69C1228E22FF26585141
256458236	building	yes		\N	9	22;24	Shotwell Street	\N	\N	\N	22;24 Shotwell Street	\N	\N	\N	0106000020110F00000100000001030000000100000008000000A375862F03FE69C1F4FC2C522458514148E2261A03FE69C150BD47D221585141422F266800FE69C1D276352E225851414807364AFDFD69C1E8C18E9822585141A49A955FFDFD69C11FC75A19255851418A7AF86FFDFD69C1CF9BA61625585141F0B7E9A700FE69C1AB65B2A824585141A375862F03FE69C1F4FC2C5224585141
261098424	building	yes		\N	8	12;14;16	Shotwell Street	\N	\N	\N	12;14;16 Shotwell Street	\N	\N	\N	0106000020110F000001000000010300000001000000070000000814B5FEFFFD69C1728A77DF29585141BA898DE7FFFD69C10C6CE01C275851419C75037BFDFD69C1D8DA657327585141B262E192FDFD69C1611A62322A5851412808B1A4FDFD69C1F2A794302A585141DB835429FFFD69C150B14EFC295851410814B5FEFFFD69C1728A77DF29585141
261098423	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000D000000516FCE69FFFD69C1717351F930585141DB835429FFFD69C150B14EFC295851412808B1A4FDFD69C1F2A794302A585141F1E3D0ABFDFD69C17D745DFB2A5851412DB4D982FDFD69C12A85AC012B5851413611E9A2FDFD69C19706ED7D2E585141F940E0CBFDFD69C1AEAE84782E5851419EF32AE5FDFD69C1C958323131585141041C1756FEFD69C1FB4FF9203158514185D84B59FEFD69C1D361B17531585141B98D3E13FFFD69C150A8A75A3158514137D10910FFFD69C11050D60631585141516FCE69FFFD69C1717351F930585141
288675791	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000019000000BF7B23FAF4FD69C136300F75415851413D4685F0F4FD69C17E91D9524058514151744FD3F4FD69C11B325B5740585141126CC9C0F4FD69C17C5616363E58514164E8C3E4F4FD69C172FCAD303E58514127E03DD2F4FD69C1BB84820E3C585141E69F3A84F4FD69C13D3853193C58514142EDEF6AF4FD69C1365DCA3A39585141651A7684F3FD69C1E8BB555A39585141CA4BD184F3FD69C1AF6E2665395851413CFEC051F2FD69C15380828F395851413360C566F2FD69C1C050ABF13B5851419619C498F3FD69C1913C4FC73B5851417A07549CF3FD69C1703F76333C5851413B866483F3FD69C1F42511373C58514141F1A096F3FD69C12208DE6E3E585141922CAFEFF3FD69C14F9A26633E585141416FC800F4FD69C1F413E0644058514163E2F848F3FD69C142641C7E40585141CFB14F34F3FD69C14B940C1B3E58514124568030F1FD69C1F32659613E5851415455CE44F1FD69C19E8CB1B84058514194D1FFF9F0FD69C1AB879BC240585141439BAF04F1FD69C1D67A0DFE41585141BF7B23FAF4FD69C136300F7541585141
256454800	building	yes		\N	\N	160;162	14th Street	\N	\N	\N	160;162 14th Street	\N	\N	\N	0106000020110F000001000000010300000001000000050000005EBFBDCE00FE69C1EA3C1E5D375851418D3A19DDFEFD69C10224E99E375851412DFB90E9FEFD69C184118E213958514179D12DCB00FE69C11BA0B3FB385851415EBFBDCE00FE69C1EA3C1E5D37585141
256454808	building	yes		\N	\N	157	13th Street	\N	\N	\N	157 13th Street	\N	\N	\N	0106000020110F00000100000001030000000100000005000000E13B133F02FE69C19C631A3558585141ED0CCE0102FE69C19538D0CC50585141EBEA25CBFAFD69C1ED0D71B45158514171584110FBFD69C1800319D156585141E13B133F02FE69C19C631A3558585141
651669420	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000800000071584110FBFD69C1800319D156585141EBEA25CBFAFD69C1ED0D71B451585141F00D9E3FF8FD69C11C7C780F52585141DC981CF6F6FD69C140A5666B52585141D3B93440F7FD69C122CDC42F565851417F0A7B44F7FD69C127B8F16456585141E1196B08FBFD69C192ED87E85658514171584110FBFD69C1800319D156585141
651669421	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000D3B93440F7FD69C122CDC42F56585141DC981CF6F6FD69C140A5666B52585141E627DEB5F5FD69C137CF54C752585141F95A66FCF5FD69C19DFC4C4656585141D3B93440F7FD69C122CDC42F56585141
256454796	building	yes	Pak Auto Service	\N	8	1748	Folsom Street	San Francisco	CA	94103	1748 Folsom Street, San Francisco, CA, 94103	\N	\N	\N	0106000020110F000001000000010300000001000000060000008E8651ADF5FD69C1795134274A5851416C903B97F5FD69C1EDB1CC3448585141271D7971F5FD69C1D13FB44846585141CBF4D2BAEFFD69C1880F4B15475851410C3018A5EFFD69C14F218EAC4B5851418E8651ADF5FD69C1795134274A585141
256454810	building	yes		\N	6	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000007000000CE178829F8FD69C1710EF3CB4F58514109E3D29CF7FD69C1BA180D85475851416C903B97F5FD69C1EDB1CC34485851418E8651ADF5FD69C1795134274A5851410C3018A5EFFD69C14F218EAC4B585141CEE1E763EFFD69C11532C55552585141CE178829F8FD69C1710EF3CB4F585141
288675796	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000500000098D9E405F5FD69C10888FFAB42585141BF7B23FAF4FD69C136300F7541585141439BAF04F1FD69C1D67A0DFE41585141D452EF12F1FD69C165212D2A4358514198D9E405F5FD69C10888FFAB42585141
288675792	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000002D83F720F5FD69C16343CA3E46585141481CFE16F5FD69C1C615F306455851415901F722F1FD69C105F9238E4558514178053A2CF1FD69C1F8A1DEBD465851412D83F720F5FD69C16343CA3E46585141
288675795	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000002918BB0DF5FD69C18E2F09E24358514198D9E405F5FD69C10888FFAB42585141D452EF12F1FD69C165212D2A43585141739AFD18F1FD69C1E271CE5A445851412918BB0DF5FD69C18E2F09E243585141
288675794	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000481CFE16F5FD69C1C615F306455851412918BB0DF5FD69C18E2F09E243585141739AFD18F1FD69C1E271CE5A44585141929E4022F1FD69C1A911898A45585141481CFE16F5FD69C1C615F30645585141
288675793	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000AAF54D15F0FD69C19DBE8483405851418CF10A0CF0FD69C1A36A640E3F5851417DE314AAEFFD69C147654E183F5851419EE757B3EFFD69C19CB96E8D40585141AAF54D15F0FD69C19DBE848340585141
169204244	building	yes		\N	\N	82	14th Street	\N	\N	\N	82 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000008000000DE37656AE7FD69C189B3814A465851416EB7273DE7FD69C1AD41A60B405851419DF7611CE7FD69C1E12DEF4A3B585141E41540E8E5FD69C153C144633B585141231EC6FAE5FD69C1498DE15C3D5851417BBF5203E6FD69C1FDD71C483E5851412C3AE94FE6FD69C15290DA6B46585141DE37656AE7FD69C189B3814A46585141
397006685	building	yes		\N	\N	74;76	14th Street	\N	\N	\N	74;76 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000F0000002C3AE94FE6FD69C15290DA6B465851417BBF5203E6FD69C1FDD71C483E585141C88A66E5E5FD69C10405D14A3E5851419B7DEBDDE5FD69C13FBA955F3D585141231EC6FAE5FD69C1498DE15C3D585141E41540E8E5FD69C153C144633B58514146468EB0E4FD69C132086B863B58514167C33AC0E4FD69C13D1C217F3D58514106CA5CFBE4FD69C1B0AE69733D585141174CFEFFE4FD69C1B05104923E585141EAF8D8C9E4FD69C19AF79B8C3E5851410943C601E5FD69C11CB844B2435851415162B105E5FD69C1E03B2CFC43585141D3974F0FE5FD69C14689AE7F465851412C3AE94FE6FD69C15290DA6B46585141
397006690	building	yes		\N	\N	70	14th Street	\N	\N	\N	70 14th Street	\N	\N	\N	0106000020110F000001000000010300000001000000090000000943C601E5FD69C11CB844B243585141EAF8D8C9E4FD69C19AF79B8C3E58514167C33AC0E4FD69C13D1C217F3D58514146468EB0E4FD69C132086B863B585141ABEF457FE3FD69C1B668F6A53B5851416549C481E3FD69C18810A8E83B585141F4CD44B8E3FD69C1486EF3B54158514123CD92CCE3FD69C129A3D6E3435851410943C601E5FD69C11CB844B243585141
169204245	building	hall	Rainbow Grocery Coop	\N	\N	1745	Folsom Street	San Francisco	CA	94103	1745 Folsom Street, San Francisco, CA, 94103	yes	\N	\N	0106000020110F0000010000000103000000010000001200000004FA3125ECFD69C133F8B05A47585141B76F0A0EECFD69C1D1E84FAA3F585141AD9991E7EBFD69C17BB685B13F5851416EB7273DE7FD69C1AD41A60B40585141DE37656AE7FD69C189B3814A465851412757506EE7FD69C1EA23CFD94658514137C9AA0FE5FD69C1A7E4E1C646585141D3974F0FE5FD69C14689AE7F465851415162B105E5FD69C1E03B2CFC4358514173CA584EE2FD69C18CF1FC0644585141D9741D55E2FD69C1C77E6C9D46585141CB1AB228E0FD69C16FC16FA646585141F7A905C6DFFD69C1B46E34805058514120BA61BBE8FD69C1F7BE2340525851419B521112EAFD69C1ED2F6D7D52585141CCCF8690EAFD69C1662E2B9B52585141F864A5C9EBFD69C17D71C0D55258514104FA3125ECFD69C133F8B05A47585141
397006686	building	residential		\N	\N	1719;1721	Folsom Street	\N	\N	\N	1719;1721 Folsom Street	\N	\N	\N	0106000020110F00000100000001030000000100000015000000F864A5C9EBFD69C17D71C0D552585141CCCF8690EAFD69C1662E2B9B52585141D85F5588EAFD69C16858030153585141FD0A030CEAFD69C1C5132CE4525851419B521112EAFD69C1ED2F6D7D5258514120BA61BBE8FD69C1F7BE234052585141CA913EB9E8FD69C10001A38452585141F3EDD27EE8FD69C12EBCB57152585141FA8BCE69E8FD69C1483A78FC535851411CC88EAEE8FD69C14EF44807545851411B4F25A8E8FD69C100223763545851413A5475E9E9FD69C160F3D2AF545851415A58B8F2E9FD69C139C52636545851412B96A57DEAFD69C15BDC5F4654585141C5EBE076EAFD69C100C5C6D45458514156B25AB0EBFD69C11797781755585141BB5C1FB7EBFD69C10B224D5954585141CF8AE999EBFD69C184F3985654585141EE8E2CA3EBFD69C139C744B553585141914177BCEBFD69C1F66A1E9253585141F864A5C9EBFD69C17D71C0D552585141
692910505	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000060000004617F7A115FE69C12CB6A0B957585141587559B411FE69C1DBCA479857585141467A4EA911FE69C1452488AF5C585141CFEA909615FE69C139CEC7D15C585141E06C329B15FE69C1D13FA1C15A5851414617F7A115FE69C12CB6A0B957585141
692910506	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000E46F594319FE69C1AC1FEC834D585141CC3E68B815FE69C1FD6A47654D5851414617F7A115FE69C12CB6A0B957585141E06C329B15FE69C1D13FA1C15A5851415CCF7E2619FE69C121B92CE15A585141E46F594319FE69C1AC1FEC834D585141
260973315	building	yes	Public Works	\N	7	161	Erie Street	San Francisco	CA	94103	161 Erie Street, San Francisco, CA, 94103	\N	\N	\N	0106000020110F000001000000010300000001000000060000006C4223FA22FE69C15C0DEA8548585141A5DAAE9522FE69C1F94EEB773D585141470FD24422FE69C187BCA2833D5851415EDC21961DFE69C16DCFF92D3E585141C1123BFA1DFE69C178C0F83B495851416C4223FA22FE69C15C0DEA8548585141
260973321	building	yes		\N	5	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000050000000771BB5E10FE69C16C5A023640585141D4F8034410FE69C1320CDB4A3D5851410A99F1360EFE69C10E84C2943D5851413C11A9510EFE69C16F91D080405851410771BB5E10FE69C16C5A023640585141
256454807	building	yes		\N	12	263;265;267	South Van Ness Avenue	\N	\N	\N	263;265;267 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000070000006B817B600AFE69C1D68463E64758514166163F4D0AFE69C1D2E91F3C45585141374E613C09FE69C13798C45A45585141E78033EA06FE69C15450769D45585141EBEB6FFD06FE69C1C6ABA04848585141D603504907FE69C1C0689D3F485851416B817B600AFE69C1D68463E647585141
256454781	building	yes		\N	10	257;259;261	South Van Ness Avenue	\N	\N	\N	257;259;261 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000060000000CBB5C730AFE69C1E5F13E8B4A5851416B817B600AFE69C1D68463E647585141D603504907FE69C1C0689D3F48585141DC6E8C5C07FE69C1C1DB78E44A585141E49AF6140AFE69C15AA90F964A5851410CBB5C730AFE69C1E5F13E8B4A585141
256454792	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000B28F12C906FE69C1C75FADC256585141A19407BE06FE69C1A9C26BFE4F5851419189B54F04FE69C1D0471A385058514177319B2404FE69C10299347D58585141B28F12C906FE69C12CD3F6EC58585141B28F12C906FE69C1C75FADC256585141
256454788	building	yes		3	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000070000005E7385FE09FE69C1D30154764F585141A19407BE06FE69C1A9C26BFE4F585141B28F12C906FE69C1C75FADC256585141197CD0D207FE69C18F1A7ECD56585141D6C721E207FE69C1E528850D565851417B3F4BCC09FE69C1E528850D565851415E7385FE09FE69C1D30154764F585141
256454804	building	yes		\N	13	251	South Van Ness Avenue	\N	\N	\N	251 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000600000086D4D7270AFE69C1038C1A304D585141E49AF6140AFE69C15AA90F964A585141DC6E8C5C07FE69C1C1DB78E44A58514102CFD14D06FE69C1828E1D034B58514140D7576006FE69C15078289D4D58514186D4D7270AFE69C1038C1A304D585141
256454803	building	yes		\N	7	269	South Van Ness Avenue	\N	\N	\N	269 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000006000000374E613C09FE69C13798C45A45585141C0A8912A09FE69C1D5F9ADE542585141A444E1C705FE69C19F5A0447435851411AEAB0D905FE69C105FF1ABC45585141E78033EA06FE69C15450769D45585141374E613C09FE69C13798C45A45585141
256454811	building	yes		\N	5	275	South Van Ness Avenue	\N	\N	\N	275 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000008000000649DD5460AFE69C1C7D93BC542585141188C17360AFE69C105282F6B405851417E20CA3D06FE69C1AD4BA5DD40585141D57A9FDF04FE69C113384D054158514185BDB8F004FE69C1F5F2595F43585141A444E1C705FE69C19F5A044743585141C0A8912A09FE69C1D5F9ADE542585141649DD5460AFE69C1C7D93BC542585141
256454797	building	yes		\N	6	164	14th Street	\N	\N	\N	164 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000009000000527B64A102FE69C1B2299F18375851415EBFBDCE00FE69C1EA3C1E5D3758514179D12DCB00FE69C11BA0B3FB385851413CC9A7B800FE69C1779C4EB242585141B2B52E3102FE69C107090F904258514116E7893102FE69C15448DCF73E585141F17CC87802FE69C12C5C2BFE3E5851416530C57D02FE69C18E8FEE803D585141527B64A102FE69C1B2299F1837585141
256454778	building	yes		\N	\N	174	14th Street	\N	\N	\N	174 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000005000000ABE1CF7A04FE69C15A3379573D585141FB9EB66904FE69C13295F6A736585141527B64A102FE69C1B2299F18375851416530C57D02FE69C18E8FEE803D585141ABE1CF7A04FE69C15A3379573D585141
256454809	building	yes		\N	\N	285	South Van Ness Avenue	\N	\N	\N	285 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000050000007E20CA3D06FE69C1AD4BA5DD40585141463DD60F06FE69C1D1E787733A585141A9277AA904FE69C1E32082AA3A585141D57A9FDF04FE69C113384D05415851417E20CA3D06FE69C1AD4BA5DD40585141
256454784	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000188C17360AFE69C105282F6B405851417D77C8070AFE69C1A5D611013A585141463DD60F06FE69C1D1E787733A5851417E20CA3D06FE69C1AD4BA5DD40585141188C17360AFE69C105282F6B40585141
363054684	building	commercial	Audi San Francisco	3	\N	300	South Van Ness Avenue	San Francisco	CA	94103	300 South Van Ness Avenue, San Francisco, CA, 94103	\N	\N	\N	0106000020110F000001000000010300000001000000060000004E1D08F811FE69C1C36A0DD82E5851411E5FA6AE11FE69C1B6BCB8CB27585141467A4EA911FE69C1D14ED74A27585141BA1739AF0DFE69C19464ACF0275851415D8997FD0DFE69C10CA0E27D2F5851414E1D08F811FE69C1C36A0DD82E585141
261089752	building	yes		\N	6	310	South Van Ness Avenue	\N	\N	\N	310 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000800000018F927FF11FE69C1E4F76E452758514191D1B6E811FE69C11AA827D22458514126BCB5CE11FE69C1080C0C022258514157744C7C10FE69C1F85AD0312258514100FFA6770DFE69C15843ABA022585141BA1739AF0DFE69C19464ACF027585141467A4EA911FE69C1D14ED74A2758514118F927FF11FE69C1E4F76E4527585141
261089739	building	yes		\N	11	324;326;328	South Van Ness Avenue	\N	\N	\N	324;326;328 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000120000008304AD5111FE69C1CBB59CA1215851417F12DA4411FE69C1D2BD8035205851414EDB0EF510FE69C1C069514020585141E8304AEE10FE69C17572438A1F585141BF51D05A10FE69C1F8C9E49F1F585141DA63405710FE69C18579753F1F5851413579780210FE69C129DE2C4B1F58514165EA57490DFE69C1A41237AF1F585141E9D94B240DFE69C11B012814205851414D84102B0DFE69C19B10F095205851414B5151530DFE69C1DDFA35CA20585141152D715A0DFE69C14488AF8E215851418C8C963D0DFE69C1404B7AD0215851413664733B0DFE69C10F38C75F2258514100FFA6770DFE69C15843ABA02258514157744C7C10FE69C1F85AD031225851410E55617810FE69C1C10128C1215851418304AD5111FE69C1CBB59CA121585141
256458252	building	yes		\N	8	333	South Van Ness Avenue	\N	\N	\N	333 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000070000003FEC5C2709FE69C13A9293CF21585141478A581209FE69C159CFDD441F5851414BE4408A05FE69C16FBE07BA1F585141A375862F03FE69C101ADF81E2058514146AF674203FE69C1FD1D69BE225851414BEEBC5106FE69C1A4A42241225851413FEC5C2709FE69C13A9293CF21585141
256458234	building	yes		\N	4	321	South Van Ness Avenue	\N	\N	\N	321 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000008000000073A0E6106FE69C11DC7CD1E245851414BEEBC5106FE69C1A4A422412258514146AF674203FE69C1FD1D69BE225851415C15AF6003FE69C189A9969626585141EE12999D03FE69C192994790265851417B60A9D004FE69C1F919CF5D26585141C08DC1C704FE69C1B372336424585141073A0E6106FE69C11DC7CD1E24585141
256458217	building	yes		\N	12	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000002D0000004BFF10ED09FE69C16D5555E72F58514110E95DE709FE69C1E4F1E3AB2E585141B0EAC1BE09FE69C1DD1D98AE2E5851412F2E8DBB09FE69C1A8C924FC2D5851412DFBCDE309FE69C16FE489F82D585141480D3EE009FE69C1EFD2F6342D5851418F6D15AF09FE69C117B891382D5851419BFDE3A609FE69C19B715B842B585141774D78BF09FE69C15CB874832B585141CBFC31BB09FE69C1DA5F56A02A585141DDB0855F08FE69C10F36FEC72A5851416F68C56D08FE69C15E75B3C02C585141521ED83508FE69C1508602C72C585141FD6E1E3A08FE69C195D7525F2D585141F01F3C0D08FE69C10D76D4632D5851414EE65AFA07FE69C1179EB5D32A5851417E9EF1A706FE69C1050290F92A585141AF9D3FBC06FE69C108CEDEC72D5851411FA0557F06FE69C125DF2DCE2D5851418B6FAC6A06FE69C1EDCBC5002B585141BA27431805FE69C143E986272B5851417773942705FE69C16019B2922D585141292F173F05FE69C11F90E45830585141F091CD3F05FE69C1C4DE598230585141AF5B46B905FE69C1978F077330585141583323B705FE69C186E9062A3058514150134F3606FE69C123E1CD19305851410B6DCD3806FE69C11787CE6230585141EE5F1BA006FE69C1B0AA49553058514135069D9D06FE69C17A4B620B305851418C663DDB06FE69C14DC745033058514147C0BBDD06FE69C175262D4D30585141CA73815107FE69C15FD7DA3D30585141111A034F07FE69C1D23AF0EA2F585141BEE870BD07FE69C13BA584DC2F585141DB734AC007FE69C1A9416F2F305851417CB2E93608FE69C19DF21C2030585141C2586B3408FE69C102C9FFCE2F58514155CFBE7708FE69C1888BFCC52F5851410F293D7A08FE69C113B5191730585141745129EB08FE69C16B1FAE083058514158C64FE808FE69C146570FB32F585141360D757109FE69C162DC08A12F58514154984E7409FE69C1BB5D8EF72F5851414BFF10ED09FE69C16D5555E72F585141
256458247	building	yes		\N	5	315	South Van Ness Avenue	\N	\N	\N	315 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000008000000ABC0717609FE69C15D2DD6C92958514149C2D54D09FE69C18B982CB6255851417B60A9D004FE69C1F919CF5D26585141EE12999D03FE69C1929947902658514164B868AF03FE69C19D87AB0B2958514162C7A2DA04FE69C126B303E428585141753B17EC04FE69C144FC7B7A2A585141ABC0717609FE69C15D2DD6C929585141
256458249	building	yes		\N	9	177	14th Street	\N	\N	\N	177 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000292F173F05FE69C11F90E458305851417773942705FE69C16019B2922D585141000FB1E004FE69C1DDB733972D5851416B659EC504FE69C1FBB43DEA2A5851415AA103BE03FE69C1F4FDB2132B5851412DDA32E503FE69C12486149730585141292F173F05FE69C11F90E45830585141
256458237	building	yes		\N	7	171;173	14th Street	\N	\N	\N	171;173 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A0000002DDA32E503FE69C124861497305851415AA103BE03FE69C1F4FDB2132B58514164B868AF03FE69C19D87AB0B29585141EE12999D03FE69C192994790265851415C15AF6003FE69C189A996962658514129A1A87102FE69C1B75BA0B126585141F0035F7202FE69C1D654C3CB2658514111401FB702FE69C1E525506730585141686842B902FE69C1B9506DB8305851412DDA32E503FE69C12486149730585141
256458254	building	yes		\N	8	159;165	14th Street	\N	\N	\N	159;165 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000700000011401FB702FE69C1E525506730585141F0035F7202FE69C1D654C3CB26585141E819EEBC00FE69C1228E22FF26585141BA898DE7FFFD69C10C6CE01C275851410814B5FEFFFD69C1728A77DF295851416D04243400FE69C19D24B9B53058514111401FB702FE69C1E525506730585141
256458250	building	yes		\N	\N	341	South Van Ness Avenue	\N	\N	\N	341 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000800000016C16DC906FE69C1722583521C5851413B71D9B006FE69C1A3BFE98619585141410EC86305FE69C1AF92E0B4195851419201121E03FE69C14FD616051A585141937A7B2403FE69C1BAEDB5A31A585141D082013703FE69C10045B0D01C585141196C896F05FE69C18D6D47821C58514116C16DC906FE69C1722583521C585141
256458233	building	yes		\N	\N	335	South Van Ness Avenue	\N	\N	\N	335 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000006000000478A581209FE69C159CFDD441F5851411612A1F708FE69C175EB9B081C58514116C16DC906FE69C1722583521C585141196C896F05FE69C18D6D47821C5851414BE4408A05FE69C16FBE07BA1F585141478A581209FE69C159CFDD441F585141
256458224	building	yes		\N	10	349	South Van Ness Avenue	\N	\N	\N	349 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000012000000DD7457F808FE69C127702B2019585141E90426F008FE69C1A792B112185851418BF85CD408FE69C1E3754C161858514143D971D008FE69C1C357D09117585141A0E53AEC08FE69C19374358E17585141B97E41E208FE69C14EEF294F16585141B12132C208FE69C1278BAB53165851414392BA6907FE69C1805AA28116585141450B247007FE69C1C39B442917585141609AAE9E06FE69C13598B64917585141FAEFE99706FE69C186BA929D1658514157B5FB4C05FE69C1A518BCC916585141410EC86305FE69C1AF92E0B4195851413B71D9B006FE69C1A3BFE9861958514139F86FAA06FE69C1BFF29CF718585141B704CBA307FE69C1339273CB18585141B87D34AA07FE69C1775EC05A19585141DD7457F808FE69C127702B2019585141
256458253	building	yes		\N	6	351;353	South Van Ness Avenue	\N	\N	\N	351;353 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000009000000B12132C208FE69C1278BAB53165851410E6FE7A808FE69C1A0E2805613585141724944DF04FE69C1C7364FEA135851419A21E69E02FE69C12BE3192C145851413CD430B802FE69C176D50E221758514157B5FB4C05FE69C1A518BCC916585141FAEFE99706FE69C186BA929D165851414392BA6907FE69C1805AA28116585141B12132C208FE69C1278BAB5316585141
256458215	building	yes		\N	12	359;363	South Van Ness Avenue	\N	\N	\N	359;363 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000C000000039E2CE608FE69C19DAB7D4D13585141F21B8BE108FE69C13396466B12585141426008CA08FE69C19007146D12585141CFAC0BC508FE69C1168E9D68115851417F688EDC08FE69C1C31CD066115851410CB591D708FE69C1BD388C6010585141725A987A08FE69C171A59272105851417E1AFFA104FE69C1F49AF8001158514173039AB004FE69C1A319EAED13585141724944DF04FE69C1C7364FEA135851410E6FE7A808FE69C1A0E2805613585141039E2CE608FE69C19DAB7D4D13585141
256458248	building	yes		\N	6	365	South Van Ness Avenue	\N	\N	\N	365 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000007000000725A987A08FE69C171A592721058514141E2E05F08FE69C18AD96E870D5851415C25F6C305FE69C13FD529E50D585141A8E4736E02FE69C19FE4BB5F0E585141762BD08802FE69C11279C64B115851417E1AFFA104FE69C1F49AF80011585141725A987A08FE69C171A5927210585141
256458246	building	yes		\N	\N	68	Shotwell Street	\N	\N	\N	68 Shotwell Street	\N	\N	\N	0106000020110F00000100000001030000000100000005000000F0FEA00E02FE69C1E45183980E58514107A6D4F701FE69C1EC2747400C5851416990789100FE69C1FED39F610C58514135E5019F00FE69C18E82BFB10E585141F0FEA00E02FE69C1E45183980E585141
256458245	building	yes		\N	9	1470;1472	15th Street	\N	\N	\N	1470;1472 15th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000081F3EFE01FE69C13ADB599504585141C0403FC501FE69C139AB7BE9FD575141F85AA3F600FE69C1F1F96B05FE57514122355F2601FE69C1C0DBD0A30358514121F4725B01FE69C1FC189B9C03585141DEC65A6401FE69C152B32DA904585141081F3EFE01FE69C13ADB599504585141
256458235	building	yes		\N	12	1474;1476;1478;1480	15th Street	\N	\N	\N	1474;1476;1478;1480 15th Street	\N	\N	\N	0106000020110F000001000000010300000001000000090000007D925B7003FE69C1293FC86304585141B33DD26203FE69C145EC96B802585141E66FDF4E03FE69C18974E37600585141D082013703FE69C136C681B2FD5751416E51A63603FE69C1CFA9949FFD575141F9DD88C401FE69C137853FD0FD575141C0403FC501FE69C139AB7BE9FD575141081F3EFE01FE69C13ADB5995045851417D925B7003FE69C1293FC86304585141
256458222	building	yes		\N	12	387;389;391	South Van Ness Avenue	\N	\N	\N	387;389;391 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000001500000032D9A86108FE69C195AC76E6045851417706C15808FE69C1A4B53CFB03585141D3DA0C3908FE69C1C307A500045851418842B82E08FE69C1E71FAAEE025851412E6E6C4E08FE69C1EDCD41E9025851415689144908FE69C1917BA95C02585141719B844508FE69C102C4A20102585141AB79BA0F08FE69C191B9DB1102585141810CD2AE04FE69C1807BB989025851419207DDB904FE69C122BD6BA703585141A5FE369905FE69C16318138603585141DF14EA9E05FE69C17BCB621E04585141CC1D90BF04FE69C11629A24004585141A57B51CB04FE69C14DC0F57305585141119152E504FE69C1C1DE5A70055851413501DF3906FE69C1DED0FB3C05585141C24DE23406FE69C12010E5B4045851411AB340D606FE69C12B9E8F9C045851418C663DDB06FE69C17235F221055851411D2DB71408FE69C1135147F10458514132D9A86108FE69C195AC76E604585141
256458244	building	yes		\N	12	395	South Van Ness Avenue	\N	\N	\N	395 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000D000000AB79BA0F08FE69C191B9DB110258514151D82D0708FE69C137E8B71C01585141B09E4CF407FE69C115116C1F015851413EEB4FEF07FE69C18254069100585141A687E70208FE69C1AB2B528E0058514141DD22FC07FE69C11474DCD2FF575141F352FBE407FE69C15F0D5ED7FF57514193CCBB8A06FE69C1F87A3B0600585141FE12620C04FE69C1E94CA75D00585141E66FDF4E03FE69C18974E37600585141B33DD26203FE69C145EC96B802585141810CD2AE04FE69C1807BB98902585141AB79BA0F08FE69C191B9DB1102585141
256458226	building	yes		\N	8	383;385	South Van Ness Avenue	\N	\N	\N	383;385 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000001100000005CC2D5A08FE69C16DC4542F0858514114D5655808FE69C16EE7F80408585141278AC63408FE69C18DF2470B085851411D2DB71408FE69C1135147F1045851418C663DDB06FE69C17235F221055851413501DF3906FE69C1DED0FB3C05585141119152E504FE69C1C1DE5A7005585141C9EAD0E704FE69C1F6E3F2B3055851419E1A917F05FE69C166719D9B05585141E9B2E58905FE69C144745F9D06585141CDE1615805FE69C1FDEF7BA5065851419736EB6505FE69C1E2A7A6F507585141F9B2AEF805FE69C1ED3351DD07585141153E88FB05FE69C1BD71EC2908585141FA36A1FE07FE69C1D72802D707585141A687E70208FE69C19D4BC03D0858514105CC2D5A08FE69C16DC4542F08585141
256458243	building	yes		\N	12	377;379;381	South Van Ness Avenue	\N	\N	\N	377;379;381 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000010000000B8001A7808FE69C10291E24D0A585141C490E86F08FE69C1B20114710958514138FE3A4608FE69C1080D637709585141C54A3E4108FE69C1BEAE19F1085851417C71FD6B08FE69C17BA3CAEA085851417BF8936508FE69C1EBF857380858514105CC2D5A08FE69C16DC4542F08585141A687E70208FE69C19D4BC03D0858514133C4A39A05FE69C1998DE3A0085851411B2B9DA405FE69C1C62B11B10958514184818A8905FE69C1B60DACB4095851410930929905FE69C17E0A956B0B585141D6FD84AD05FE69C1ECE0E0680B58514105CC2D5A08FE69C17FDFD6040B5851419F21695308FE69C1FBE34A530A585141B8001A7808FE69C10291E24D0A585141
256458221	building	yes		\N	11	371;373;375	South Van Ness Avenue	\N	\N	\N	371;373;375 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000D0000005B3AFB8A08FE69C1291ABDFB0C585141F58F368408FE69C1029914420C585141ED32276408FE69C1B63396460C585141DDB0855F08FE69C1B14869C80B58514167CAC98208FE69C109AEE7C30B5851410120057C08FE69C1F4B522020B58514105CC2D5A08FE69C17FDFD6040B585141D6FD84AD05FE69C1ECE0E0680B5851415C25F6C305FE69C13FD529E50D58514141E2E05F08FE69C18AD96E870D585141B8001A7808FE69C143F7D3830D585141454D1D7308FE69C166FC57FF0C5851415B3AFB8A08FE69C1291ABDFB0C585141
261089751	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000007000000B148985C10FE69C1B5F66DD502585141843B1D5510FE69C18C5D240602585141A007E32210FE69C1418A937BFC5751414BDFBF2010FE69C1580E1840FC575141DADB9C250FFE69C186D52464FC575141414575610FFE69C1DDC37AF902585141B148985C10FE69C1B5F66DD502585141
261089750	building	yes		\N	\N	370	South Van Ness Avenue	\N	\N	\N	370 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000070000002F9121BD10FE69C197A720D40B585141200F80B810FE69C1DD6A8B500B585141CD191C8E10FE69C19C53728A06585141486B147E10FE69C190B4B5BF04585141A81C2EA40DFE69C1955EA624055851418F423BE30DFE69C1996311390C5851412F9121BD10FE69C197A720D40B585141
261089756	building	yes		\N	\N	366;368	South Van Ness Avenue	\N	\N	\N	366;368 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000900000027F325D210FE69C1D98F92330E5851412F9121BD10FE69C197A720D40B5851418F423BE30DFE69C1996311390C585141179C5E990CFE69C1422708670C58514155A4E4AB0CFE69C184F7927C0E58514199DB786A0DFE69C1630E70620E5851415235F76C0DFE69C1FB2E57AC0E585141FCE0EC6610FE69C1CFD1E4420E58514127F325D210FE69C1D98F92330E585141
261089735	building	yes		\N	\N	360;362	South Van Ness Avenue	\N	\N	\N	360;362 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000100000007E168B7010FE69C16CC0C6550F585141FCE0EC6610FE69C1CFD1E4420E5851415235F76C0DFE69C1FB2E57AC0E585141203F18E80CFE69C1835344BF0E5851411136E0E90CFE69C14D268AF30E585141A32E0CC30CFE69C1588F8A3C0F585141A32E0CC30CFE69C18ABBBAC30F585141303A23F30CFE69C18CB9B4FA0F5851416A50D6F80CFE69C144DF56A210585141999A8C9F0DFE69C1A71EE88A10585141B72566A20DFE69C14B5C6DE1105851419A5F6B700FFE69C1A12670A110585141E105ED6D0FFE69C12091BB5510585141EC598DFE0FFE69C195FA004110585141BF4C12F70FFE69C16EBBFF650F5851417E168B7010FE69C16CC0C6550F585141
261089733	building	yes		\N	12	350;352;354	South Van Ness Avenue	\N	\N	\N	350;352;354 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000F000000AB23067810FE69C1CDA6FF9015585141EC5E4B6210FE69C16FB20B2D13585141C4F83AD50FFE69C1D091DF401358514196E4E7F90CFE69C13AFC51AA1358514188DBAFFB0CFE69C182BBF9D11358514129567DD90CFE69C1D26A8B0314585141AA12B2DC0CFE69C1CE45047F14585141613971070DFE69C1B65486CC145851411993EF090DFE69C1AF5980031558514112AF49F00CFE69C17C0A123515585141A274B6F10CFE69C1187A849E155851419DC88D130DFE69C1AF0EB1D315585141BB5367160DFE69C122F8450E1658514186B4865B10FE69C18F42819515585141AB23067810FE69C1CDA6FF9015585141
261089743	building	yes		\N	9	356;358	South Van Ness Avenue	\N	\N	\N	356;358 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000014000000C4F83AD50FFE69C1D091DF401358514150CCD4C90FFE69C11E833C071258514183F923520FFE69C1E7375C181258514173FE18470FFE69C101EB9FDF10585141F27D12AB0EFE69C12CF327F6105851410F09ECAD0EFE69C136D1F54011585141B33393950DFE69C1168E9D6811585141F9D914930DFE69C159926A21115851412272D7BF0CFE69C1E85F283F115851414C06E9C00CFE69C18A2DE65C1158514124A596970CFE69C110C96198115851413527389C0CFE69C1115E492B1258514108D9D0C90CFE69C13FB7725712585141FBCF98CB0CFE69C172479F8C125851410C0C90A10CFE69C1719D01C912585141F0F91FA50CFE69C1BB0C3559135851419817A7D10CFE69C193E57A8D1358514135E64BD10CFE69C15A2606AD1358514196E4E7F90CFE69C13AFC51AA13585141C4F83AD50FFE69C1D091DF4013585141
261089737	building	yes		\N	9	338;340;342	South Van Ness Avenue	\N	\N	\N	338;340;342 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000110000004675904511FE69C1D49A304D1A5851419AABE03A11FE69C127702B2019585141243D812C10FE69C1306E9D401958514180494A4810FE69C166646AF918585141E3013C4210FE69C10BF1134F185851419F8E791C10FE69C12FCC7B0B185851417D98630610FE69C19CF62F0E18585141DAD013260DFE69C19726897818585141503E66FC0CFE69C176BA99EE185851417BD277FD0CFE69C1CAECF25819585141C2370D300DFE69C1E6B0D3901958514150FD79310DFE69C13ABD94B719585141613971070DFE69C1F571D1191A585141DF7C3C040DFE69C13C52C27E1A5851410BD0613A0DFE69C1F517A3B61A585141FDC6293C0DFE69C1E508FFE01A5851414675904511FE69C1D49A304D1A585141
261089730	building	yes		\N	\N	344;346	South Van Ness Avenue	\N	\N	\N	344;346 South Van Ness Avenue	\N	\N	\N	0106000020110F0000010000000103000000010000000C00000098AF916610FE69C1873521C61658514186B4865B10FE69C18F42819515585141BB5367160DFE69C122F8450E165851413FBCC4F70CFE69C101272D5816585141936B7EF30CFE69C1F3DC2AE116585141D957AA1F0DFE69C115627A3017585141DF7C3C040DFE69C1D0834B8417585141613971070DFE69C1B771F74618585141DAD013260DFE69C197268978185851417D98630610FE69C19CF62F0E185851416B9D58FB0FFE69C1CB7A73D51658514198AF916610FE69C1873521C616585141
261089754	building	yes		\N	6	334	South Van Ness Avenue	\N	\N	\N	334 South Van Ness Avenue	\N	\N	\N	0106000020110F00000100000001030000000100000009000000A208F05A11FE69C19E4305A01C5851414675904511FE69C1D49A304D1A585141FDC6293C0DFE69C1E508FFE01A585141A4AC332D0DFE69C18133B3E31A5851411A52033F0DFE69C16B53FFD61C58514107A71E2A0EFE69C19EE0BFB41C585141EC94AE2D0EFE69C1FB7148141D585141CF0FA0C60FFE69C12D7EB3D91C585141A208F05A11FE69C19E4305A01C585141
261089741	building	yes		\N	\N	330;332	South Van Ness Avenue	\N	\N	\N	330;332 South Van Ness Avenue	\N	\N	\N	0106000020110F000001000000010300000001000000130000007732E55610FE69C1DFB14CAF1D585141A04D8D5110FE69C1E88EE6201D585141923F97EF0FFE69C1C5646B2E1D585141CF0FA0C60FFE69C12D7EB3D91C585141EC94AE2D0EFE69C1FB7148141D585141981C65350DFE69C14073BA341D5851415B14DF220DFE69C19C30F7961D58514143AE97040DFE69C1713130A71D58514143AE97040DFE69C1DA63AC2B1E585141F85BED280DFE69C1AB0167401E585141A4AC332D0DFE69C178FCDFBB1E5851419DC88D130DFE69C1DF54BAE11E5851412B8EFA140DFE69C181EEB4611F5851410A57F8330DFE69C109A9D4721F5851415F7F1B360DFE69C1973DEBB11F58514165EA57490DFE69C1A41237AF1F5851413579780210FE69C129DE2C4B1F585141A3C138F40FFE69C1DB40B8BD1D5851417732E55610FE69C1DFB14CAF1D585141
261089748	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000683EB21F13FE69C14FB424BB1A5851415643A71413FE69C15131B78819585141F0D9CED812FE69C1E6B0D390195851419C66434412FE69C1280575A619585141AE614E4F12FE69C10A89E2D81A585141683EB21F13FE69C14FB424BB1A585141
261089740	building	yes		\N	7	1347;1349	Natoma Street	\N	\N	\N	1347;1349 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000012000000F31717B014FE69C15963A30919585141C60A9CA814FE69C19539F43D1858514137861B7214FE69C1A792B11218585141FEE8D17214FE69C1149706E21758514180EBB0A414FE69C1CCDFE6D0175851418A7B7F9C14FE69C1FD5B47E91658514179B119F911FE69C13598B6491758514114C1AAC311FE69C15417D351175851418C667AD511FE69C18951384419585141F115FD3F12FE69C1540BE634195851419C66434412FE69C1280575A619585141F0D9CED812FE69C1E6B0D390195851410BEC3ED512FE69C153B67D2F19585141F649C94F13FE69C17CFE5D1E19585141D937595313FE69C10D40CD7E19585141E01BFF6C13FE69C1B05C327B19585141AD2BEB8314FE69C1EBDEA35219585141F31717B014FE69C15963A30919585141
261089747	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000500000035535C9A14FE69C1E76A9BBF1B585141AD2BEB8314FE69C1EBDEA35219585141E01BFF6C13FE69C1B05C327B195851416643708313FE69C1413243E71B58514135535C9A14FE69C1E76A9BBF1B585141
261089738	building	yes		\N	13	1337	Natoma Street	\N	\N	\N	1337 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000012000000E68C061C15FE69C1FE910B5F1E58514139C3561115FE69C11222A8901D585141A21944F614FE69C1462E4C661D585141DBB68DF514FE69C16B53FFD61C5851417EF06E0815FE69C1CBD1379E1C58514135D1830415FE69C108EBF0D71B5851413DF615E914FE69C14F07E4B31B58514135535C9A14FE69C1E76A9BBF1B5851416643708313FE69C1413243E71B585141593A388513FE69C1F6F9231F1C58514124CBEFF912FE69C1CCDDF7321C58514132D427F812FE69C1C787E4FC1B585141D5C2A07812FE69C1C2F9EA0E1C5851412CEBC37A12FE69C14BA5664A1C585141973CF3FB11FE69C169176D5C1C585141105B2C1412FE69C18CC9F9031F585141B806220E15FE69C12A5DEC961E585141E68C061C15FE69C1FE910B5F1E585141
261007333	building	yes		\N	11	1334;1336;1338	Natoma Street	\N	\N	\N	1334;1336;1338 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A000000E42E6D7819FE69C18215FAA91B5851419A96186E19FE69C112E02D8D1A58514187DCF92D19FE69C1BA1831961A58514113B0932219FE69C1775EC05A195851411A11546E18FE69C1F695FC7319585141A8D6C06F18FE69C1B7CC719D19585141D524284218FE69C19FDAC0A319585141E792D1B716FE69C1FF5788DC1958514118921FCC16FE69C10FCF360C1C585141E42E6D7819FE69C18215FAA91B585141
261007301	building	yes		\N	12	1340	Natoma Street	\N	\N	\N	1340 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C000000F7E3CD5419FE69C1281BC31A195851419139094E19FE69C16DFD9B6518585141B1F7A12819FE69C15652046B185851412FC2031F19FE69C1404FD65A1758514126E20E3118FE69C16FBD157D175851410857352E18FE69C1580D122B175851411B7F347516FE69C1BE94286A17585141A3A6A58B16FE69C1F165D7E219585141E792D1B716FE69C1FF5788DC19585141D524284218FE69C19FDAC0A319585141F136983E18FE69C1DDDF6A4219585141F7E3CD5419FE69C1281BC31A19585141
261007297	building	yes		\N	12	1350	Natoma Street	\N	\N	\N	1350 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C000000DC13575B1AFE69C14288C2DB1658514197272B2F1AFE69C1C7116F0512585141526DB1A218FE69C14284363E12585141FFF35A7216FE69C1D1B86C8E12585141D80B724F16FE69C13D54EE9212585141222B5D5316FE69C15258E200135851418908E13116FE69C1CBF36305135851413EB6365616FE69C13A3D1BFD16585141D55F497116FE69C1175A80F9165851411B7F347516FE69C1BE94286A175851410857352E18FE69C1580D122B17585141DC13575B1AFE69C14288C2DB16585141
261007323	building	yes		\N	\N	1354	Natoma Street	\N	\N	\N	1354 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000526DB1A218FE69C14284363E125851414272A69718FE69C1CB18150911585141C5A2863D18FE69C18CEA991611585141275B783718FE69C1430A116E1058514150B1416116FE69C18769C2B010585141FFF35A7216FE69C1D1B86C8E12585141526DB1A218FE69C14284363E12585141
261089731	building	yes		\N	\N	1357;1359	Natoma Street	\N	\N	\N	1357;1359 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C00000029C38DA214FE69C1AA7D81A91158514136CCC5A014FE69C14B4F1812115851412BF64C7A14FE69C101EB9FDF10585141B6C9E66E14FE69C1C8E2AD9F0F5851412CE6051712FE69C1CC654CF50F585141DAAFB52112FE69C1A903382311585141F34D7A7B12FE69C1E431B31511585141687AE08612FE69C185D4D75312585141211A09B812FE69C1C5C7884D12585141DABFFC8414FE69C1CF65D70A12585141AD2BEB8314FE69C1FCB47EE91158514129C38DA214FE69C1AA7D81A911585141
261089736	building	yes		\N	\N	1355	Natoma Street	\N	\N	\N	1355 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000001100000010A3F0B214FE69C1883A492114585141C98305AF14FE69C12FB8FF9A13585141E9419E8914FE69C1C143386213585141F74AD68714FE69C117D3371913585141FFA7E5A714FE69C175EADBEE1258514129C38DA214FE69C13FB77257125851416885698614FE69C1C340E42E12585141DABFFC8414FE69C1CF65D70A12585141211A09B812FE69C1C5C7884D12585141A34FA7C112FE69C16A8E185113585141387B927212FE69C1D736E95B1358514102D01B8012FE69C1961ABCD314585141D8BEEF4C13FE69C11903E5B614585141CBB6C48614FE69C18CEED48914585141C318C99B14FE69C1A30B3A8614585141D121019A14FE69C1943E43581458514110A3F0B214FE69C1883A492114585141
261089755	building	yes		\N	\N	1351;1353	Natoma Street	\N	\N	\N	1351;1353 Natoma Street	\N	\N	\N	0106000020110F000001000000010300000001000000090000008A7B7F9C14FE69C1FD5B47E916585141CBB6C48614FE69C18CEED48914585141D8BEEF4C13FE69C11903E5B6145851412DE7124F13FE69C19786FBF5145851417309A24611FE69C12B6CC94015585141224CBB5711FE69C1BE80A61C17585141C0579BF611FE69C14BBC37051758514179B119F911FE69C13598B649175851418A7B7F9C14FE69C1FD5B47E916585141
261089732	building	yes		\N	10	1361;1363	Natoma Street	\N	\N	\N	1361;1363 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000D000000DABFFC8414FE69C1D5E8C1280E585141821E707C14FE69C1237AB77B0D585141C067E25914FE69C1463E2C5C0D58514195D3D05814FE69C16391D33A0D585141BC299A8212FE69C192C1D07A0D58514190584DE211FE69C11AAAF3940D5851413D22FDEC11FE69C1B82990BC0E5851412019FC7F11FE69C17C24C9CC0E5851419345628B11FE69C192432009105851412CE6051712FE69C1CC654CF50F585141B6C9E66E14FE69C1C8E2AD9F0F585141429D806314FE69C1BFF00A660E585141DABFFC8414FE69C1D5E8C1280E585141
261089753	building	yes		\N	\N	1367;1369	Natoma Street	\N	\N	\N	1367;1369 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000009000000B842507514FE69C192F651360D5851415DAFF05F14FE69C15AE8DCCD0A585141A2DC085714FE69C15D59AACF0A585141F7B8B68E12FE69C123CDC00E0B5851417C67BE9E12FE69C1EC43B0D70C585141E644427D12FE69C1B4DE31DC0C585141BC299A8212FE69C192C1D07A0D58514195D3D05814FE69C16391D33A0D585141B842507514FE69C192F651360D585141
261089749	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000A2DC085714FE69C15D59AACF0A585141ECB5492C14FE69C1FF09780A06585141CD191C8E10FE69C19C53728A06585141200F80B810FE69C1DD6A8B500B585141F7B8B68E12FE69C123CDC00E0B585141A2DC085714FE69C15D59AACF0A585141
261089728	building	yes		\N	\N	1514;1516;1518	15th Street	\N	\N	\N	1514;1516;1518 15th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C000000BD600A8611FE69C1CFCEE1DA015851411AAEBF6C11FE69C13497B214FF57514176FB745311FE69C18E015150FC5751413388B22D11FE69C191B9F1D3FB5751410051E7DD10FE69C1695273D8FB5751415F1706CB10FE69C162496A4FFC575141E6F8CCB210FE69C1BEB93751FC575141DF14279910FE69C1FEBEC8F0FB575141ACDD5B4910FE69C12A77AFF1FB575141A007E32210FE69C1418A937BFC575141843B1D5510FE69C18C5D240602585141BD600A8611FE69C1CFCEE1DA01585141
261089729	building	yes		\N	11	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000C000000B29F962614FE69C1D3B9B309035851418F63D6E113FE69C1D0580478FB575141D5C2A07812FE69C1135A63ABFB575141E644427D12FE69C13831F525FC57514133CF699412FE69C1ED2EC5B8FE575141DE246EFC12FE69C130AB59AAFE57514145489C0913FE69C11EEA901E00585141C686A9A212FE69C1606EFC2C005851416839F4BB12FE69C1DDC37AF9025851411B3770D613FE69C1135DECD002585141715F93D813FE69C1D15D841403585141B29F962614FE69C1D3B9B30903585141
261089746	building	yes		\N	9	1383;1385	Natoma Street	\N	\N	\N	1383;1385 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000018000000D50E164314FE69C1D344D96B05585141E3174E4114FE69C1D3C114F304585141B318002D14FE69C136315ADE0458514107C8B92814FE69C1B549176A04585141354E9E3614FE69C1921FDB50045851417CF41F3414FE69C1BB624CDF03585141CBB1062314FE69C114B42CCE035851411358882014FE69C181BCE390035851411603A4C612FE69C1E40F5CC303585141328E7DC912FE69C15F645C0C0458514115857C5C12FE69C1C45A951C04585141F8F9A25912FE69C12D0695D303585141CDDDED2611FE69C1C307A5000458514150138C3011FE69C1768F99000558514152CDE10111FE69C18395B95A05585141E10BB80911FE69C16E2655F0055851416F17CF3911FE69C182C66E3806585141FBAA899B12FE69C1675CE00F065851414F5A439712FE69C1D68F029805585141840F365113FE69C12DF4F87C0558514130607C5513FE69C16BC0D6F4055851416EEBE73514FE69C1BE197ED305585141ED2EB33214FE69C1BBD5938005585141D50E164314FE69C1D344D96B05585141
261007320	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000600000077D6652317FE69C1C3C952F103585141294C3E0C17FE69C15C61E45101585141802DAAA715FE69C198F9758301585141CDB7D1BE15FE69C14465E42204585141336296C515FE69C1E8ACFD210458514177D6652317FE69C1C3C952F103585141
261007308	building	yes		\N	7	1380	Natoma Street	\N	\N	\N	1380 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000E00000070F3CC4118FE69C120DDD25905585141FCC6663618FE69C181B6C411045851416813D85317FE69C1FDEA4F310458514113EBB45117FE69C14CBF03EB0358514177D6652317FE69C1C3C952F103585141336296C515FE69C1E8ACFD2104585141888AB9C715FE69C1BC71435604585141AF2CF8BB15FE69C175E210580458514127D2C7CD15FE69C1244F625D06585141B90271E215FE69C1836DC7590658514149C8DDE315FE69C1BA4823840658514134A59C0018FE69C1E97E5539065851416CC97CF917FE69C15DC9BC630558514170F3CC4118FE69C120DDD25905585141
261007305	building	yes		\N	8	1370;1372;1374	Natoma Street	\N	\N	\N	1370;1372;1374 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000D000000EF7C426D18FE69C16B8C6EFF0A585141DD81376218FE69C16577B2C6095851413E02AC2018FE69C13DACB5CF095851410E7CC71218FE69C185BC8D3F08585141BA8FD27717FE69C158072F5508585141F4A5857D17FE69C102BA68F7085851418557FAEF15FE69C1E8390D16095851413EB178F215FE69C14E67926C095851415166D9CE15FE69C193EBBEA1095851418A0323CE15FE69C11527DC3B0A585141DDF886F815FE69C176D1345D0A585141E071F0FE15FE69C1FDBDF3550B585141EF7C426D18FE69C16B8C6EFF0A585141
261007306	building	yes		\N	8	1376;1378	Natoma Street	\N	\N	\N	1376;1378 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000E0000001FBD7C4C18FE69C17993EE5707585141D524284218FE69C1DF4A52300658514134A59C0018FE69C1E97E55390658514149C8DDE315FE69C1BA48238406585141DEB2DCC915FE69C15F2ABE8706585141D3220ED215FE69C11B0744700758514193A11EB915FE69C1274157A607585141125E53BC15FE69C16A2D5B41085851412AC49ADA15FE69C17EFF676508585141B88907DC15FE69C1FC6BF68D08585141BA8FD27717FE69C158072F55085851410E7CC71218FE69C185BC8D3F085851417F3DF10A18FE69C1C8C7F160075851411FBD7C4C18FE69C17993EE5707585141
261007326	building	yes		\N	9	1364;1366;1368	Natoma Street	\N	\N	\N	1364;1366;1368 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000008000000EA99A98B19FE69C1EDDE74500D5851412BD5EE7519FE69C1FAB761DB0A58514110B902B218FE69C14C576BF60A585141EF7C426D18FE69C16B8C6EFF0A585141E071F0FE15FE69C1FDBDF3550B5851419D36AB1416FE69C182EC06CB0D5851412C111DDD18FE69C13656CA680D585141EA99A98B19FE69C1EDDE74500D585141
261007329	building	yes		\N	9	1360;1362	Natoma Street	\N	\N	\N	1360;1362 Natoma Street	\N	\N	\N	0106000020110F000001000000010300000001000000090000006919A3EF18FE69C1D45D09810F5851412C111DDD18FE69C13656CA680D5851419D36AB1416FE69C182EC06CB0D585141F4D7371D16FE69C181EEC5C30E585141806AE54616FE69C1545C8DFC0E5851412F34955116FE69C17D7095321058514162F303D317FE69C1CC2A82FC0F585141E036CFCF17FE69C1F518B1A80F5851416919A3EF18FE69C1D45D09810F585141
261007309	building	yes		\N	12	1359	Minna Street	\N	\N	\N	1359 Minna Street	\N	\N	\N	0106000020110F0000010000000103000000010000000F000000F63F8A821DFE69C14A187AC60E5851414876DA771DFE69C1B13EED820D5851411B695F701DFE69C19D8B08B00C5851413F503B5B1CFE69C1D2D2E2D50C58514196785E5D1CFE69C1EDBAC6160D5851416FD161051CFE69C1361A7E220D585141B677E3021CFE69C17979B3E00C58514199E74B9C1BFE69C15D021FEF0C58514171C7E53D1BFE69C1291ABDFB0C585141BCD8A34E1BFE69C17E6154EC0E58514139212DAF1BFE69C17A90CFDE0E585141200FBDB21BFE69C10B7E74460F585141373067DA1CFE69C1B20AE61D0F585141E20744D81CFE69C1E1D7E8DD0E585141F63F8A821DFE69C14A187AC60E585141
261007313	building	yes		\N	10	1363	Minna Street	\N	\N	\N	1363 Minna Street	\N	\N	\N	0106000020110F000001000000010300000001000000140000008FDB6FAA1DFE69C15FC446F70B585141373AE3A11DFE69C16B8C6EFF0A5851411DE2C8761DFE69C17FDFD6040B5851411B695F701DFE69C1063E7A480A58514179A7DA2B1CFE69C1718EA3740A5851413301592E1CFE69C140D13EC10A5851418673D78A1BFE69C1F1D5C6D70A58514104B7A2871BFE69C1F299F27A0A5851417D52F6D11AFE69C1FFC72E940A585141D8E555E71AFE69C16B7974070D58514171C7E53D1BFE69C1291ABDFB0C58514199E74B9C1BFE69C15D021FEF0C58514143BF289A1BFE69C110D321AF0C585141B7AF603E1CFE69C152CD99980C5851410DD883401CFE69C109B57DD90C5851413F503B5B1CFE69C1D2D2E2D50C5851411B695F701DFE69C19D8B08B00C585141AF9908851DFE69C1F66154AD0C5851417583557F1DFE69C11DD095FD0B5851418FDB6FAA1DFE69C15FC446F70B585141
261007314	building	yes		\N	11	1371;1373;1375;1377;1379	Minna Street	\N	\N	\N	1371;1373;1375;1377;1379 Minna Street	\N	\N	\N	0106000020110F00000100000001030000000100000014000000054053F11DFE69C11DD473360A5851414E1994C61DFE69C1D28A6A5405585141524C539E1DFE69C15B6C0558055851415D1285611BFE69C1DD863BA8055851410963CB651BFE69C10C40032A06585141AC97EE141BFE69C1E3E4D33406585141A007201D1BFE69C13A28602F075851416104586E1BFE69C1B3CAA8230758514146F2E7711BFE69C17E51E58507585141F6F314B81BFE69C1BA64FB7B07585141300AC8BD1BFE69C127AEB622085851411BD6323F1AFE69C13F78FC5608585141937B02511AFE69C1F44D51650A5851415ADEB8511AFE69C170703E780A5851412F915EB71BFE69C1878593470A5851416E124ED01BFE69C18DA3F8430A585141C43A71D21BFE69C1F4EC5A800A58514179A7DA2B1CFE69C1718EA3740A5851411B695F701DFE69C1063E7A480A585141054053F11DFE69C11DD473360A585141
261007330	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000A0000008D0B08DA19FE69C1406FA299095851413278A8C419FE69C1A8E046300758514179D87F9319FE69C110A47C3707585141CC0ED08819FE69C199B70F0506585141BDC39E8718FE69C13FCF35280658514110B902B218FE69C14C576BF60A5851412BD5EE7519FE69C1FAB761DB0A585141752C57B519FE69C1E5825ED20A5851412B9402AB19FE69C11933D8A0095851418D0B08DA19FE69C1406FA29909585141
261007319	building	yes		\N	\N	1544;1546	15th Street	\N	\N	\N	1544;1546 15th Street	\N	\N	\N	0106000020110F000001000000010300000001000000050000006B51202B19FE69C1FD0DC47F03585141E46A9BDF18FE69C1F563AECDFA575141FFF9250E18FE69C1A56885EAFA575141E911065A18FE69C1FC189B9C035851416B51202B19FE69C1FD0DC47F03585141
261007324	building	yes		\N	8	1548	15th Street	\N	\N	\N	1548 15th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000A5A9CC331AFE69C1E269F37403585141E725FEE819FE69C18E4D98D7FA575141596091E719FE69C1389EA1A9FA575141E46A9BDF18FE69C1F563AECDFA5751416B51202B19FE69C1FD0DC47F0358514132B4D62B19FE69C19A37009903585141A5A9CC331AFE69C1E269F37403585141
261007295	building	yes		\N	12	1381;1383;1385	Minna Street	\N	\N	\N	1381;1383;1385 Minna Street	\N	\N	\N	0106000020110F0000010000000103000000010000000B00000011110EB41DFE69C1D7B4B4E4035851411F1A46B21DFE69C18B35E03E03585141D8B4B07F1DFE69C12BF77D020358514126707DFE1AFE69C1AECFE959035851419C9CE3091BFE69C17B19ACA4045851411862879C1AFE69C1629F17B3045851413866CAA51AFE69C1DCB177C1055851415D1285611BFE69C1DD863BA805585141524C539E1DFE69C15B6C05580558514197796B951DFE69C18DF416210458514111110EB41DFE69C1D7B4B4E403585141
261007299	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000B00000019B4C7021EFE69C19A42BD7911585141BE2068ED1DFE69C1E97BB31F0F585141E529AF1419FE69C13DD458D00F5851419E832D1719FE69C195085610105851414E02758F18FE69C1C72D4323105851414272A69718FE69C1CB18150911585141526DB1A218FE69C14284363E1258514197272B2F1AFE69C1C7116F05125851413F9127261CFE69C1F4143CBE115851419B6B3EA21DFE69C128CD28881158514119B4C7021EFE69C19A42BD7911585141
261007316	building	yes		\N	10	1347;1349;1351;1353	Minna Street	\N	\N	\N	1347;1349;1351;1353 Minna Street	\N	\N	\N	0106000020110F0000010000000103000000010000001800000085831EEE1DFE69C1D593B65315585141F3CBDEDF1DFE69C147A7BB8A14585141A24FE4BB1DFE69C1943E4358145851419E5D11AF1DFE69C1C431F5ED12585141FDE243D11DFE69C16D1296BA12585141ED60A2CC1DFE69C1632285FB11585141F09361A41DFE69C146B0BDC2115851419B6B3EA21DFE69C128CD2888115851413F9127261CFE69C1F4143CBE115851415C1C01291CFE69C12D01590F125851415C991B5B1BFE69C169CF162D12585141420015651BFE69C1814AC64113585141DD917EC51AFE69C107544E5813585141F005F3D61AFE69C1A8DD96421558514180089B771BFE69C10CD30E2C15585141D7A927801BFE69C16C674C20165851417109DF401CFE69C1BE075C0416585141B7AF603E1CFE69C177F6D9B615585141DE9749611CFE69C1EFA171B1155851415F547E641CFE69C1CBEAF60716585141E0D484001DFE69C1BFDF6EF1155851416CA46DC91DFE69C133807ED5155851417AADA5C71DFE69C157C19D9D1558514185831EEE1DFE69C1D593B65315585141
261007311	building	yes		\N	9	1341;1343;1345	Minna Street	\N	\N	\N	1341;1343;1345 Minna Street	\N	\N	\N	0106000020110F00000100000001030000000100000010000000E8B937521EFE69C13FB166A7185851414307ED381EFE69C160C9032C16585141E581BA161EFE69C19865E0C8155851416CA46DC91DFE69C133807ED515585141E0D484001DFE69C1BFDF6EF1155851416091B9031DFE69C1C47D5C4D1658514173FAA4151BFE69C1FEC9A893165851411042B31B1BFE69C1EE35FF3D17585141D6EEC4761AFE69C17FFA6D5517585141582463801AFE69C1167E7F5D18585141223DBE261BFE69C1E6B81046185851415E53712C1BFE69C1342D2EE018585141810E66131DFE69C1BD95C89A1858514172052E151DFE69C175CA76D41858514108FAA8C21DFE69C12D4C21BC18585141E8B937521EFE69C13FB166A718585141
261007336	building	yes		\N	16	1335	Minna Street	\N	\N	\N	1335 Minna Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A000000A48C1F5B1EFE69C14DDD2E1F1B5851414972294C1EFE69C16B23688219585141177C4AC71DFE69C136C305461958514108FAA8C21DFE69C12D4C21BC1858514172052E151DFE69C175CA76D41858514125ACAB651AFE69C1017DB336195851417D4D386E1AFE69C1F17F20201A585141F3F7C5E31AFE69C18D80E70F1A585141237EAAF11AFE69C145878E9B1B585141A48C1F5B1EFE69C14DDD2E1F1B585141
261007325	building	yes		\N	7	1330	Natoma Street	\N	\N	\N	1330 Natoma Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000700314A51AFE69C1697089111E5851414D0DFE8E1AFE69C18215FAA91B585141F61473BC16FE69C18208AC351C5851411A0B89D216FE69C1DD6B3B9D1E585141326D1FC517FE69C1963E157A1E58514164314CAA19FE69C1465696351E585141700314A51AFE69C1697089111E585141
261007328	building	yes		\N	9	1333	Minna Street	\N	\N	\N	1333 Minna Street	\N	\N	\N	0106000020110F000001000000010300000001000000080000006251DA701EFE69C1CD2FBE861D585141A48C1F5B1EFE69C14DDD2E1F1B585141237EAAF11AFE69C145878E9B1B5851414D0DFE8E1AFE69C18215FAA91B585141700314A51AFE69C1697089111E5851410B1D21371BFE69C1B3D2CEFC1D58514134CBF5621EFE69C1ACA18B881D5851416251DA701EFE69C1CD2FBE861D585141
261007304	building	yes		\N	11	1319;1321;1323;1325;1327;1329	Minna Street	\N	\N	\N	1319;1321;1323;1325;1327;1329 Minna Street	\N	\N	\N	0106000020110F0000010000000103000000010000000D0000001586C68E1EFE69C15FA75B512258514134CBF5621EFE69C1ACA18B881D5851410B1D21371BFE69C1B3D2CEFC1D5851411C182C421BFE69C1CC3F72361F5851415C5DEDF31BFE69C1A404361D1F585141414B7DF71BFE69C1C99BBE7C1F585141B732460C1DFE69C1DCD016551F58514139EF7A0F1DFE69C192F6D1B21F5851414533D43C1BFE69C1786F83F51F585141CC5A45531BFE69C1031F9B7322585141A3047C291DFE69C1E5E8023022585141C18F552C1DFE69C1D421D483225851411586C68E1EFE69C15FA75B5122585141
261007322	building	yes		\N	7	1315	Minna Street	\N	\N	\N	1315 Minna Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000505B8DC91EFE69C1AB949FBB24585141CA331CB31EFE69C12151F34B225851411586C68E1EFE69C15FA75B5122585141C18F552C1DFE69C1D421D48322585141433C43CC1AFE69C19D8659DA22585141653259E21AFE69C1E4D2054A25585141505B8DC91EFE69C1AB949FBB24585141
261007334	building	yes		\N	\N	257;259;261	14th Street	\N	\N	\N	257;259;261 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000B00000099B1E8D01DFE69C1F2EEB9D22C5851414B27C1B91DFE69C1B3F4E63F2A58514138B34CA81DFE69C1C40BFC3F28585141C016EC251DFE69C15083025228585141B10DB4271DFE69C1C077488628585141F8EF638C1CFE69C126D4E99B28585141CED4BB911CFE69C1D3870736295851416300A7421CFE69C13536D840295851410248B5481CFE69C1CDA0FFF529585141FC2223641CFE69C1BF7632052D58514199B1E8D01DFE69C1F2EEB9D22C585141
261007296	building	yes		\N	\N	1303;1305;1307;1309	Minna Street	\N	\N	\N	1303;1305;1307;1309 Minna Street	\N	\N	\N	0106000020110F0000010000000103000000010000000B00000065077F161FFE69C10FBFA9A52C585141A8FC19D21EFE69C14BCBFEEE245851419C678D761EFE69C1B6EA9CFB245851412A2DFA771EFE69C1CE58C62725585141B112728B1DFE69C1AC6038482558514144431BA01DFE69C15BD9C19D2758514179F34FF61DFE69C144720A92275851412BAFD20D1EFE69C1D38C2F342A5851414B27C1B91DFE69C1B3F4E63F2A58514199B1E8D01DFE69C1F2EEB9D22C58514165077F161FFE69C10FBFA9A52C585141
261007315	building	yes		\N	\N	251;253;255	14th Street	\N	\N	\N	251;253;255 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000016000000FC2223641CFE69C1BF7632052D5851410248B5481CFE69C1CDA0FFF52958514145B6B90A1CFE69C1F5DC02FF295851417B6130FD1BFE69C192C9777B28585141196852381CFE69C1F1465B7328585141B244242B1CFE69C137276BF326585141B9230CE11BFE69C1D51B55FD265851410D5A5CD61BFE69C1722A98C42558514120C912841BFE69C103914FD025585141A18547871BFE69C1E20C242D26585141292164401BFE69C14F010E3726585141562EDF471BFE69C174103F0727585141DBD728F41AFE69C16577F612275851410CD776081BFE69C1A0FA30622958514135B132381BFE69C10331FB5A29585141533C0C3B1BFE69C17DEB99B0295851414F094D631BFE69C13C9431AB29585141A63170651BFE69C115D7C9EE2958514161FF990A1BFE69C118F867FB29585141E2BBCE0D1BFE69C19B62D75B2A585141866E19271BFE69C1C7ED5B312D585141FC2223641CFE69C1BF7632052D585141
261007300	building	yes		\N	\N	239;241;243	14th Street	\N	\N	\N	239;241;243 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000C000000EA17D1F519FE69C1DCDE8B6F2D58514101BF04DF19FE69C1F967EBDA2A5851413B16A4AF19FE69C19F783AE12A5851418D4CF4A419FE69C11D174EB329585141EA94EB2719FE69C14E8F54C5295851413E44A52319FE69C10157764D29585141BFFB1BC318FE69C10331FB5A29585141081B07C718FE69C1361271CD2958514133F0049318FE69C1E7DBA6D42958514109D55C9818FE69C184CA8E672A5851412E44DCB418FE69C15956B59B2D585141EA17D1F519FE69C1DCDE8B6F2D585141
261007312	building	yes		\N	\N	245;247;249	14th Street	\N	\N	\N	245;247;249 14th Street	\N	\N	\N	0106000020110F000001000000010300000001000000130000004ED1CF271BFE69C124DA2F452D585141866E19271BFE69C1C7ED5B312D585141E2BBCE0D1BFE69C19B62D75B2A58514183BD32E51AFE69C14EF9C3252A58514164B9EFDB1AFE69C19A20AC54295851414D12BCF21AFE69C101F5F75129585141027A67E81AFE69C18658F224285851415DD549C21AFE69C191AF5A2A28585141A00262B91AFE69C1DA19B12727585141CC138EEC19FE69C19685A14327585141EA17D1F519FE69C11173B34B2858514119DFA1CE19FE69C122CA1B5128585141C6A851D919FE69C18F31578529585141E89E67EF19FE69C1F205A38229585141A5714FF819FE69C1ABD600882A58514156E727E119FE69C1C91460BB2A58514101BF04DF19FE69C1F967EBDA2A585141EA17D1F519FE69C1DCDE8B6F2D5851414ED1CF271BFE69C124DA2F452D585141
261007332	building	yes		\N	12	1314;1316;1318	Natoma Street	\N	\N	\N	1314;1316;1318 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A000000727C7DAB1AFE69C1EB548D1725585141C339649A1AFE69C1A3B414382358514197272B2F1AFE69C1B1FE6647235851417A9C512C1AFE69C161A830F722585141785F168D19FE69C1CEBAB80D23585141249B57CA16FE69C1D4B1A972235851410FF423E116FE69C18B52A8F12558514138610C421AFE69C152412F76255851411BD6323F1AFE69C1B39FDF2625585141727C7DAB1AFE69C1EB548D1725585141
261007335	building	yes		\N	9	1326;1328	Natoma Street	\N	\N	\N	1326;1328 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A00000011BFCD4D1AFE69C19A9E22942058514148E3AD461AFE69C118EBF4CC1F585141217D9DB919FE69C1C3D0C8E01F58514164314CAA19FE69C1465696351E585141326D1FC517FE69C1963E157A1E585141B32954C817FE69C16C7E35D41E58514194613F2617FE69C17A47A4EB1E5851419ACC7B3917FE69C1793BE403215851414760C87819FE69C1B677E0B12058514111BFCD4D1AFE69C19A9E229420585141
261007338	building	yes		\N	9	1320;1322	Natoma Street	\N	\N	\N	1320;1322 Natoma Street	\N	\N	\N	0106000020110F0000010000000103000000010000000A000000A9DC8B0B1AFE69C17C6E5FA32258514151C295FC19FE69C16073AEFC20585141C81CFD7B19FE69C19FE7B40E215851414760C87819FE69C1B677E0B1205851419ACC7B3917FE69C1793BE40321585141C907F8B416FE69C1BF68D11621585141249B57CA16FE69C1D4B1A97223585141785F168D19FE69C1CEBAB80D23585141F7A2E18919FE69C17CE365B522585141A9DC8B0B1AFE69C17C6E5FA322585141
261089744	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000014000000002BCB7515FE69C1D8889105245851417F6E967215FE69C1B7DC8F2A235851411905BE3615FE69C10E550102235851416E2DE13815FE69C1ECACCD71225851413C743D5315FE69C13CBC1C78225851412C79324815FE69C140C7DDF120585141139A812315FE69C12EB88EEB205851412C79324815FE69C1ADF6C3A920585141E359474415FE69C1F36B11D51F5851413A3CC01715FE69C1D5D833A61F585141B806220E15FE69C12A5DEC961E585141105B2C1412FE69C18CC9F9031F58514179F205C411FE69C11D2EB10F1F58514179B119F911FE69C1CF7C73CF2458514191D1B6E811FE69C11AA827D22458514118F927FF11FE69C1E4F76E4527585141438D390012FE69C15548FA64275851416981B85A15FE69C19D3281E9265851411CF7904315FE69C181F44F6C24585141002BCB7515FE69C1D888910524585141
261089745	building	yes		\N	\N	215;217	14th Street	\N	\N	\N	215;217 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000015000000DEE3813113FE69C17F5E55832E585141DF9DD70213FE69C14262E86D29585141938C19F212FE69C14E8792A827585141368050D612FE69C1876898712758514155C57FAA12FE69C101944C74275851410549858612FE69C1433563B32758514159F3801E12FE69C1BA0EE8C027585141C1D004FD11FE69C12F0B538627585141B308B9C911FE69C1807D2088275851411E5FA6AE11FE69C1B6BCB8CB275851414E1D08F811FE69C1C36A0DD82E585141A737FE0612FE69C1F23620C52E585141F5C1251E12FE69C13995E4F42E585141F8F9A25912FE69C1433D7CEF2E5851413EE6CE8512FE69C113165F9E2E5851417F5991AB12FE69C129BEF6982E585141501957CC12FE69C1F23620C52E585141EF1F790713FE69C195A9EDC62E585141ADE4331D13FE69C1AE9B588C2E585141DEE3813113FE69C15CE2718B2E585141DEE3813113FE69C17F5E55832E585141
261089734	building	yes		\N	\N	221;223;225	14th Street	\N	\N	\N	221;223;225 14th Street	\N	\N	\N	0106000020110F000001000000010300000001000000100000007D2C9D6F14FE69C15E735E552E585141F066306E14FE69C12D3838322E58514148C2124814FE69C133B7870C2A585141A2D28C8F13FE69C186B2AA262A58514177C5118813FE69C1D177145A29585141DF9DD70213FE69C14262E86D29585141DEE3813113FE69C17F5E55832E5851412AF53F4213FE69C18B32A1802E5851418701095E13FE69C1AC25D1BE2E585141739252B013FE69C1D4494CB12E585141978868C613FE69C1E1FEB36D2E585141019E69E013FE69C19D19196A2E585141158B47F813FE69C19338FDAA2E5851414A3B7C4E14FE69C11EEAAA9B2E5851416C31926414FE69C1FFE52B572E5851417D2C9D6F14FE69C15E735E552E585141
261089742	building	yes		\N	11	227;229	14th Street	\N	\N	\N	227;229 14th Street	\N	\N	\N	0106000020110F000001000000010300000001000000130000002F70C3B815FE69C15AC840572C58514111E5E9B515FE69C134BBD0AD2B5851416A40CC8F15FE69C1615AD36D2B585141C78D817615FE69C1F7A258B328585141A5976B6015FE69C1B687F3B6285851419EB3C54615FE69C109A9D96E285851415FEC2BFF14FE69C16210917A285851415516B3D814FE69C1D771C7CA28585141E262B6D314FE69C1B6B4933A285851412845663814FE69C1F41035502858514148C2124814FE69C133B7870C2A585141F066306E14FE69C12D3838322E585141BF26F68E14FE69C19F99B62D2E585141EABA079014FE69C13D365B4C2E5851412EB1AF8315FE69C112FB34292E585141031D9E8215FE69C1925E900A2E5851411CFC4EA715FE69C1BA0628052E585141190A7C9A15FE69C17A56F2992C5851412F70C3B815FE69C15AC840572C585141
261007317	building	yes		\N	12	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F000001000000010300000001000000210000002E44DCB418FE69C15956B59B2D58514109D55C9818FE69C184CA8E672A5851418EC4507318FE69C1DC21F76C2A585141ED03D96618FE69C1DE048F032958514195A8F68C18FE69C1B6AD26FE285851416622127F18FE69C1B0217F72275851416C88902E18FE69C1BE88367E27585141932ACF2218FE69C1FCFCD42626585141D5A1427417FE69C17D832A3F265851414ACEA87F17FE69C1A08D6F8E27585141C22810FF16FE69C17EE910A427585141E0B3E90117FE69C16D022EF52758514148916DE016FE69C1589F0B2428585141559AA5DE16FE69C12B8216D1285851413855760A17FE69C132B35F0E29585141D4231B0A17FE69C12AB5CFB729585141F8D386F116FE69C1534E74D6295851417990BBF416FE69C17EA0368F2A5851416754C41E17FE69C1A6DE95C22A5851414B42542217FE69C13ACE212B2B5851410A48FB0217FE69C1BD06484E2B585141EF358B0617FE69C1AFFAAE252C585141BD7CE72017FE69C1DD5F894B2C5851418758072817FE69C12B3752162D585141AD81DC1517FE69C17A23262A2D5851416362F11117FE69C16C1E0EBD2D5851411E7B834917FE69C1B16D022B2E585141FB892B9717FE69C14FE0CF2C2E585141681896B717FE69C1FE7399DC2D58514126E20E3118FE69C18C6C60CC2D585141F136983E18FE69C1CEDA73022E585141C4A744A118FE69C19A8C21F32D5851412E44DCB418FE69C15956B59B2D585141
260973327	building	yes		\N	8	224	14th Street	\N	\N	\N	224 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000008000000FE2E7CA114FE69C1CC93FD9A3F5851410B38B49F14FE69C149C7D0653F5851416F64513C14FE69C1FE07C57334585141CFA2CCF712FE69C132FABBA13458514177C0532413FE69C136FA658739585141B7822F0813FE69C10E9AE78B39585141FF602E4113FE69C1783376CD3F585141FE2E7CA114FE69C1CC93FD9A3F585141
260973322	building	yes		\N	6	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000006000000FF602E4113FE69C1783376CD3F585141B7822F0813FE69C10E9AE78B39585141BF92BC2510FE69C18AB073F439585141D4F8034410FE69C1320CDB4A3D5851410771BB5E10FE69C16C5A023640585141FF602E4113FE69C1783376CD3F585141
260973323	building	yes		\N	7	250;252	14th Street	\N	\N	\N	250;252 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000F0CF8F0B1DFE69C123E348343E585141E14DEE061DFE69C18586CFB83D58514160D2A5CE1CFE69C14C66DF833758514154FC2CA81CFE69C107783D42335851416F64513C14FE69C1FE07C573345851410B38B49F14FE69C149C7D0653F585141F0CF8F0B1DFE69C123E348343E585141
260973326	building	yes		\N	7	266;270	14th Street	\N	\N	\N	266;270 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000800000099860E0522FE69C1A9A646593D5851413B01DCE221FE69C15093D19539585141D41E9AA021FE69C11DD8964832585141A11D321C1FFE69C1B9B784A432585141C77E84451FFE69C1F9A7A52A3758514148FACC7D1FFE69C13FBA955F3D5851416685A6801FFE69C135E64DB43D58514199860E0522FE69C1A9A646593D585141
260973318	building	yes		\N	7	256	14th Street	\N	\N	\N	256 14th Street	\N	\N	\N	0106000020110F0000010000000103000000010000000500000048FACC7D1FFE69C13FBA955F3D585141C77E84451FFE69C1F9A7A52A3758514160D2A5CE1CFE69C14C66DF8337585141E14DEE061DFE69C18586CFB83D58514148FACC7D1FFE69C13FBA955F3D585141
260973325	building	yes	Standard Deviant	\N	6	280	14th Street	\N	\N	\N	280 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000007000000F42E73E124FE69C1FFDDC32839585141D1385DCB24FE69C13FBA94B4365851418B4C319F24FE69C13EF06FDC31585141D41E9AA021FE69C11DD89648325851413B01DCE221FE69C15093D19539585141F792D72022FE69C19F53CE8C39585141F42E73E124FE69C1FFDDC32839585141
260973316	building	yes		\N	11	1799	Mission Street	\N	\N	\N	1799 Mission Street	\N	\N	\N	0106000020110F000001000000010300000001000000050000003EDDD9EA28FE69C1B0913BCB335851416E967DD028FE69C1A9A8F8D7305851413E811DBD24FE69C136B1E06A315851410EC879D724FE69C125A5235E345851413EDDD9EA28FE69C1B0913BCB33585141
260973317	building	yes		\N	9	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000005000000F34485E028FE69C175E58F9838585141D04E6FCA28FE69C120117A2336585141D1385DCB24FE69C13FBA94B436585141F42E73E124FE69C1FFDDC32839585141F34485E028FE69C175E58F9838585141
260973329	building	yes		\N	4	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000900000045C17F0429FE69C15A7C7D8E3C585141F34485E028FE69C175E58F9838585141F42E73E124FE69C1FFDDC32839585141F792D72022FE69C19F53CE8C39585141470FD24422FE69C187BCA2833D585141A5DAAE9522FE69C1F94EEB773D585141B694CDD522FE69C1680EE86E3D5851417401BAE328FE69C12ED6E5933C58514145C17F0429FE69C15A7C7D8E3C585141
260998417	building	yes		\N	\N	\N	Mission Street	San Francisco	\N	94103	Mission Street, San Francisco, 94103	\N	\N	\N	0106000020110F0000010000000103000000010000000700000091C8C14D28FE69C1FBFD5AC626585141C5FACE3928FE69C1AB4EF18124585141BFBF2A5624FE69C140C3210925585141A2ADBA5924FE69C152412F7625585141446E326624FE69C12C07CDE626585141275CC26924FE69C16F33724E2758514191C8C14D28FE69C1FBFD5AC626585141
260998415	building	yes		\N	13	277;279;281;285	14th Street	\N	\N	\N	277;279;281;285 14th Street	\N	\N	\N	0106000020110F00000100000001030000000100000010000000B3EE6F9324FE69C1B91F2A182C5851410F3C257A24FE69C1DB4B042D2958514120781C5024FE69C10AA36C322958514154AA293C24FE69C10B5E35EC26585141446E326624FE69C12C07CDE626585141A2ADBA5924FE69C152412F7625585141E71BBF1B24FE69C1757C327F25585141303BAA1F24FE69C14AE0DAEF2558514196D634FB22FE69C1CEB18217265851416BC9B9F322FE69C1EFCECC392558514172E4CF1022FE69C1A5647158255851418558442222FE69C1749A295A275851413655B30422FE69C1147FC45D27585141EC7B722F22FE69C1CB7AEE472C5851411710843022FE69C149B4146B2C585141B3EE6F9324FE69C1B91F2A182C585141
260998410	building	yes		\N	11	269	14th Street	San Francisco	\N	94103	269 14th Street, San Francisco, 94103	\N	\N	\N	0106000020110F00000100000001030000000100000018000000EC7B722F22FE69C1CB7AEE472C5851413655B30422FE69C1147FC45D275851411ACAD90122FE69C1BCDB18E426585141D55617DC21FE69C1B29BDCCA2658514136969FCF21FE69C1C09F7461255851410EADA97420FE69C1A4395290255851417CAFBF3720FE69C1ACBB6E9825585141F3DB254320FE69C177799AE8265851419A80436920FE69C1BCDB18E426585141B60B1D6C20FE69C1FC394F34275851410F67FF4520FE69C1E590B73927585141F6CDF84F20FE69C185883B6228585141F29A397820FE69C17331D35C2858514175D0D78120FE69C11047837129585141C29BEB6320FE69C116E50476295851410B34406E20FE69C18C8B0AA32A585141CFEACD9020FE69C164ED889E2A585141FCF7489820FE69C15CEE3E7C2B585141AA7B4E7420FE69C1059655BB2B58514156CC947820FE69C13FD98F5D2C585141AF2C35B620FE69C108C6E2B52C585141B5CFEE0421FE69C1FDCFF8AB2C5851415BFBA22421FE69C1906DFB6B2C585141EC7B722F22FE69C1CB7AEE472C585141
-3504260	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000200000013000000C5FACE3928FE69C1AB4EF18124585141834162E527FE69C1B6252BCD1A585141FB4F549A25FE69C18D6B611D1B585141285DCFA125FE69C1FB1517FB1B585141003D694325FE69C175EB9B081C585141D52FEE3B25FE69C1D887FF291B585141CBF33C2020FE69C19CCE8BDB1B5851414804494520FE69C112E5C217205851413BBA247C20FE69C1251D8D1020585141A164E98220FE69C1F6A606D520585141A885CA3B21FE69C1C56ACABB20585141D984185021FE69C1CEBAB80D23585141797C006020FE69C1F4C02A2E235851410EADA97420FE69C1A43952902558514136969FCF21FE69C1C09F74612558514172E4CF1022FE69C1A5647158255851416BC9B9F322FE69C1EFCECC3925585141BFBF2A5624FE69C140C3210925585141C5FACE3928FE69C1AB4EF181245851410700000097A0D12F25FE69C13AB36AEC215851411994763624FE69C17D71C30D225851412816183B24FE69C102345C9A22585141E597CC1522FE69C143332AE522585141B41F15FB21FE69C113A4DBCD1F58514175AABB1925FE69C181EEB4611F58514197A0D12F25FE69C13AB36AEC21585141
260998416	building	yes		\N	8	1342;1344	Minna Street	\N	\N	\N	1342;1344 Minna Street	\N	\N	\N	0106000020110F00000100000001030000000100000010000000E88E5D8622FE69C16207969C185851417E795C6C22FE69C15AA438A115585141ABB77CDB1FFE69C15D1772FA15585141EFE494D21FFE69C11ED058FB15585141BBF373B11FFE69C1150AC85B1658514104135FB51FFE69C12A2444E0165851419B35DBD61FFE69C19A6FC93617585141F3D667DF1FFE69C1149706E2175851411687D3C61FFE69C12159E71918585141509D86CC1FFE69C14DE8A2C018585141215D4CED1FFE69C1BFF29CF71858514185D55E5421FE69C1403D0BC6185851411222624F21FE69C1D68F23331858514154DBCEA321FE69C1492D6C2718585141C78ECBA821FE69C15B933ABB18585141E88E5D8622FE69C16207969C18585141
260998414	building	apartments	Vincentian Villa	\N	12	1828	Mission Street	San Francisco	\N	94103	1828 Mission Street, San Francisco, 94103	\N	\N	\N	0106000020110F0000010000000103000000010000001D0000000D9C92D327FE69C1CB7A73D516585141F14378A827FE69C1A99FF49016585141C7AF66A727FE69C14679290616585141EB1EE6C327FE69C172C797D415585141DB23DBB827FE69C147FDC22E15585141DECF039727FE69C11591830C15585141A732BA9727FE69C14F89C2E5145851416D94636026FE69C1449ED21215585141E047606526FE69C19CCEECA31558514135ACB1CE25FE69C1BB208EB915585141B4EF7CCB25FE69C1CD3C875E15585141CB91F25025FE69C1C6AB8D70155851414C4E275425FE69C11CD7ADCA15585141185848CF24FE69C109FF9ADD15585141A5A44BCA24FE69C1DCCD804C15585141CACC138023FE69C1C5545E7B15585141D1B0B99923FE69C1C97CB86D185851410138ABDF24FE69C1D71C8F41185851418E84AEDA24FE69C1228E0CAB17585141191C1A6825FE69C18DAC389717585141623B056C25FE69C1FD84620C18585141752DA1E725FE69C1A2CD42FB1758514166ABFFE225FE69C10E93617A1758514156ED2F7726FE69C1C7F8A66517585141D7A9647A26FE69C1CE78DAF51758514113C124B827FE69C16EED35D71758514176F27FB827FE69C122F28AA6175851410D9C92D327FE69C191B18D66175851410D9C92D327FE69C1CB7A73D516585141
260998411	building	yes		\N	10	1855	Mission Street	San Francisco	\N	94103	1855 Mission Street, San Francisco, 94103	\N	\N	\N	0106000020110F00000100000001030000000100000009000000A732BA9727FE69C14F89C2E514585141C7AAA84327FE69C1029914420C585141870253901FFE69C1CD6DA74E0D585141ABB77CDB1FFE69C15D1772FA155851417E795C6C22FE69C15AA438A115585141CACC138023FE69C1C5545E7B15585141A5A44BCA24FE69C1DCCD804C155851416D94636026FE69C1449ED21215585141A732BA9727FE69C14F89C2E514585141
260998413	building	yes		\N	13	1875	Mission Street	San Francisco	\N	94103	1875 Mission Street, San Francisco, 94103	\N	\N	\N	0106000020110F000001000000010300000001000000060000003A9F911327FE69C118A44D8B075851419C986FD826FE69C18333B1C10058514141675A9221FE69C1540E8C7901585141064160291FFE69C13D025DCD01585141A64782641FFE69C18DA0F996085851413A9F911327FE69C118A44D8B07585141
260973320	building	yes		\N	7	1775	Mission Street	\N	\N	\N	1775 Mission Street	\N	\N	\N	0106000020110F00000100000001030000000100000005000000C96F871429FE69C1AFDEA1EF415851417401BAE328FE69C12ED6E5933C585141B694CDD522FE69C1680EE86E3D5851410C039B0623FE69C139EE8ACB42585141C96F871429FE69C1AFDEA1EF41585141
587670476	building	yes	Health Right 360	\N	\N	1735	Mission Street	San Francisco	CA	94103	1735 Mission Street, San Francisco, CA, 94103	\N	\N	\N	0106000020110F0000010000000103000000010000000A0000003B6470E428FE69C105E7595A50585141428902C928FE69C1828AF1545058514100D553D828FE69C1CC6CAE0E4F58514154FC69A227FE69C163A3E6D54E58514196B0189327FE69C1AF61AB2050585141526DEE9C23FE69C187784D644F585141BFB5AE8E23FE69C143CCB27B5058514141AE11F922FE69C1C4F950315D585141C673384028FE69C1BC61DF2B5E5851413B6470E428FE69C105E7595A50585141
587670478	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F0000010000000103000000010000000A000000BFB5AE8E23FE69C143CCB27B50585141F691CAE820FE69C1A9C26BFE4F5851416C32DC9620FE69C1A1623FF456585141DDF9D02A22FE69C13B0A273E575851415F705BFF21FE69C1620030EA5A585141FB38356320FE69C150DD7A9E5A585141025909E41FFE69C1AFCEB97365585141EB07C78C22FE69C1B8AB77636658514141AE11F922FE69C1C4F950315D585141BFB5AE8E23FE69C143CCB27B50585141
587670480	building	yes		\N	\N	\N	\N	\N	\N	\N		\N	\N	\N	0106000020110F00000100000001030000000100000007000000C673384028FE69C1BC61DF2B5E58514141AE11F922FE69C1C4F950315D585141EB07C78C22FE69C1B8AB776366585141486C9BAA27FE69C1668E3553675851416C9A2EFC27FE69C16A42FD696058514195FB802528FE69C10716337160585141C673384028FE69C1BC61DF2B5E585141
\.


--
-- Data for Name: indoor_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.indoor_line (osm_id, osm_type, name, layer, level, room, entrance, door, capacity, highway, geom) FROM stdin;
\.


--
-- Data for Name: indoor_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.indoor_point (osm_id, osm_type, name, layer, level, room, entrance, door, capacity, highway, geom) FROM stdin;
\.


--
-- Data for Name: indoor_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.indoor_polygon (osm_id, osm_type, name, layer, level, room, entrance, door, capacity, highway, geom) FROM stdin;
\.


--
-- Data for Name: infrastructure_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.infrastructure_line (osm_id, osm_type, osm_subtype, name, ele, height, operator, material, geom) FROM stdin;
\.


--
-- Data for Name: infrastructure_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.infrastructure_point (osm_id, osm_type, osm_subtype, name, ele, height, operator, material, geom) FROM stdin;
5747580158	emergency	fire_alarm_box		\N	\N	\N	\N	0101000020110F000090A2F14DF0FD69C1929F0AA639585141
8889609060	power	generator		\N	\N	\N	\N	0101000020110F0000D80E5F54F3FD69C1B35AA34D3B585141
\.


--
-- Data for Name: infrastructure_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.infrastructure_polygon (osm_id, osm_type, osm_subtype, name, ele, height, operator, material, geom) FROM stdin;
197048563	emergency	assembly point		\N	\N	\N	\N	0106000020110F00000100000001030000000100000013000000600BB9A4ECFD69C1E1D4624C44585141176EA636ECFD69C167BD4836395851412B12767DDDFD69C1108730E43A5851414E741530CEFD69C1F919145B3D5851415E6E1303CDFD69C1109E80A026585141364E70AAC1FD69C11F004274285851417605C38EBFFD69C155FDECE12F585141F8E362CEBBFD69C179E1A9E0385851410E3E14B5B8FD69C19EDA251A3E5851411BAE54E6B3FD69C1530A62034458514180C4DF83AFFD69C180AB6B6F47585141F3259C22ACFD69C1620928314958514197D8E63BACFD69C1B37BA7E950585141B5A038D8B7FD69C1850D8AA053585141D50E25B1CCFD69C16668DA0A55585141A96114ACEBFD69C1D66313085758514140486266ECFD69C1DE9D060A53585141600BB9A4ECFD69C1BAC8C8334B585141600BB9A4ECFD69C1E1D4624C44585141
104597417	emergency	assembly_point		\N	\N	\N	\N	0106000020110F00000100000001030000000100000005000000C9B8E14DFBFD69C196E759E6315851413250BBFDFAFD69C10E550102235851419293B722EFFD69C18AABF51C2558514125C91E9BEFFD69C1F25E94EC33585141C9B8E14DFBFD69C196E759E631585141
\.


--
-- Data for Name: landuse_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.landuse_point (osm_id, osm_type, name, geom) FROM stdin;
\.


--
-- Data for Name: landuse_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.landuse_polygon (osm_id, osm_type, name, geom) FROM stdin;
676720003	commercial		0106000020110F0000010000000103000000010000000800000086259161F6FD69C1D07EDD79FA575141C2368603F6FD69C165DF4044F05751413F7E022CF5FD69C12904CC63F057514122ED5D8DF3FD69C1506E479FF05751419C8400ACF3FD69C1D130DBF3F357514101EED8E7F3FD69C166562977FA57514183AA0DEBF3FD69C1FB6CFDD3FA57514186259161F6FD69C1D07EDD79FA575141
676719999	residential		0106000020110F00000100000001030000000100000010000000410D7E31F9FD69C1A27F1F13FA575141BC59B8BDF8FD69C1CE582F86ED575141AB4D5917F5FD69C1B5F1F910EE575141AC83BCE2F2FD69C114951662EE5751417B3EC49FF2FD69C176815B35E757514163FD8BB1ECFD69C180522912E85751413BA6B54FEDFD69C1139D5A08F95751411A86D2A5F2FD69C1D6AF2D41F857514112E8D6BAF2FD69C13C9552A3FA5751412E73B0BDF2FD69C1C58372FDFA5751415A07C2BEF2FD69C19C2E920EFB57514183AA0DEBF3FD69C1FB6CFDD3FA57514122ED5D8DF3FD69C1506E479FF0575141C2368603F6FD69C165DF4044F057514186259161F6FD69C1D07EDD79FA575141410D7E31F9FD69C1A27F1F13FA575141
676720001	retail		0106000020110F000001000000010300000001000000080000005A07C2BEF2FD69C19C2E920EFB5751412E73B0BDF2FD69C1C58372FDFA57514112E8D6BAF2FD69C13C9552A3FA5751411A86D2A5F2FD69C1D6AF2D41F85751416E70ADD0F0FD69C1FC7E6088F85751413BA6B54FEDFD69C1139D5A08F957514183C5A053EDFD69C166010BD3FB5751415A07C2BEF2FD69C19C2E920EFB575141
483432849	industrial	H. Welton Flynn Motor Coach Division	0106000020110F00000100000001030000000100000008000000A0F97B8CE9FD69C11C8F241BFC575141A3675C93E7FD69C1AABEABE5C9575141A6F65DA4D5FD69C128264CD5CC5751411535A2CED4FD69C15D3F5E2DD257514145D15BE1CDFD69C135CE4831DE57514168C771F7CDFD69C14997889BE057514129478F16CFFD69C13E784B3300585141A0F97B8CE9FD69C11C8F241BFC575141
197048563	retail		0106000020110F00000100000001030000000100000013000000600BB9A4ECFD69C1E1D4624C44585141176EA636ECFD69C167BD4836395851412B12767DDDFD69C1108730E43A5851414E741530CEFD69C1F919145B3D5851415E6E1303CDFD69C1109E80A026585141364E70AAC1FD69C11F004274285851417605C38EBFFD69C155FDECE12F585141F8E362CEBBFD69C179E1A9E0385851410E3E14B5B8FD69C19EDA251A3E5851411BAE54E6B3FD69C1530A62034458514180C4DF83AFFD69C180AB6B6F47585141F3259C22ACFD69C1620928314958514197D8E63BACFD69C1B37BA7E950585141B5A038D8B7FD69C1850D8AA053585141D50E25B1CCFD69C16668DA0A55585141A96114ACEBFD69C1D66313085758514140486266ECFD69C1DE9D060A53585141600BB9A4ECFD69C1BAC8C8334B585141600BB9A4ECFD69C1E1D4624C44585141
586782486	residential	Division Circle Navigation Center	0106000020110F000001000000010300000001000000160000001671C1C71BFE69C1463C25B75158514127EEA4681BFE69C1C84648AE4D5851412825156C1AFE69C196CA2D154A58514121FAB7EB18FE69C19372AA48475851418074610E17FE69C161E0BE914558514135D1830415FE69C1B181941C455851417C6C7C0213FE69C16ABBE2F44558514128714D3C11FE69C14935080548585141D6F345E00FFE69C1B943D8174B58514147ABF3100FFE69C1CD731CDD4E585141D72AB6E30EFE69C138707EF35258514120C30AEE0EFE69C130D197E7575851416578C61610FE69C13DB6CF5A5C585141728B7ADC10FE69C1B4CEC36C5E58514143101FCE12FE69C137C4B0515F585141164F199114FE69C1F67BAD485F5851412FB2BCBB16FE69C17BF1BA9A5E5851417A559AC518FE69C153A5D1EC5C585141433785681AFE69C1627FD7F659585141D2C0C3021BFE69C1EBFBB9B85758514139E9AF731BFE69C16740D413565851411671C1C71BFE69C1463C25B751585141
\.


--
-- Data for Name: leisure_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.leisure_point (osm_id, osm_type, name, geom) FROM stdin;
4270584674	sports_centre	10th Planet Jiu Jitsu - San Francisco	0101000020110F00006BBDA9C709FE69C1160F541D49585141
\.


--
-- Data for Name: leisure_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.leisure_polygon (osm_id, osm_type, name, geom) FROM stdin;
\.


--
-- Data for Name: natural_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.natural_line (osm_id, osm_type, name, ele, geom) FROM stdin;
\.


--
-- Data for Name: natural_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.natural_point (osm_id, osm_type, name, ele, geom) FROM stdin;
9419035930	tree		\N	0101000020110F0000E122143B21FE69C13DF83F9E31585141
\.


--
-- Data for Name: natural_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.natural_polygon (osm_id, osm_type, name, ele, geom) FROM stdin;
\.


--
-- Data for Name: pgosm_flex; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.pgosm_flex (id, imported, osm_date, default_date, region, pgosm_flex_version, srid, project_url, osm2pgsql_version, language, osm2pgsql_mode) FROM stdin;
1	2022-04-10 09:45:34.934348-06	2022-04-10	f	test-emergency-assembly-point.osm.pbf	0.4.6-209769b	3857	https://github.com/rustprooflabs/pgosm-flex	1.6.0		create
\.


--
-- Data for Name: place_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.place_line (osm_id, osm_type, boundary, admin_level, name, geom) FROM stdin;
\.


--
-- Data for Name: place_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.place_point (osm_id, osm_type, boundary, admin_level, name, geom) FROM stdin;
\.


--
-- Data for Name: place_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.place_polygon (osm_id, osm_type, boundary, admin_level, name, member_ids, geom) FROM stdin;
\.


--
-- Data for Name: place_polygon_nested; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.place_polygon_nested (osm_id, name, osm_type, admin_level, nest_level, name_path, osm_id_path, admin_level_path, innermost, geom) FROM stdin;
\.


--
-- Data for Name: poi_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.poi_line (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, operator, geom) FROM stdin;
\.


--
-- Data for Name: poi_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.poi_point (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, operator, geom) FROM stdin;
5087504022	shop	confectionery	Sixth Course	1544	15th Street	\N	\N	94103	1544 15th Street, 94103	\N	0101000020110F0000ED49839518FE69C1191EB268FB575141
4631886603	shop	laundry	A Laundromat	\N	\N	\N	\N	\N		\N	0101000020110F0000A159238913FE69C18C897AC5FC575141
281652616	amenity	pub	The Wooden Nickel	1900	Folsom Street	\N	\N	\N	1900 Folsom Street	\N	0101000020110F000030940EC2EDFD69C136AC2600FB575141
3940894710	amenity	veterinary	San Francisco SPCA Veterinary Hospital - Mission Campus	201	Alabama Street	San Francisco	CA	94103	201 Alabama Street, San Francisco, CA, 94103	\N	0101000020110F00007884F730C1FD69C1C3DF94E308585141
3940887840	amenity	animal_shelter	Animal Care & Control	1200	15th Street	San Francisco	CA	94103	1200 15th Street, San Francisco, CA, 94103	\N	0101000020110F0000BAA5B6EAC8FD69C1EDD6393B04585141
1409407314	amenity	car_sharing	15th & Folsom (UCSF)	\N	\N	\N	\N	\N		City CarShare	0101000020110F0000B70C3912DAFD69C17CC48A2603585141
4628752984	amenity	cafe		\N	\N	\N	\N	\N		\N	0101000020110F0000375B5014D1FD69C11024501926585141
5089298921	amenity	restaurant	Pink Onion	\N	\N	\N	\N	94103	94103	\N	0101000020110F0000187434D8E2FD69C1777B8E043D585141
1243846554	amenity	bar	Nihon	1779	Folsom Street	\N	\N	94103	1779 Folsom Street, 94103	\N	0101000020110F000062BF43DAEAFD69C168C25EAB3B585141
281652606	amenity	post_box		\N	\N	\N	\N	\N		\N	0101000020110F0000B507F5A2EFFD69C1AF6E266539585141
2049063016	amenity	post_box	USPS	\N	\N	\N	\N	\N		United States Postal Service	0101000020110F00004A389EB7EFFD69C1A7D3840834585141
368168766	amenity	library	Far West Library for Educational Research and Development	\N	\N	\N	CA	\N	CA	\N	0101000020110F000083169787E4FD69C133332C0D06585141
6028467888	shop	hardware	City Door and Hardware	165	13th Street	\N	\N	\N	165 13th Street	\N	0101000020110F00007943BFFDFDFD69C1C2B225DA55585141
6028467887	shop	car_repair	Folsom Auto Body Center	1728	Folsom Street	\N	\N	\N	1728 Folsom Street	\N	0101000020110F000051C68F39F8FD69C126DC57BD54585141
5757635621	amenity	restaurant	Rintaro	\N	\N	\N	\N	\N		\N	0101000020110F000009C1ED6BE5FD69C1F5160D7F3F585141
1803661677	amenity	restaurant	Chez Spencer	82 	14th St, San Francisco 	\N	\N	94103	82  14th St, San Francisco , 94103	\N	0101000020110F00004CFD3F8EE6FD69C17D1D2C473F585141
4270584674	leisure	sports_centre	10th Planet Jiu Jitsu - San Francisco	261	South Van Ness Avenue	San Francisco	CA	94103	261 South Van Ness Avenue, San Francisco, CA, 94103	\N	0101000020110F00006BBDA9C709FE69C1160F541D49585141
4631784859	shop	car	Volvo	\N	\N	\N	\N	\N		\N	0101000020110F0000555762A909FE69C1B20D67343B585141
2000101334	amenity	post_box	USPS	\N	\N	\N	\N	\N		United States Postal Service	0101000020110F0000988938040AFE69C184023E5F2F585141
4307902891	amenity	restaurant	Doña Margo	\N	\N	\N	\N	\N		\N	0101000020110F0000E25DBB7509FE69C1A4E094A52E585141
4013644509	amenity	restaurant	Walzwerk	\N	\N	\N	\N	\N		\N	0101000020110F00001A3BE40708FE69C14BFED49709585141
4631774686	shop	car_repair	AVS Motors Auto Repair	\N	\N	\N	\N	\N		\N	0101000020110F00004707734408FE69C11313B3D60E585141
4631771784	shop	tyres	Larkins Brothers Tire Shop	\N	\N	\N	\N	\N		\N	0101000020110F00003760C20F0EFE69C10EE6565D07585141
2411576667	amenity	restaurant	Mission Public SF	233	14th Street	San Francisco	\N	94103	233 14th Street, San Francisco, 94103	\N	0101000020110F0000F2F0ED0F18FE69C156D0194F2D585141
9419035931	amenity	bicycle_parking		\N	\N	\N	\N	\N		\N	0101000020110F0000A694046722FE69C1AE9FB47E31585141
4516187333	amenity	bar	The Armory Club	\N	\N	\N	\N	\N		\N	0101000020110F0000FFCE883C27FE69C19E0D845B32585141
3345049955	amenity	car_sharing	14th & Mission (on-street)	\N	\N	\N	\N	\N		City CarShare	0101000020110F0000E185A83C28FE69C1A311D3992F585141
420508633	amenity	post_box	USPS	\N	\N	\N	\N	\N		United States Postal Service	0101000020110F0000FA282BFA28FE69C1CDA658B832585141
3009487838	shop	convenience	New Star Market	269	14th Street	San Francisco	\N	94103	269 14th Street, San Francisco, 94103	\N	0101000020110F0000D592454321FE69C195D258C42B585141
\.


--
-- Data for Name: poi_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.poi_polygon (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, operator, member_ids, geom) FROM stdin;
260998412	building	yes	Impact Hub San Francisco	1899	Mission Street	San Francisco	\N	94103	1899 Mission Street, San Francisco, 94103	\N	\N	0106000020110F000001000000010300000001000000060000009C986FD826FE69C18333B1C10058514118A4BD9926FE69C122E5088BF95751419B5B343926FE69C18F04D903F9575141E78D504E21FE69C1DBA915AFF957514141675A9221FE69C1540E8C79015851419C986FD826FE69C18333B1C100585141
132605501	amenity	parking		\N	\N	\N	\N	\N		\N	\N	0106000020110F0000010000000103000000010000000900000068C627C5C1FD69C19F1809771158514100E4E582C1FD69C122BE828809585141D7AD6D25BDFD69C196DFC23C0A585141CC9BC697BDFD69C10CD30E2C15585141ACC60E86B8FD69C14EE6682816585141D4695AB2B9FD69C12C8EAA4635585141AB23D8EBBDFD69C1A6DE95C22A585141AA3D9B16C1FD69C1FA6A455E1B58514168C627C5C1FD69C19F18097711585141
688747551	amenity	marketplace	SoMa StrEat Food Park	428	11th Street	\N	\N	\N	428 11th Street	\N	\N	0106000020110F0000010000000103000000010000001200000058752B28BFFD69C1FC788B36625851413DA4A7F6BEFD69C158143795615851419969B9ABBDFD69C1680F09585E585141AB184FECBBFD69C1F1209A405E585141A8980D12B9FD69C1481034FB5D58514198833FDCB5FD69C1B1D7186A5D585141D1A26171B5FD69C11392FF6A5D5851414451A012B5FD69C1277785C15D585141078A06CBB4FD69C13E19B17F5E5851417EE92BAEB4FD69C17DF364545F585141DAF5F4C9B4FD69C1C1891520605851414B7632F7B4FD69C167DCC199605851412F331D93B7FD69C1A53166ED65585141F2F433B5B9FD69C19AF849486A5851419BD68C7ABAFD69C1E1C132AD6B5851411D63294EBEFD69C17DE80FE8635851416F1C5F11BFFD69C12B411A5F6258514158752B28BFFD69C1FC788B3662585141
25371859	shop	stationery	OfficeMax	1750	Harrison Street	San Francisco	\N	94103	1750 Harrison Street, San Francisco, 94103	\N	\N	0106000020110F00000100000001030000000100000009000000A17659C4DDFD69C19C191F233F5851417BB48C09D9FD69C1865A27AC3E585141DA7AABF6D8FD69C1A9A646593D585141D938B2F3D7FD69C1D25C24883D58514123D106FED7FD69C1B05104923E585141E8739C91D6FD69C1744EF76D3E58514195BF2432D6FD69C16D1AAAA14D585141EB908664DDFD69C1EC2AD2564E585141A17659C4DDFD69C19C191F233F585141
132605458	amenity	parking		\N	\N	\N	\N	\N		OfficeMax	\N	0106000020110F00000100000001030000000100000008000000EB908664DDFD69C1EC2AD2564E58514195BF2432D6FD69C16D1AAAA14D585141E8739C91D6FD69C1744EF76D3E585141795A6797D1FD69C19D379B433E5851418CC91D45D1FD69C1978B81D94E585141AECF7ABED3FD69C19D51DDF85358514103AC65F0DCFD69C1CBC44A9954585141EB908664DDFD69C1EC2AD2564E585141
132605487	amenity	parking	Best Buy Parking	\N	\N	\N	\N	\N		\N	\N	0106000020110F0000010000000103000000010000001A000000E513AC83CDFD69C11AC1BFEF3E5851418707E367CDFD69C1451A86FC3A585141CA01FF8CC2FD69C1D09BF8803C585141CEE8489AC0FD69C1E76E447E3C585141C1DA5238C0FD69C1610A92F23B585141258AD5A2C0FD69C115E7BB033B58514118F32ED7BDFD69C1F4014E3736585141499C8B59BBFD69C1621A93203B585141799ACC35BAFD69C1DDCCE8B73D585141D7E3D0F0BAFD69C17C348DF13E5851417EC9DAE1BAFD69C1CB67526A3F585141DB52BE2FBAFD69C11B85C48A3F58514129564F4DBAFD69C126D91F7247585141642B1688BAFD69C1B160C5F44858514128249DADBBFD69C179257F194F5851411F4A735BBCFD69C128AC6A9A4E585141A1898D2CBDFD69C1C925D99E5058514191127527BFFD69C16B213D374F58514157C093BABFFD69C195F05C484F5851419BEDABB1BFFD69C1E06684CF50585141087D6004CCFD69C11A5374BD515851411A786B0FCCFD69C12D72DF954F5851419D2B3183CCFD69C1F070C99F4F585141BEA8DD92CCFD69C15A4D9F224C585141A93EE548CDFD69C15A4D9F224C585141E513AC83CDFD69C11AC1BFEF3E585141
25821942	shop	electronics	Best Buy	1717	Harrison Street	\N	\N	94103	1717 Harrison Street, 94103	\N	\N	0106000020110F0000010000000103000000010000000B000000B4145E6FCDFD69C10D58FECA39585141B15EB9C9CCFD69C1285C3FB4285851419D765C1BC2FD69C15E26D4522A585141A84CD541C2FD69C17D1BF64F2E5851419EA80EBBC0FD69C15CE2718B2E585141973CC56FBFFD69C1440FCA8F32585141183BF375C0FD69C181D1D760345851413DE6A0F9BFFD69C1F4180D833558514164516FEAC0FD69C18B47272F37585141E1DAE415C1FD69C12C4F91A93B585141B4145E6FCDFD69C10D58FECA39585141
132605518	amenity	parking		\N	\N	\N	\N	\N		\N	\N	0106000020110F000001000000010300000001000000050000008FC6B64BDEFD69C1B3C7000F1A5851417E07DAA7DDFD69C1D898E72B045851410072914ACFFD69C1F3BF2F5F06585141DB440B31D0FD69C18EA4BB191C5851418FC6B64BDEFD69C1B3C7000F1A585141
261095625	amenity	animal_boarding	Wag Hotels	25	14th Street	San Francisco	CA	94103	25 14th Street, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000050000000A95C96DDDFD69C1A713CD7B365851418F3E131ADDFD69C123CF80262E585141DF8EE93FD5FD69C190865A672F585141E7B83988D5FD69C11C0A84A2375851410A95C96DDDFD69C1A713CD7B36585141
25821952	shop	supermarket	Foods Co	1800	Folsom Street	\N	\N	\N	1800 Folsom Street	\N	\N	0106000020110F000001000000010300000001000000050000003250BBFDFAFD69C10E55010223585141F4C44F1DFAFD69C102274B1408585141CBA85DF0EDFD69C1900A6DDB095851419293B722EFFD69C18AABF51C255851413250BBFDFAFD69C10E55010223585141
104597417	amenity	parking		\N	\N	\N	\N	\N		\N	\N	0106000020110F00000100000001030000000100000005000000C9B8E14DFBFD69C196E759E6315851413250BBFDFAFD69C10E550102235851419293B722EFFD69C18AABF51C2558514125C91E9BEFFD69C1F25E94EC33585141C9B8E14DFBFD69C196E759E631585141
256454796	shop	car_repair	Pak Auto Service	1748	Folsom Street	San Francisco	CA	94103	1748 Folsom Street, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000060000008E8651ADF5FD69C1795134274A5851416C903B97F5FD69C1EDB1CC3448585141271D7971F5FD69C1D13FB44846585141CBF4D2BAEFFD69C1880F4B15475851410C3018A5EFFD69C14F218EAC4B5851418E8651ADF5FD69C1795134274A585141
25821948	amenity	parking		\N	\N	\N	\N	\N		\N	\N	0106000020110F00000100000001030000000100000008000000B291F295E2FD69C1C17522E1435851418192A481E2FD69C102E8CDDB41585141CE5DB863E2FD69C10DFBA3303F585141D309E141E2FD69C1399EE70A3C585141D290773BE2FD69C1D347616B3B58514140C43266DFFD69C1AAE3F3E53B58514135F377A3DFFD69C191E9B15244585141B291F295E2FD69C1C17522E143585141
169204245	shop	supermarket	Rainbow Grocery Coop	1745	Folsom Street	San Francisco	CA	94103	1745 Folsom Street, San Francisco, CA, 94103	\N	\N	0106000020110F0000010000000103000000010000001200000004FA3125ECFD69C133F8B05A47585141B76F0A0EECFD69C1D1E84FAA3F585141AD9991E7EBFD69C17BB685B13F5851416EB7273DE7FD69C1AD41A60B40585141DE37656AE7FD69C189B3814A465851412757506EE7FD69C1EA23CFD94658514137C9AA0FE5FD69C1A7E4E1C646585141D3974F0FE5FD69C14689AE7F465851415162B105E5FD69C1E03B2CFC4358514173CA584EE2FD69C18CF1FC0644585141D9741D55E2FD69C1C77E6C9D46585141CB1AB228E0FD69C16FC16FA646585141F7A905C6DFFD69C1B46E34805058514120BA61BBE8FD69C1F7BE2340525851419B521112EAFD69C1ED2F6D7D52585141CCCF8690EAFD69C1662E2B9B52585141F864A5C9EBFD69C17D71C0D55258514104FA3125ECFD69C133F8B05A47585141
260973315	amenity	nightclub	Public Works	161	Erie Street	San Francisco	CA	94103	161 Erie Street, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000060000006C4223FA22FE69C15C0DEA8548585141A5DAAE9522FE69C1F94EEB773D585141470FD24422FE69C187BCA2833D5851415EDC21961DFE69C16DCFF92D3E585141C1123BFA1DFE69C178C0F83B495851416C4223FA22FE69C15C0DEA8548585141
363054684	shop	car	Audi San Francisco	300	South Van Ness Avenue	San Francisco	CA	94103	300 South Van Ness Avenue, San Francisco, CA, 94103	\N	\N	0106000020110F000001000000010300000001000000060000004E1D08F811FE69C1C36A0DD82E5851411E5FA6AE11FE69C1B6BCB8CB27585141467A4EA911FE69C1D14ED74A27585141BA1739AF0DFE69C19464ACF0275851415D8997FD0DFE69C10CA0E27D2F5851414E1D08F811FE69C1C36A0DD82E585141
260973325	building	yes	Standard Deviant	280	14th Street	\N	\N	\N	280 14th Street	\N	\N	0106000020110F00000100000001030000000100000007000000F42E73E124FE69C1FFDDC32839585141D1385DCB24FE69C13FBA94B4365851418B4C319F24FE69C13EF06FDC31585141D41E9AA021FE69C11DD89648325851413B01DCE221FE69C15093D19539585141F792D72022FE69C19F53CE8C39585141F42E73E124FE69C1FFDDC32839585141
260998414	building	apartments	Vincentian Villa	1828	Mission Street	San Francisco	\N	94103	1828 Mission Street, San Francisco, 94103	\N	\N	0106000020110F0000010000000103000000010000001D0000000D9C92D327FE69C1CB7A73D516585141F14378A827FE69C1A99FF49016585141C7AF66A727FE69C14679290616585141EB1EE6C327FE69C172C797D415585141DB23DBB827FE69C147FDC22E15585141DECF039727FE69C11591830C15585141A732BA9727FE69C14F89C2E5145851416D94636026FE69C1449ED21215585141E047606526FE69C19CCEECA31558514135ACB1CE25FE69C1BB208EB915585141B4EF7CCB25FE69C1CD3C875E15585141CB91F25025FE69C1C6AB8D70155851414C4E275425FE69C11CD7ADCA15585141185848CF24FE69C109FF9ADD15585141A5A44BCA24FE69C1DCCD804C15585141CACC138023FE69C1C5545E7B15585141D1B0B99923FE69C1C97CB86D185851410138ABDF24FE69C1D71C8F41185851418E84AEDA24FE69C1228E0CAB17585141191C1A6825FE69C18DAC389717585141623B056C25FE69C1FD84620C18585141752DA1E725FE69C1A2CD42FB1758514166ABFFE225FE69C10E93617A1758514156ED2F7726FE69C1C7F8A66517585141D7A9647A26FE69C1CE78DAF51758514113C124B827FE69C16EED35D71758514176F27FB827FE69C122F28AA6175851410D9C92D327FE69C191B18D66175851410D9C92D327FE69C1CB7A73D516585141
587670476	building	yes	Health Right 360	1735	Mission Street	San Francisco	CA	94103	1735 Mission Street, San Francisco, CA, 94103	\N	\N	0106000020110F0000010000000103000000010000000A0000003B6470E428FE69C105E7595A50585141428902C928FE69C1828AF1545058514100D553D828FE69C1CC6CAE0E4F58514154FC69A227FE69C163A3E6D54E58514196B0189327FE69C1AF61AB2050585141526DEE9C23FE69C187784D644F585141BFB5AE8E23FE69C143CCB27B5058514141AE11F922FE69C1C4F950315D585141C673384028FE69C1BC61DF2B5E5851413B6470E428FE69C105E7595A50585141
112593518	amenity	parking		\N	\N	\N	\N	\N		\N	\N	0106000020110F0000010000000103000000010000000C0000002FCFE38828FE69C1EBA894BE4B58514153521E3A1FFE69C1EB7042CA4C585141C487F3D41EFE69C1092055DA5058514116401C601EFE69C1AF1062F3555851414192345E1DFE69C13590CF6D5A585141123DF5B71AFE69C1393F48DD62585141F3D1A97B1FFE69C1D6D8331D65585141A2DD528920FE69C16F08D39F4E585141AD574C7C27FE69C1D93DBDC44F5851414D18C48827FE69C18ABF8DB44E585141BE1BE78328FE69C1F6A1D0DF4E5851412FCFE38828FE69C1EBA894BE4B585141
\.


--
-- Data for Name: public_transport_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.public_transport_line (osm_id, osm_type, osm_subtype, public_transport, layer, name, ref, operator, network, surface, bus, shelter, bench, lit, wheelchair, wheelchair_desc, geom) FROM stdin;
51052359	railway	subway	other	-2	M-Line	\N	\N	BART	\N	\N	\N	\N	\N	\N	\N	0102000020110F000018000000869A3E674CFF69C1EA64E905CC525141DC9AB19C38FF69C180F06F93E05251417E14F84D21FF69C10A875236FC52514113122B9C00FF69C1F4DCDD6B2F5351417DA8BA19F4FE69C16C2AF1E0455351419306A337DAFE69C14762262A715351418CB932FA73FE69C111BC2D411A545141EEF382955DFE69C1D1B2E76D495451410D17CD384BFE69C14104E090865451411F9CE14D12FE69C1DD8FC187655551419EDE9F1211FE69C1C3D0AC156A5551419244555310FE69C15804EAAA6D5551411B215ED70FFE69C19A402381705551418D1547A70FFE69C14F217503745551412200468D0FFE69C10B393FD179555141938083BA0FFE69C1A1F585897E555141BC5A3FEA0FFE69C10E3E3391825551413411639713FE69C1C6E9947AE3555141698B342216FE69C18D23AF5D265651410089DE0D27FE69C1D3F5E36FE8575141947D59BB27FE69C1FAFC1238FA5751416AA9682729FE69C11F02AF981F5851419066777E2DFE69C19BAFFD9F995851412AC170DB2DFE69C1301E2261B0585141
28049694	railway	subway	other	-2	M-Line	\N	\N	BART	\N	\N	\N	\N	\N	\N	\N	0102000020110F00001B000000EF371F6B2FFE69C18AC31E58B0585141626DF4052FFE69C1475961539958514187085B262CFE69C1E97014C546585141E7002CB32AFE69C143FA91471F58514105BEB75529FE69C14618A117FA575141ACDFEFAD28FE69C1FC9DB73AE85751411042F01526FE69C1A7858843A5575141DF77BB9A17FE69C183C8E15B265651416E6ECD0315FE69C1CFA19783E3555141C14D1F2F11FE69C18953AC72815551417304E4E210FE69C17E2AF930785551411AA9010911FE69C120670B5074555141F092177211FE69C1475B376E7055514196FB063112FE69C10FCD77796C555141FA78D7FB13FE69C192863F28655551412EC51EB048FE69C14B17AE3D96545141E8B7947F4DFE69C1768F375B8354514127D739C952FE69C187F9F57E7154514175582F4B5EFE69C158D037A04A545141BF69675074FE69C1949465451C5451414678CAF4DAFE69C143B46A1B7353514138F2B4BEE6FE69C13B4E8C315F535141B44F80E0F4FE69C14F3E31C947535141C514651A02FF69C1A073DF95315351412AE8232022FF69C1B110D500FE5251412BA3001E39FF69C1EBEDE015E252514174A4F1BF4CFF69C19B8B536DCD525141
654563359	railway	subway	other	-2		\N	\N	BART	\N	\N	\N	\N	\N	\N	\N	0102000020110F00000300000005BEB75529FE69C14618A117FA5751415502353E29FE69C10C2C94180D5851416AA9682729FE69C11F02AF981F585141
654563358	railway	subway	other	-2		\N	\N	BART	\N	\N	\N	\N	\N	\N	\N	0102000020110F000003000000E7002CB32AFE69C143FA91471F5851415502353E29FE69C10C2C94180D585141947D59BB27FE69C1FAFC1238FA575141
\.


--
-- Data for Name: public_transport_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.public_transport_point (osm_id, osm_type, osm_subtype, public_transport, layer, name, ref, operator, network, surface, bus, shelter, bench, lit, wheelchair, wheelchair_desc, geom) FROM stdin;
2208932498	railway	stop	stop_position	0	Glen Park	\N	San Francisco Bay Area Rapid Transit District	BART	\N	\N	\N	\N	\N	\N	\N	0101000020110F00009306A337DAFE69C14762262A71535141
3742505341	railway	stop	stop_position	0	Glen Park	\N	San Francisco Bay Area Rapid Transit District	BART	\N	\N	\N	\N	\N	\N	\N	0101000020110F0000B44F80E0F4FE69C14F3E31C947535141
2208932832	railway	stop	stop_position	0	16th Street Mission	\N	San Francisco Bay Area Rapid Transit District	BART	\N	\N	\N	\N	\N	\N	\N	0101000020110F00001042F01526FE69C1A7858843A5575141
6133371943	railway	switch	other	0		\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020110F000005BEB75529FE69C14618A117FA575141
6133371940	railway	switch	other	0		\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020110F0000947D59BB27FE69C1FAFC1238FA575141
2208932836	railway	stop	stop_position	0	16th Street Mission	\N	San Francisco Bay Area Rapid Transit District	BART	\N	\N	\N	\N	\N	\N	\N	0101000020110F00000089DE0D27FE69C1D3F5E36FE8575141
2208932859	railway	stop	stop_position	0	24th Street Mission	\N	San Francisco Bay Area Rapid Transit District	BART	\N	\N	\N	\N	\N	\N	\N	0101000020110F0000698B342216FE69C18D23AF5D26565141
257073482	railway	stop	stop_position	0	24th Street Mission	\N	San Francisco Bay Area Rapid Transit District	BART	\N	\N	\N	\N	\N	\N	\N	0101000020110F00006E6ECD0315FE69C1CFA19783E3555141
4087600426	bus	yes	stop_position	0	Folsom Street & 16th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000BF4369C4E9FD69C1C1EA127BCE575141
6914180167	bus	yes	stop_position	0	Folsom Street & 14th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000354037A0EDFD69C1E0EA0A4433585141
6384663490	bus	yes	platform	0	Folsom Street & 14th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000EF9F803EEFFD69C1131B0C0E31585141
6914180166	bus	yes	stop_position	0	Folsom Street & 14th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000E53CA682EDFD69C19538593930585141
6384663491	bus	yes	platform	0	Folsom Street & 14th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F000048AEE015ECFD69C1BEFF9F7E33585141
6906659803	bus	yes	stop_position	0	Mission Street & 14th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000773F02BB2AFE69C1E4727C7F34585141
3742505386	bus	yes	platform	0	Mission Street & 14th Street	14;49	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000C1909F5E29FE69C15B77C2B334585141
6133371941	railway	switch	other	0		\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020110F0000E7002CB32AFE69C143FA91471F585141
6906659804	bus	yes	stop_position	0	Mission Street & 14th Street	\N	San Francisco Municipal Railway	Muni	\N	yes	\N	\N	\N	\N	\N	0101000020110F0000A388AB292AFE69C116CB286425585141
6133371942	railway	switch	other	0		\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020110F00006AA9682729FE69C11F02AF981F585141
6133371939	railway	railway_crossing	other	0		\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020110F00005502353E29FE69C10C2C94180D585141
\.


--
-- Data for Name: public_transport_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.public_transport_polygon (osm_id, osm_type, osm_subtype, public_transport, layer, name, ref, operator, network, surface, bus, shelter, bench, lit, wheelchair, wheelchair_desc, geom) FROM stdin;
\.


--
-- Data for Name: road_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.road_line (osm_id, osm_type, name, ref, maxspeed, oneway, layer, tunnel, bridge, major, route_foot, route_cycle, route_motor, access, geom) FROM stdin;
286676859	secondary	Mission Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000003000000B1CC045728FE69C11E7A3130F5575141547F4F7028FE69C168B66FDAF75751417A6CF6F628FE69C1240DA7B605585141
26225306	residential	15th Street	\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F000005000000C2A4E0FE09FE69C1DA65D3CCF9575141CC4F7F590EFE69C196581826F9575141E3D6617614FE69C16817AC3CF8575141646D7A1119FE69C1213F1D82F75751418875F1FA1DFE69C1CEF171BFF6575141
564392699	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000CB9529880EFE69C158485199FC575141CC4F7F590EFE69C196581826F9575141
564435482	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F000002000000072F856104FE69C191263DDCF757514123879F8C04FE69C1F22485A1FA575141
921362450	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000344181D2F9FD69C1F236C47AFA575141BBEBD7B6FAFD69C1737A065DFA57514143CEABD6FBFD69C1FAFC1238FA575141
921360744	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000EC72C9FCFBFD69C18FEB9B8CFE575141735490E4FBFD69C1572F96F2FB57514143CEABD6FBFD69C1FAFC1238FA575141
921360666	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000EC72C9FCFBFD69C18FEB9B8CFE575141AAAFE0E0FAFD69C1AF76DEB7FE575141D2CE3907FAFD69C1295F50D8FE575141
8921264	residential	Shotwell Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000A000000912163EAFCFD69C18646C87C34585141AAAFE0E0FAFD69C1AF76DEB7FE575141CE5F4CC8FAFD69C1A3B7D81DFC575141BBEBD7B6FAFD69C1737A065DFA575141F67EA5EEF9FD69C19B031242E55751416AECF7C4F9FD69C10C3CBBE2E05751410D9A847AF9FD69C15B34AD0BD9575141E2874B0FF9FD69C1EEFB38C3CD57514188AE41CBF8FD69C1DC8A80D6C65751413FD04292F8FD69C19F8FB468C3575141
921361662	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000D2CE3907FAFD69C1295F50D8FE57514190D4E0E7F9FD69C1580E1840FC575141344181D2F9FD69C1F236C47AFA575141
921366466	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000002000000344181D2F9FD69C1F236C47AFA575141092EFE34EDFD69C1FA804475FC575141
706542863	residential	15th Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000A000000E33942E0DEFD69C1150FDD64005851412CD2D3E4E9FD69C1390611B6FE575141FC9764A1EBFD69C1EB0C7972FE5751410382D556EDFD69C10D14E12EFE575141A44DD662EFFD69C1A408ABDEFD57514190D4E0E7F9FD69C1580E1840FC575141CE5F4CC8FAFD69C1A3B7D81DFC575141735490E4FBFD69C1572F96F2FB57514123879F8C04FE69C1F22485A1FA575141C2A4E0FE09FE69C1DA65D3CCF9575141
406720012	tertiary	Folsom Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000006000000BF4369C4E9FD69C1C1EA127BCE575141066354C8E9FD69C17DE79DE3CE575141DFC015D4E9FD69C1AADFA010D0575141591C8A8BEAFD69C1FFF1987EE2575141BF8FDE8EEBFD69C143643EACFC575141FC9764A1EBFD69C1EB0C7972FE575141
921366255	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000092EFE34EDFD69C1FA804475FC5751410382D556EDFD69C10D14E12EFE5751415CE27594EDFD69C1EB25821501585141
921365352	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000CF3E74CFE9FD69C1D3E0B9E7FC575141BF8FDE8EEBFD69C143643EACFC575141092EFE34EDFD69C1FA804475FC575141
594569788	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000030000000ED140E6BBFD69C1F951AE6A0B5851414D4C6563BAFD69C1D0A85FAD0B585141D4AB53B5BAFD69C124DC653312585141
564435430	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000040000001D076D20BAFD69C1622C074912585141D4AB53B5BAFD69C124DC653312585141BF4BD732BCFD69C10FDB6BFC115851410ED140E6BBFD69C1F951AE6A0B585141
564435436	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000006F5E5814C0FD69C1D1B6E235175851411DAAE0B4BFFD69C1C11CAB610B585141
564435432	service		\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F0000050000006F5E5814C0FD69C1D1B6E23517585141709A867BBFFD69C1BE7C08A91C585141AFD97C91BEFD69C123ECDE30235851414209196EBDFD69C18EA7E32527585141F8A73467BCFD69C1F1BB64F229585141
564435441	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000007000000E46EE184BAFD69C1246DED512A585141F8A73467BCFD69C1F1BB64F2295851413DDA0AC2BCFD69C1F3FAAAB1255851419635ED9BBCFD69C129ABBF0E2058514166F0F458BCFD69C1BE43AC881A585141BF4BD732BCFD69C1C6F3A12E185851416F5E5814C0FD69C1D1B6E23517585141
8916415	residential	Treat Avenue	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000C0000005420C419B8FD69C10D6229083D585141199772A9B9FD69C143071DAE3A585141F03F9C47BAFD69C1702C3DA4395851413B9DCF22BCFD69C1F09A8907365851411B26EEAEBDFD69C1680EA775325851413506AC0BBFFD69C1CB7500B42E585141573EBB24C0FD69C175270BEC2A58514162971919C1FD69C177799AE826585141925A39C6C1FD69C126848AAA23585141B39BB76EC2FD69C124D67311205851415653C0EBC2FD69C12EE086A41C585141FDBBAFAAC3FD69C1D0C95EC415585141
564435438	service		\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F000004000000BF4BD732BCFD69C1C6F3A12E18585141617571E2B9FD69C17EA317A1185851412D890E25BAFD69C1349A856C1F585141E46EE184BAFD69C1246DED512A585141
398499281	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000006000000199772A9B9FD69C143071DAE3A58514123367BCCBAFD69C1D589B69E3C585141DB997596BBFD69C174758DD63D5851417D563C77BCFD69C1C7B698833E5851410A262540BDFD69C1E2CDF4AD3E585141F685C92AC0FD69C16ED206523E585141
356310092	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000B8BE2FE3BFFD69C1911CF11E4E585141F685C92AC0FD69C16ED206523E585141
356310093	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000000A262540BDFD69C1E2CDF4AD3E585141E770FBF4BCFD69C1721FA5064D585141
611290713	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000008000000CDDCB262BDFD69C1F73AAEF34D585141E770FBF4BCFD69C1721FA5064D585141E6F2D38ABCFD69C1E7627BBF4B585141E9667F2DBCFD69C182318D484A58514194F8B1FCBBFD69C1475F644A49585141237874CFBBFD69C10C3BE93C485851413A1FA8B8BBFD69C15ABFEF3347585141DB997596BBFD69C174758DD63D585141
356310097	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000050000007053CF14BEFD69C14674808D565851416C20103DBEFD69C1658015B85058514157BAC81EBEFD69C1FE51E0DE4F58514137F771E0BDFD69C16A6B98184F585141CDDCB262BDFD69C1F73AAEF34D585141
133735128	secondary	13th Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000008000000E39B4FB5CEFD69C18ECFC3D3575851417053CF14BEFD69C14674808D565851416E064D12BBFD69C1EFE5D15356585141FC4209AAB8FD69C13FCB32FE555851419F6CA359B6FD69C149B193A855585141C5CBDB12B4FD69C1AF97203F555851415C1FFD9BB1FD69C160F3D2AF545851412A1FA24FB0FD69C11B7FB55E54585141
1049986923	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F00000400000019C24C75B5FD69C16E3D6D5F595851411C474CB3B8FD69C1B67C03E3595851413C4DA92CBBFD69C12B2BD5365A5851417BEE260CC0FD69C1D6D8BC805A585141
418241132	secondary_link		\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F00000C0000003A20F2EAC7FD69C148EBB4F75A58514182869455C9FD69C1A78A98DC5C585141253E9DD2C9FD69C197E0C0915D585141F1104E4ACAFD69C12B98514C5E5851410098ADB2CAFD69C1DA3C7D0A5F5851418FDB411ECBFD69C1031A31DF5F585141F4441A5ACBFD69C1D3FFCD746058514165C55787CBFD69C19F33581D615851417AB2359FCBFD69C166CC34D5615851415310F7AACBFD69C18901ECB262585141C2D120A3CBFD69C194253E9463585141F7BD8360CBFD69C1BA76F34268585141
991915375	tertiary	Harrison Street	\N	40	0	0	\N	\N	t	f	t	t	\N	0102000020110F000009000000F7BD8360CBFD69C1BA76F3426858514190DC4E56CCFD69C1C7F1AF5865585141FCB063A5CCFD69C18085BDD863585141A022C2F3CCFD69C1A870CE6162585141D1E0233DCDFD69C1F20D61EF60585141F60EB78ECDFD69C1D7D72B445F585141B4191CD3CDFD69C1273640D65D585141B3D82F08CEFD69C1B00765955C585141888AC835CEFD69C1C9737A705B585141
8916048	residential	Isis Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000009000000B07408C3DBFD69C18FA389B57F5851419C8837E3DCFD69C1BC5BD9617B585141CFFC3DD2DDFD69C15750316977585141D6EA5FB3DEFD69C100A8304F73585141F27FB57DDFFD69C11EDA6C4E6F585141947D6829E0FD69C115C0EF816B58514181462FB7E0FD69C1D3C95AFF67585141700FF644E1FD69C1C55063406458514186390FFCE1FD69C13AF9A7C05C585141
8916341	residential	Bernice Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000007000000CA9B408CD3FD69C1D022A0AE76585141C207C168D4FD69C116161447735851410D9C6447D5FD69C18362AAB06F5851414B27D027D6FD69C1B59525896B585141C1D61B01D7FD69C1186011F0665851414F1F6ED0D7FD69C18C5F3C3062585141E29A7F77D8FD69C1A7AC3D295C585141
33111467	motorway	Central Freeway	US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F00000F00000044C2159FF8FD69C1649F5A5F5B58514145A85274F5FD69C1BB8B62E85A5851416F30CE3DF2FD69C15CD7D2765A58514148FB6218EFFD69C1B06C30185A5851414CCDA75EEAFD69C14B8EC0B759585141693408CCBFFD69C12993B114575851416A24C168BDFD69C1DDBED3E556585141C13C9D07BBFD69C1053025AC565851413659BCAFB8FD69C199A0A25E565851410F2ECD51B6FD69C108114CFD555851411A35EBDFB3FD69C1DD989C7A555851414B24F290B1FD69C1492203EE54585141D91FC25DAFFD69C1C3AD954D54585141F3679525ADFD69C13D3C5499535851416163D314AAFD69C122BB898552585141
398499279	secondary_link		\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F00000A000000B3F9CA06D4FD69C1E8F02047585851416FC6E773D2FD69C105108EDF555851414760D7E6D1FD69C16B7F6BF35458514185A48B60D1FD69C174F45EFD5358514151EF98A6D0FD69C1B88BA996525851411E3F6450D0FD69C1820C45C851585141BF7387FFCFFD69C14E930CE6505851412F769DC2CFFD69C1BDD4622C50585141CCFE9793CFFD69C1983234654F5851417DFB0676CFFD69C1601AE0C34E585141
515833903	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F000004000000888AC835CEFD69C1C9737A705B585141E29A7F77D8FD69C1A7AC3D295C58514186390FFCE1FD69C13AF9A7C05C5851413D34E722E5FD69C153A5D1EC5C585141
191296171	secondary	13th Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000004000000696D8628EDFD69C1B67C03E359585141246B0B03DEFD69C1B02E8BDE58585141B3F9CA06D4FD69C1E8F0204758585141E39B4FB5CEFD69C18ECFC3D357585141
8917188	residential	Trainor Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000008000000246B0B03DEFD69C1B02E8BDE5858514162784F79DEFD69C1D2679AC55058514145AC89ABDEFD69C1911D8F104D585141B23AF4CBDEFD69C1D3148009495851415E8B3AD0DEFD69C1AA59D74745585141972884CFDEFD69C13EA0BDAE41585141D9DC32C0DEFD69C1C015132D3E585141995B43A7DEFD69C1151CD45539585141
564435470	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000060000000D9C6447D5FD69C13614CEC040585141417D3E05D3FD69C12819E4B640585141946DE4CBD2FD69C11DF283994E58514160C83875D4FD69C1A7227ED8515851415CE0E12FD5FD69C195C4E9E65158514169516C93DCFD69C18601B97A52585141
564435468	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000000D9C6447D5FD69C13614CEC0405851415CE0E12FD5FD69C195C4E9E651585141
356310095	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000007286CBE6C8FD69C1D51BF6B94E585141EDDC813AC9FD69C1A4F471FC3C585141
356310096	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000B09AE730CCFD69C12BDCFB893C5851416451ACE4CBFD69C1CE423CEE4E585141
25821947	tertiary	Harrison Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F00000E000000E39B4FB5CEFD69C18ECFC3D3575851413891B3DFCEFD69C10B15706056585141FBC0AA08CFFD69C1F72171BC545851410697232FCFFD69C16E6F52075358514173258E4FCFFD69C1CE5EBE28515851417DFB0676CFFD69C1601AE0C34E585141CCFE9793CFFD69C1C98EE9A84C585141FE764FAECFFD69C15A6D4E6F4A585141D94D7AC0CFFD69C153872E2848585141779588C6CFFD69C1026FD2C745585141859EC0C4CFFD69C19930477243585141589145BDCFFD69C1D53844334158514161A8AAAECFFD69C1A0FCAC023F585141DD3A8F69CFFD69C1489DDAE63B585141
119237653	motorway	Central Freeway	US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F000006000000BA260854B1FD69C13470FCB558585141075A6E9BB8FD69C1E24991C259585141A3385AFEBAFD69C12C53F7075A585141E7FE69C2BFFD69C1F6A6346A5A5851411E47C350EAFD69C1E2638C015D5851410AF3DC05EFFD69C196F2517A5D585141
458779334	tertiary	Harrison Street	\N	40	0	0	\N	\N	t	f	t	t	\N	0102000020110F000003000000888AC835CEFD69C1C9737A705B58514146952D7ACEFD69C1F4CE318F59585141E39B4FB5CEFD69C18ECFC3D357585141
1049986924	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F0000020000003A20F2EAC7FD69C148EBB4F75A585141888AC835CEFD69C1C9737A705B585141
760623357	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F0000020000007BEE260CC0FD69C1D6D8BC805A5851413A20F2EAC7FD69C148EBB4F75A585141
356310098	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000060000006451ACE4CBFD69C1CE423CEE4E5851417286CBE6C8FD69C1D51BF6B94E5851412F3FF0C4C5FD69C10781E2834E5851416E735DDBC2FD69C1B68850524E585141B8BE2FE3BFFD69C1911CF11E4E585141CDDCB262BDFD69C1F73AAEF34D585141
356310094	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000002F3FF0C4C5FD69C10781E2834E5851416F7FF312C6FD69C1A8DB1D763D585141
356310091	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000006E735DDBC2FD69C1B68850524E58514192288726C3FD69C178644BF43D585141
356310090	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000007000000F685C92AC0FD69C16ED206523E58514192288726C3FD69C178644BF43D5851416F7FF312C6FD69C1A8DB1D763D585141EDDC813AC9FD69C1A4F471FC3C585141B09AE730CCFD69C12BDCFB893C585141BEF4525DCEFD69C1536C2A363C585141DD3A8F69CFFD69C1489DDAE63B585141
513595716	tertiary	Harrison Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000002000000DD3A8F69CFFD69C1489DDAE63B585141D889A827CFFD69C14713FDB936585141
110365012	tertiary	Harrison Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000006000000D889A827CFFD69C14713FDB936585141A1A6B4F9CEFD69C1E22EDE0E335851412691EA70CEFD69C1CBB776D8245851416986852CCEFD69C1916CA5D01D585141FB7EB105CEFD69C1339152D519585141635C35E4CDFD69C129ED625F16585141
25821940	unclassified	Alameda Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000300000062971919C1FD69C177799AE8265851411F2A5F89CDFD69C1D1A383FC245851412691EA70CEFD69C1CBB776D824585141
398499276	residential	Alabama Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000005000000FDBBAFAAC3FD69C1D0C95EC415585141C5DD79E0C3FD69C17F48720E125851411FF86FEFC3FD69C14AF086EA0E585141B3E26ED5C3FD69C160243DDC0B585141DB01C8FBC2FD69C18A4A5136F9575141
8921645	residential	15th Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000A0E1D528CDFD69C12491871D03585141FB7EB105CEFD69C13453ADF702585141292173AED3FD69C15B34F81902585141
779105816	tertiary	Harrison Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000003000000635C35E4CDFD69C129ED625F16585141A0E1D528CDFD69C12491871D0358514130A284C6CCFD69C1139D5A08F9575141
617565057	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000300000000F57618D0FD69C17793A7A4195851413B01AE56CFFD69C16004AEB619585141FB7EB105CEFD69C1339152D519585141
617565053	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F00000200000042F59AD3D1FD69C160CEFF7C1958514100F57618D0FD69C17793A7A419585141
564435471	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000030000006986852CCEFD69C1916CA5D01D5851418AF9F26ED8FD69C194511B961C5851412BF7A51AD9FD69C1C5646B2E1D585141
564435476	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F0000020000007897DF30DDFD69C1D85BA9F0125851418BCEDBA8D1FD69C1B3AE7CB114585141
564435478	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F00000600000093EFF95BDDFD69C1DEB0DDFE1758514142F59AD3D1FD69C160CEFF7C195851418BCEDBA8D1FD69C1B3AE7CB1145851418B0FC873D1FD69C1E4D060C70E58514151B36A3FD1FD69C17BA3CAEA08585141EACCB4CBDCFD69C1D59E6C0A07585141
564435477	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F0000020000009563A5FEDCFD69C12F97D9030D5851418B0FC873D1FD69C1E4D060C70E585141
706542864	residential	15th Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000292173AED3FD69C15B34F8190258514122ABEA95DCFD69C1655216BE00585141E33942E0DEFD69C1150FDD6400585141
564435475	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000200000022ABEA95DCFD69C1655216BE005851419D428DB4DCFD69C1BC71435604585141
617565059	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F0000060000009D428DB4DCFD69C1BC71435604585141EACCB4CBDCFD69C1D59E6C0A075851419563A5FEDCFD69C12F97D9030D5851417897DF30DDFD69C1D85BA9F0125851417E021C44DDFD69C1BE512B341558514193EFF95BDDFD69C1DEB0DDFE17585141
564435474	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000050000002BF7A51AD9FD69C1C5646B2E1D58514159939C27DDFD69C194511B961C585141FB237C04E1FD69C13A9293CF215851416F081E71DEFD69C110022F1C2258514159939C27DDFD69C194511B961C585141
564435473	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000005000000609D5EA9D8FD69C119BB151D225851416AFA6DC9D8FD69C13B3D612B25585141645E8C4EDBFD69C1613AFEA524585141DCBDB131DBFD69C13A9293CF21585141609D5EA9D8FD69C119BB151D22585141
564435472	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000008AF9F26ED8FD69C194511B961C585141609D5EA9D8FD69C119BB151D22585141
564435467	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000001772DD6DD5FD69C177CD49E33A5851410D9C6447D5FD69C13614CEC040585141
26297408	residential	14th Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000700000030940EC2EDFD69C157C5CDC436585141DC98DFFBEBFD69C13FB7015537585141F82CEB93E0FD69C11FACEC0B39585141995B43A7DEFD69C1151CD455395851411772DD6DD5FD69C177CD49E33A585141A69E52A2D0FD69C1BAD5ADB13B585141DD3A8F69CFFD69C1489DDAE63B585141
732858974	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F000003000000F82CEB93E0FD69C11FACEC0B395851410E9332B2E0FD69C15906B4DE3C585141B8B0B9DEE0FD69C1E7B2BC8042585141
617565055	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000200000024D39A62F0FD69C1A9C04D062858514197F36A36EDFD69C1F410355028585141
618375257	tertiary	Folsom Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000005000000E7322ABBECFD69C1EF3126961B58514197F36A36EDFD69C1F410355028585141E53CA682EDFD69C19538593930585141354037A0EDFD69C1E0EA0A443358514130940EC2EDFD69C157C5CDC436585141
617565063	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F0000090000006C90FE9CEAFD69C179B298FF1B5851419EC0F118E8FD69C12F5FF87B1C585141B5C4B16DE2FD69C1C93C9B6C1D585141A2C8992AE1FD69C15914929A1D585141640100E3E0FD69C1E422E1A01D585141BF8FA194E0FD69C12364321E1D58514140051F31DFFD69C1CAECF25819585141B668F53FDEFD69C1C3FB56CD165851417E021C44DDFD69C1BE512B3415585141
513968173	tertiary	Folsom Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000003000000FC9764A1EBFD69C1EB0C7972FE575141914177BCEBFD69C1974CCE5B01585141E7322ABBECFD69C1EF3126961B585141
921364963	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F0000030000007C4ECE08EAFD69C1A769CB9B015851412CD2D3E4E9FD69C1390611B6FE575141CF3E74CFE9FD69C1D3E0B9E7FC575141
921363600	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F0000030000005CE27594EDFD69C1EB25821501585141914177BCEBFD69C1974CCE5B015851417C4ECE08EAFD69C1A769CB9B01585141
564435480	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000A44DD662EFFD69C1A408ABDEFD575141F4C9D086EFFD69C18D2962BB00585141CD279292EFFD69C185EF267D01585141
564435479	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000CD279292EFFD69C185EF267D015851416BB54AC7EFFD69C1EE5F3D8D04585141
617565061	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000E7322ABBECFD69C1EF3126961B585141C5AFB20FEBFD69C10CA410E91B5851416C90FE9CEAFD69C179B298FF1B585141
921366326	footway		\N	\N	0	0	\N	\N	f	t	f	f	\N	0102000020110F000003000000D2CE3907FAFD69C1295F50D8FE575141F4C9D086EFFD69C18D2962BB005851415CE27594EDFD69C1EB25821501585141
564435485	service		\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F00000200000030B5A9C0F3FD69C178B4F83B325851419368DD56F3FD69C19AA0247626585141
564435491	service		\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F0000070000002F1CEFEDF9FD69C163D4384331585141DB67778EF9FD69C1CBA7E68125585141291E86A9F6FD69C1C9C475F3255851419368DD56F3FD69C19AA0247626585141E8437E56F0FD69C10B5E35EC2658514124D39A62F0FD69C1A9C04D0628585141D21A72D7F0FD69C1AA1A49D432585141
564435486	service		\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000D7ECF317F7FD69C1DE5A4A0232585141291E86A9F6FD69C1C9C475F325585141
564435488	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000005F8DCE34F7FD69C19F0BB15835585141D7ECF317F7FD69C1DE5A4A0232585141
1043462454	residential	14th Street	\N	40	1	0	\N	\N	f	t	t	t	\N	0102000020110F000007000000D2D404A3FBFD69C1991E5AAE34585141E150DB0BFAFD69C1F261A3EB345851415F8DCE34F7FD69C19F0BB15835585141E627DEB5F5FD69C1136A5F9235585141E0702CD8F3FD69C1996079DA35585141ACF19CE9F0FD69C1CFF2214B3658514130940EC2EDFD69C157C5CDC436585141
564435489	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000D21A72D7F0FD69C1AA1A49D432585141ACF19CE9F0FD69C1CFF2214B36585141
564435487	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000E0702CD8F3FD69C1996079DA3558514130B5A9C0F3FD69C178B4F83B32585141
564435496	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000E627DEB5F5FD69C1136A5F9235585141E6E6F1EAF5FD69C17B6344FF39585141
564435490	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000E150DB0BFAFD69C1F261A3EB345851412F1CEFEDF9FD69C163D4384331585141
8917285	service	Erie Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000004000000BF13D194EDFD69C131292312535851417A37ECCBEFFD69C1AF5261BD5358514185BC6EBEF8FD69C1D0499B0E51585141661C0AE90BFE69C135697D874E585141
27374665	secondary	13th Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000005000000E98C8C27FFFD69C1B2057B8B5C5851416FA9743EFDFD69C16C50BF2D5C58514194D13CF4FBFD69C178A1C1ED5B585141A9E543ACF8FD69C12ABB7D795B585141C8A78DB2F7FD69C168FDC2645B585141
1039091830	secondary	13th Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000003000000C8A78DB2F7FD69C168FDC2645B585141E85A9D8DF5FD69C158DECB365B585141161CA3CAF3FD69C1565E98EF5A585141
261517390	secondary_link		\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000004000000161CA3CAF3FD69C1565E98EF5A585141B9407F16F1FD69C1D4CC7AB1585851411255AA89EFFD69C1D1FFB28B56585141BF13D194EDFD69C13129231253585141
564435495	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000E6E6F1EAF5FD69C17B6344FF3958514169E0618DF6FD69C18C9C86CA45585141
27029219	tertiary	Folsom Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F00000700000030940EC2EDFD69C157C5CDC436585141610CC6DCEDFD69C15C39603D3C585141A4061FFCEDFD69C17FE6D6AD415851415D609DFEEDFD69C1B9691D9746585141838972ECEDFD69C15EED245E4B58514175C126B9EDFD69C1EE8F5F2350585141BF13D194EDFD69C13129231253585141
1030068318	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F0000020000003D34E722E5FD69C153A5D1EC5C5851411B244BDCECFD69C17202F9585D585141
261517388	tertiary	Folsom Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F000002000000BF13D194EDFD69C13129231253585141696D8628EDFD69C1B67C03E359585141
771471742	secondary	13th Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000002000000161CA3CAF3FD69C1565E98EF5A585141696D8628EDFD69C1B67C03E359585141
458779333	secondary	Folsom Street	\N	40	0	0	\N	\N	t	f	t	t	\N	0102000020110F000002000000696D8628EDFD69C1B67C03E3595851411B244BDCECFD69C17202F9585D585141
458779331	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F0000030000001B244BDCECFD69C17202F9585D5851418DE89B7CF0FD69C11B1B07C65D5851417D3FD1D7F3FD69C1656B87535E585141
397093083	secondary	Folsom Street	\N	40	0	0	\N	\N	t	f	t	t	\N	0102000020110F0000040000001B244BDCECFD69C17202F9585D585141C6B0BF47ECFD69C1646E2A5E63585141E9E203C5EBFD69C16D601EE66758514157AD9C4CEBFD69C11171459A6B585141
771471743	secondary	13th Street	\N	\N	1	0	\N	\N	t	t	t	t	\N	0102000020110F0000070000007D3FD1D7F3FD69C1656B87535E5851418609F1C0FBFD69C1EB6AF205605851414F3293CAFEFD69C1F20D61EF60585141E46ED21602FE69C1257E5E0162585141DBEA995605FE69C13DB0421463585141E68BBCE908FE69C12C8CD560645851410A889D9B0AFE69C14500140C65585141
458780377	service		\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F0000050000007D3FD1D7F3FD69C1656B87535E585141259E44CFF3FD69C18081480B625851416043B0D402FE69C13D618E4668585141BDAC425608FE69C1B1CD3C246A585141DFEECD360AFE69C1952AC7CC6A585141
25337748	motorway_link		US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F0000090000000AF3DC05EFFD69C196F2517A5D5851410C4CF53FF5FD69C13E9AA60860585141DCDFD35CF8FD69C1FD75885B61585141F1193477FBFD69C19A7D8DC862585141D554467DFEFD69C13D967C3F64585141403E609301FE69C11E5072C865585141C147179904FE69C12177A321675851412BB4167D08FE69C141D8CBA8685851410DED4B0D14FE69C1929131086D585141
222603227	motorway	Central Freeway	US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F00001F0000000AF3DC05EFFD69C196F2517A5D58514190AD7A4DF2FD69C1B32699F75D5851413EC4AC5AF5FD69C1ECFD776F5E585141FED5E972F8FD69C13410B3115F585141C5CBCCA4FBFD69C10373C5D05F585141675230BAFEFD69C13BC946A760585141C724E5DE01FE69C1BAB8B8996158514196B8C3FB04FE69C183CE4DA662585141B067DCF008FE69C1BDFBA119645851415EC5C5640DFE69C11F6AC1CE655851417315387E14FE69C1E683F48B68585141B07E382219FE69C13A53C8436A5851414F4FF7911BFE69C147D2CE276B5851410FDE4EDC1DFE69C108901AF76B585141B7C5723D20FE69C164B575AA6C585141A5DAAE9522FE69C1059574336D5851413F4031F224FE69C1F7FC628F6D5851411243FD4D27FE69C19AE3AFD56D5851413132788A2FFE69C1B2C507806E5851417E0DD3CF31FE69C139F36DC56E5851414107672D34FE69C181F662336F585141634EB07136FE69C1A88BCDCA6F585141DC77728938FE69C1B400B19470585141822719AF3AFE69C17E527CA87158514149DB02DE3CFE69C1D325C700735851419E54590E3FFE69C10096F69974585141220EEA1D41FE69C1ACFB9E65765851412219731D43FE69C1B1E7F261785851418DF3520845FE69C123BA708A7A585141CDC0B7EB46FE69C1568EECF27C585141E99706B948FE69C1ADB0A16B7F585141
25371880	primary_link		\N	\N	1	0	\N	\N	t	f	f	t	\N	0102000020110F0000040000000A73D5CE12FE69C1228D91EC635851414346829910FE69C1A369DFEA60585141FB5D07990FFE69C1656B87535E5851414A5CDA520FFE69C1E83E29975D585141
27167746	motorway_link		US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F00000C000000196D109C1CFE69C1C62A7BEA52585141B7F50A6D1CFE69C1E6AE853B55585141F37F69151CFE69C1FB233462575851415FD198961BFE69C121597A8359585141237EAAF11AFE69C10BB6BF5B5B5851417A9C512C1AFE69C19EAB8F0A5D5851418D47364119FE69C1E659F66A5E58514157E15C4518FE69C1BDD142835F585141A0F10D1E17FE69C14A98A751605851416FB0C60616FE69C17CE869C160585141E55489E014FE69C1A369DFEA605851411C32B27213FE69C11E3457D460585141
692910507	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000001B64A10C1DFE69C139B3246B59585141D2C0C3021BFE69C1EBFBB9B857585141
658560948	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000B000000EB6FDCF71EFE69C147AE4D414B585141111B8A7B1EFE69C1D083ABFD4B5851416A766C551EFE69C1C1AA7A914C5851414AEB92521EFE69C1E882AC614D58514174063B4D1EFE69C17B5770634E585141C445FAD11DFE69C12F3EEE53535851412AEB00751DFE69C1AE0DB96F575851411B64A10C1DFE69C139B3246B59585141B6B41EA21CFE69C172B9936F5B5851415B9ED9BE1BFE69C1682B6D0B5E585141FCD6AD991AFE69C19606B6EC5F585141
692910508	motorway_link		US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F000003000000F9A9B95D1CFE69C1871157644E585141A5B913971CFE69C122DA3BDB50585141196D109C1CFE69C1C62A7BEA52585141
385184173	motorway_link		US 101	80	1	0	\N	\N	t	f	f	t	\N	0102000020110F00000A0000002C2CB04512FE69C1D033E14744585141DC2EEAC313FE69C16ADE0A5943585141788AF05815FE69C1C0FCA41343585141422631CD16FE69C1D6D5DE6C435851415176203218FE69C112B8E759445851416D899D6619FE69C1A8A7C8AC455851418B56706C1AFE69C1D87DB76C47585141BD510D551BFE69C12FD5E697495851414E54B5F51BFE69C112B68BEC4B585141F9A9B95D1CFE69C1871157644E585141
198565345	primary	South Van Ness Avenue	\N	40	1	0	\N	\N	t	t	f	t	\N	0102000020110F000005000000371EC90C0DFE69C14EB91704495851417F3DB4100DFE69C19C35306945585141EFFEDD080DFE69C1B6D37ED541585141E7A1CEE80CFE69C126DD111A405851419C04BC7A0CFE69C1EFBEAFA73D585141
8919009	primary	South Van Ness Avenue	\N	40	1	0	\N	\N	t	f	f	t	\N	0102000020110F000003000000D71F2DE40CFE69C169AEB0D651585141FC8EAC000DFE69C1F3F679634D585141371EC90C0DFE69C14EB9170449585141
8915677	motorway_link		US 101	80	1	0	\N	\N	t	f	f	t	\N	0102000020110F000006000000D71F2DE40CFE69C169AEB0D65158514147280E430EFE69C1E0FA015F4C5851419B5AAD0C0FFE69C11897AED049585141F8E95BF60FFE69C1D75E268447585141E384211011FE69C18BF1F7A1455851412C2CB04512FE69C1D033E14744585141
198565347	primary_link		\N	\N	1	0	\N	\N	t	f	f	t	\N	0102000020110F0000050000004A5CDA520FFE69C1E83E29975D585141B3758C980EFE69C1FED265F15A585141B7A38D0C0EFE69C1B8E2F5A358585141791DE08F0DFE69C17CE3551856585141D71F2DE40CFE69C169AEB0D651585141
198565352	trunk	South Van Ness Avenue	US 101	40	1	0	\N	\N	t	f	f	t	\N	0102000020110F000004000000A5E3A3300CFE69C195822F3A6158514106A1538E0CFE69C1FDA7EC905B58514113F035BB0CFE69C1D3491CDA56585141D71F2DE40CFE69C169AEB0D651585141
27225038	primary	South Van Ness Avenue	\N	40	1	0	\N	\N	t	t	f	t	\N	0102000020110F00000C0000009C04BC7A0CFE69C1EFBEAFA73D585141EC89252E0CFE69C1C5D7F251405851412CC56A180CFE69C16B4F5029425851419EFFFD160CFE69C1F568DB9945585141E32C160E0CFE69C1F10D9FD148585141B1B45EF30BFE69C14B5A3A414D585141661C0AE90BFE69C135697D874E585141A6DEE5CC0BFE69C1A111DF8251585141F9CE8B930BFE69C10F0403DB56585141E8146D530BFE69C1036DD2485B5851410C3E42410BFE69C17C7F73305C5851411F348FE80AFE69C18970B2B560585141
198651498	motorway_link		US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F00000C0000001C32B27213FE69C11E3457D46058514187BA51F711FE69C1DFFCE36A6058514129E9A90A10FE69C1DF671DA95F585141AB9A550E0EFE69C186B833CD5E585141459F5DD90BFE69C164802DE95D58514134DAB59909FE69C1BC80AF1B5D5851417E6781A407FE69C1777674795C58514160D11EA205FE69C18E416FDE5B585141E181BD6D02FE69C170AA59165B5851416BC22A31FFFD69C196C615A25A585141BF654EF5FBFD69C1A2C9E9B55A58514144C2159FF8FD69C1649F5A5F5B585141
878214045	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000080000000C3E42410BFE69C17C7F73305C585141A3133C6008FE69C105FAEE505B585141295AF10A01FE69C14FA1679659585141184F9F9CFEFD69C1DC091135595851413DF58EBCFDFD69C1C686447C5958514129C20676FDFD69C16814703A5A5851419126214EFDFD69C14E331F8F5B5851416FA9743EFDFD69C16C50BF2D5C585141
1039091829	secondary	13th Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F0000040000000E6A294508FE69C18306CB995F5851410B680FD505FE69C1A1DD3FA85E5851417239FD7B02FE69C1BD21067D5D585141E98C8C27FFFD69C1B2057B8B5C585141
254759968	residential	14th Street	\N	40	1	0	\N	\N	f	t	t	t	\N	0102000020110F0000040000004CC9AD210CFE69C17715773732585141C384523805FE69C1BF4B893F33585141912163EAFCFD69C18646C87C34585141D2D404A3FBFD69C1991E5AAE34585141
564435492	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000024CEC7F05FE69C179E1A9E038585141C384523805FE69C1BF4B893F33585141
564435493	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000200000016549AFA09FE69C1E8E25F5A38585141024CEC7F05FE69C179E1A9E038585141
564435494	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000002FFDE7530CFE69C1E59C09F93758514116549AFA09FE69C1E8E25F5A38585141
925052345	primary	South Van Ness Avenue	\N	40	0	0	\N	\N	t	t	f	t	\N	0102000020110F000003000000CFBD5F600CFE69C14BDF0DAF39585141AFB91C570CFE69C1F5E97550385851412FFDE7530CFE69C1E59C09F937585141
414156935	primary	South Van Ness Avenue	\N	40	0	0	\N	\N	t	t	f	t	\N	0102000020110F0000020000009C04BC7A0CFE69C1EFBEAFA73D585141CFBD5F600CFE69C14BDF0DAF39585141
564392708	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000685F10240EFE69C140280D66395851415EE095C711FE69C1C0B6E8B938585141D63FBBAA11FE69C1D3907A0835585141
564392707	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000CFBD5F600CFE69C14BDF0DAF39585141685F10240EFE69C140280D6639585141
925052344	primary	South Van Ness Avenue	\N	40	0	0	\N	\N	t	t	f	t	\N	0102000020110F0000070000002FFDE7530CFE69C1E59C09F9375851414CC9AD210CFE69C17715773732585141126785510AFE69C1C7D7D85102585141C2A4E0FE09FE69C1DA65D3CCF9575141E9870BBE09FE69C162062004F3575141BA3D551709FE69C1266EC8BCE2575141E0616CA108FE69C123E4BC3AD5575141
564392701	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000126785510AFE69C1C7D7D8510258514197997F670CFE69C13A4986F901585141
564392703	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000300000097997F670CFE69C13A4986F901585141D76BA2AE0EFE69C1C8DA108701585141CB9529880EFE69C158485199FC575141
8917802	residential	Natoma Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000300000043671D9816FE69C1E6EFCBA2305851419515CA5B15FE69C18D2F49EC0F585141E3D6617614FE69C16817AC3CF8575141
8917498	residential	Minna Street	\N	\N	1	0	\N	\N	f	t	t	t	\N	0102000020110F0000070000001A38BA0820FE69C111B5C8352F585141915AA44C1FFE69C11E7A3E031B5851415977B01E1FFE69C16E22FA1016585141454428D81EFE69C14A21477F0E5851412FDEE0B91EFE69C1E565033A0B5851416D683F621EFE69C1ADC492D4015851418875F1FA1DFE69C1CEF171BFF6575141
564392706	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000D63FBBAA11FE69C1D3907A0835585141C152DD9211FE69C1869F916431585141
254759969	residential	14th Street	\N	40	1	0	\N	\N	f	t	t	t	\N	0102000020110F0000060000003AF1D1792AFE69C11FEB20AA2D5851411A38BA0820FE69C111B5C8352F5851412BAFD20D1EFE69C1C03E64822F58514143671D9816FE69C1E6EFCBA230585141C152DD9211FE69C1869F9164315851414CC9AD210CFE69C17715773732585141
564392704	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000C058E5281EFE69C1AC88692E33585141F2D09C431EFE69C1DE644FC936585141
564392705	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000002BAFD20D1EFE69C1C03E64822F585141C058E5281EFE69C1AC88692E33585141
403152783	secondary	Mission Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F0000070000003AF1D1792AFE69C11FEB20AA2D58514171D4C5A72AFE69C10AF4417932585141773F02BB2AFE69C1E4727C7F34585141D73D9EE32AFE69C1DA29B6BB38585141315D52562BFE69C1AFB4B29B4458514175497E822BFE69C1754F413049585141BA35AAAE2BFE69C1AC1FEC834D585141
658601439	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F00000200000078099FEF2CFE69C17276F5323258514171D4C5A72AFE69C10AF4417932585141
806660464	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F000004000000034A0CB329FE69C128C5932519585141192C61CB27FE69C1D1415B5E195851412900063C20FE69C1E941C9D91A585141915AA44C1FFE69C11E7A3E031B585141
806660465	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F0000040000006930FF2029FE69C16F1ECC0E0A5851413201962827FE69C174249D620A585141EE25819D1FFE69C1AEF674110B5851412FDEE0B91EFE69C1E565033A0B585141
422638702	secondary	Mission Street	\N	\N	0	0	\N	\N	t	f	t	t	\N	0102000020110F0000060000007A6CF6F628FE69C1240DA7B6055851416930FF2029FE69C16F1ECC0E0A585141428EC02C29FE69C1A2C4BA450B585141034A0CB329FE69C128C5932519585141A388AB292AFE69C116CB2864255851413AF1D1792AFE69C11FEB20AA2D585141
721524803	service		\N	\N	0	0	\N	\N	f	f	f	f	private	0102000020110F00000B000000EA8675233AFE69C17FDFD6040B585141FE72460339FE69C1C2A1CD320B5851414BF2E41A37FE69C1A0C9425C0B585141BB67994835FE69C1D044208B0B58514173C5C87634FE69C149694C770B585141B43C3CC833FE69C1041B97990A58514108E7376033FE69C13BDB3A260A585141FBD3839A32FE69C10DC353DC09585141C12F62C72FFE69C1C0B186230A58514119F70A382BFE69C1C89E84F50A585141428EC02C29FE69C1A2C4BA450B585141
706543957	residential	14th Street	\N	40	1	0	\N	\N	f	t	t	t	\N	0102000020110F000007000000F22A79A446FE69C1D4519967295851418ADFD7C43DFE69C141872DBD2A5851415DC2155A3BFE69C1A20E021A2B585141B4011B9935FE69C14B12B8F72B585141803509A82FFE69C1DF1058DF2C58514102A10A7D2DFE69C1A51910342D5851413AF1D1792AFE69C11FEB20AA2D585141
564392713	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000BA35AAAE2BFE69C1AC1FEC834D5851410A28E73028FE69C137A19ABD4D585141
564392710	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000002000000315D52562BFE69C1AFB4B29B44585141BF990EEE28FE69C1B25A2BCE44585141
564392711	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000BF990EEE28FE69C1B25A2BCE4458514126E3586324FE69C1DA55C151455851411D455D7824FE69C15958FA9747585141
564392709	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000020000001D455D7824FE69C15958FA974758514142B4DC9424FE69C1D7A244544A585141
183026362	residential	Erie Street	\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F000003000000EB6FDCF71EFE69C147AE4D414B58514142B4DC9424FE69C1D7A244544A58514175497E822BFE69C1754F413049585141
564392714	service		\N	\N	0	0	\N	\N	f	t	t	t	\N	0102000020110F0000030000000A28E73028FE69C137A19ABD4D585141F21C120E20FE69C1792CE84C4E585141B30903FC1DFE69C1852CE42963585141
397093084	secondary	Mission Street	\N	\N	1	0	\N	\N	t	f	t	t	\N	0102000020110F000005000000015946DE2AFE69C1471CC7C959585141209E75B22AFE69C1A3E23E5F5E5851416977B6872AFE69C1BBF92EDE6258514113907F502AFE69C14127266F675851412AF1080B2AFE69C1AEBE47886A585141
222603229	motorway	Central Freeway	US 101	80	1	1	\N	yes	t	f	f	t	\N	0102000020110F00001C000000972A46C049FE69C1D58D7DDB7C58514181F1F2DD47FE69C1D6A065267A58514176569BE645FE69C1AB84ADA4775851413DAEC8E743FE69C15699A7657558514171D54CD441FE69C129C47F5573585141CA25A6AE3FFE69C1542EEA7671585141F084DE673DFE69C10DBC81CD6F585141CE3D95233BFE69C1F112B2676E58514112A110E638FE69C1135C2F486D585141BD27BAB536FE69C18EAC48756C5851416CE1225D34FE69C126098FD76B585141866AE2EF31FE69C1C299CC676B585141F0F632A02FFE69C1BBFC98206B5851416DD65C6327FE69C1172941766A585141C8E00B0F25FE69C11903DB306A58514106D94ABE22FE69C14718BAD6695851413841BB7520FE69C1DB2E565169585141934B6A211EFE69C1290396A16858514149E978E21BFE69C14741E5D5675851410433B08119FE69C1BB86F1DE66585141D3597ED514FE69C1BE76B4D8645851419767CDC70DFE69C1338A05E06158514110258C4E09FE69C1182BAD1A6058514184C2765405FE69C1590A0AA15E5851414002322C02FE69C1E83E29975D585141B59B6B06FFFD69C1FF9855B15C585141A97870DDFBFD69C184D075F05B58514144C2159FF8FD69C1649F5A5F5B585141
\.


--
-- Data for Name: road_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.road_point (osm_id, osm_type, name, ref, maxspeed, oneway, layer, tunnel, bridge, access, geom) FROM stdin;
65363251	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000B1CC045728FE69C11E7A3130F5575141
8455177957	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000547F4F7028FE69C168B66FDAF7575141
65334190	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000C2A4E0FE09FE69C1DA65D3CCF9575141
3188130246	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F000088AE41CBF8FD69C1DC8A80D6C6575141
8554191671	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000BBEBD7B6FAFD69C1737A065DFA575141
8554180153	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000735490E4FBFD69C1572F96F2FB575141
8554196251	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000AAAFE0E0FAFD69C1AF76DEB7FE575141
8554200447	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F000090D4E0E7F9FD69C1580E1840FC575141
8554218746	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F00000382D556EDFD69C10D14E12EFE575141
8554237523	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000BF8FDE8EEBFD69C143643EACFC575141
65317585	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000FC9764A1EBFD69C1EB0C7972FE575141
8554196286	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F00002CD2D3E4E9FD69C1390611B6FE575141
4186794512	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F00000098ADB2CAFD69C1DA3C7D0A5F585141
4012499528	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F000085A48B60D1FD69C174F45EFD53585141
65317769	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000E39B4FB5CEFD69C18ECFC3D357585141
4547300237	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000888AC835CEFD69C1C9737A705B585141
4904616766	stop		\N	\N	0	0	\N	\N	\N	0101000020110F0000DD3A8F69CFFD69C1489DDAE63B585141
65309810	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F000030940EC2EDFD69C157C5CDC436585141
6384663490	bus_stop	Folsom Street & 14th Street	\N	\N	0	0	\N	\N	\N	0101000020110F0000EF9F803EEFFD69C1131B0C0E31585141
6384663491	bus_stop	Folsom Street & 14th Street	\N	\N	0	0	\N	\N	\N	0101000020110F000048AEE015ECFD69C1BEFF9F7E33585141
8554209058	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000914177BCEBFD69C1974CCE5B01585141
8554227162	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F0000F4C9D086EFFD69C18D2962BB00585141
276545995	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000696D8628EDFD69C1B67C03E359585141
1266060482	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F00001B244BDCECFD69C17202F9585D585141
65284015	motorway_junction		434B-A	\N	0	0	\N	\N	\N	0101000020110F00000AF3DC05EFFD69C196F2517A5D585141
4547308119	stop		\N	\N	0	0	\N	\N	\N	0101000020110F0000BDAC425608FE69C1B1CD3C246A585141
4547308120	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000DFEECD360AFE69C1952AC7CC6A585141
4547300241	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F00000A889D9B0AFE69C14500140C65585141
276546183	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F00001F348FE80AFE69C18970B2B560585141
276546182	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000A5E3A3300CFE69C195822F3A61585141
276546210	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F0000FB5D07990FFE69C1656B87535E585141
2086914134	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F00004A5CDA520FFE69C1E83E29975D585141
65299217	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F00004CC9AD210CFE69C17715773732585141
3742505386	bus_stop	Mission Street & 14th Street	14;49	\N	0	0	\N	\N	\N	0101000020110F0000C1909F5E29FE69C15B77C2B334585141
65309820	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F00003AF1D1792AFE69C11FEB20AA2D585141
65362975	traffic_signals		\N	\N	0	0	\N	\N	\N	0101000020110F00002AF1080B2AFE69C1AEBE47886A585141
4761685559	crossing		\N	\N	0	0	\N	\N	\N	0101000020110F000013907F502AFE69C14127266F67585141
\.


--
-- Data for Name: road_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.road_polygon (osm_id, osm_type, name, ref, maxspeed, layer, tunnel, bridge, major, route_foot, route_cycle, route_motor, access, geom) FROM stdin;
\.


--
-- Data for Name: shop_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.shop_point (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, phone, wheelchair, wheelchair_desc, operator, brand, website, geom) FROM stdin;
5087504022	shop	confectionery	Sixth Course	1544	15th Street	\N	\N	94103	1544 15th Street, 94103	4158292461	\N	\N	\N	\N	http://sixthcourse.com	0101000020110F0000ED49839518FE69C1191EB268FB575141
4631886603	shop	laundry	A Laundromat	\N	\N	\N	\N	\N		\N	\N	\N	\N	\N	\N	0101000020110F0000A159238913FE69C18C897AC5FC575141
281652616	amenity	pub	The Wooden Nickel	1900	Folsom Street	\N	\N	\N	1900 Folsom Street	\N	yes	\N	\N	\N	\N	0101000020110F000030940EC2EDFD69C136AC2600FB575141
4628752984	amenity	cafe		\N	\N	\N	\N	\N		\N	\N	\N	\N	\N	\N	0101000020110F0000375B5014D1FD69C11024501926585141
6028467888	shop	hardware	City Door and Hardware	165	13th Street	\N	\N	\N	165 13th Street	\N	\N	\N	\N	\N	\N	0101000020110F00007943BFFDFDFD69C1C2B225DA55585141
6028467887	shop	car_repair	Folsom Auto Body Center	1728	Folsom Street	\N	\N	\N	1728 Folsom Street	\N	\N	\N	\N	\N	\N	0101000020110F000051C68F39F8FD69C126DC57BD54585141
4631784859	shop	car	Volvo	\N	\N	\N	\N	\N		\N	\N	\N	\N	Volvo	\N	0101000020110F0000555762A909FE69C1B20D67343B585141
4631774686	shop	car_repair	AVS Motors Auto Repair	\N	\N	\N	\N	\N		\N	\N	\N	\N	\N	\N	0101000020110F00004707734408FE69C11313B3D60E585141
4631771784	shop	tyres	Larkins Brothers Tire Shop	\N	\N	\N	\N	\N		\N	\N	\N	\N	\N	https://larkinsbrostire.com/	0101000020110F00003760C20F0EFE69C10EE6565D07585141
3009487838	shop	convenience	New Star Market	269	14th Street	San Francisco	\N	94103	269 14th Street, San Francisco, 94103	(415) 861-0723	\N	\N	\N	\N	\N	0101000020110F0000D592454321FE69C195D258C42B585141
\.


--
-- Data for Name: shop_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.shop_polygon (osm_id, osm_type, osm_subtype, name, housenumber, street, city, state, postcode, address, phone, wheelchair, wheelchair_desc, operator, brand, website, geom) FROM stdin;
25371859	shop	stationery	OfficeMax	1750	Harrison Street	San Francisco	\N	94103	1750 Harrison Street, San Francisco, 94103	\N	\N	\N	\N	OfficeMax	\N	0106000020110F00000100000001030000000100000009000000A17659C4DDFD69C19C191F233F5851417BB48C09D9FD69C1865A27AC3E585141DA7AABF6D8FD69C1A9A646593D585141D938B2F3D7FD69C1D25C24883D58514123D106FED7FD69C1B05104923E585141E8739C91D6FD69C1744EF76D3E58514195BF2432D6FD69C16D1AAAA14D585141EB908664DDFD69C1EC2AD2564E585141A17659C4DDFD69C19C191F233F585141
25821942	shop	electronics	Best Buy	1717	Harrison Street	\N	\N	94103	1717 Harrison Street, 94103	+1 (415) 626-9682	\N	\N	\N	Best Buy	http://stores.bestbuy.com/187/	0106000020110F0000010000000103000000010000000B000000B4145E6FCDFD69C10D58FECA39585141B15EB9C9CCFD69C1285C3FB4285851419D765C1BC2FD69C15E26D4522A585141A84CD541C2FD69C17D1BF64F2E5851419EA80EBBC0FD69C15CE2718B2E585141973CC56FBFFD69C1440FCA8F32585141183BF375C0FD69C181D1D760345851413DE6A0F9BFFD69C1F4180D833558514164516FEAC0FD69C18B47272F37585141E1DAE415C1FD69C12C4F91A93B585141B4145E6FCDFD69C10D58FECA39585141
25821952	shop	supermarket	Foods Co	1800	Folsom Street	\N	\N	\N	1800 Folsom Street	\N	\N	\N	\N	Foods Co	\N	0106000020110F000001000000010300000001000000050000003250BBFDFAFD69C10E55010223585141F4C44F1DFAFD69C102274B1408585141CBA85DF0EDFD69C1900A6DDB095851419293B722EFFD69C18AABF51C255851413250BBFDFAFD69C10E55010223585141
256454796	shop	car_repair	Pak Auto Service	1748	Folsom Street	San Francisco	CA	94103	1748 Folsom Street, San Francisco, CA, 94103	\N	\N	\N	\N	\N	\N	0106000020110F000001000000010300000001000000060000008E8651ADF5FD69C1795134274A5851416C903B97F5FD69C1EDB1CC3448585141271D7971F5FD69C1D13FB44846585141CBF4D2BAEFFD69C1880F4B15475851410C3018A5EFFD69C14F218EAC4B5851418E8651ADF5FD69C1795134274A585141
169204245	shop	supermarket	Rainbow Grocery Coop	1745	Folsom Street	San Francisco	CA	94103	1745 Folsom Street, San Francisco, CA, 94103	+1 415 8630620	yes	\N	\N	\N	https://www.rainbow.coop/	0106000020110F0000010000000103000000010000001200000004FA3125ECFD69C133F8B05A47585141B76F0A0EECFD69C1D1E84FAA3F585141AD9991E7EBFD69C17BB685B13F5851416EB7273DE7FD69C1AD41A60B40585141DE37656AE7FD69C189B3814A465851412757506EE7FD69C1EA23CFD94658514137C9AA0FE5FD69C1A7E4E1C646585141D3974F0FE5FD69C14689AE7F465851415162B105E5FD69C1E03B2CFC4358514173CA584EE2FD69C18CF1FC0644585141D9741D55E2FD69C1C77E6C9D46585141CB1AB228E0FD69C16FC16FA646585141F7A905C6DFFD69C1B46E34805058514120BA61BBE8FD69C1F7BE2340525851419B521112EAFD69C1ED2F6D7D52585141CCCF8690EAFD69C1662E2B9B52585141F864A5C9EBFD69C17D71C0D55258514104FA3125ECFD69C133F8B05A47585141
363054684	shop	car	Audi San Francisco	300	South Van Ness Avenue	San Francisco	CA	94103	300 South Van Ness Avenue, San Francisco, CA, 94103	+1 (888) 896-1405	\N	\N	\N	Audi	http://www.audisanfrancisco.com/	0106000020110F000001000000010300000001000000060000004E1D08F811FE69C1C36A0DD82E5851411E5FA6AE11FE69C1B6BCB8CB27585141467A4EA911FE69C1D14ED74A27585141BA1739AF0DFE69C19464ACF0275851415D8997FD0DFE69C10CA0E27D2F5851414E1D08F811FE69C1C36A0DD82E585141
\.


--
-- Data for Name: tags; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.tags (geom_type, osm_id, tags) FROM stdin;
N	65284015	{"ref": "434B-A", "highway": "motorway_junction", "ref:left": "434B", "ref:right": "434A"}
N	65299217	{"highway": "traffic_signals"}
N	65309810	{"highway": "traffic_signals", "traffic_signals": "signal", "traffic_signals:sound": "yes"}
N	65309820	{"highway": "traffic_signals"}
N	65317585	{"highway": "traffic_signals", "traffic_signals:sound": "yes"}
N	65317769	{"highway": "traffic_signals", "traffic_signals:sound": "yes"}
N	65334190	{"highway": "traffic_signals"}
N	65362975	{"highway": "traffic_signals", "traffic_signals": "signal"}
N	65363251	{"highway": "traffic_signals"}
N	257073482	{"name": "24th Street Mission", "subway": "yes", "network": "BART", "railway": "stop", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "24TH", "public_transport": "stop_position"}
N	276545995	{"highway": "traffic_signals", "traffic_signals": "signal", "traffic_signals:sound": "yes"}
N	276546182	{"highway": "traffic_signals", "traffic_signals": "signal"}
N	276546183	{"highway": "traffic_signals", "traffic_signals": "signal"}
N	276546210	{"highway": "traffic_signals", "traffic_signals": "signal", "traffic_signals:direction": "forward"}
N	281652606	{"amenity": "post_box"}
N	281652616	{"name": "The Wooden Nickel", "amenity": "pub", "wheelchair": "yes", "addr:street": "Folsom Street", "addr:housenumber": "1900", "toilets:wheelchair": "no"}
N	300517501	{"traffic_calming": "island"}
N	368168766	{"ele": "7", "name": "Far West Library for Educational Research and Development", "amenity": "library", "addr:state": "CA", "gnis:reviewed": "no", "gnis:feature_id": "1655376", "gnis:county_name": "San Francisco", "gnis:import_uuid": "57871b70-0100-4405-bb30-88b2e001a944"}
N	420508633	{"amenity": "post_box", "capacity": "1", "operator": "United States Postal Service", "short_name": "USPS", "operator:type": "public", "operator:wikidata": "Q668687", "operator:wikipedia": "en:United States Postal Service"}
N	1209228821	{"addr:street": "Erie Street", "addr:housenumber": "165"}
N	1243846554	{"name": "Nihon", "amenity": "bar", "addr:street": "Folsom Street", "addr:postcode": "94103", "addr:housenumber": "1779"}
N	1266060482	{"highway": "traffic_signals", "traffic_signals": "signal"}
N	1409407314	{"ref": "82", "name": "15th & Folsom (UCSF)", "amenity": "car_sharing", "website": "http://www.citycarshare.org/", "operator": "City CarShare", "source:pkey": "82"}
N	1803661677	{"name": "Chez Spencer", "amenity": "restaurant", "cuisine": "french", "website": "http://chezspencer.net/", "addr:street": "14th St, San Francisco ", "addr:postcode": "94103", "addr:housenumber": "82 "}
N	2000101334	{"amenity": "post_box", "operator": "United States Postal Service", "short_name": "USPS", "operator:type": "public", "operator:wikidata": "Q668687", "operator:wikipedia": "en:United States Postal Service"}
N	2049063016	{"amenity": "post_box", "operator": "United States Postal Service", "short_name": "USPS", "operator:type": "public", "collection_times": "Mo-Fr 16:30; Sa 09:45", "operator:wikidata": "Q668687", "operator:wikipedia": "en:United States Postal Service"}
N	2086914134	{"highway": "crossing", "crossing": "traffic_signals", "tactile_paving": "yes", "button_operated": "no", "traffic_signals:sound": "no", "traffic_signals:vibration": "no"}
N	2208932498	{"name": "Glen Park", "subway": "yes", "network": "BART", "railway": "stop", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "GLEN", "public_transport": "stop_position"}
N	2208932832	{"name": "16th Street Mission", "subway": "yes", "network": "BART", "railway": "stop", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "16TH", "public_transport": "stop_position"}
N	2208932836	{"name": "16th Street Mission", "subway": "yes", "network": "BART", "railway": "stop", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "16TH", "public_transport": "stop_position"}
N	2208932859	{"name": "24th Street Mission", "subway": "yes", "network": "BART", "railway": "stop", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "24TH", "public_transport": "stop_position"}
N	2411576667	{"name": "Mission Public SF", "amenity": "restaurant", "website": "http://missionpublicsf.com", "addr:city": "San Francisco", "addr:street": "14th Street", "addr:postcode": "94103", "addr:housenumber": "233"}
N	3009487838	{"name": "New Star Market", "shop": "convenience", "phone": "(415) 861-0723", "addr:city": "San Francisco", "addr:street": "14th Street", "addr:postcode": "94103", "opening_hours": "Mo-Sa 07:00-20:30; Su 08:30-17:00", "addr:housenumber": "269"}
N	3051467912	{"traffic_calming": "island"}
N	3188130246	{"highway": "crossing", "crossing": "marked", "crossing:island": "no"}
N	3345049955	{"ref": "332", "name": "14th & Mission (on-street)", "amenity": "car_sharing", "website": "http://www.citycarshare.org/", "operator": "City CarShare", "source:pkey": "332"}
N	3742505341	{"name": "Glen Park", "subway": "yes", "network": "BART", "railway": "stop", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "GLEN", "public_transport": "stop_position"}
N	3742505386	{"bus": "yes", "name": "Mission Street & 14th Street", "highway": "bus_stop", "network": "Muni", "operator": "San Francisco Municipal Railway", "route_ref": "14;49", "trolleybus": "yes", "public_transport": "platform"}
N	3940887840	{"name": "Animal Care & Control", "amenity": "animal_shelter", "website": "http://www.animalshelter.sfgov.org", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "15th Street", "addr:postcode": "94103", "animal_shelter": "dog;cat;rabbit;bird", "addr:housenumber": "1200", "animal_shelter:adoption": "yes"}
N	3940894710	{"name": "San Francisco SPCA Veterinary Hospital - Mission Campus", "amenity": "veterinary", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "Alabama Street", "addr:postcode": "94103", "addr:housenumber": "201"}
N	4012499528	{"highway": "crossing", "crossing": "marked", "tactile_paving": "yes"}
N	4013644509	{"name": "Walzwerk", "amenity": "restaurant"}
N	4087600426	{"bus": "yes", "name": "Folsom Street & 16th Street", "network": "Muni", "operator": "San Francisco Municipal Railway", "public_transport": "stop_position"}
N	4186794512	{"highway": "crossing", "crossing": "marked", "tactile_paving": "yes"}
N	4270584674	{"name": "10th Planet Jiu Jitsu - San Francisco", "sport": "jiu-jitsu", "leisure": "sports_centre", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "South Van Ness Avenue", "addr:postcode": "94103", "opening_hours": "07:30-20:30", "addr:housenumber": "261"}
N	4307902891	{"name": "Doña Margo", "amenity": "restaurant"}
N	4516187333	{"name": "The Armory Club", "amenity": "bar"}
N	4547300237	{"highway": "traffic_signals"}
N	4547300241	{"highway": "traffic_signals", "traffic_signals": "signal"}
N	4547308119	{"stop": "minor", "highway": "stop", "direction": "forward"}
N	4547308120	{"highway": "traffic_signals", "traffic_signals": "signal"}
N	4628752984	{"amenity": "cafe"}
N	4631771784	{"name": "Larkins Brothers Tire Shop", "shop": "tyres", "website": "https://larkinsbrostire.com/"}
N	4631774686	{"name": "AVS Motors Auto Repair", "shop": "car_repair"}
N	4631784859	{"name": "Volvo", "shop": "car", "brand": "Volvo", "brand:wikidata": "Q215293", "brand:wikipedia": "en:Volvo Cars"}
N	4631886603	{"name": "A Laundromat", "shop": "laundry"}
N	4761685550	{"traffic_calming": "hump"}
N	4761685551	{"traffic_calming": "hump"}
N	4761685559	{"highway": "crossing", "crossing": "unmarked"}
N	4904616766	{"stop": "all", "highway": "stop", "direction": "both"}
N	5087504022	{"name": "Sixth Course", "shop": "confectionery", "phone": "4158292461", "name:en": "Sixth Course", "website": "http://sixthcourse.com", "addr:street": "15th Street", "addr:postcode": "94103", "opening_hours": "Tu-Sa 14:00-22:00", "addr:housenumber": "1544"}
N	5089298921	{"name": "Pink Onion", "phone": "4155292635", "amenity": "restaurant", "cuisine": "italian_pizza", "website": "https://www.pinkonionpizza.com/", "addr:postcode": "94103", "opening_hours": "Tu-Su 11:00-22:00"}
N	5747580158	{"emergency": "fire_alarm_box"}
N	5757635621	{"name": "Rintaro", "amenity": "restaurant", "cuisine": "japanese"}
N	5837767007	{"access": "private", "barrier": "gate"}
N	5837767008	{"access": "private", "barrier": "gate"}
N	5837767018	{"access": "no", "barrier": "gate"}
N	6028467887	{"name": "Folsom Auto Body Center", "shop": "car_repair", "addr:street": "Folsom Street", "addr:housenumber": "1728"}
N	6028467888	{"name": "City Door and Hardware", "shop": "hardware", "addr:street": "13th Street", "addr:housenumber": "165"}
N	6133371939	{"railway": "railway_crossing"}
N	6133371940	{"railway": "switch"}
N	6133371941	{"railway": "switch"}
N	6133371942	{"railway": "switch"}
N	6133371943	{"railway": "switch"}
N	6384663490	{"bus": "yes", "name": "Folsom Street & 14th Street", "highway": "bus_stop", "network": "Muni", "operator": "San Francisco Municipal Railway", "network:wikidata": "Q1140138", "public_transport": "platform", "network:wikipedia": "en:San Francisco Municipal Railway"}
N	6384663491	{"bus": "yes", "name": "Folsom Street & 14th Street", "highway": "bus_stop", "network": "Muni", "operator": "San Francisco Municipal Railway", "network:wikidata": "Q1140138", "public_transport": "platform", "network:wikipedia": "en:San Francisco Municipal Railway"}
N	6441756875	{"name": "Lee Woodward Counseling Center for Women", "phone": "+1 (415) 776-1001", "website": "http://www.healthright360.org/program/lee-woodward-counseling-center-women-lwcc", "addr:city": "San Francisco", "addr:state": "CA", "healthcare": "clinic", "addr:street": "Mission Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1735"}
N	6441756876	{"name": "Lyon-Martin Health Services", "phone": "+1 (415) 565-7667", "website": "http://lyon-martin.org", "addr:city": "San Francisco", "addr:state": "CA", "healthcare": "clinic", "addr:street": "Mission Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1735"}
N	6441756877	{"name": "Women's Community Clinic", "phone": "+1 (415) 379-7800", "website": "http://womenscommunityclinic.org", "addr:city": "San Francisco", "addr:state": "CA", "healthcare": "clinic", "addr:street": "Mission Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1735"}
N	6459941675	{"barrier": "gate"}
N	6768689457	{"barrier": "gate"}
N	6768689465	{"barrier": "gate"}
N	6862532114	{"barrier": "gate"}
N	6906659803	{"bus": "yes", "name": "Mission Street & 14th Street", "network": "Muni", "operator": "San Francisco Municipal Railway", "trolleybus": "yes", "public_transport": "stop_position"}
N	6906659804	{"bus": "yes", "name": "Mission Street & 14th Street", "network": "Muni", "operator": "San Francisco Municipal Railway", "trolleybus": "yes", "public_transport": "stop_position"}
N	6914180166	{"bus": "yes", "name": "Folsom Street & 14th Street", "network": "Muni", "operator": "San Francisco Municipal Railway", "public_transport": "stop_position"}
N	6914180167	{"bus": "yes", "name": "Folsom Street & 14th Street", "network": "Muni", "operator": "San Francisco Municipal Railway", "public_transport": "stop_position"}
N	7543166923	{"barrier": "gate"}
N	7543166924	{"barrier": "gate"}
N	8455177957	{"highway": "crossing", "crossing": "marked"}
N	8554180153	{"highway": "crossing", "crossing": "unmarked", "crossing:island": "no"}
N	8554191671	{"highway": "crossing", "crossing": "unmarked", "crossing:island": "no"}
N	8554196251	{"highway": "crossing", "crossing": "unmarked", "crossing:island": "no"}
N	8554196286	{"highway": "crossing", "crossing": "marked", "crossing:island": "no"}
N	8554200447	{"highway": "crossing", "crossing": "unmarked"}
N	8554209056	{"kerb": "lowered", "barrier": "kerb", "tactile_paving": "yes"}
N	8554209058	{"highway": "crossing", "crossing": "marked", "crossing:island": "no"}
N	8554218746	{"highway": "crossing", "crossing": "marked", "crossing:island": "no"}
N	8554227162	{"highway": "crossing", "crossing": "unmarked", "tactile_paving": "no"}
N	8554237523	{"highway": "crossing", "crossing": "marked", "crossing:island": "no"}
R	8549304	{"type": "restriction", "restriction": "no_right_turn"}
N	8889609060	{"power": "generator", "generator:type": "solar_photovoltaic_panel", "generator:method": "photovoltaic", "generator:source": "solar", "generator:output:electricity": "yes"}
N	9419035930	{"natural": "tree"}
N	9419035931	{"amenity": "bicycle_parking", "capacity": "4", "bicycle_parking": "stands"}
W	8915677	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "2", "oneway": "yes", "bicycle": "no", "highway": "motorway_link", "surface": "asphalt", "maxspeed": "50 mph", "tiger:cfcc": "A41", "turn:lanes": "through|through", "destination": "Oakland;San Jose", "tiger:county": "San Francisco, CA", "destination:ref": "US 101 South;I 80 East"}
W	8916048	{"name": "Isis Street", "highway": "residential", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "Isis", "tiger:name_type": "St"}
W	8916341	{"name": "Bernice Street", "highway": "residential", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "Bernice", "tiger:name_type": "St"}
W	8916415	{"name": "Treat Avenue", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "Treat", "tiger:name_type": "Ave", "name:etymology:wikidata": "Q18228005"}
W	8917188	{"name": "Trainor Street", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_base": "Trainor", "tiger:name_type": "St"}
W	8917285	{"name": "Erie Street", "highway": "service", "service": "alley", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_base": "Erie", "tiger:name_type": "St"}
W	8917498	{"name": "Minna Street", "oneway": "yes", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_base": "Minna", "tiger:name_type": "St"}
W	8917802	{"name": "Natoma Street", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "Natoma", "tiger:name_type": "St"}
W	8919009	{"name": "South Van Ness Avenue", "lanes": "2", "oneway": "yes", "highway": "primary", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "no", "tiger:cfcc": "A25;A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:reviewed": "no", "tiger:name_base": "Van Ness", "tiger:name_type": "Ave", "tiger:name_base_1": "United States Highway 101", "name:etymology:wikidata": "Q6144602", "tiger:name_direction_prefix": "S"}
W	8921264	{"foot": "yes", "name": "Shotwell Street", "bicycle": "yes", "highway": "residential", "surface": "asphalt", "cycleway": "shared_lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "motor_vehicle": "destination", "tiger:name_type": "St"}
W	8921645	{"name": "15th Street", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "15th", "tiger:name_type": "St"}
W	25337748	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "2", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway_link", "surface": "concrete", "maxspeed": "50 mph", "tiger:cfcc": "A25", "turn:lanes": "through|through", "destination": "Duboce Avenue;Golden Gate Bridge;Mission Street", "junction:ref": "434A", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "destination:ref": "US 101 North", "tiger:name_base": "United States Highway 101", "destination:lanes": "Duboce Avenue|Golden Gate Bridge;Mission Street", "tiger:name_base_1": "13th", "tiger:name_type_1": "St", "destination:street": "Duboce Avenue;Mission Street", "destination:ref:lanes": "|US 101 North"}
W	25371853	{"height": "13", "building": "transportation", "building:levels": "3"}
W	25371859	{"name": "OfficeMax", "shop": "stationery", "brand": "OfficeMax", "height": "7", "building": "yes", "addr:city": "San Francisco", "addr:street": "Harrison Street", "addr:postcode": "94103", "brand:wikidata": "Q7079111", "brand:wikipedia": "en:OfficeMax", "addr:housenumber": "1750"}
W	25371880	{"lanes": "2", "oneway": "yes", "highway": "primary_link", "sidewalk": "right", "destination": "South Van Ness Avenue"}
W	25821940	{"name": "Alameda Street", "highway": "unclassified", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "Alameda", "tiger:name_type": "St"}
W	25821942	{"ref": "187", "name": "Best Buy", "shop": "electronics", "brand": "Best Buy", "phone": "+1 (415) 626-9682", "height": "8", "website": "http://stores.bestbuy.com/187/", "building": "yes", "addr:street": "Harrison Street", "addr:postcode": "94103", "opening_hours": "Mo-Th 10:00-21:00; Fr 10:00-21:00; Sa 10:00-21:00; Su 11:00-20:00", "brand:wikidata": "Q533415", "brand:wikipedia": "en:Best Buy", "addr:housenumber": "1717"}
W	25821947	{"name": "Harrison Street", "highway": "tertiary", "lcn_ref": "25;36", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_type": "St"}
W	25821948	{"access": "private", "amenity": "parking", "parking": "surface"}
W	25821952	{"name": "Foods Co", "shop": "supermarket", "brand": "Foods Co", "building": "retail", "addr:street": "Folsom Street", "opening_hours": "06:00-01:00", "brand:wikidata": "Q5465282", "brand:wikipedia": "en:Food 4 Less", "addr:housenumber": "1800"}
W	26225306	{"name": "15th Street", "lanes": "1", "oneway": "yes", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:reviewed": "no", "tiger:name_type": "St"}
W	26297408	{"name": "14th Street", "oneway": "no", "highway": "residential", "lcn_ref": "36", "cycleway": "shared_lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "14th", "tiger:name_type": "St"}
W	27029219	{"lit": "yes", "name": "Folsom Street", "lanes": "3", "bicycle": "yes", "highway": "tertiary", "lcn_ref": "30", "surface": "asphalt", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "lanes:forward": "2", "lanes:backward": "1", "tiger:name_type": "St", "name:etymology:wikidata": "Q3185252"}
W	27167746	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "1", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway_link", "surface": "concrete", "maxspeed": "50 mph", "tiger:cfcc": "A41", "destination": "Oakland;San Jose", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "destination:ref": "US 101 South;I 80 East"}
W	256458253	{"height": "6", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "351;353"}
W	27225038	{"foot": "yes", "name": "South Van Ness Avenue", "lanes": "2", "oneway": "yes", "highway": "primary", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "right", "tiger:cfcc": "A45", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:reviewed": "no", "tiger:name_base": "South Van Ness", "tiger:name_type": "Ave", "name:etymology:wikidata": "Q6144602"}
W	27374665	{"name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "tiger:cfcc": "A41", "turn:lanes": "none|none|right", "tiger:county": "San Francisco, CA", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	28049694	{"name": "M-Line", "gauge": "1676", "layer": "-2", "level": "-2", "owner": "San Francisco Bay Area Rapid Transit District", "tunnel": "yes", "network": "BART", "railway": "subway", "voltage": "1000", "frequency": "0", "electrified": "rail", "railway:preferred_direction": "forward"}
W	33111467	{"NHS": "STRAHNET", "ref": "US 101", "foot": "no", "lanes": "3", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway", "surface": "concrete", "maxspeed": "50 mph", "old_name": "Central Freeway", "wikidata": "Q564339", "tiger:cfcc": "A25:A63;A41;A25", "tiger:county": "San Francisco, CA:San Francisco, CA;San Francisco, CA;San Francisco, CA", "tiger:name_base": "United States Highway 101", "tiger:name_base_1": "13th:Central", "tiger:name_type_1": "Fwy:St"}
W	51052359	{"name": "M-Line", "gauge": "1676", "layer": "-2", "level": "-2", "owner": "San Francisco Bay Area Rapid Transit District", "tunnel": "yes", "network": "BART", "railway": "subway", "voltage": "1000", "frequency": "0", "electrified": "rail", "railway:preferred_direction": "forward"}
W	104597417	{"fee": "no", "access": "customers", "amenity": "parking", "parking": "surface", "emergency": "assembly_point"}
W	110365012	{"name": "Harrison Street", "highway": "tertiary", "lcn_ref": "25", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_type": "St"}
W	112593518	{"amenity": "parking", "parking": "surface"}
W	119237653	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "3", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway", "surface": "concrete", "maxspeed": "50 mph", "old_name": "Central Freeway", "wikidata": "Q564339", "tiger:cfcc": "A41;A25:A63", "turn:lanes": "none|through;slight_right|slight_right", "tiger:county": "San Francisco, CA:San Francisco, CA;San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "United States Highway 101", "destination:lanes": "Octavia Boulevard;Fell Street|Octavia Boulevard;Fell Street;Duboce Avenue|Golden Gate Bridge;Mission Street", "tiger:name_base_1": "13th", "tiger:name_type_1": "St"}
W	132605458	{"fee": "yes", "access": "customers", "amenity": "parking", "parking": "surface", "operator": "OfficeMax"}
W	132605486	{"building": "yes"}
W	132605487	{"fee": "no", "name": "Best Buy Parking", "access": "customers", "amenity": "parking", "parking": "surface"}
W	132605488	{"height": "14", "building": "yes"}
W	132605501	{"amenity": "parking", "parking": "surface"}
W	132605510	{"access": "private", "amenity": "parking", "parking": "multi-storey", "building": "parking"}
W	132605518	{"fee": "no", "access": "customers", "amenity": "parking", "parking": "surface"}
W	133735128	{"name": "13th Street", "lanes": "2", "oneway": "yes", "highway": "secondary", "lcn_ref": "36", "surface": "asphalt", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "track", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	169204244	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "82"}
W	169204245	{"name": "Rainbow Grocery Coop", "note": "HOLIDAYS:( CLOSED ON ) New Year’s Day (January 1st) Martin Luther King Day (3rd Monday in January) Cesar Chavez Day (March 31st) May Day (May 1st) Gay Pride Day (Last Sunday in June) Labor Day (1st Monday in September) Thanksgiving (4th Thursday", "shop": "supermarket", "email": "general@rainbow.coop", "image": "https://upload.wikimedia.org/wikipedia/en/4/46/Rainbow_grocery_logo.png", "phone": "+1 415 8630620", "website": "https://www.rainbow.coop/", "building": "hall", "wikidata": "Q7284643", "addr:city": "San Francisco", "wikipedia": "en:Rainbow Grocery Cooperative", "addr:state": "CA", "wheelchair": "yes", "addr:street": "Folsom Street", "cooperative": "yes", "addr:country": "US", "addr:postcode": "94103", "opening_hours": "Mo-Su 09:00-21:00", "addr:housenumber": "1745"}
W	183026362	{"name": "Erie Street", "oneway": "no", "highway": "residential", "surface": "paved", "sidewalk": "left"}
W	191296171	{"name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	197048563	{"landuse": "retail", "emergency": "assembly point"}
W	198565345	{"foot": "yes", "name": "South Van Ness Avenue", "lanes": "2", "oneway": "yes", "highway": "primary", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "right", "tiger:cfcc": "A25;A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:reviewed": "no", "tiger:name_base": "Van Ness", "tiger:name_type": "Ave", "tiger:name_base_1": "United States Highway 101", "name:etymology:wikidata": "Q6144602", "tiger:name_direction_prefix": "S"}
W	198565347	{"lanes": "2", "oneway": "yes", "highway": "primary_link", "sidewalk": "no", "turn:lanes": "through;right|right", "destination": "South Van Ness Avenue"}
W	198565352	{"NHS": "STRAHNET", "ref": "US 101", "name": "South Van Ness Avenue", "lanes": "3", "oneway": "yes", "highway": "trunk", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "no", "tiger:cfcc": "A25;A41", "turn:lanes": "|through;right|right", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:name_base": "Van Ness", "tiger:name_type": "Ave", "tiger:name_base_1": "United States Highway 101", "name:etymology:wikidata": "Q6144602", "tiger:name_direction_prefix": "S"}
W	198651498	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "1", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway_link", "surface": "concrete", "maxspeed": "50 mph", "tiger:cfcc": "A41", "destination": "Oakland;San Jose", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "destination:ref": "US 101 South;I 80 East"}
W	222603227	{"ref": "US 101", "lanes": "2", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway", "surface": "concrete", "maxspeed": "50 mph", "old_name": "Central Freeway", "wikidata": "Q564339", "tiger:cfcc": "A63;A41;A25", "junction:ref": "434B", "tiger:county": "San Francisco, CA;San Francisco, CA;San Francisco, CA", "unsigned_ref": "US 101", "tiger:name_base": "United States Highway 101", "tiger:name_base_1": "13th", "tiger:name_type_1": "St", "destination:street": "Octavia Boulevard;Fell Street"}
W	222603229	{"ref": "US 101", "lanes": "2", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway", "surface": "concrete", "maxspeed": "50 mph", "old_name": "Central Freeway", "wikidata": "Q564339", "tiger:cfcc": "A63;A41;A25", "tiger:county": "San Francisco, CA;San Francisco, CA;San Francisco, CA", "tiger:name_base": "United States Highway 101", "tiger:name_base_1": "13th", "tiger:name_type_1": "St"}
W	254759968	{"name": "14th Street", "lanes": "2", "oneway": "yes", "highway": "residential", "lcn_ref": "30", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "turn:lanes": "left|none", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:name_type": "St", "bicycle:designated": "greenwave"}
W	254759969	{"lit": "yes", "name": "14th Street", "lanes": "2", "oneway": "yes", "highway": "residential", "lcn_ref": "30", "surface": "asphalt", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "cycleway:right": "lane", "tiger:name_type": "St", "bicycle:designated": "greenwave"}
W	256454778	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "174"}
W	256454781	{"height": "10", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "257;259;261"}
W	256454784	{"building": "yes"}
W	256454788	{"building": "yes", "building:levels": "3"}
W	256454792	{"building": "yes"}
W	256454796	{"name": "Pak Auto Service", "shop": "car_repair", "height": "8", "building": "yes", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "Folsom Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1748"}
W	256454797	{"height": "6", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "164"}
W	256454800	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "160;162"}
W	256454803	{"height": "7", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "269"}
W	256454804	{"height": "13", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "251"}
W	256454807	{"height": "12", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "263;265;267"}
W	256454808	{"building": "yes", "addr:street": "13th Street", "addr:housenumber": "157"}
W	256454809	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "285"}
W	256454810	{"height": "6", "building": "yes"}
W	256454811	{"height": "5", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "275"}
W	256458215	{"height": "12", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "359;363"}
W	256458216	{"height": "7", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1454;1456;1458;1460;1462;1464;1466;1468"}
W	256458217	{"height": "12", "building": "yes"}
W	256458218	{"height": "7", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "74;76"}
W	256458219	{"height": "10", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "28;30"}
W	256458221	{"height": "11", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "371;373;375"}
W	256458222	{"height": "12", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "387;389;391"}
W	256458224	{"height": "10", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "349"}
W	256458226	{"height": "8", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "383;385"}
W	256458227	{"height": "11", "building": "yes"}
W	256458229	{"height": "7", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "48;50"}
W	256458230	{"height": "11", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "62;64;66"}
W	256458231	{"height": "10", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "42;44"}
W	256458232	{"height": "10", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "58;60"}
W	256458233	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "335"}
W	256458234	{"height": "4", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "321"}
W	256458235	{"height": "12", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1474;1476;1478;1480"}
W	256458236	{"height": "9", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "22;24"}
W	256458237	{"height": "7", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "171;173"}
W	256458238	{"height": "5", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "36;40"}
W	256458239	{"height": "7", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "52;54"}
W	256458240	{"height": "6", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "32"}
W	256458242	{"height": "7", "building": "yes"}
W	256458243	{"height": "12", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "377;379;381"}
W	256458244	{"height": "12", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "395"}
W	256458245	{"height": "9", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1470;1472"}
W	256458246	{"building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "68"}
W	256458247	{"height": "5", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "315"}
W	256458248	{"height": "6", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "365"}
W	256458249	{"height": "9", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "177"}
W	256458250	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "341"}
W	256458251	{"building": "yes"}
W	256458252	{"height": "8", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "333"}
W	651669421	{"building": "yes"}
W	256458254	{"height": "8", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "159;165"}
W	256472200	{"building": "yes"}
W	256472207	{"height": "10", "building": "yes"}
W	256472212	{"height": "8", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "41"}
W	256851470	{"building": "yes", "addr:street": "15th Street", "addr:housenumber": "1405;1407;1409;1411;1413;1415"}
W	256851477	{"height": "11", "building": "mixd_use", "addr:street": "Folsom Street", "addr:housenumber": "1900;1902"}
W	256851488	{"height": "9", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1417;1419"}
W	260973315	{"name": "Public Works", "height": "7", "amenity": "nightclub", "website": "https://publicsf.com/", "building": "yes", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "Erie Street", "addr:postcode": "94103", "contact:twitter": "publicworkssf", "addr:housenumber": "161", "contact:facebook": "PublicWorksSF", "contact:instagram": "publicworkssf"}
W	260973316	{"height": "11", "building": "yes", "addr:street": "Mission Street", "addr:housenumber": "1799"}
W	260973317	{"height": "9", "building": "yes"}
W	260973318	{"height": "7", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "256"}
W	260973320	{"height": "7", "building": "yes", "addr:street": "Mission Street", "addr:housenumber": "1775"}
W	260973321	{"height": "5", "building": "yes"}
W	260973322	{"height": "6", "building": "yes"}
W	260973323	{"height": "7", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "250;252"}
W	260973325	{"name": "Standard Deviant", "note": "outdoor seating is a covid parklet", "craft": "brewery", "phone": "+1 415 5902550", "height": "6", "website": "https://www.standarddeviantbrewing.com/", "building": "yes", "addr:street": "14th Street", "opening_hours": "Tu-We 16:00-21:00; Th 16:00-22:00; Fr 15:00-24:00; Sa 12:00-24:00; Su 10:00-20:00", "outdoor_seating": "yes", "addr:housenumber": "280", "contact:facebook": "standarddeviantbrewing", "contact:instagram": "standarddeviantbrewing", "opening_hours:url": "https://www.standarddeviantbrewing.com/"}
W	260973326	{"height": "7", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "266;270"}
W	260973327	{"height": "8", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "224"}
W	260973329	{"height": "4", "building": "yes"}
W	260998410	{"height": "11", "building": "yes", "addr:city": "San Francisco", "addr:street": "14th Street", "addr:postcode": "94103", "addr:housename": "New Star Liquor and Market", "addr:housenumber": "269"}
W	260998411	{"height": "10", "building": "yes", "addr:city": "San Francisco", "addr:street": "Mission Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1855"}
W	260998412	{"name": "Impact Hub San Francisco", "height": "11", "office": "yes", "building": "yes", "addr:city": "San Francisco", "addr:street": "Mission Street", "addr:postcode": "94103", "addr:housenumber": "1899"}
W	260998413	{"height": "13", "building": "yes", "addr:city": "San Francisco", "addr:street": "Mission Street", "addr:postcode": "94103", "addr:housenumber": "1875"}
W	260998414	{"name": "Vincentian Villa", "height": "12", "building": "apartments", "addr:city": "San Francisco", "addr:street": "Mission Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1828"}
W	260998415	{"height": "13", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "277;279;281;285"}
W	260998416	{"height": "8", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1342;1344"}
W	260998417	{"building": "yes", "addr:city": "San Francisco", "addr:street": "Mission Street", "addr:postcode": "94103"}
W	261007295	{"height": "12", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1381;1383;1385"}
W	261007296	{"building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1303;1305;1307;1309"}
W	261007297	{"height": "12", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1350"}
W	261007299	{"building": "yes"}
W	261007300	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "239;241;243"}
W	261007301	{"height": "12", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1340"}
W	261007303	{"building": "yes", "addr:street": "15th Street", "addr:housenumber": "1540;1542"}
W	261007304	{"height": "11", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1319;1321;1323;1325;1327;1329"}
W	261007305	{"height": "8", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1370;1372;1374"}
W	261007306	{"height": "8", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1376;1378"}
W	261007308	{"height": "7", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1380"}
W	261007309	{"height": "12", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1359"}
W	261007310	{"building": "yes"}
W	261007311	{"height": "9", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1341;1343;1345"}
W	261007312	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "245;247;249"}
W	261007313	{"height": "10", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1363"}
W	261007314	{"height": "11", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1371;1373;1375;1377;1379"}
W	261007315	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "251;253;255"}
W	261007316	{"height": "10", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1347;1349;1351;1353"}
W	261007317	{"height": "12", "building": "yes"}
W	261007318	{"building": "yes"}
W	261007319	{"building": "yes", "addr:street": "15th Street", "addr:housenumber": "1544;1546"}
W	261007320	{"building": "yes"}
W	261007322	{"height": "7", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1315"}
W	261007323	{"building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1354"}
W	261007324	{"height": "8", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1548"}
W	261007325	{"height": "7", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1330"}
W	261007326	{"height": "9", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1364;1366;1368"}
W	261007328	{"height": "9", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1333"}
W	261007329	{"height": "9", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1360;1362"}
W	261007330	{"building": "yes"}
W	261007332	{"height": "12", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1314;1316;1318"}
W	261007333	{"height": "11", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1334;1336;1338"}
W	261007334	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "257;259;261"}
W	261007335	{"height": "9", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1326;1328"}
W	261007336	{"height": "16", "building": "yes", "addr:street": "Minna Street", "addr:housenumber": "1335"}
W	261007338	{"height": "9", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1320;1322"}
W	261089728	{"building": "yes", "addr:street": "15th Street", "addr:housenumber": "1514;1516;1518"}
W	261089729	{"height": "11", "building": "yes"}
W	261089730	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "344;346"}
W	261089731	{"building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1357;1359"}
W	261089732	{"height": "10", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1361;1363"}
W	261089733	{"height": "12", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "350;352;354"}
W	261089734	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "221;223;225"}
W	261089735	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "360;362"}
W	261089736	{"building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1355"}
W	261089737	{"height": "9", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "338;340;342"}
W	261089738	{"height": "13", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1337"}
W	261089739	{"height": "11", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "324;326;328"}
W	261089740	{"height": "7", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1347;1349"}
W	261089741	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "330;332"}
W	261089742	{"height": "11", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "227;229"}
W	261089743	{"height": "9", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "356;358"}
W	261089744	{"building": "yes"}
W	261089745	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "215;217"}
W	261089746	{"height": "9", "building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1383;1385"}
W	261089747	{"building": "yes"}
W	261089748	{"building": "yes"}
W	261089749	{"building": "yes"}
W	261089750	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "370"}
W	261089751	{"building": "yes"}
W	261089752	{"height": "6", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "310"}
W	261089753	{"building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1367;1369"}
W	261089754	{"height": "6", "building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "334"}
W	261089755	{"building": "yes", "addr:street": "Natoma Street", "addr:housenumber": "1351;1353"}
W	261089756	{"building": "yes", "addr:street": "South Van Ness Avenue", "addr:housenumber": "366;368"}
W	261089757	{"building": "yes", "addr:street": "15th Street", "addr:housenumber": "1520"}
W	261095624	{"building": "yes"}
W	261095625	{"name": "Wag Hotels", "amenity": "animal_boarding", "building": "yes", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "14th Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "25"}
W	261095626	{"height": "7", "building": "yes", "addr:street": "Folsom Street", "addr:housenumber": "1811"}
W	261095627	{"height": "24", "building": "yes"}
W	261095628	{"height": "9", "building": "yes"}
W	261095629	{"height": "5", "building": "yes", "addr:street": "14th Street", "addr:housenumber": "75"}
W	261095630	{"height": "6", "building": "yes", "addr:street": "Folsom Street", "addr:housenumber": "1825"}
W	261095632	{"height": "11", "building": "yes", "addr:street": "Harrison Street", "addr:housenumber": "1818;1820"}
W	261095634	{"building": "yes"}
W	261095636	{"building": "yes"}
W	261095638	{"building": "yes"}
W	261098422	{"height": "9", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "18;20"}
W	261098423	{"building": "yes"}
W	261098424	{"height": "8", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "12;14;16"}
W	261100106	{"building": "yes"}
W	261100107	{"height": "6", "building": "yes"}
W	261100108	{"height": "6", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1434"}
W	261100109	{"height": "11", "building": "yes", "addr:street": "15th Street", "addr:housenumber": "1402;1404"}
W	261517388	{"name": "Folsom Street", "highway": "tertiary", "lcn_ref": "30", "surface": "asphalt", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:name_type": "St", "name:etymology:wikidata": "Q3185252"}
W	261517390	{"lanes": "1", "oneway": "yes", "highway": "secondary_link", "destination": "Folsom Street"}
W	286676859	{"name": "Mission Street", "lanes": "4", "oneway": "no", "highway": "secondary", "sidewalk": "both", "lanes:bus": "1", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "lanes:forward": "2", "lanes:backward": "2", "tiger:name_base": "Mission", "tiger:name_type": "St", "gosm:sig:8CBDE645": "highway name oneway iEYEABECAAYFAkrCgAMACgkQNyBQgYy95kUrgQCfVEZQ2F/6GL02T2CiORCVpn5/xKkAnjTGy1oyOPMjBrLzF84SG+LZROOa 2009-09-29T21:45:40Z", "bus:lanes:backward": "yes|designated"}
W	288675791	{"building": "yes"}
W	288675792	{"building": "yes"}
W	288675793	{"building": "yes"}
W	288675794	{"building": "yes"}
W	288675795	{"building": "yes"}
W	288675796	{"building": "yes"}
W	356310090	{"highway": "service", "sidewalk": "left"}
W	356310091	{"highway": "service", "service": "parking_aisle"}
W	356310092	{"highway": "service", "service": "parking_aisle"}
W	356310093	{"highway": "service", "service": "parking_aisle"}
W	356310094	{"highway": "service", "service": "parking_aisle"}
W	356310095	{"highway": "service", "service": "parking_aisle"}
W	356310096	{"highway": "service", "service": "parking_aisle"}
W	356310097	{"highway": "service", "surface": "asphalt", "sidewalk": "no"}
W	356310098	{"highway": "service", "service": "parking_aisle", "surface": "asphalt"}
W	363054684	{"name": "Audi San Francisco", "note": "Constructed in early 2015. Doesn't show up on satellite yet.", "shop": "car", "brand": "Audi", "phone": "+1 (888) 896-1405", "website": "http://www.audisanfrancisco.com/", "building": "commercial", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "South Van Ness Avenue", "addr:postcode": "94103", "brand:wikidata": "Q23317", "brand:wikipedia": "en:Audi", "building:levels": "3", "addr:housenumber": "300"}
W	385184173	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "2", "oneway": "yes", "bicycle": "no", "highway": "motorway_link", "surface": "asphalt", "maxspeed": "50 mph", "tiger:cfcc": "A41", "turn:lanes": "|merge_to_left", "destination": "Oakland;San Jose", "tiger:county": "San Francisco, CA", "destination:ref": "US 101 South;I 80 East"}
W	397006685	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "74;76"}
W	397006686	{"building": "residential", "addr:street": "Folsom Street", "addr:housenumber": "1719;1721"}
W	397006687	{"building": "yes"}
W	397006688	{"building": "yes"}
W	397006689	{"building": "yes", "addr:street": "14th Street", "addr:postcode": "94103", "addr:housenumber": "64"}
W	397006690	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "70"}
W	397006815	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "77;85"}
W	397006816	{"building": "yes"}
W	397006817	{"building": "yes"}
W	397006818	{"building": "yes"}
W	397006819	{"building": "yes", "addr:street": "14th Street", "addr:housenumber": "81"}
W	397093083	{"lit": "yes", "name": "Folsom Street", "lanes": "4", "oneway": "no", "highway": "secondary", "lcn_ref": "30", "surface": "asphalt", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:left": "no", "lanes:forward": "2", "cycleway:right": "lane", "lanes:backward": "2", "tiger:name_type": "St", "turn:lanes:backward": "left|", "name:etymology:wikidata": "Q3185252"}
W	397093084	{"name": "Mission Street", "lanes": "4", "oneway": "yes", "highway": "secondary", "sidewalk": "right", "tiger:cfcc": "A45", "turn:lanes": "|||right", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:name_base": "Mission", "tiger:name_type": "St"}
W	398499276	{"name": "Alabama Street", "highway": "residential", "sidewalk": "left", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_type": "St"}
W	398499279	{"lanes": "1", "oneway": "yes", "highway": "secondary_link", "surface": "paved", "sidewalk": "right", "destination": "Harrison Street"}
W	398499281	{"highway": "service", "sidewalk": "no"}
W	403152783	{"name": "Mission Street", "lanes": "3", "oneway": "no", "highway": "secondary", "sidewalk": "both", "lanes:bus": "1", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "lanes:forward": "1", "lanes:backward": "2", "tiger:name_base": "Mission", "tiger:name_type": "St", "gosm:sig:8CBDE645": "highway name oneway iEYEABECAAYFAkrCgAMACgkQNyBQgYy95kUrgQCfVEZQ2F/6GL02T2CiORCVpn5/xKkAnjTGy1oyOPMjBrLzF84SG+LZROOa 2009-09-29T21:45:40Z", "bus:lanes:backward": "yes|designated"}
W	406720012	{"name": "Folsom Street", "lanes": "3", "bicycle": "yes", "highway": "tertiary", "surface": "asphalt", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "lanes:forward": "1", "lanes:backward": "1", "lanes:both_ways": "1", "tiger:name_type": "St", "bicycle:designated": "greenwave", "turn:lanes:both_ways": "left", "name:etymology:wikidata": "Q3185252"}
W	414156935	{"foot": "yes", "name": "South Van Ness Avenue", "lanes": "4", "oneway": "no", "highway": "primary", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:name_base": "Van Ness", "tiger:name_type": "Ave", "name:etymology:wikidata": "Q6144602", "tiger:name_direction_prefix": "S"}
W	418241132	{"lanes": "1", "oneway": "yes", "highway": "secondary_link", "surface": "asphalt", "sidewalk": "right"}
W	422638702	{"name": "Mission Street", "lanes": "3", "oneway": "no", "highway": "secondary", "sidewalk": "both", "lanes:bus": "1", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "lanes:forward": "1", "lanes:backward": "2", "tiger:name_base": "Mission", "tiger:name_type": "St", "gosm:sig:8CBDE645": "highway name oneway iEYEABECAAYFAkrCgAMACgkQNyBQgYy95kUrgQCfVEZQ2F/6GL02T2CiORCVpn5/xKkAnjTGy1oyOPMjBrLzF84SG+LZROOa 2009-09-29T21:45:40Z", "bus:lanes:backward": "yes|designated"}
W	458779331	{"foot": "yes", "name": "13th Street", "oneway": "yes", "highway": "secondary", "surface": "paved", "sidewalk": "right", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	458779333	{"name": "Folsom Street", "highway": "secondary", "lcn_ref": "30", "surface": "asphalt", "maxspeed": "25 mph", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:name_type": "St", "turn:lanes:backward": "left|", "name:etymology:wikidata": "Q3185252"}
W	458779334	{"name": "Harrison Street", "highway": "tertiary", "lcn_ref": "25", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:reviewed": "no", "tiger:name_type": "St"}
W	458780377	{"oneway": "yes", "highway": "service"}
W	483432849	{"name": "H. Welton Flynn Motor Coach Division", "landuse": "industrial", "alt_name": "Flynn Division", "operator": "San Francisco Municipal Railway"}
W	513595716	{"lit": "yes", "name": "Harrison Street", "lanes": "2", "highway": "tertiary", "lcn_ref": "25;36", "surface": "asphalt", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:both": "lane", "tiger:reviewed": "no", "tiger:name_type": "St", "cycleway:both:lane": "exclusive"}
W	513968173	{"lit": "yes", "name": "Folsom Street", "lanes": "3", "bicycle": "yes", "highway": "tertiary", "surface": "asphalt", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "lanes:forward": "2", "lanes:backward": "1", "tiger:name_type": "St", "bicycle:designated": "greenwave", "name:etymology:wikidata": "Q3185252"}
W	515833903	{"foot": "yes", "name": "13th Street", "lanes": "2", "oneway": "yes", "highway": "secondary", "surface": "paved", "sidewalk": "right", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "track", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	564392699	{"highway": "service", "service": "driveway"}
W	564392701	{"highway": "service", "service": "driveway"}
W	564392703	{"highway": "service", "service": "parking_aisle"}
W	564392704	{"highway": "service", "service": "parking_aisle"}
W	564392705	{"highway": "service"}
W	564392706	{"highway": "service", "surface": "asphalt"}
W	564392707	{"highway": "service"}
W	564392708	{"highway": "service", "service": "parking_aisle", "surface": "asphalt"}
W	564392709	{"highway": "service"}
W	564392710	{"highway": "service"}
W	564392711	{"highway": "service", "service": "parking_aisle"}
W	564392713	{"highway": "service"}
W	564392714	{"highway": "service", "service": "parking_aisle"}
W	564435430	{"highway": "service", "service": "parking_aisle"}
W	564435432	{"oneway": "yes", "highway": "service", "service": "parking_aisle"}
W	564435436	{"highway": "service", "service": "parking_aisle"}
W	564435438	{"oneway": "yes", "highway": "service", "service": "parking_aisle"}
W	564435441	{"highway": "service", "service": "parking_aisle"}
W	564435467	{"highway": "service"}
W	564435468	{"highway": "service", "service": "parking_aisle"}
W	564435470	{"highway": "service", "service": "parking_aisle", "surface": "asphalt"}
W	564435471	{"highway": "service"}
W	564435472	{"highway": "service"}
W	564435473	{"highway": "service", "service": "parking_aisle"}
W	564435474	{"highway": "service", "service": "parking_aisle"}
W	564435475	{"highway": "service"}
W	564435476	{"access": "private", "highway": "service", "service": "parking_aisle"}
W	564435477	{"access": "private", "highway": "service", "service": "parking_aisle"}
W	564435478	{"access": "private", "highway": "service", "service": "parking_aisle"}
W	564435479	{"highway": "service", "service": "parking_aisle"}
W	564435480	{"highway": "service", "service": "driveway"}
W	564435482	{"access": "private", "highway": "service", "service": "driveway"}
W	564435485	{"oneway": "yes", "highway": "service", "service": "parking_aisle"}
W	564435486	{"oneway": "yes", "highway": "service", "service": "parking_aisle"}
W	564435487	{"highway": "service"}
W	564435488	{"highway": "service"}
W	564435489	{"highway": "service"}
W	564435490	{"highway": "service"}
W	564435491	{"oneway": "yes", "highway": "service", "service": "parking_aisle"}
W	564435492	{"highway": "service"}
W	564435493	{"highway": "service", "service": "parking_aisle"}
W	564435494	{"highway": "service"}
W	564435495	{"highway": "service", "service": "parking_aisle"}
W	564435496	{"highway": "service"}
W	586782486	{"name": "Division Circle Navigation Center", "amenity": "social_facility", "landuse": "residential", "capacity": "126", "addr:city": "San Francisco", "addr:state": "CA", "addr:street": "South Van Ness Avenue", "description": "Center for temporary shelter to San Francisco’s highly vulnerable and long-term homeless residents.", "addr:postcode": "94103", "social_facility": "shelter", "addr:housenumber": "224", "social_facility:for": "homeless"}
W	587670476	{"name": "Health Right 360", "note": "Formerly known as Haight-Ashbury Free Clinic", "building": "yes", "wikidata": "Q30283747", "addr:city": "San Francisco", "addr:state": "CA", "healthcare": "clinic", "addr:street": "Mission Street", "addr:country": "US", "addr:postcode": "94103", "addr:housenumber": "1735"}
W	587670478	{"building": "yes"}
W	587670480	{"building": "yes"}
W	594569788	{"highway": "service", "service": "parking_aisle"}
W	611290713	{"highway": "service", "service": "parking_aisle", "surface": "asphalt"}
W	617565053	{"access": "private", "highway": "service"}
W	617565055	{"highway": "service"}
W	617565057	{"highway": "service"}
W	617565059	{"access": "private", "highway": "service"}
W	617565061	{"oneway": "no", "highway": "service"}
W	617565063	{"access": "private", "highway": "service"}
W	618375257	{"lit": "yes", "name": "Folsom Street", "lanes": "3", "bicycle": "yes", "highway": "tertiary", "surface": "asphalt", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "lanes:forward": "2", "lanes:backward": "1", "tiger:name_type": "St", "bicycle:designated": "greenwave", "name:etymology:wikidata": "Q3185252"}
W	651669420	{"building": "yes"}
W	654563358	{"note": "location approximate", "gauge": "1676", "layer": "-2", "owner": "San Francisco Bay Area Rapid Transit District", "tunnel": "yes", "network": "BART", "railway": "subway", "service": "crossover", "voltage": "1000", "frequency": "0", "electrified": "rail"}
W	654563359	{"note": "location approximate", "gauge": "1676", "layer": "-2", "owner": "San Francisco Bay Area Rapid Transit District", "tunnel": "yes", "network": "BART", "railway": "subway", "service": "crossover", "voltage": "1000", "frequency": "0", "electrified": "rail"}
W	658560948	{"highway": "service", "sidewalk": "no"}
W	658601439	{"highway": "service"}
W	676719999	{"landuse": "residential"}
W	676720001	{"landuse": "retail"}
W	676720003	{"landuse": "commercial"}
W	688747551	{"name": "SoMa StrEat Food Park", "note": "Outdoor area for food trucks.", "amenity": "marketplace", "barrier": "fence", "website": "http://www.somastreatfoodpark.com", "wheelchair": "yes", "addr:street": "11th Street", "opening_hours": "Mo-Fr 11:00-15:00,17:00-21:00; Sa 11:00-22:00, Su 11:00-17:00", "addr:housenumber": "428"}
W	692910505	{"building": "yes"}
W	692910506	{"building": "yes"}
W	692910507	{"highway": "service", "service": "driveway", "sidewalk": "no"}
W	692910508	{"NHS": "STRAHNET", "ref": "US 101", "lanes": "2", "layer": "1", "bridge": "yes", "oneway": "yes", "bicycle": "no", "highway": "motorway_link", "surface": "concrete", "maxspeed": "50 mph", "tiger:cfcc": "A41", "turn:lanes": "|merge_to_left", "destination": "Oakland;San Jose", "tiger:county": "San Francisco, CA", "destination:ref": "US 101 South;I 80 East"}
W	706542863	{"lit": "yes", "name": "15th Street", "highway": "residential", "surface": "asphalt", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "15th", "tiger:name_type": "St"}
W	706542864	{"name": "15th Street", "highway": "residential", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_base": "15th", "tiger:name_type": "St"}
W	706543957	{"lit": "yes", "name": "14th Street", "lanes": "2", "oneway": "yes", "highway": "residential", "lcn_ref": "30", "surface": "asphalt", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:name_type": "St", "bicycle:designated": "greenwave"}
W	721524803	{"access": "private", "highway": "service"}
W	732858974	{"access": "private", "highway": "service"}
W	760623357	{"foot": "yes", "name": "13th Street", "lanes": "4", "oneway": "yes", "highway": "secondary", "surface": "asphalt", "sidewalk": "right", "tiger:cfcc": "A41", "turn:lanes": "left|||right", "tiger:county": "San Francisco, CA", "cycleway:right": "track", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	771471742	{"name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "tiger:cfcc": "A41", "turn:lanes": "reverse;left|none|none", "tiger:county": "San Francisco, CA", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	771471743	{"foot": "yes", "name": "13th Street", "lanes": "2", "oneway": "yes", "highway": "secondary", "surface": "paved", "sidewalk": "right", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	779105816	{"name": "Harrison Street", "highway": "tertiary", "lcn_ref": "25", "cycleway": "lane", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_type": "St"}
W	806660464	{"access": "private", "highway": "service"}
W	806660465	{"access": "private", "highway": "service"}
W	878214045	{"highway": "service"}
W	921360666	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "unmarked"}
W	921360744	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "unmarked"}
W	921361662	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "unmarked"}
W	921362450	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "unmarked"}
W	921363600	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "marked"}
W	921364963	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "marked"}
W	921365352	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "marked"}
W	921366255	{"lit": "yes", "footway": "crossing", "highway": "footway", "surface": "asphalt", "crossing": "marked"}
W	921366326	{"lit": "yes", "footway": "sidewalk", "highway": "footway", "surface": "concrete"}
W	921366466	{"lit": "yes", "footway": "sidewalk", "highway": "footway", "surface": "concrete"}
W	925052344	{"lit": "yes", "foot": "yes", "name": "South Van Ness Avenue", "lanes": "4", "oneway": "no", "highway": "primary", "surface": "asphalt", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "cycleway:both": "no", "tiger:name_base": "Van Ness", "tiger:name_type": "Ave", "name:etymology:wikidata": "Q6144602", "tiger:name_direction_prefix": "S"}
W	925052345	{"foot": "yes", "name": "South Van Ness Avenue", "lanes": "4", "oneway": "no", "highway": "primary", "maxspeed": "25 mph", "old_name": "Howard Street", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "trolley_wire": "yes", "tiger:name_base": "Van Ness", "tiger:name_type": "Ave", "name:etymology:wikidata": "Q6144602", "tiger:name_direction_prefix": "S"}
W	991915375	{"name": "Harrison Street", "highway": "tertiary", "lcn_ref": "25", "cycleway": "lane", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:reviewed": "no", "tiger:name_type": "St"}
W	1030068318	{"foot": "yes", "name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "surface": "paved", "sidewalk": "right", "tiger:cfcc": "A41", "turn:lanes": "none|none|right", "tiger:county": "San Francisco, CA", "cycleway:right": "track", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	1039091829	{"name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "tiger:name_base": "13th", "tiger:name_type": "St"}
R	7474768	{"type": "restriction", "restriction": "no_right_turn"}
W	1039091830	{"name": "13th Street", "lanes": "4", "oneway": "yes", "highway": "secondary", "tiger:cfcc": "A41", "turn:lanes": "left|none|none|right", "tiger:county": "San Francisco, CA", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	1043462454	{"name": "14th Street", "lanes": "2", "oneway": "yes", "highway": "residential", "lcn_ref": "30", "maxspeed": "25 mph", "sidewalk": "both", "tiger:cfcc": "A41", "turn:lanes": "left|left;through", "tiger:county": "San Francisco, CA", "cycleway:right": "lane", "tiger:name_type": "St", "bicycle:designated": "greenwave"}
W	1049986923	{"foot": "yes", "name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "surface": "asphalt", "sidewalk": "right", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "track", "tiger:name_base": "13th", "tiger:name_type": "St"}
W	1049986924	{"foot": "yes", "name": "13th Street", "lanes": "3", "oneway": "yes", "highway": "secondary", "surface": "asphalt", "sidewalk": "right", "tiger:cfcc": "A41", "tiger:county": "San Francisco, CA", "cycleway:right": "track", "tiger:name_base": "13th", "tiger:name_type": "St"}
R	32314	{"ref": "25", "type": "route", "route": "bicycle", "network": "lcn", "cycle_network": "US:CA:SF"}
R	32317	{"ref": "30", "type": "route", "route": "bicycle", "network": "rcn", "cycle_network": "US:CA:SF"}
R	71162	{"to": "Los Angeles", "NHS": "STRAHNET", "ref": "101", "from": "Hopland", "name": "US 101 (CA southbound, south of Hopland)", "type": "route", "route": "road", "symbol": "https://upload.wikimedia.org/wikipedia/commons/5/5b/US_101_(CA).svg", "network": "US:US", "wikidata": "Q400444", "direction": "south", "wikipedia": "en:U.S. Route 101 in California", "is_in:state": "CA"}
R	108619	{"to": "Hopland", "NHS": "STRAHNET", "ref": "101", "from": "Los Angeles", "name": "US 101 (CA northbound, south of Hopland)", "type": "route", "route": "road", "symbol": "https://upload.wikimedia.org/wikipedia/commons/5/5b/US_101_(CA).svg", "network": "US:US", "wikidata": "Q400444", "direction": "north", "wikipedia": "en:U.S. Route 101 in California", "is_in:state": "CA"}
R	1539483	{"ref": "36", "type": "route", "route": "bicycle", "network": "lcn", "cycle_network": "US:CA:SF"}
R	1967678	{"type": "restriction", "restriction": "no_left_turn"}
R	1967679	{"type": "restriction", "restriction": "no_u_turn"}
R	2580420	{"type": "restriction", "restriction": "no_left_turn"}
R	2580425	{"type": "restriction", "restriction": "only_straight_on"}
R	2580441	{"type": "restriction", "restriction": "no_left_turn"}
R	2716239	{"to": "24th Street & Mission Street", "fee": "yes", "ref": "800", "via": "Market Street & South Van Ness Avenue", "from": "Richmond BART", "name": "AC Transit 800: Richmond BART => Market & Van Ness => 24th Street & Mission (weekends)", "type": "route", "route": "bus", "network": "AC Transit", "operator": "Alameda-Contra Costa Transit District", "payment:cash": "yes", "payment:clipper": "yes", "network:wikidata": "Q4353850", "network:wikipedia": "en:AC Transit", "payment:prepaid_ticket": "no", "public_transport:version": "2"}
R	2716240	{"ref": "800", "name": "AC Transit 800", "type": "route_master", "network": "AC Transit", "operator": "Alameda-Contra Costa Transit District", "route_master": "bus", "network:wikidata": "Q4353850", "network:wikipedia": "en:AC Transit"}
R	2827683	{"to": "San Francisco International Airport", "fee": "yes", "ref": "Yellow", "from": "Antioch", "name": "BART Yellow Line: Antioch => SFO Airport", "note": "opening_hours has approximate departure times at Antioch", "type": "route", "route": "subway", "colour": "#ffe800", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q54874971", "passenger": "suburban", "wikipedia": "en:Antioch–SFO/Millbrae line", "payment:cash": "no", "opening_hours": "Mo-Fr 04:45-18:30, Sa 05:45-17:45", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2827684	{"to": "Antioch", "fee": "yes", "ref": "Yellow", "via": "San Francisco International Airport", "from": "Millbrae", "name": "BART Yellow Line: Millbrae => SFO Airport => Antioch", "note": "opening_hours has approximate departure times at Millbrae", "type": "route", "route": "subway", "colour": "#ffe800", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q54874971", "passenger": "suburban", "wikipedia": "en:Antioch–SFO/Millbrae line", "payment:cash": "no", "opening_hours": "Mo-Fr 05:00-06:00, 20:45-24:00, Sa 06:00-6:45, 19:45-24:00, Su 07:15-21:00", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2827685	{"to": "Antioch", "fee": "yes", "ref": "Yellow", "from": "San Francisco International Airport", "name": "BART Yellow Line: SFO Airport => Antioch", "note": "opening_hours has approximate departure times at SFO", "type": "route", "route": "subway", "colour": "#ffe800", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q54874971", "passenger": "suburban", "wikipedia": "en:Antioch–SFO/Millbrae line", "payment:cash": "no", "opening_hours": "Mo-Fr 06:30-20:30, Sa 07:00-19:15", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2827686	{"to": "Millbrae", "fee": "yes", "ref": "Yellow", "via": "San Francisco International Airport", "from": "Antioch", "name": "BART Yellow Line: Antioch => SFO Airport => Millbrae", "note": "opening_hours has approximate departure times at Antioch", "type": "route", "route": "subway", "colour": "#ffe800", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q54874971", "passenger": "suburban", "wikipedia": "en:Antioch–SFO/Millbrae line", "payment:cash": "no", "opening_hours": "Mo-Fr 18:45-23:45, Sa 18:00-24:00, Su 07:15-20:45", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2827687	{"ref": "Yellow", "name": "Antioch–SFO+Millbrae Line", "type": "route_master", "colour": "#ffe800", "network": "BART", "alt_name": "Yellow Line", "old_name": "Antioch–SFO/Millbrae Line", "operator": "Bay Area Rapid Transit District", "wikidata": "Q54874971", "wikipedia": "en:Antioch–SFO/Millbrae line", "route_master": "subway;light_rail", "network:wikidata": "Q610120", "operator:wikidata": "Q4873922"}
R	7474779	{"type": "restriction", "restriction": "no_right_turn"}
R	7475008	{"type": "restriction", "restriction": "no_right_turn"}
R	2851509	{"to": "Daly City", "fee": "yes", "ref": "Red", "from": "Richmond", "name": "BART Red Line: Richmond => Daly City", "type": "route", "route": "subway", "colour": "#ed1c24", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3809179", "passenger": "suburban", "payment:cash": "no", "opening_hours": "Mo-Fr 21:00+; Sa", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851511	{"to": "Richmond", "fee": "yes", "ref": "Red", "from": "Daly City", "name": "BART Red Line: Daly City => Richmond", "type": "route", "route": "subway", "colour": "#ed1c24", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3809179", "passenger": "suburban", "payment:cash": "no", "opening_hours": "Mo-Fr 21:00+; Sa", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851513	{"ref": "Red", "name": "Richmond–Millbrae+SFO Line", "type": "route_master", "colour": "#ed1c24", "network": "BART", "alt_name": "Red Line", "old_name": "Richmond–Daly City/Millbrae Line;Richmond–Millbrae Line", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3809179", "wikipedia": "en:Richmond–Daly City/Millbrae line", "route_master": "subway", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District"}
R	2851612	{"to": "San Francisco International Airport", "fee": "yes", "ref": "Red", "via": "Millbrae", "from": "Richmond", "name": "BART Red Line: Richmond => Millbrae => SFO Airport", "type": "route", "route": "subway", "colour": "#ed1c24", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3809179", "passenger": "suburban", "wikipedia": "en:Richmond–Millbrae line", "payment:cash": "no", "opening_hours": "Mo-Fr 05:00-21:00", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851613	{"to": "Richmond", "fee": "yes", "ref": "Red", "via": "Millbrae", "from": "San Francisco International Airport", "name": "BART Red Line: SFO Airport => Millbrae => Richmond", "type": "route", "route": "subway", "colour": "#ed1c24", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3809179", "passenger": "suburban", "wikipedia": "en:Richmond–Millbrae line", "payment:cash": "no", "opening_hours": "Mo-Fr 5:47-21:00", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851725	{"to": "Daly City", "fee": "yes", "ref": "Blue", "from": "Dublin/Pleasanton", "name": "BART Blue Line: Dublin/Pleasanton => Daly City", "type": "route", "route": "subway", "colour": "#00aeef", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3720569", "passenger": "suburban", "payment:cash": "no", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851726	{"to": "Daly City", "fee": "yes", "ref": "Green", "from": "Berryessa/North San José", "name": "BART Green Line: Berryessa/North San José => Daly City", "type": "route", "route": "subway", "colour": "#4db848", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3720557", "passenger": "suburban", "payment:cash": "no", "opening_hours": "Mo-Sa", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851727	{"to": "Dublin/Pleasanton", "fee": "yes", "ref": "Blue", "from": "Daly City", "name": "BART Blue Line: Daly City => Dublin/Pleasanton", "type": "route", "route": "subway", "colour": "#00aeef", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3720569", "passenger": "suburban", "payment:cash": "no", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851728	{"to": "Berryessa/North San José", "fee": "yes", "ref": "Green", "from": "Daly City", "name": "BART Green Line: Daly City => Berryessa/North San José", "type": "route", "route": "subway", "colour": "#4db848", "network": "BART", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3720557", "passenger": "suburban", "payment:cash": "no", "opening_hours": "Mo-Sa", "payment:clipper": "yes", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2851729	{"ref": "Green", "name": "Berryessa/North San José–Daly City Line", "type": "route_master", "colour": "#4db848", "network": "BART", "alt_name": "Green Line", "old_name": "Warm Springs/South Fremont–Daly City Line", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3720557", "wikipedia": "en:Berryessa/North San José–Daly City line", "route_master": "subway", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District"}
R	2851730	{"ref": "Blue", "name": "Dublin/Pleasanton–Daly City Line", "type": "route_master", "colour": "#00aeef", "network": "BART", "alt_name": "Blue Line", "operator": "Bay Area Rapid Transit District", "wikidata": "Q3720569", "wikipedia": "en:Dublin/Pleasanton–Daly City line", "route_master": "subway", "network:wikidata": "Q610120", "network:wikipedia": "en:Bay Area Rapid Transit", "operator:wikidata": "Q4873922", "operator:wikipedia": "en:Bay Area Rapid Transit District"}
R	2996793	{"to": "Jackson Street & Van Ness Avenue", "fee": "yes", "ref": "12", "from": "24th Street & Mission Street", "name": "Muni 12 inbound: The Mission => Russian Hill", "type": "route", "route": "bus:suspended", "network": "Muni", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	7868288	{"name": "Glen Park", "type": "public_transport", "subway": "yes", "network": "BART", "railway": "facility", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "GLEN", "public_transport": "stop_area"}
R	8549303	{"type": "restriction", "restriction": "no_left_turn"}
R	2996794	{"to": "24th Street & Mission Street", "fee": "yes", "ref": "12", "from": "Pacific Avenue & Van Ness Avenue", "name": "Muni 12 outbound: Russian Hill => The Mission", "type": "route", "route": "bus:suspended", "network": "Muni", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	2996795	{"ref": "12", "name": "Muni 12-Folsom/Pacific", "type": "route_master", "network": "Muni", "operator": "San Francisco Municipal Railway", "route_master": "bus", "nextbus:route": "12", "nextbus:agency": "sf-muni", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway"}
R	3000713	{"to": "Ferry Plaza", "fee": "yes", "ref": "14", "from": "Mission Street & San Jose Avenue", "name": "Muni 14 inbound: Daly City => Downtown", "note": "includes owl service", "type": "route", "route": "trolleybus", "network": "Muni", "operator": "San Francisco Municipal Transportation Agency", "payment:cash": "yes", "operator:short": "SFMTA", "payment:clipper": "yes", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "operator:wikidata": "Q7414072", "operator:wikipedia": "en:San Francisco Municipal Transportation Agency", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3000714	{"to": "Mission Street & San Jose Avenue", "fee": "yes", "ref": "14", "from": "Ferry Plaza", "name": "Muni 14 outbound: Downtown => Daly City", "note": "includes owl service", "type": "route", "route": "trolleybus", "network": "Muni", "operator": "San Francisco Municipal Transportation Agency", "payment:cash": "yes", "operator:short": "SFMTA", "payment:clipper": "yes", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "operator:wikidata": "Q7414072", "operator:wikipedia": "en:San Francisco Municipal Transportation Agency", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3000715	{"ref": "14", "name": "Muni 14-Mission", "type": "route_master", "network": "Muni", "operator": "San Francisco Municipal Railway", "route_master": "trolleybus", "nextbus:route": "14", "nextbus:agency": "sf-muni", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "operator:wikidata": "Q7414072", "operator:wikipedia": "en:San Francisco Municipal Transportation Agency"}
R	3281725	{"name": "Mission Street", "type": "associatedStreet"}
R	3406707	{"to": "Mission Street & Main Street", "fee": "yes", "ref": "14R", "from": "Daly City BART", "name": "Muni 14R inbound: Daly City => Downtown", "type": "route", "route": "bus", "network": "Muni", "old_ref": "14L", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3406708	{"to": "Daly City BART", "fee": "yes", "ref": "14R", "from": "Mission Street & Main Street", "name": "Muni 14R outbound: Downtown => Daly City", "type": "route", "route": "bus", "network": "Muni", "old_ref": "14L", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3406712	{"ref": "14R", "name": "Muni 14R-Mission Rapid", "type": "route_master", "network": "Muni", "operator": "San Francisco Municipal Railway", "route_master": "bus", "nextbus:route": "14R", "nextbus:agency": "sf-muni", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway"}
R	3412976	{"to": "Powell Street & Beach Street", "fee": "yes", "ref": "49", "from": "City College Terminal", "name": "Muni 49 inbound: City College => Fisherman's Wharf", "note": "normally a trolleybus. substituted with diesel bus due to Van Ness BRT construction", "type": "route", "route": "bus", "network": "Muni", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3412977	{"to": "City College Terminal", "fee": "yes", "ref": "49", "from": "Powell Street & Beach Street", "name": "Muni 49 outbound: Fisherman's Wharf => City College", "note": "normally a trolleybus. substituted with diesel bus due to Van Ness BRT construction", "type": "route", "route": "bus", "network": "Muni", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3412978	{"ref": "49", "name": "Muni 49-Mission/Van Ness", "note": "normally a trolleybus. substituted with diesel bus due to Van Ness BRT construction", "type": "route_master", "network": "Muni", "operator": "San Francisco Municipal Railway", "route_master": "bus", "nextbus:route": "49", "nextbus:agency": "sf-muni"}
R	3413094	{"to": "Jackson Street & Van Ness Avenue", "fee": "yes", "ref": "27", "from": "24th Street & Mission Street", "name": "Muni 27 inbound: The Mission => Russian Hill", "type": "route", "route": "bus", "network": "Muni", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3413095	{"to": "24th Street & Mission Street", "fee": "yes", "ref": "27", "from": "Pacific Avenue & Van Ness Avenue", "name": "Muni 27 outbound: Russian Hill => The Mission", "type": "route", "route": "bus", "network": "Muni", "operator": "San Francisco Municipal Railway", "payment:cash": "yes", "payment:clipper": "yes", "payment:prepaid_ticket": "yes", "public_transport:version": "2"}
R	3413096	{"ref": "27", "name": "Muni 27-Bryant", "type": "route_master", "network": "Muni", "operator": "San Francisco Municipal Railway", "route_master": "bus", "nextbus:route": "27", "nextbus:agency": "sf-muni", "network:wikidata": "Q1140138", "network:wikipedia": "en:San Francisco Municipal Railway"}
R	3442900	{"type": "multipolygon", "building": "yes", "addr:street": "Shotwell Street", "addr:housenumber": "101;103;105;107;109;111;113;115;117;119"}
R	3504260	{"type": "multipolygon", "building": "yes"}
R	6043230	{"name": "No left turn from Mission St to 14th St", "type": "restriction", "except": "psv", "restriction": "no_left_turn"}
R	6085237	{"name": "24th Street Mission", "type": "public_transport", "subway": "yes", "network": "BART", "railway": "facility", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "24TH", "public_transport": "stop_area"}
R	6085261	{"name": "16th Street Mission", "type": "public_transport", "subway": "yes", "network": "BART", "railway": "facility", "operator": "San Francisco Bay Area Rapid Transit District", "railway:ref": "16TH", "public_transport": "stop_area"}
R	7379835	{"type": "restriction", "restriction": "no_left_turn"}
R	9101203	{"name": "M-Line", "type": "route", "owner": "San Francisco Bay Area Rapid Transit District", "route": "railway"}
R	9517992	{"name": "Glen Park", "type": "public_transport", "public_transport": "stop_area_group"}
R	9518458	{"name": "24th Street Mission", "type": "public_transport", "public_transport": "stop_area_group"}
R	9518459	{"name": "16th Street Mission", "type": "public_transport", "public_transport": "stop_area_group"}
R	9723855	{"to": "Market Street & South Van Ness Avenue", "fee": "yes", "ref": "800", "from": "Richmond BART", "name": "AC Transit 800: Richmond BART => Market & Van Ness (weekdays)", "type": "route", "route": "bus", "network": "AC Transit", "operator": "Alameda-Contra Costa Transit District", "payment:cash": "yes", "payment:clipper": "yes", "network:wikidata": "Q4353850", "network:wikipedia": "en:AC Transit", "payment:prepaid_ticket": "no", "public_transport:version": "2"}
R	10189111	{"name": "Mission Street & 14th Street", "type": "public_transport", "network": "Muni", "operator": "San Francisco Municipal Railway", "public_transport": "stop_area"}
R	10213873	{"name": "Folsom Street & 14th Street", "type": "public_transport", "network": "Muni", "operator": "San Francisco Municipal Railway", "public_transport": "stop_area"}
R	10213874	{"name": "Folsom Street & 16th Street", "type": "public_transport", "network": "Muni", "alt_name": "16th Street & Folsom Street;16th Street & Shotwell Street", "operator": "San Francisco Municipal Railway", "short_name": "Folsom & 16th Street", "public_transport": "stop_area"}
R	10699321	{"type": "restriction", "restriction": "no_left_turn"}
R	12526000	{"type": "restriction", "restriction": "no_left_turn"}
R	12989284	{"NHS": "STRAHNET", "ref": "101", "name": "US 101 (CA)", "type": "route", "route": "road", "symbol": "https://upload.wikimedia.org/wikipedia/commons/5/5b/US_101_(CA).svg", "network": "US:US", "operator": "California Department of Transportation", "wikidata": "Q400444", "wikipedia": "en:U.S. Route 101 in California", "is_in:state": "CA", "operator:wikidata": "Q127743"}
R	13313587	{"type": "restriction", "implicit": "yes", "restriction": "no_left_turn"}
R	13372956	{"type": "restriction", "except": "bicycle;emergency", "restriction": "no_left_turn"}
R	13372957	{"type": "restriction", "except": "bicycle;emergency", "restriction": "no_left_turn"}
R	13841961	{"type": "restriction", "except": "bicycle;emergency", "restriction": "only_right_turn"}
R	13841962	{"type": "restriction", "except": "bicycle;emergency", "restriction": "only_right_turn"}
\.


--
-- Data for Name: traffic_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.traffic_line (osm_id, osm_type, osm_subtype, geom) FROM stdin;
\.


--
-- Data for Name: traffic_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.traffic_point (osm_id, osm_type, osm_subtype, geom) FROM stdin;
65363251	traffic_signals	\N	0101000020110F0000B1CC045728FE69C11E7A3130F5575141
8455177957	crossing	\N	0101000020110F0000547F4F7028FE69C168B66FDAF7575141
65334190	traffic_signals	\N	0101000020110F0000C2A4E0FE09FE69C1DA65D3CCF9575141
3188130246	crossing	\N	0101000020110F000088AE41CBF8FD69C1DC8A80D6C6575141
8554191671	crossing	\N	0101000020110F0000BBEBD7B6FAFD69C1737A065DFA575141
8554180153	crossing	\N	0101000020110F0000735490E4FBFD69C1572F96F2FB575141
8554196251	crossing	\N	0101000020110F0000AAAFE0E0FAFD69C1AF76DEB7FE575141
8554200447	crossing	\N	0101000020110F000090D4E0E7F9FD69C1580E1840FC575141
8554218746	crossing	\N	0101000020110F00000382D556EDFD69C10D14E12EFE575141
8554237523	crossing	\N	0101000020110F0000BF8FDE8EEBFD69C143643EACFC575141
65317585	traffic_signals	\N	0101000020110F0000FC9764A1EBFD69C1EB0C7972FE575141
8554196286	crossing	\N	0101000020110F00002CD2D3E4E9FD69C1390611B6FE575141
6459941675	barrier	gate	0101000020110F00002F331D93B7FD69C1A53166ED65585141
4186794512	crossing	\N	0101000020110F00000098ADB2CAFD69C1DA3C7D0A5F585141
300517501	traffic_calming	island	0101000020110F0000F60EB78ECDFD69C1D7D72B445F585141
4012499528	crossing	\N	0101000020110F000085A48B60D1FD69C174F45EFD53585141
3051467912	traffic_calming	island	0101000020110F00000697232FCFFD69C16E6F520753585141
65317769	traffic_signals	\N	0101000020110F0000E39B4FB5CEFD69C18ECFC3D357585141
4547300237	traffic_signals	\N	0101000020110F0000888AC835CEFD69C1C9737A705B585141
4904616766	stop	\N	0101000020110F0000DD3A8F69CFFD69C1489DDAE63B585141
5837767007	barrier	gate	0101000020110F000000F57618D0FD69C17793A7A419585141
5837767008	barrier	gate	0101000020110F00009D428DB4DCFD69C1BC71435604585141
6862532114	barrier	gate	0101000020110F00000E9332B2E0FD69C15906B4DE3C585141
65309810	traffic_signals	\N	0101000020110F000030940EC2EDFD69C157C5CDC436585141
8554209058	crossing	\N	0101000020110F0000914177BCEBFD69C1974CCE5B01585141
8554209056	barrier	kerb	0101000020110F00005CE27594EDFD69C1EB25821501585141
8554227162	crossing	\N	0101000020110F0000F4C9D086EFFD69C18D2962BB00585141
5837767018	barrier	gate	0101000020110F00006C90FE9CEAFD69C179B298FF1B585141
276545995	traffic_signals	\N	0101000020110F0000696D8628EDFD69C1B67C03E359585141
1266060482	traffic_signals	\N	0101000020110F00001B244BDCECFD69C17202F9585D585141
65284015	motorway_junction	\N	0101000020110F00000AF3DC05EFFD69C196F2517A5D585141
4547308119	stop	\N	0101000020110F0000BDAC425608FE69C1B1CD3C246A585141
4547308120	traffic_signals	\N	0101000020110F0000DFEECD360AFE69C1952AC7CC6A585141
4547300241	traffic_signals	\N	0101000020110F00000A889D9B0AFE69C14500140C65585141
276546183	traffic_signals	\N	0101000020110F00001F348FE80AFE69C18970B2B560585141
276546182	traffic_signals	\N	0101000020110F0000A5E3A3300CFE69C195822F3A61585141
276546210	traffic_signals	\N	0101000020110F0000FB5D07990FFE69C1656B87535E585141
2086914134	crossing	\N	0101000020110F00004A5CDA520FFE69C1E83E29975D585141
65299217	traffic_signals	\N	0101000020110F00004CC9AD210CFE69C17715773732585141
4761685551	traffic_calming	hump	0101000020110F00009515CA5B15FE69C18D2F49EC0F585141
4761685550	traffic_calming	hump	0101000020110F0000454428D81EFE69C14A21477F0E585141
7543166924	barrier	gate	0101000020110F00002900063C20FE69C1E941C9D91A585141
9419035931	amenity	bicycle_parking	0101000020110F0000A694046722FE69C1AE9FB47E31585141
65309820	traffic_signals	\N	0101000020110F00003AF1D1792AFE69C11FEB20AA2D585141
7543166923	barrier	gate	0101000020110F0000192C61CB27FE69C1D1415B5E19585141
6768689465	barrier	gate	0101000020110F000019F70A382BFE69C1C89E84F50A585141
6768689457	barrier	gate	0101000020110F0000FE72460339FE69C1C2A1CD320B585141
65362975	traffic_signals	\N	0101000020110F00002AF1080B2AFE69C1AEBE47886A585141
4761685559	crossing	\N	0101000020110F000013907F502AFE69C14127266F67585141
\.


--
-- Data for Name: traffic_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.traffic_polygon (osm_id, osm_type, osm_subtype, geom) FROM stdin;
132605501	amenity	parking	0106000020110F0000010000000103000000010000000900000068C627C5C1FD69C19F1809771158514100E4E582C1FD69C122BE828809585141D7AD6D25BDFD69C196DFC23C0A585141CC9BC697BDFD69C10CD30E2C15585141ACC60E86B8FD69C14EE6682816585141D4695AB2B9FD69C12C8EAA4635585141AB23D8EBBDFD69C1A6DE95C22A585141AA3D9B16C1FD69C1FA6A455E1B58514168C627C5C1FD69C19F18097711585141
688747551	barrier	fence	0106000020110F0000010000000103000000010000001200000058752B28BFFD69C1FC788B36625851413DA4A7F6BEFD69C158143795615851419969B9ABBDFD69C1680F09585E585141AB184FECBBFD69C1F1209A405E585141A8980D12B9FD69C1481034FB5D58514198833FDCB5FD69C1B1D7186A5D585141D1A26171B5FD69C11392FF6A5D5851414451A012B5FD69C1277785C15D585141078A06CBB4FD69C13E19B17F5E5851417EE92BAEB4FD69C17DF364545F585141DAF5F4C9B4FD69C1C1891520605851414B7632F7B4FD69C167DCC199605851412F331D93B7FD69C1A53166ED65585141F2F433B5B9FD69C19AF849486A5851419BD68C7ABAFD69C1E1C132AD6B5851411D63294EBEFD69C17DE80FE8635851416F1C5F11BFFD69C12B411A5F6258514158752B28BFFD69C1FC788B3662585141
132605458	amenity	parking	0106000020110F00000100000001030000000100000008000000EB908664DDFD69C1EC2AD2564E58514195BF2432D6FD69C16D1AAAA14D585141E8739C91D6FD69C1744EF76D3E585141795A6797D1FD69C19D379B433E5851418CC91D45D1FD69C1978B81D94E585141AECF7ABED3FD69C19D51DDF85358514103AC65F0DCFD69C1CBC44A9954585141EB908664DDFD69C1EC2AD2564E585141
132605487	amenity	parking	0106000020110F0000010000000103000000010000001A000000E513AC83CDFD69C11AC1BFEF3E5851418707E367CDFD69C1451A86FC3A585141CA01FF8CC2FD69C1D09BF8803C585141CEE8489AC0FD69C1E76E447E3C585141C1DA5238C0FD69C1610A92F23B585141258AD5A2C0FD69C115E7BB033B58514118F32ED7BDFD69C1F4014E3736585141499C8B59BBFD69C1621A93203B585141799ACC35BAFD69C1DDCCE8B73D585141D7E3D0F0BAFD69C17C348DF13E5851417EC9DAE1BAFD69C1CB67526A3F585141DB52BE2FBAFD69C11B85C48A3F58514129564F4DBAFD69C126D91F7247585141642B1688BAFD69C1B160C5F44858514128249DADBBFD69C179257F194F5851411F4A735BBCFD69C128AC6A9A4E585141A1898D2CBDFD69C1C925D99E5058514191127527BFFD69C16B213D374F58514157C093BABFFD69C195F05C484F5851419BEDABB1BFFD69C1E06684CF50585141087D6004CCFD69C11A5374BD515851411A786B0FCCFD69C12D72DF954F5851419D2B3183CCFD69C1F070C99F4F585141BEA8DD92CCFD69C15A4D9F224C585141A93EE548CDFD69C15A4D9F224C585141E513AC83CDFD69C11AC1BFEF3E585141
132605510	amenity	parking	0106000020110F00000100000001030000000100000005000000CDAC572DCCFD69C1C069514020585141EAB44B62CBFD69C1B73F98740B585141A85D29DDC5FD69C196B0B24E0C58514132263AD2C3FD69C1512DD56821585141CDAC572DCCFD69C1C069514020585141
132605518	amenity	parking	0106000020110F000001000000010300000001000000050000008FC6B64BDEFD69C1B3C7000F1A5851417E07DAA7DDFD69C1D898E72B045851410072914ACFFD69C1F3BF2F5F06585141DB440B31D0FD69C18EA4BB191C5851418FC6B64BDEFD69C1B3C7000F1A585141
104597417	amenity	parking	0106000020110F00000100000001030000000100000005000000C9B8E14DFBFD69C196E759E6315851413250BBFDFAFD69C10E550102235851419293B722EFFD69C18AABF51C2558514125C91E9BEFFD69C1F25E94EC33585141C9B8E14DFBFD69C196E759E631585141
25821948	amenity	parking	0106000020110F00000100000001030000000100000008000000B291F295E2FD69C1C17522E1435851418192A481E2FD69C102E8CDDB41585141CE5DB863E2FD69C10DFBA3303F585141D309E141E2FD69C1399EE70A3C585141D290773BE2FD69C1D347616B3B58514140C43266DFFD69C1AAE3F3E53B58514135F377A3DFFD69C191E9B15244585141B291F295E2FD69C1C17522E143585141
112593518	amenity	parking	0106000020110F0000010000000103000000010000000C0000002FCFE38828FE69C1EBA894BE4B58514153521E3A1FFE69C1EB7042CA4C585141C487F3D41EFE69C1092055DA5058514116401C601EFE69C1AF1062F3555851414192345E1DFE69C13590CF6D5A585141123DF5B71AFE69C1393F48DD62585141F3D1A97B1FFE69C1D6D8331D65585141A2DD528920FE69C16F08D39F4E585141AD574C7C27FE69C1D93DBDC44F5851414D18C48827FE69C18ABF8DB44E585141BE1BE78328FE69C1F6A1D0DF4E5851412FCFE38828FE69C1EBA894BE4B585141
\.


--
-- Data for Name: water_line; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.water_line (osm_id, osm_type, osm_subtype, name, layer, tunnel, bridge, boat, geom) FROM stdin;
\.


--
-- Data for Name: water_point; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.water_point (osm_id, osm_type, osm_subtype, name, layer, tunnel, bridge, boat, geom) FROM stdin;
\.


--
-- Data for Name: water_polygon; Type: TABLE DATA; Schema: osm; Owner: postgres
--

COPY osm.water_polygon (osm_id, osm_type, osm_subtype, name, layer, tunnel, bridge, boat, geom) FROM stdin;
\.


--
-- Data for Name: road; Type: TABLE DATA; Schema: pgosm; Owner: postgres
--

COPY pgosm.road (id, region, osm_type, route_motor, route_foot, route_cycle, maxspeed) FROM stdin;
1	United States	motorway	t	f	f	104.61
2	United States	motorway_link	t	f	f	104.61
3	United States	trunk	t	f	t	96.56
4	United States	trunk_link	t	f	t	96.56
5	United States	primary	t	f	t	96.56
6	United States	primary_link	t	f	t	96.56
7	United States	secondary	t	f	t	72.42
8	United States	secondary_link	t	f	t	72.42
9	United States	tertiary	t	f	t	72.42
10	United States	tertiary_link	t	f	t	72.42
11	United States	residential	t	t	t	40.23
12	United States	service	t	t	t	40.23
13	United States	unclassified	t	t	t	30.00
14	United States	proposed	f	f	f	-1.00
15	United States	planned	f	f	f	-1.00
16	United States	path	f	t	t	4.00
17	United States	footway	f	t	f	4.00
18	United States	track	f	t	t	2.00
19	United States	pedestrian	f	t	f	4.00
20	United States	cycleway	f	t	t	32.00
21	United States	crossing	f	t	t	2.00
22	United States	platform	f	t	f	2.00
23	United States	social_path	f	t	f	3.00
24	United States	steps	f	t	f	2.00
25	United States	trailhead	f	t	t	3.00
\.


--
-- Data for Name: layer_styles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.layer_styles (id, f_table_catalog, f_table_schema, f_table_name, f_geometry_column, stylename, styleqml, stylesld, useasdefault, description, owner, ui, update_time, type) FROM stdin;
1	pgosm	osm	road_line	geom	osm_road_line	<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>\n<qgis maxScale="0" labelsEnabled="0" readOnly="0" styleCategories="AllStyleCategories" simplifyLocal="1" minScale="25000" version="3.16.1-Hannover" hasScaleBasedVisibilityFlag="0" simplifyDrawingTol="1" simplifyDrawingHints="1" simplifyAlgorithm="0" simplifyMaxScale="1">\n <flags>\n  <Identifiable>1</Identifiable>\n  <Removable>1</Removable>\n  <Searchable>1</Searchable>\n </flags>\n <temporal accumulate="0" startField="" startExpression="" endExpression="" fixedDuration="0" endField="" durationField="" enabled="0" durationUnit="min" mode="0">\n  <fixedRange>\n   <start></start>\n   <end></end>\n  </fixedRange>\n </temporal>\n <renderer-v2 symbollevels="0" forceraster="0" type="RuleRenderer" enableorderby="0">\n  <rules key="{c13d8e6b-872c-4920-8225-706a00f6e061}">\n   <rule key="{ab70c36a-fd09-41e5-8e70-532cb4eaad4b}" symbol="0" filter="ELSE" scalemaxdenom="20000" scalemindenom="1"/>\n   <rule key="{8707c673-9d1d-4b13-98b0-ba157753d504}" filter=" &quot;osm_type&quot; IN ( 'motorway' , 'trunk' )" label="motorway">\n    <rule key="{6f1c216a-4518-4066-a9d8-091a2a75eb25}" symbol="1" scalemaxdenom="10000" label="Motorway &lt; 10k"/>\n    <rule key="{7b8f4c97-f1ef-4d3e-a36a-7c2001e5dd49}" symbol="2" scalemaxdenom="40000" scalemindenom="10000" label="Motorway 10-40k"/>\n    <rule key="{fa6a489c-1af2-44f1-938f-50bad3b4f9b4}" symbol="3" scalemaxdenom="100000" scalemindenom="40000" label="Motorway 40-100k"/>\n    <rule key="{2a6c7f19-f94e-42fe-aa70-84e0a3c92f4d}" symbol="4" scalemindenom="100000" label="Motorway > 100k"/>\n   </rule>\n   <rule key="{9e4a609a-01d4-42a3-ae48-4f33d9e45ac5}" filter=" &quot;osm_type&quot; IN ( 'motorway_link' , 'trunk_link' )" label="motorway_link">\n    <rule key="{bad8d45a-40d1-4c29-b213-901adc869664}" symbol="5" scalemaxdenom="10000" label="0 - 10000"/>\n    <rule key="{a68b1236-ad96-4a55-b059-d5dcbdfa3652}" symbol="6" scalemaxdenom="40000" scalemindenom="10000" label="10000 - 40000"/>\n    <rule key="{34274842-afef-4734-af8a-253e0b2228d1}" symbol="7" scalemaxdenom="100000" scalemindenom="40000" label="40000 - 100000"/>\n    <rule key="{f3674b70-bfac-48f2-9f71-d9f752d4445e}" symbol="8" scalemindenom="100000" label="100000 - 0"/>\n   </rule>\n   <rule key="{5b935b53-ae8d-419e-8228-b4b4392a6b37}" filter=" &quot;osm_type&quot;  = 'primary' " label="primary">\n    <rule key="{369477b2-9880-4796-b58f-2c4c5f6f518d}" symbol="9" scalemaxdenom="10000" label="Primary &lt; 10k"/>\n    <rule key="{7f70ea5b-00cb-41b3-90a2-fa75ebb824bd}" symbol="10" scalemaxdenom="40000" scalemindenom="10000" label="Primary 10-40k"/>\n    <rule key="{8b50862e-2e6c-4eaf-be9f-0ddb0bfb4634}" symbol="11" scalemaxdenom="100000" scalemindenom="40000" label="Primary 40-100k"/>\n    <rule key="{d625ec6a-6979-47a1-90f9-d35ddb15088e}" symbol="12" scalemaxdenom="150000" scalemindenom="100000" label="Primary 100-150k"/>\n    <rule key="{0d658ee9-20ba-492d-b932-de8e7e3be152}" symbol="13" scalemindenom="150000" label="Primary > 150k"/>\n   </rule>\n   <rule key="{7197a67a-ca50-464e-b4f3-8afc3c59ff5d}" filter=" &quot;osm_type&quot;  = 'primary_link' " label="primary_link">\n    <rule key="{c2b8bfda-82bd-487b-8060-04ae1835835d}" symbol="14" scalemaxdenom="10000" label="Primary Link &lt; 10k"/>\n    <rule key="{91953c2d-0604-40ef-943e-4875b060e82a}" symbol="15" scalemaxdenom="40000" scalemindenom="10000" label="Primary Link 10-40k"/>\n    <rule key="{e43c2650-bf61-4186-8e37-425bcce08107}" symbol="16" scalemaxdenom="100000" scalemindenom="40000" label="Primary Link 40-100k"/>\n    <rule key="{3f114110-93d4-4da6-bc24-99957cac9515}" symbol="17" scalemaxdenom="150000" scalemindenom="100000" label="Primary Link 100-150k"/>\n    <rule key="{92e1ffa0-c49a-48c7-b6d0-aa9c9f909e35}" symbol="18" scalemindenom="150000" label="Primary Link > 150k"/>\n   </rule>\n   <rule key="{0728bd93-0b98-41c3-b647-d31cb2ce8db5}" filter=" &quot;osm_type&quot; IN ( 'secondary' , 'secondary_link' )" label="secondary">\n    <rule key="{cfe3f623-cac3-440f-be77-e83712c39f15}" symbol="19" scalemaxdenom="50000" scalemindenom="1" label="Secondary &lt; 10k"/>\n    <rule key="{3fab97bc-9167-47a4-8fca-e2e684bd1c87}" symbol="20" scalemaxdenom="80000" scalemindenom="10000" label="Secondary 10-50k"/>\n    <rule key="{4f7642a8-1ff2-4842-b4c6-ba838e70d03e}" symbol="21" scalemaxdenom="80000" scalemindenom="50000" label="Secondary 50-80k"/>\n    <rule key="{6a70e768-2ef4-4220-aecd-1c6587aae6b3}" symbol="22" scalemaxdenom="110000" scalemindenom="80000" label="Secondary 80-110k"/>\n    <rule key="{95f3d6fa-492c-4d91-990a-d77e1b024b00}" symbol="23" scalemaxdenom="200000" scalemindenom="110000" label="Secondary 110-200k"/>\n    <rule key="{431d94f7-d124-4f65-befd-68b41505e964}" symbol="24" scalemaxdenom="500000" scalemindenom="200000" label="Secondary 200-350k"/>\n   </rule>\n   <rule key="{3256c075-5558-4372-90ef-644809d9e34d}" filter=" &quot;osm_type&quot; IN ( 'tertiary' , 'tertiary_link' )" label="tertiary">\n    <rule key="{80b32985-3c90-4979-9659-1d85580febac}" symbol="25" scalemaxdenom="50000" scalemindenom="1" label="Tertiary &lt; 50k"/>\n    <rule key="{0fb6169a-0c12-4d2a-bdbc-80deddc2fe28}" symbol="26" scalemaxdenom="80000" scalemindenom="50000" label="Tertiary 50-80k"/>\n    <rule key="{72c67a60-4c0b-4af1-bce5-dfdeb024b12b}" symbol="27" scalemaxdenom="110000" scalemindenom="80000" label="Tertiary 80-110k"/>\n    <rule key="{fb814aab-a56d-427e-bc44-43c87e5d1335}" symbol="28" scalemaxdenom="200000" scalemindenom="110000" label="Tertiary 110-200k"/>\n   </rule>\n   <rule key="{25426803-5277-4c7c-a8d6-0124fdee071c}" filter=" &quot;osm_type&quot;  = 'residential' " label="residential">\n    <rule key="{2a6f4968-3485-4f89-b70c-1db564e105cc}" symbol="29" scalemaxdenom="10000" label="Residential &lt; 10k"/>\n    <rule key="{ae0199aa-9b1c-4021-b120-e9a5e06fa587}" symbol="30" scalemaxdenom="25000" scalemindenom="10000" label="Residential 10-25k"/>\n    <rule key="{6af53b1a-e56a-48be-b575-8596856acd77}" symbol="31" scalemaxdenom="50000" scalemindenom="25000" label="Residential 25-50k"/>\n    <rule key="{ed8f165f-27d5-4a64-8e12-178f6786f588}" symbol="32" scalemaxdenom="100000" scalemindenom="50000" label="Residential 50-100k"/>\n   </rule>\n   <rule key="{dac688bd-df49-42ac-a84b-1d17e3ff09be}" filter="osm_type IN ('road','service','turning_circle', 'unclassified')" label="road">\n    <rule key="{46fe9598-92e3-4116-aabb-39681a57998d}" symbol="33" scalemaxdenom="2000" label="0 - 2000"/>\n    <rule key="{f10c485e-87e7-4232-b4cc-d55621b9685a}" symbol="34" scalemaxdenom="5000" scalemindenom="2000" label="2000 - 5000"/>\n    <rule key="{fbee0ebf-9a27-4596-bc59-475f420ca4bc}" symbol="35" scalemaxdenom="10000" scalemindenom="5000" label="5000 - 10000"/>\n    <rule key="{ed2d9f64-76e5-4654-8f61-3a363a9375c2}" symbol="36" scalemaxdenom="45000" scalemindenom="10000" label="10000 - 45000"/>\n   </rule>\n   <rule key="{812bf89b-6891-4729-b3af-e1939d41a225}" filter="osm_type IN ('path', 'track', 'path;track', 'bridleway', 'cycleway', 'footway', 'living_street', 'pedestrian','trail')" scalemaxdenom="45000" scalemindenom="1" label="path">\n    <rule key="{e657a292-492f-46c7-83f5-8f0e7c130716}" symbol="37" scalemaxdenom="2000" scalemindenom="1" label="1 - 2000"/>\n    <rule key="{62a46839-0bd2-4edc-bb3f-94ab581e0112}" symbol="38" scalemaxdenom="5000" scalemindenom="2000" label="2000 - 5000"/>\n    <rule key="{16ce9b1d-2f47-4860-b0ef-6f76fe694cc3}" symbol="39" scalemaxdenom="10000" scalemindenom="5000" label="5000 - 10000"/>\n    <rule key="{0acc795c-5988-4a2e-ad8c-ad828bb1d13b}" symbol="40" scalemaxdenom="25000" scalemindenom="10000" label="10000 - 25000"/>\n    <rule key="{3aaf2c57-ffa8-4444-8da0-67c615421ddb}" symbol="41" scalemaxdenom="45000" scalemindenom="25000" label="25000 - 45000"/>\n   </rule>\n   <rule key="{52f969e6-e22f-44fc-acfe-df2613f0a31a}" symbol="42" filter="osm_type = 'raceway'" label="raceway"/>\n   <rule key="{824522d7-3389-47e1-8a85-a88d5388f370}" filter="highway = 'steps'" scalemaxdenom="45000" scalemindenom="1" label="steps">\n    <rule key="{faf6821f-bbe9-411d-9aff-71e8f5ce770d}" symbol="43" scalemaxdenom="2000" scalemindenom="1" label="1 - 2000"/>\n    <rule key="{3c0c7182-81b8-4697-af2e-83952d9fcefe}" symbol="44" scalemaxdenom="5000" scalemindenom="2000" label="2000 - 5000"/>\n    <rule key="{871ba29f-cc71-4c97-9903-66aa748391b5}" symbol="45" scalemaxdenom="10000" scalemindenom="5000" label="5000 - 10000"/>\n    <rule key="{4f09a5a6-723a-42c5-abbd-839f0130dc7e}" symbol="46" scalemaxdenom="25000" scalemindenom="10000" label="10000 - 25000"/>\n    <rule key="{05caafa2-ffd1-4d04-97ad-c5a88e6d9fe7}" symbol="47" scalemaxdenom="45000" scalemindenom="25000" label="25000 - 45000"/>\n   </rule>\n  </rules>\n  <symbols>\n   <symbol alpha="1" type="line" name="0" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="250,0,254,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.26"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="1" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="5.46"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="20" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="94,146,148,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="5.03565"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="10" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.56"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="18" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.36"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="11" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.16"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="18" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.03865"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="12" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.56"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="18" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.47236"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="13" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.96"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="18" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.906067"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="14" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.5"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.2619"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="15" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.1"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.9"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="16" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.7"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.5381"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="17" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.1"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.995238"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="18" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.5"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.452381"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="19" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.7"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="2" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.86"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="20" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="94,146,148,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.56"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="20" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.5"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="21" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.3"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="22" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.9"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="23" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.7"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="24" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.7"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="25" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.3"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="26" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.9"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="27" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.3"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="28" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.5"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="29" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="7" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="80,80,80,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.16"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="14" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.09095"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="3" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.06"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="20" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="94,146,148,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.82218"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="30" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="7" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="80,80,80,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.66"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="14" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.620715"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="31" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="7" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="80,80,80,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.26"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="14" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.244524"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="32" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="7" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="80,80,80,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.26"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="14" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="233,150,91,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.244524"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="33" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="238,137,65,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.06"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="34" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="238,137,65,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.86"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="35" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="238,137,65,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.66"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="36" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="238,137,65,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="0.16"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="37" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.53"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="38" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.53"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="39" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.43"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="4" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.26"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="20" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="94,146,148,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.08436"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="40" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.23"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="41" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.13"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="42" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="square"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="line_color" v="208,110,40,255"/>\n     <prop k="line_style" v="dash dot"/>\n     <prop k="line_width" v="0.46"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="43" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="2;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.83"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="1"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="44" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="2;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.53"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="1"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="45" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="2;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.43"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="1"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="46" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="2;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.23"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="1"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="47" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="2" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="2;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="227,26,28,255"/>\n     <prop k="line_style" v="dot"/>\n     <prop k="line_width" v="0.13"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="1"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="5" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.6"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="100,165,165,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.48182"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="6" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.2"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="100,165,165,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2.1"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="7" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="2"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="100,165,165,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.90909"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="8" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="20,50,50,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.6"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="16" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="100,165,165,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="1.52727"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="line" name="9" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleLine" locked="1" pass="0" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="76,38,0,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.96"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer class="SimpleLine" locked="0" pass="18" enabled="1">\n     <prop k="align_dash_pattern" v="0"/>\n     <prop k="capstyle" v="round"/>\n     <prop k="customdash" v="5;2"/>\n     <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="customdash_unit" v="MM"/>\n     <prop k="dash_pattern_offset" v="0"/>\n     <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="dash_pattern_offset_unit" v="MM"/>\n     <prop k="draw_inside_polygon" v="0"/>\n     <prop k="joinstyle" v="round"/>\n     <prop k="line_color" v="255,206,128,255"/>\n     <prop k="line_style" v="solid"/>\n     <prop k="line_width" v="3.73753"/>\n     <prop k="line_width_unit" v="MM"/>\n     <prop k="offset" v="0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="ring_filter" v="0"/>\n     <prop k="tweak_dash_pattern_on_corners" v="0"/>\n     <prop k="use_custom_dash" v="0"/>\n     <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n  </symbols>\n </renderer-v2>\n <customproperties>\n  <property key="embeddedWidgets/count" value="0"/>\n  <property key="variableNames"/>\n  <property key="variableValues"/>\n </customproperties>\n <blendMode>0</blendMode>\n <featureBlendMode>0</featureBlendMode>\n <layerOpacity>1</layerOpacity>\n <SingleCategoryDiagramRenderer attributeLegend="1" diagramType="Pie">\n  <DiagramCategory penWidth="0" labelPlacementMethod="XHeight" scaleDependency="Area" height="15" showAxis="0" backgroundColor="#ffffff" barWidth="5" sizeScale="3x:0,0,0,0,0,0" scaleBasedVisibility="0" sizeType="MM" direction="1" penAlpha="255" diagramOrientation="Up" lineSizeScale="3x:0,0,0,0,0,0" maxScaleDenominator="25000" spacingUnit="MM" minimumSize="0" rotationOffset="270" width="15" spacing="0" backgroundAlpha="255" opacity="1" spacingUnitScale="3x:0,0,0,0,0,0" penColor="#000000" lineSizeType="MM" enabled="0" minScaleDenominator="0">\n   <fontProperties style="" description=".SF NS Text,13,-1,5,50,0,0,0,0,0"/>\n   <attribute label="" color="#000000" field=""/>\n   <axisSymbol>\n    <symbol alpha="1" type="line" name="" clip_to_extent="1" force_rhr="0">\n     <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n      <prop k="align_dash_pattern" v="0"/>\n      <prop k="capstyle" v="square"/>\n      <prop k="customdash" v="5;2"/>\n      <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <prop k="customdash_unit" v="MM"/>\n      <prop k="dash_pattern_offset" v="0"/>\n      <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <prop k="dash_pattern_offset_unit" v="MM"/>\n      <prop k="draw_inside_polygon" v="0"/>\n      <prop k="joinstyle" v="bevel"/>\n      <prop k="line_color" v="35,35,35,255"/>\n      <prop k="line_style" v="solid"/>\n      <prop k="line_width" v="0.26"/>\n      <prop k="line_width_unit" v="MM"/>\n      <prop k="offset" v="0"/>\n      <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <prop k="offset_unit" v="MM"/>\n      <prop k="ring_filter" v="0"/>\n      <prop k="tweak_dash_pattern_on_corners" v="0"/>\n      <prop k="use_custom_dash" v="0"/>\n      <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <data_defined_properties>\n       <Option type="Map">\n        <Option type="QString" name="name" value=""/>\n        <Option name="properties"/>\n        <Option type="QString" name="type" value="collection"/>\n       </Option>\n      </data_defined_properties>\n     </layer>\n    </symbol>\n   </axisSymbol>\n  </DiagramCategory>\n </SingleCategoryDiagramRenderer>\n <DiagramLayerSettings zIndex="0" obstacle="0" placement="2" showAll="1" linePlacementFlags="2" dist="0" priority="0">\n  <properties>\n   <Option type="Map">\n    <Option type="QString" name="name" value=""/>\n    <Option name="properties"/>\n    <Option type="QString" name="type" value="collection"/>\n   </Option>\n  </properties>\n </DiagramLayerSettings>\n <geometryOptions removeDuplicateNodes="0" geometryPrecision="0">\n  <activeChecks/>\n  <checkConfiguration/>\n </geometryOptions>\n <legend type="default-vector"/>\n <referencedLayers/>\n <fieldConfiguration>\n  <field name="way_id" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="osm_type" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="name" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="ref" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="maxspeed" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="oneway" configurationFlags="None">\n   <editWidget type="Range">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="tags" configurationFlags="None">\n   <editWidget type="KeyValue">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n </fieldConfiguration>\n <aliases>\n  <alias name="" field="way_id" index="0"/>\n  <alias name="" field="osm_type" index="1"/>\n  <alias name="" field="name" index="2"/>\n  <alias name="" field="ref" index="3"/>\n  <alias name="" field="maxspeed" index="4"/>\n  <alias name="" field="oneway" index="5"/>\n  <alias name="" field="tags" index="6"/>\n </aliases>\n <defaults>\n  <default expression="" applyOnUpdate="0" field="way_id"/>\n  <default expression="" applyOnUpdate="0" field="osm_type"/>\n  <default expression="" applyOnUpdate="0" field="name"/>\n  <default expression="" applyOnUpdate="0" field="ref"/>\n  <default expression="" applyOnUpdate="0" field="maxspeed"/>\n  <default expression="" applyOnUpdate="0" field="oneway"/>\n  <default expression="" applyOnUpdate="0" field="tags"/>\n </defaults>\n <constraints>\n  <constraint constraints="1" unique_strength="0" notnull_strength="1" exp_strength="0" field="way_id"/>\n  <constraint constraints="1" unique_strength="0" notnull_strength="1" exp_strength="0" field="osm_type"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="name"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="ref"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="maxspeed"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="oneway"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="tags"/>\n </constraints>\n <constraintExpressions>\n  <constraint desc="" exp="" field="way_id"/>\n  <constraint desc="" exp="" field="osm_type"/>\n  <constraint desc="" exp="" field="name"/>\n  <constraint desc="" exp="" field="ref"/>\n  <constraint desc="" exp="" field="maxspeed"/>\n  <constraint desc="" exp="" field="oneway"/>\n  <constraint desc="" exp="" field="tags"/>\n </constraintExpressions>\n <expressionfields/>\n <attributeactions>\n  <defaultAction key="Canvas" value="{00000000-0000-0000-0000-000000000000}"/>\n </attributeactions>\n <attributetableconfig actionWidgetStyle="dropDown" sortExpression="" sortOrder="0">\n  <columns>\n   <column hidden="0" type="field" name="name" width="-1"/>\n   <column hidden="0" type="field" name="ref" width="-1"/>\n   <column hidden="1" type="actions" width="-1"/>\n   <column hidden="0" type="field" name="maxspeed" width="-1"/>\n   <column hidden="0" type="field" name="osm_type" width="-1"/>\n   <column hidden="0" type="field" name="tags" width="-1"/>\n   <column hidden="0" type="field" name="way_id" width="-1"/>\n   <column hidden="0" type="field" name="oneway" width="-1"/>\n  </columns>\n </attributetableconfig>\n <conditionalstyles>\n  <rowstyles/>\n  <fieldstyles/>\n </conditionalstyles>\n <storedexpressions/>\n <editform tolerant="1"></editform>\n <editforminit/>\n <editforminitcodesource>0</editforminitcodesource>\n <editforminitfilepath></editforminitfilepath>\n <editforminitcode><![CDATA[# -*- coding: utf-8 -*-\n"""\nQGIS forms can have a Python function that is called when the form is\nopened.\n\nUse this function to add extra logic to your forms.\n\nEnter the name of the function in the "Python Init function"\nfield.\nAn example follows:\n"""\nfrom qgis.PyQt.QtWidgets import QWidget\n\ndef my_form_open(dialog, layer, feature):\n\tgeom = feature.geometry()\n\tcontrol = dialog.findChild(QWidget, "MyLineEdit")\n]]></editforminitcode>\n <featformsuppress>0</featformsuppress>\n <editorlayout>generatedlayout</editorlayout>\n <editable>\n  <field editable="1" name="?column?"/>\n  <field editable="1" name="code"/>\n  <field editable="1" name="highway"/>\n  <field editable="1" name="maxspeed"/>\n  <field editable="1" name="name"/>\n  <field editable="1" name="oneway"/>\n  <field editable="1" name="osm_id"/>\n  <field editable="1" name="osm_type"/>\n  <field editable="1" name="ref"/>\n  <field editable="1" name="tags"/>\n  <field editable="1" name="tracktype"/>\n  <field editable="1" name="traffic"/>\n  <field editable="1" name="way_id"/>\n </editable>\n <labelOnTop>\n  <field name="?column?" labelOnTop="0"/>\n  <field name="code" labelOnTop="0"/>\n  <field name="highway" labelOnTop="0"/>\n  <field name="maxspeed" labelOnTop="0"/>\n  <field name="name" labelOnTop="0"/>\n  <field name="oneway" labelOnTop="0"/>\n  <field name="osm_id" labelOnTop="0"/>\n  <field name="osm_type" labelOnTop="0"/>\n  <field name="ref" labelOnTop="0"/>\n  <field name="tags" labelOnTop="0"/>\n  <field name="tracktype" labelOnTop="0"/>\n  <field name="traffic" labelOnTop="0"/>\n  <field name="way_id" labelOnTop="0"/>\n </labelOnTop>\n <dataDefinedFieldProperties/>\n <widgets/>\n <previewExpression>"osm_id"</previewExpression>\n <mapTip>addr:housename</mapTip>\n <layerGeometryType>1</layerGeometryType>\n</qgis>\n	<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" xmlns:se="http://www.opengis.net/se" xmlns:ogc="http://www.opengis.net/ogc" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.1.0/StyledLayerDescriptor.xsd" version="1.1.0">\n <NamedLayer>\n  <se:Name>road_line</se:Name>\n  <UserStyle>\n   <se:Name>road_line</se:Name>\n   <se:FeatureTypeStyle>\n    <se:Rule>\n     <se:Name></se:Name>\n     <!--Parser Error: \nsyntax error, unexpected ELSE - Expression was: ELSE-->\n     <se:MinScaleDenominator>1</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>20000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#fa00fe</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Motorway &lt; 10k</se:Name>\n     <se:Description>\n      <se:Title>Motorway &lt; 10k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">20</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#5e9294</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">18</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Motorway 10-40k</se:Name>\n     <se:Description>\n      <se:Title>Motorway 10-40k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>40000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">14</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#5e9294</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">13</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Motorway 40-100k</se:Name>\n     <se:Description>\n      <se:Title>Motorway 40-100k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>40000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>100000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">11</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#5e9294</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">10</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Motorway > 100k</se:Name>\n     <se:Description>\n      <se:Title>Motorway > 100k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>100000</se:MinScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">8</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#5e9294</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">7</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>0 - 10000</se:Name>\n     <se:Description>\n      <se:Title>0 - 10000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">9</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#64a5a5</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">9</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>10000 - 40000</se:Name>\n     <se:Description>\n      <se:Title>10000 - 40000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>40000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">8</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#64a5a5</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">8</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>40000 - 100000</se:Name>\n     <se:Description>\n      <se:Title>40000 - 100000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>40000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>100000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">7</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#64a5a5</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">7</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>100000 - 0</se:Name>\n     <se:Description>\n      <se:Title>100000 - 0</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>motorway_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trunk_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>100000</se:MinScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#143232</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">6</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#64a5a5</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary &lt; 10k</se:Name>\n     <se:Description>\n      <se:Title>Primary &lt; 10k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">14</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">13</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary 10-40k</se:Name>\n     <se:Description>\n      <se:Title>Primary 10-40k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>40000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">13</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">12</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary 40-100k</se:Name>\n     <se:Description>\n      <se:Title>Primary 40-100k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>40000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>100000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">8</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">7</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary 100-150k</se:Name>\n     <se:Description>\n      <se:Title>Primary 100-150k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>100000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>150000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">6</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary > 150k</se:Name>\n     <se:Description>\n      <se:Title>Primary > 150k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>150000</se:MinScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">3</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">3</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary Link &lt; 10k</se:Name>\n     <se:Description>\n      <se:Title>Primary Link &lt; 10k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary_link</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">9</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">8</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary Link 10-40k</se:Name>\n     <se:Description>\n      <se:Title>Primary Link 10-40k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary_link</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>40000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">8</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">7</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary Link 40-100k</se:Name>\n     <se:Description>\n      <se:Title>Primary Link 40-100k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary_link</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>40000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>100000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">6</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary Link 100-150k</se:Name>\n     <se:Description>\n      <se:Title>Primary Link 100-150k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary_link</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>100000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>150000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">4</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">4</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Primary Link > 150k</se:Name>\n     <se:Description>\n      <se:Title>Primary Link > 150k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>primary_link</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>150000</se:MinScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#4c2600</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ffce80</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Secondary &lt; 10k</se:Name>\n     <se:Description>\n      <se:Title>Secondary &lt; 10k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>1</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>50000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">10</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Secondary 10-50k</se:Name>\n     <se:Description>\n      <se:Title>Secondary 10-50k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>80000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Secondary 50-80k</se:Name>\n     <se:Description>\n      <se:Title>Secondary 50-80k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>50000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>80000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Secondary 80-110k</se:Name>\n     <se:Description>\n      <se:Title>Secondary 80-110k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>80000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>110000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">3</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Secondary 110-200k</se:Name>\n     <se:Description>\n      <se:Title>Secondary 110-200k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>110000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>200000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Secondary 200-350k</se:Name>\n     <se:Description>\n      <se:Title>Secondary 200-350k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>secondary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>200000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>500000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Tertiary &lt; 50k</se:Name>\n     <se:Description>\n      <se:Title>Tertiary &lt; 50k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>1</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>50000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Tertiary 50-80k</se:Name>\n     <se:Description>\n      <se:Title>Tertiary 50-80k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>50000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>80000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">3</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Tertiary 80-110k</se:Name>\n     <se:Description>\n      <se:Title>Tertiary 80-110k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>80000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>110000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Tertiary 110-200k</se:Name>\n     <se:Description>\n      <se:Title>Tertiary 110-200k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>tertiary_link</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>110000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>200000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Residential &lt; 10k</se:Name>\n     <se:Description>\n      <se:Title>Residential &lt; 10k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>residential</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#505050</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">4</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">4</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Residential 10-25k</se:Name>\n     <se:Description>\n      <se:Title>Residential 10-25k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>residential</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>25000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#505050</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Residential 25-50k</se:Name>\n     <se:Description>\n      <se:Title>Residential 25-50k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>residential</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>25000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>50000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#505050</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Residential 50-100k</se:Name>\n     <se:Description>\n      <se:Title>Residential 50-100k</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>residential</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>50000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>100000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#505050</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e9965b</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>0 - 2000</se:Name>\n     <se:Description>\n      <se:Title>0 - 2000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>road</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>service</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>turning_circle</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>unclassified</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>2000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ee8941</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">4</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>2000 - 5000</se:Name>\n     <se:Description>\n      <se:Title>2000 - 5000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>road</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>service</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>turning_circle</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>unclassified</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>2000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>5000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ee8941</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">3</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>5000 - 10000</se:Name>\n     <se:Description>\n      <se:Title>5000 - 10000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>road</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>service</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>turning_circle</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>unclassified</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>5000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ee8941</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>10000 - 45000</se:Name>\n     <se:Description>\n      <se:Title>10000 - 45000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>road</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>service</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>turning_circle</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>unclassified</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>45000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#ee8941</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>1 - 2000</se:Name>\n     <se:Description>\n      <se:Title>1 - 2000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path;track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>bridleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>cycleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>footway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>living_street</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>pedestrian</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trail</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>1</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>2000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">1 2</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>2000 - 5000</se:Name>\n     <se:Description>\n      <se:Title>2000 - 5000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path;track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>bridleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>cycleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>footway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>living_street</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>pedestrian</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trail</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>2000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>5000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">1 2</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>5000 - 10000</se:Name>\n     <se:Description>\n      <se:Title>5000 - 10000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path;track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>bridleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>cycleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>footway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>living_street</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>pedestrian</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trail</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>5000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">1 2</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>10000 - 25000</se:Name>\n     <se:Description>\n      <se:Title>10000 - 25000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path;track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>bridleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>cycleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>footway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>living_street</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>pedestrian</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trail</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>25000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">1 2</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>25000 - 45000</se:Name>\n     <se:Description>\n      <se:Title>25000 - 45000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>path;track</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>bridleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>cycleway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>footway</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>living_street</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>pedestrian</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>trail</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:MinScaleDenominator>25000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>45000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">0.5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">1 2</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>raceway</se:Name>\n     <se:Description>\n      <se:Title>raceway</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>raceway</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#d06e28</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">4 2 1 2</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>1 - 2000</se:Name>\n     <se:Description>\n      <se:Title>1 - 2000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>highway</ogc:PropertyName>\n       <ogc:Literal>steps</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>1</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>2000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">3</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">7 7</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>2000 - 5000</se:Name>\n     <se:Description>\n      <se:Title>2000 - 5000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>highway</ogc:PropertyName>\n       <ogc:Literal>steps</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>2000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>5000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">7 7</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>5000 - 10000</se:Name>\n     <se:Description>\n      <se:Title>5000 - 10000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>highway</ogc:PropertyName>\n       <ogc:Literal>steps</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>5000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>10000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">7 7</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>10000 - 25000</se:Name>\n     <se:Description>\n      <se:Title>10000 - 25000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>highway</ogc:PropertyName>\n       <ogc:Literal>steps</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>25000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">7 7</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>25000 - 45000</se:Name>\n     <se:Description>\n      <se:Title>25000 - 45000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>highway</ogc:PropertyName>\n       <ogc:Literal>steps</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>25000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>45000</se:MaxScaleDenominator>\n     <se:LineSymbolizer>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#e31a1c</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">0.5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-linecap">round</se:SvgParameter>\n       <se:SvgParameter name="stroke-dasharray">7 7</se:SvgParameter>\n      </se:Stroke>\n     </se:LineSymbolizer>\n    </se:Rule>\n   </se:FeatureTypeStyle>\n  </UserStyle>\n </NamedLayer>\n</StyledLayerDescriptor>\n	t	OpenStreetMap roads styling for use with PgOSM-Flex styles.  Sub-layer logic based on osm_type column storing values from highway tags in OSM.	rustprooflabs	\N	2020-12-22 22:10:30.13422	\N
2	pgosm	osm	building_polygon	geom	osm_building_polygon	<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>\n<qgis maxScale="-4.656612873077393e-10" labelsEnabled="0" readOnly="0" styleCategories="AllStyleCategories" simplifyLocal="1" minScale="100000000" version="3.16.1-Hannover" hasScaleBasedVisibilityFlag="0" simplifyDrawingTol="1" simplifyDrawingHints="1" simplifyAlgorithm="0" simplifyMaxScale="1">\n <flags>\n  <Identifiable>1</Identifiable>\n  <Removable>1</Removable>\n  <Searchable>1</Searchable>\n </flags>\n <temporal accumulate="0" startField="" startExpression="" endExpression="" fixedDuration="0" endField="" durationField="" enabled="0" durationUnit="min" mode="0">\n  <fixedRange>\n   <start></start>\n   <end></end>\n  </fixedRange>\n </temporal>\n <renderer-v2 symbollevels="0" forceraster="0" type="RuleRenderer" enableorderby="0">\n  <rules key="{c2c73c7d-59b0-44da-9930-178fe0f6a20c}">\n   <rule key="{d944a184-2dfb-4a62-a484-2c21e03266a5}" filter="True" label="Buildings">\n    <rule key="{a0319868-ab10-49f4-95a0-01c3fedf4302}" symbol="0" scalemaxdenom="1000" label="Buildings &lt; 1k"/>\n    <rule key="{72883be8-708d-4bd8-912f-5994bbcea039}" symbol="1" scalemaxdenom="2000" scalemindenom="1000" label="Buildings 1-2k"/>\n    <rule key="{16abd420-1662-4cae-b97d-eb73acd4fb0c}" symbol="2" scalemaxdenom="5000" scalemindenom="2000" label="Buildings 2-5k"/>\n    <rule key="{9cc89847-46ca-4749-85c3-cf72817ac9c6}" symbol="3" scalemaxdenom="30000" scalemindenom="5000" label="Buildings 5-30k"/>\n    <rule key="{efe0b22b-6c27-406d-99d3-f4d20d4bb773}" symbol="4" scalemaxdenom="45000" scalemindenom="30000" label="Buildings 30-45k"/>\n    <rule key="{782c567f-d3f6-4aca-a75b-33bd9bcbd888}" symbol="5" scalemaxdenom="75000" scalemindenom="45000" label="Buildings 45-75k"/>\n   </rule>\n  </rules>\n  <symbols>\n   <symbol alpha="1" type="fill" name="0" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleFill" locked="0" pass="0" enabled="1">\n     <prop k="border_width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="color" v="227,227,227,255"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="offset" v="0,0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="outline_color" v="0,0,0,255"/>\n     <prop k="outline_style" v="solid"/>\n     <prop k="outline_width" v="0.26"/>\n     <prop k="outline_width_unit" v="MM"/>\n     <prop k="style" v="solid"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="fill" name="1" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleFill" locked="0" pass="0" enabled="1">\n     <prop k="border_width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="color" v="227,227,227,255"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="offset" v="0,0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="outline_color" v="103,103,103,255"/>\n     <prop k="outline_style" v="solid"/>\n     <prop k="outline_width" v="0.26"/>\n     <prop k="outline_width_unit" v="MM"/>\n     <prop k="style" v="solid"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="fill" name="2" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleFill" locked="0" pass="0" enabled="1">\n     <prop k="border_width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="color" v="227,227,227,255"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="offset" v="0,0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="outline_color" v="103,103,103,255"/>\n     <prop k="outline_style" v="solid"/>\n     <prop k="outline_width" v="0.26"/>\n     <prop k="outline_width_unit" v="MM"/>\n     <prop k="style" v="solid"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" type="fill" name="3" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleFill" locked="0" pass="0" enabled="1">\n     <prop k="border_width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="color" v="227,227,227,255"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="offset" v="0,0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="outline_color" v="125,125,125,255"/>\n     <prop k="outline_style" v="solid"/>\n     <prop k="outline_width" v="0.26"/>\n     <prop k="outline_width_unit" v="MM"/>\n     <prop k="style" v="solid"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="0.862745" type="fill" name="4" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleFill" locked="0" pass="0" enabled="1">\n     <prop k="border_width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="color" v="227,227,227,255"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="offset" v="0,0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="outline_color" v="125,125,125,165"/>\n     <prop k="outline_style" v="solid"/>\n     <prop k="outline_width" v="0.06"/>\n     <prop k="outline_width_unit" v="MM"/>\n     <prop k="style" v="solid"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="0.752941" type="fill" name="5" clip_to_extent="1" force_rhr="0">\n    <layer class="SimpleFill" locked="0" pass="0" enabled="1">\n     <prop k="border_width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="color" v="227,227,227,255"/>\n     <prop k="joinstyle" v="bevel"/>\n     <prop k="offset" v="0,0"/>\n     <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n     <prop k="offset_unit" v="MM"/>\n     <prop k="outline_color" v="125,125,125,39"/>\n     <prop k="outline_style" v="solid"/>\n     <prop k="outline_width" v="0.06"/>\n     <prop k="outline_width_unit" v="MM"/>\n     <prop k="style" v="solid"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" name="name" value=""/>\n       <Option name="properties"/>\n       <Option type="QString" name="type" value="collection"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n  </symbols>\n </renderer-v2>\n <customproperties>\n  <property key="embeddedWidgets/count" value="0"/>\n  <property key="variableNames"/>\n  <property key="variableValues"/>\n </customproperties>\n <blendMode>0</blendMode>\n <featureBlendMode>0</featureBlendMode>\n <layerOpacity>1</layerOpacity>\n <SingleCategoryDiagramRenderer attributeLegend="1" diagramType="Histogram">\n  <DiagramCategory penWidth="0" labelPlacementMethod="XHeight" scaleDependency="Area" height="15" showAxis="0" backgroundColor="#ffffff" barWidth="5" sizeScale="3x:0,0,0,0,0,0" scaleBasedVisibility="0" sizeType="MM" direction="1" penAlpha="255" diagramOrientation="Up" lineSizeScale="3x:0,0,0,0,0,0" maxScaleDenominator="1e+08" spacingUnit="MM" minimumSize="0" rotationOffset="270" width="15" spacing="0" backgroundAlpha="255" opacity="1" spacingUnitScale="3x:0,0,0,0,0,0" penColor="#000000" lineSizeType="MM" enabled="0" minScaleDenominator="-4.65661e-10">\n   <fontProperties style="" description="Ubuntu,11,-1,5,50,0,0,0,0,0"/>\n   <attribute label="" color="#000000" field=""/>\n   <axisSymbol>\n    <symbol alpha="1" type="line" name="" clip_to_extent="1" force_rhr="0">\n     <layer class="SimpleLine" locked="0" pass="0" enabled="1">\n      <prop k="align_dash_pattern" v="0"/>\n      <prop k="capstyle" v="square"/>\n      <prop k="customdash" v="5;2"/>\n      <prop k="customdash_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <prop k="customdash_unit" v="MM"/>\n      <prop k="dash_pattern_offset" v="0"/>\n      <prop k="dash_pattern_offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <prop k="dash_pattern_offset_unit" v="MM"/>\n      <prop k="draw_inside_polygon" v="0"/>\n      <prop k="joinstyle" v="bevel"/>\n      <prop k="line_color" v="35,35,35,255"/>\n      <prop k="line_style" v="solid"/>\n      <prop k="line_width" v="0.26"/>\n      <prop k="line_width_unit" v="MM"/>\n      <prop k="offset" v="0"/>\n      <prop k="offset_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <prop k="offset_unit" v="MM"/>\n      <prop k="ring_filter" v="0"/>\n      <prop k="tweak_dash_pattern_on_corners" v="0"/>\n      <prop k="use_custom_dash" v="0"/>\n      <prop k="width_map_unit_scale" v="3x:0,0,0,0,0,0"/>\n      <data_defined_properties>\n       <Option type="Map">\n        <Option type="QString" name="name" value=""/>\n        <Option name="properties"/>\n        <Option type="QString" name="type" value="collection"/>\n       </Option>\n      </data_defined_properties>\n     </layer>\n    </symbol>\n   </axisSymbol>\n  </DiagramCategory>\n </SingleCategoryDiagramRenderer>\n <DiagramLayerSettings zIndex="0" obstacle="0" placement="1" showAll="1" linePlacementFlags="18" dist="0" priority="0">\n  <properties>\n   <Option type="Map">\n    <Option type="QString" name="name" value=""/>\n    <Option name="properties"/>\n    <Option type="QString" name="type" value="collection"/>\n   </Option>\n  </properties>\n </DiagramLayerSettings>\n <geometryOptions removeDuplicateNodes="0" geometryPrecision="0">\n  <activeChecks/>\n  <checkConfiguration type="Map">\n   <Option type="Map" name="QgsGeometryGapCheck">\n    <Option type="double" name="allowedGapsBuffer" value="0"/>\n    <Option type="bool" name="allowedGapsEnabled" value="false"/>\n    <Option type="QString" name="allowedGapsLayer" value=""/>\n   </Option>\n  </checkConfiguration>\n </geometryOptions>\n <legend type="default-vector"/>\n <referencedLayers/>\n <fieldConfiguration>\n  <field name="osm_id" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="osm_type" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="name" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="levels" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="height" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="housenumber" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="street" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="city" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="state" configurationFlags="None">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="wheelchair" configurationFlags="None">\n   <editWidget type="CheckBox">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field name="tags" configurationFlags="None">\n   <editWidget type="KeyValue">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n </fieldConfiguration>\n <aliases>\n  <alias name="" field="osm_id" index="0"/>\n  <alias name="" field="osm_type" index="1"/>\n  <alias name="" field="name" index="2"/>\n  <alias name="" field="levels" index="3"/>\n  <alias name="" field="height" index="4"/>\n  <alias name="" field="housenumber" index="5"/>\n  <alias name="" field="street" index="6"/>\n  <alias name="" field="city" index="7"/>\n  <alias name="" field="state" index="8"/>\n  <alias name="" field="wheelchair" index="9"/>\n  <alias name="" field="tags" index="10"/>\n </aliases>\n <defaults>\n  <default expression="" applyOnUpdate="0" field="osm_id"/>\n  <default expression="" applyOnUpdate="0" field="osm_type"/>\n  <default expression="" applyOnUpdate="0" field="name"/>\n  <default expression="" applyOnUpdate="0" field="levels"/>\n  <default expression="" applyOnUpdate="0" field="height"/>\n  <default expression="" applyOnUpdate="0" field="housenumber"/>\n  <default expression="" applyOnUpdate="0" field="street"/>\n  <default expression="" applyOnUpdate="0" field="city"/>\n  <default expression="" applyOnUpdate="0" field="state"/>\n  <default expression="" applyOnUpdate="0" field="wheelchair"/>\n  <default expression="" applyOnUpdate="0" field="tags"/>\n </defaults>\n <constraints>\n  <constraint constraints="1" unique_strength="0" notnull_strength="1" exp_strength="0" field="osm_id"/>\n  <constraint constraints="1" unique_strength="0" notnull_strength="1" exp_strength="0" field="osm_type"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="name"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="levels"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="height"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="housenumber"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="street"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="city"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="state"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="wheelchair"/>\n  <constraint constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0" field="tags"/>\n </constraints>\n <constraintExpressions>\n  <constraint desc="" exp="" field="osm_id"/>\n  <constraint desc="" exp="" field="osm_type"/>\n  <constraint desc="" exp="" field="name"/>\n  <constraint desc="" exp="" field="levels"/>\n  <constraint desc="" exp="" field="height"/>\n  <constraint desc="" exp="" field="housenumber"/>\n  <constraint desc="" exp="" field="street"/>\n  <constraint desc="" exp="" field="city"/>\n  <constraint desc="" exp="" field="state"/>\n  <constraint desc="" exp="" field="wheelchair"/>\n  <constraint desc="" exp="" field="tags"/>\n </constraintExpressions>\n <expressionfields/>\n <attributeactions>\n  <defaultAction key="Canvas" value="{00000000-0000-0000-0000-000000000000}"/>\n </attributeactions>\n <attributetableconfig actionWidgetStyle="dropDown" sortExpression="" sortOrder="0">\n  <columns>\n   <column hidden="0" type="field" name="osm_id" width="-1"/>\n   <column hidden="0" type="field" name="name" width="-1"/>\n   <column hidden="0" type="field" name="tags" width="-1"/>\n   <column hidden="1" type="actions" width="-1"/>\n   <column hidden="0" type="field" name="housenumber" width="-1"/>\n   <column hidden="0" type="field" name="levels" width="-1"/>\n   <column hidden="0" type="field" name="height" width="-1"/>\n   <column hidden="0" type="field" name="osm_type" width="-1"/>\n   <column hidden="0" type="field" name="street" width="-1"/>\n   <column hidden="0" type="field" name="city" width="-1"/>\n   <column hidden="0" type="field" name="state" width="-1"/>\n   <column hidden="0" type="field" name="wheelchair" width="-1"/>\n  </columns>\n </attributetableconfig>\n <conditionalstyles>\n  <rowstyles/>\n  <fieldstyles/>\n </conditionalstyles>\n <storedexpressions/>\n <editform tolerant="1"></editform>\n <editforminit/>\n <editforminitcodesource>0</editforminitcodesource>\n <editforminitfilepath></editforminitfilepath>\n <editforminitcode><![CDATA[# -*- coding: utf-8 -*-\n"""\nQGIS forms can have a Python function that is called when the form is\nopened.\n\nUse this function to add extra logic to your forms.\n\nEnter the name of the function in the "Python Init function"\nfield.\nAn example follows:\n"""\nfrom qgis.PyQt.QtWidgets import QWidget\n\ndef my_form_open(dialog, layer, feature):\n\tgeom = feature.geometry()\n\tcontrol = dialog.findChild(QWidget, "MyLineEdit")\n]]></editforminitcode>\n <featformsuppress>0</featformsuppress>\n <editorlayout>generatedlayout</editorlayout>\n <editable>\n  <field editable="1" name="addr:housename"/>\n  <field editable="1" name="addr:housenumber"/>\n  <field editable="1" name="addr:interpolation"/>\n  <field editable="1" name="building"/>\n  <field editable="1" name="city"/>\n  <field editable="1" name="code"/>\n  <field editable="1" name="height"/>\n  <field editable="1" name="housename"/>\n  <field editable="1" name="housenumber"/>\n  <field editable="1" name="levels"/>\n  <field editable="1" name="name"/>\n  <field editable="1" name="office"/>\n  <field editable="1" name="operator"/>\n  <field editable="1" name="osm_id"/>\n  <field editable="1" name="osm_type"/>\n  <field editable="1" name="place"/>\n  <field editable="1" name="state"/>\n  <field editable="1" name="street"/>\n  <field editable="1" name="tags"/>\n  <field editable="1" name="wheelchair"/>\n </editable>\n <labelOnTop>\n  <field name="addr:housename" labelOnTop="0"/>\n  <field name="addr:housenumber" labelOnTop="0"/>\n  <field name="addr:interpolation" labelOnTop="0"/>\n  <field name="building" labelOnTop="0"/>\n  <field name="city" labelOnTop="0"/>\n  <field name="code" labelOnTop="0"/>\n  <field name="height" labelOnTop="0"/>\n  <field name="housename" labelOnTop="0"/>\n  <field name="housenumber" labelOnTop="0"/>\n  <field name="levels" labelOnTop="0"/>\n  <field name="name" labelOnTop="0"/>\n  <field name="office" labelOnTop="0"/>\n  <field name="operator" labelOnTop="0"/>\n  <field name="osm_id" labelOnTop="0"/>\n  <field name="osm_type" labelOnTop="0"/>\n  <field name="place" labelOnTop="0"/>\n  <field name="state" labelOnTop="0"/>\n  <field name="street" labelOnTop="0"/>\n  <field name="tags" labelOnTop="0"/>\n  <field name="wheelchair" labelOnTop="0"/>\n </labelOnTop>\n <dataDefinedFieldProperties/>\n <widgets/>\n <previewExpression>addr:housename</previewExpression>\n <mapTip></mapTip>\n <layerGeometryType>2</layerGeometryType>\n</qgis>\n	<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" xmlns:se="http://www.opengis.net/se" xmlns:ogc="http://www.opengis.net/ogc" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.1.0/StyledLayerDescriptor.xsd" version="1.1.0">\n <NamedLayer>\n  <se:Name>building_polygon</se:Name>\n  <UserStyle>\n   <se:Name>building_polygon</se:Name>\n   <se:FeatureTypeStyle>\n    <se:Rule>\n     <se:Name>Buildings &lt; 1k</se:Name>\n     <se:Description>\n      <se:Title>Buildings &lt; 1k</se:Title>\n     </se:Description>\n     <se:MaxScaleDenominator>1000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e3e3e3</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#000000</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Buildings 1-2k</se:Name>\n     <se:Description>\n      <se:Title>Buildings 1-2k</se:Title>\n     </se:Description>\n     <se:MinScaleDenominator>1000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>2000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e3e3e3</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#676767</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Buildings 2-5k</se:Name>\n     <se:Description>\n      <se:Title>Buildings 2-5k</se:Title>\n     </se:Description>\n     <se:MinScaleDenominator>2000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>5000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e3e3e3</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#676767</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Buildings 5-30k</se:Name>\n     <se:Description>\n      <se:Title>Buildings 5-30k</se:Title>\n     </se:Description>\n     <se:MinScaleDenominator>5000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>30000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e3e3e3</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#7d7d7d</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Buildings 30-45k</se:Name>\n     <se:Description>\n      <se:Title>Buildings 30-45k</se:Title>\n     </se:Description>\n     <se:MinScaleDenominator>30000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>45000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e3e3e3</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#7d7d7d</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.65</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">0.5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Buildings 45-75k</se:Name>\n     <se:Description>\n      <se:Title>Buildings 45-75k</se:Title>\n     </se:Description>\n     <se:MinScaleDenominator>45000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>75000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e3e3e3</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#7d7d7d</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.15</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">0.5</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n   </se:FeatureTypeStyle>\n  </UserStyle>\n </NamedLayer>\n</StyledLayerDescriptor>\n	t	OpenStreetMap roads styling for use with PgOSM-Flex structured data.  Zoom based logic for all buildings equally.	rustprooflabs	\N	2020-12-22 23:03:17.911282	\N
3	pgosm	osm	landuse_polygon	geom	osm_landuse_polygon	<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>\n<qgis readOnly="0" simplifyAlgorithm="0" styleCategories="AllStyleCategories" hasScaleBasedVisibilityFlag="0" minScale="100000000" maxScale="0" simplifyDrawingTol="1" labelsEnabled="0" version="3.16.2-Hannover" simplifyDrawingHints="1" simplifyLocal="1" simplifyMaxScale="1">\n <flags>\n  <Identifiable>1</Identifiable>\n  <Removable>1</Removable>\n  <Searchable>1</Searchable>\n </flags>\n <temporal mode="0" durationField="" endField="" accumulate="0" startExpression="" durationUnit="min" enabled="0" startField="" endExpression="" fixedDuration="0">\n  <fixedRange>\n   <start></start>\n   <end></end>\n  </fixedRange>\n </temporal>\n <renderer-v2 forceraster="0" enableorderby="0" symbollevels="0" type="RuleRenderer">\n  <rules key="{d93b3a21-c6d7-4d0d-a61d-cd56d9299a56}">\n   <rule label="Basin" filter="&quot;osm_type&quot; = 'basin'" key="{8131e002-8a77-4749-86f6-fbc23a5762ed}" symbol="0"/>\n   <rule label="Reservoir" filter="&quot;osm_type&quot; = 'reservoir'" key="{e2f243c4-2dce-45bf-81a7-666d40526408}" symbol="1"/>\n   <rule label="cemetery" filter="&quot;osm_type&quot; = 'cemetery'" key="{05d211e5-b427-4016-ad71-2763be30eab1}" symbol="2"/>\n   <rule label="Residential" filter="&quot;osm_type&quot; = 'residential'" key="{baac5588-4e92-408e-b16d-e103cdf5dfc2}" symbol="3"/>\n   <rule label="Commercial / Retail" filter="&quot;osm_type&quot; IN ('commercial', 'retail')" key="{4ca4cf47-24ab-4630-a31f-7e40331fa5ad}" symbol="4"/>\n   <rule label="Farmland" filter="&quot;osm_type&quot; = 'farmland'" key="{d4eb22a8-36f2-456a-91ed-0f9cb97a372c}" symbol="5"/>\n   <rule label="garage" filter="&quot;osm_type&quot; = 'garage'" key="{4883258c-126d-423d-bfaa-4626b7ea8385}" symbol="6"/>\n   <rule label="Government" filter="&quot;osm_type&quot; = 'government'" key="{2c8b3c43-0e0c-4b4d-a23a-ee3264f70bd9}" symbol="7"/>\n   <rule label="Forest" filter="&quot;osm_type&quot; = 'forest'" key="{4b5edec5-517e-45b8-8532-0ff09cc3cdd7}" symbol="8"/>\n   <rule label="Grass / Meadow" filter="&quot;osm_type&quot; IN ('grass', 'meadow', 'village_green')" key="{205a315f-da0b-4037-a2d5-eace6c9a7d7a}" symbol="9"/>\n   <rule label="Nursery / Garden" filter="&quot;osm_type&quot;  IN ( 'plant_nursery', 'allotments')" key="{4c1dbd2e-9151-4f6a-a02f-e76779ceb1c7}" symbol="10"/>\n   <rule label="Industrial" filter="&quot;osm_type&quot; = 'industrial'" key="{297adc11-2f2e-4936-87c6-3957dc916a02}" symbol="11"/>\n   <rule label="Landfill" filter="&quot;osm_type&quot; = 'landfill'" key="{1611b9c9-406c-4e99-a134-726273ed11ee}" symbol="12"/>\n   <rule label="military" filter="&quot;osm_type&quot; = 'military'" key="{d85a76e6-65e9-4e04-9671-2d92cb2171e2}" symbol="13"/>\n   <rule label="railway" filter="&quot;osm_type&quot; = 'railway'" key="{96df6bb7-c2dd-493d-be46-c14baa2b0748}" symbol="14"/>\n   <rule label="Brownfield" filter="&quot;osm_type&quot; = 'brownfield'" key="{4a909555-8f60-44ff-94d0-579424acb903}" symbol="15"/>\n   <rule label="Construction" filter="&quot;osm_type&quot; = 'construction'" key="{7a4e1d2b-3689-4860-b9f1-514014fab0aa}" symbol="16"/>\n   <rule label="Vacant" filter="&quot;osm_type&quot; = 'vacant'" key="{cc0df159-2cc6-4c72-b334-c8048275b894}" symbol="17"/>\n   <rule label="Recreation Ground" filter="&quot;osm_type&quot; = 'recreation_ground'" key="{09bbefe5-83fd-4b11-92a6-1f767ee90e8b}" symbol="18"/>\n   <rule label="Traffic Island" filter="&quot;osm_type&quot; = 'traffic_island'" key="{c9afaa59-eaad-4922-9ac5-8429a065997c}" symbol="19"/>\n   <rule label="Unknown Landuse" filter="ELSE" key="{2d54b489-991f-4078-9b43-7c306a8e5d74}" symbol="20"/>\n  </rules>\n  <symbols>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="0">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="3,194,223,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="1,121,137,255" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer pass="0" class="HashLine" enabled="1" locked="0">\n     <prop v="4" k="average_angle_length"/>\n     <prop v="3x:0,0,0,0,0,0" k="average_angle_map_unit_scale"/>\n     <prop v="MM" k="average_angle_unit"/>\n     <prop v="0" k="hash_angle"/>\n     <prop v="3" k="hash_length"/>\n     <prop v="3x:0,0,0,0,0,0" k="hash_length_map_unit_scale"/>\n     <prop v="MM" k="hash_length_unit"/>\n     <prop v="3" k="interval"/>\n     <prop v="3x:0,0,0,0,0,0" k="interval_map_unit_scale"/>\n     <prop v="MM" k="interval_unit"/>\n     <prop v="0" k="offset"/>\n     <prop v="0" k="offset_along_line"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_along_line_map_unit_scale"/>\n     <prop v="MM" k="offset_along_line_unit"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="interval" k="placement"/>\n     <prop v="0" k="ring_filter"/>\n     <prop v="1" k="rotate"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n     <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="line" name="@0@1">\n      <layer pass="0" class="SimpleLine" enabled="1" locked="0">\n       <prop v="0" k="align_dash_pattern"/>\n       <prop v="square" k="capstyle"/>\n       <prop v="5;2" k="customdash"/>\n       <prop v="3x:0,0,0,0,0,0" k="customdash_map_unit_scale"/>\n       <prop v="MM" k="customdash_unit"/>\n       <prop v="5.55112e-17" k="dash_pattern_offset"/>\n       <prop v="3x:0,0,0,0,0,0" k="dash_pattern_offset_map_unit_scale"/>\n       <prop v="MM" k="dash_pattern_offset_unit"/>\n       <prop v="0" k="draw_inside_polygon"/>\n       <prop v="bevel" k="joinstyle"/>\n       <prop v="35,35,35,255" k="line_color"/>\n       <prop v="solid" k="line_style"/>\n       <prop v="0.16" k="line_width"/>\n       <prop v="MM" k="line_width_unit"/>\n       <prop v="-5.55112e-17" k="offset"/>\n       <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n       <prop v="MM" k="offset_unit"/>\n       <prop v="0" k="ring_filter"/>\n       <prop v="0" k="tweak_dash_pattern_on_corners"/>\n       <prop v="0" k="use_custom_dash"/>\n       <prop v="3x:0,0,0,0,0,0" k="width_map_unit_scale"/>\n       <data_defined_properties>\n        <Option type="Map">\n         <Option type="QString" value="" name="name"/>\n         <Option name="properties"/>\n         <Option type="QString" value="collection" name="type"/>\n        </Option>\n       </data_defined_properties>\n      </layer>\n     </symbol>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="1">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="2,214,241,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="1,121,137,255" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="10">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="48,201,17,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer pass="0" class="LinePatternFill" enabled="1" locked="0">\n     <prop v="45" k="angle"/>\n     <prop v="0,0,255,255" k="color"/>\n     <prop v="5" k="distance"/>\n     <prop v="3x:0,0,0,0,0,0" k="distance_map_unit_scale"/>\n     <prop v="MM" k="distance_unit"/>\n     <prop v="0.26" k="line_width"/>\n     <prop v="3x:0,0,0,0,0,0" k="line_width_map_unit_scale"/>\n     <prop v="MM" k="line_width_unit"/>\n     <prop v="0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="3x:0,0,0,0,0,0" k="outline_width_map_unit_scale"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n     <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="line" name="@10@1">\n      <layer pass="0" class="SimpleLine" enabled="1" locked="0">\n       <prop v="0" k="align_dash_pattern"/>\n       <prop v="square" k="capstyle"/>\n       <prop v="5;2" k="customdash"/>\n       <prop v="3x:0,0,0,0,0,0" k="customdash_map_unit_scale"/>\n       <prop v="MM" k="customdash_unit"/>\n       <prop v="0" k="dash_pattern_offset"/>\n       <prop v="3x:0,0,0,0,0,0" k="dash_pattern_offset_map_unit_scale"/>\n       <prop v="MM" k="dash_pattern_offset_unit"/>\n       <prop v="0" k="draw_inside_polygon"/>\n       <prop v="bevel" k="joinstyle"/>\n       <prop v="27,119,44,255" k="line_color"/>\n       <prop v="solid" k="line_style"/>\n       <prop v="0.26" k="line_width"/>\n       <prop v="MM" k="line_width_unit"/>\n       <prop v="0" k="offset"/>\n       <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n       <prop v="MM" k="offset_unit"/>\n       <prop v="0" k="ring_filter"/>\n       <prop v="0" k="tweak_dash_pattern_on_corners"/>\n       <prop v="0" k="use_custom_dash"/>\n       <prop v="3x:0,0,0,0,0,0" k="width_map_unit_scale"/>\n       <data_defined_properties>\n        <Option type="Map">\n         <Option type="QString" value="" name="name"/>\n         <Option name="properties"/>\n         <Option type="QString" value="collection" name="type"/>\n        </Option>\n       </data_defined_properties>\n      </layer>\n     </symbol>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="11">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="215,124,202,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="12">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="204,96,123,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n    <layer pass="0" class="LinePatternFill" enabled="1" locked="0">\n     <prop v="-45" k="angle"/>\n     <prop v="0,0,255,255" k="color"/>\n     <prop v="5" k="distance"/>\n     <prop v="3x:0,0,0,0,0,0" k="distance_map_unit_scale"/>\n     <prop v="MM" k="distance_unit"/>\n     <prop v="0.26" k="line_width"/>\n     <prop v="3x:0,0,0,0,0,0" k="line_width_map_unit_scale"/>\n     <prop v="MM" k="line_width_unit"/>\n     <prop v="0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="3x:0,0,0,0,0,0" k="outline_width_map_unit_scale"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n     <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="line" name="@12@1">\n      <layer pass="0" class="SimpleLine" enabled="1" locked="0">\n       <prop v="0" k="align_dash_pattern"/>\n       <prop v="square" k="capstyle"/>\n       <prop v="5;2" k="customdash"/>\n       <prop v="3x:0,0,0,0,0,0" k="customdash_map_unit_scale"/>\n       <prop v="MM" k="customdash_unit"/>\n       <prop v="0" k="dash_pattern_offset"/>\n       <prop v="3x:0,0,0,0,0,0" k="dash_pattern_offset_map_unit_scale"/>\n       <prop v="MM" k="dash_pattern_offset_unit"/>\n       <prop v="0" k="draw_inside_polygon"/>\n       <prop v="bevel" k="joinstyle"/>\n       <prop v="73,1,9,255" k="line_color"/>\n       <prop v="solid" k="line_style"/>\n       <prop v="0.26" k="line_width"/>\n       <prop v="MM" k="line_width_unit"/>\n       <prop v="0" k="offset"/>\n       <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n       <prop v="MM" k="offset_unit"/>\n       <prop v="0" k="ring_filter"/>\n       <prop v="0" k="tweak_dash_pattern_on_corners"/>\n       <prop v="0" k="use_custom_dash"/>\n       <prop v="3x:0,0,0,0,0,0" k="width_map_unit_scale"/>\n       <data_defined_properties>\n        <Option type="Map">\n         <Option type="QString" value="" name="name"/>\n         <Option name="properties"/>\n         <Option type="QString" value="collection" name="type"/>\n        </Option>\n       </data_defined_properties>\n      </layer>\n     </symbol>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="13">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="199,21,234,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="14">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="119,217,54,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="15">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="176,119,20,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="16">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="205,138,23,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="17">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="228,181,86,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="18">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="130,231,156,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="19">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="113,114,115,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="2">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="66,113,214,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="20">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="31,179,216,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="3">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="196,197,200,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="4">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="243,181,241,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="5">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="199,235,197,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="6">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="197,201,137,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="7">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="192,145,215,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="8">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="0,157,10,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="fill" name="9">\n    <layer pass="0" class="SimpleFill" enabled="1" locked="0">\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="0,237,15,255" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="0,0,0,255" k="outline_color"/>\n     <prop v="no" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n  </symbols>\n </renderer-v2>\n <customproperties>\n  <property key="embeddedWidgets/count" value="0"/>\n  <property key="variableNames"/>\n  <property key="variableValues"/>\n </customproperties>\n <blendMode>0</blendMode>\n <featureBlendMode>0</featureBlendMode>\n <layerOpacity>1</layerOpacity>\n <SingleCategoryDiagramRenderer attributeLegend="1" diagramType="Histogram">\n  <DiagramCategory diagramOrientation="Up" minimumSize="0" height="15" direction="1" enabled="0" sizeType="MM" spacing="0" scaleDependency="Area" backgroundAlpha="255" showAxis="0" scaleBasedVisibility="0" spacingUnit="MM" rotationOffset="270" backgroundColor="#ffffff" penWidth="0" penAlpha="255" maxScaleDenominator="1e+08" opacity="1" sizeScale="3x:0,0,0,0,0,0" labelPlacementMethod="XHeight" width="15" penColor="#000000" minScaleDenominator="0" barWidth="5" spacingUnitScale="3x:0,0,0,0,0,0" lineSizeType="MM" lineSizeScale="3x:0,0,0,0,0,0">\n   <fontProperties description="Ubuntu,11,-1,5,50,0,0,0,0,0" style=""/>\n   <attribute color="#000000" label="" field=""/>\n   <axisSymbol>\n    <symbol alpha="1" force_rhr="0" clip_to_extent="1" type="line" name="">\n     <layer pass="0" class="SimpleLine" enabled="1" locked="0">\n      <prop v="0" k="align_dash_pattern"/>\n      <prop v="square" k="capstyle"/>\n      <prop v="5;2" k="customdash"/>\n      <prop v="3x:0,0,0,0,0,0" k="customdash_map_unit_scale"/>\n      <prop v="MM" k="customdash_unit"/>\n      <prop v="0" k="dash_pattern_offset"/>\n      <prop v="3x:0,0,0,0,0,0" k="dash_pattern_offset_map_unit_scale"/>\n      <prop v="MM" k="dash_pattern_offset_unit"/>\n      <prop v="0" k="draw_inside_polygon"/>\n      <prop v="bevel" k="joinstyle"/>\n      <prop v="35,35,35,255" k="line_color"/>\n      <prop v="solid" k="line_style"/>\n      <prop v="0.26" k="line_width"/>\n      <prop v="MM" k="line_width_unit"/>\n      <prop v="0" k="offset"/>\n      <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n      <prop v="MM" k="offset_unit"/>\n      <prop v="0" k="ring_filter"/>\n      <prop v="0" k="tweak_dash_pattern_on_corners"/>\n      <prop v="0" k="use_custom_dash"/>\n      <prop v="3x:0,0,0,0,0,0" k="width_map_unit_scale"/>\n      <data_defined_properties>\n       <Option type="Map">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n      </data_defined_properties>\n     </layer>\n    </symbol>\n   </axisSymbol>\n  </DiagramCategory>\n </SingleCategoryDiagramRenderer>\n <DiagramLayerSettings dist="0" linePlacementFlags="18" priority="0" obstacle="0" showAll="1" placement="1" zIndex="0">\n  <properties>\n   <Option type="Map">\n    <Option type="QString" value="" name="name"/>\n    <Option name="properties"/>\n    <Option type="QString" value="collection" name="type"/>\n   </Option>\n  </properties>\n </DiagramLayerSettings>\n <geometryOptions removeDuplicateNodes="0" geometryPrecision="0">\n  <activeChecks/>\n  <checkConfiguration type="Map">\n   <Option type="Map" name="QgsGeometryGapCheck">\n    <Option type="double" value="0" name="allowedGapsBuffer"/>\n    <Option type="bool" value="false" name="allowedGapsEnabled"/>\n    <Option type="QString" value="" name="allowedGapsLayer"/>\n   </Option>\n  </checkConfiguration>\n </geometryOptions>\n <legend type="default-vector"/>\n <referencedLayers/>\n <fieldConfiguration>\n  <field configurationFlags="None" name="osm_id">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="osm_type">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="name">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n </fieldConfiguration>\n <aliases>\n  <alias field="osm_id" index="0" name=""/>\n  <alias field="osm_type" index="1" name=""/>\n  <alias field="name" index="2" name=""/>\n </aliases>\n <defaults>\n  <default applyOnUpdate="0" expression="" field="osm_id"/>\n  <default applyOnUpdate="0" expression="" field="osm_type"/>\n  <default applyOnUpdate="0" expression="" field="name"/>\n </defaults>\n <constraints>\n  <constraint unique_strength="1" constraints="3" exp_strength="0" field="osm_id" notnull_strength="1"/>\n  <constraint unique_strength="0" constraints="1" exp_strength="0" field="osm_type" notnull_strength="1"/>\n  <constraint unique_strength="0" constraints="0" exp_strength="0" field="name" notnull_strength="0"/>\n </constraints>\n <constraintExpressions>\n  <constraint desc="" field="osm_id" exp=""/>\n  <constraint desc="" field="osm_type" exp=""/>\n  <constraint desc="" field="name" exp=""/>\n </constraintExpressions>\n <expressionfields/>\n <attributeactions>\n  <defaultAction key="Canvas" value="{00000000-0000-0000-0000-000000000000}"/>\n </attributeactions>\n <attributetableconfig sortOrder="0" actionWidgetStyle="dropDown" sortExpression="">\n  <columns>\n   <column hidden="0" type="field" width="-1" name="osm_id"/>\n   <column hidden="0" type="field" width="-1" name="name"/>\n   <column hidden="1" type="actions" width="-1"/>\n   <column hidden="0" type="field" width="-1" name="osm_type"/>\n  </columns>\n </attributetableconfig>\n <conditionalstyles>\n  <rowstyles/>\n  <fieldstyles/>\n </conditionalstyles>\n <storedexpressions/>\n <editform tolerant="1"></editform>\n <editforminit/>\n <editforminitcodesource>0</editforminitcodesource>\n <editforminitfilepath></editforminitfilepath>\n <editforminitcode><![CDATA[# -*- coding: utf-8 -*-\n"""\nQGIS forms can have a Python function that is called when the form is\nopened.\n\nUse this function to add extra logic to your forms.\n\nEnter the name of the function in the "Python Init function"\nfield.\nAn example follows:\n"""\nfrom qgis.PyQt.QtWidgets import QWidget\n\ndef my_form_open(dialog, layer, feature):\n\tgeom = feature.geometry()\n\tcontrol = dialog.findChild(QWidget, "MyLineEdit")\n]]></editforminitcode>\n <featformsuppress>0</featformsuppress>\n <editorlayout>generatedlayout</editorlayout>\n <editable>\n  <field editable="1" name="boundary"/>\n  <field editable="1" name="code"/>\n  <field editable="1" name="landuse"/>\n  <field editable="1" name="leisure"/>\n  <field editable="1" name="name"/>\n  <field editable="1" name="natural"/>\n  <field editable="1" name="osm_id"/>\n  <field editable="1" name="osm_type"/>\n </editable>\n <labelOnTop>\n  <field labelOnTop="0" name="boundary"/>\n  <field labelOnTop="0" name="code"/>\n  <field labelOnTop="0" name="landuse"/>\n  <field labelOnTop="0" name="leisure"/>\n  <field labelOnTop="0" name="name"/>\n  <field labelOnTop="0" name="natural"/>\n  <field labelOnTop="0" name="osm_id"/>\n  <field labelOnTop="0" name="osm_type"/>\n </labelOnTop>\n <dataDefinedFieldProperties/>\n <widgets/>\n <previewExpression>"name"</previewExpression>\n <mapTip></mapTip>\n <layerGeometryType>2</layerGeometryType>\n</qgis>\n	<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:ogc="http://www.opengis.net/ogc" xmlns:se="http://www.opengis.net/se" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.1.0" xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.1.0/StyledLayerDescriptor.xsd">\n <NamedLayer>\n  <se:Name>landuse_polygon</se:Name>\n  <UserStyle>\n   <se:Name>landuse_polygon</se:Name>\n   <se:FeatureTypeStyle>\n    <se:Rule>\n     <se:Name>Basin</se:Name>\n     <se:Description>\n      <se:Title>Basin</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>basin</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#03c2df</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#017989</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n     <!--SymbolLayerV2 HashLine not implemented yet-->\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Reservoir</se:Name>\n     <se:Description>\n      <se:Title>Reservoir</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>reservoir</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#02d6f1</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#017989</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>cemetery</se:Name>\n     <se:Description>\n      <se:Title>cemetery</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>cemetery</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#4271d6</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#000000</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Residential</se:Name>\n     <se:Description>\n      <se:Title>Residential</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>residential</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#c4c5c8</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Commercial / Retail</se:Name>\n     <se:Description>\n      <se:Title>Commercial / Retail</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>commercial</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>retail</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#f3b5f1</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Farmland</se:Name>\n     <se:Description>\n      <se:Title>Farmland</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>farmland</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#c7ebc5</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>garage</se:Name>\n     <se:Description>\n      <se:Title>garage</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>garage</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#c5c989</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Government</se:Name>\n     <se:Description>\n      <se:Title>Government</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>government</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#c091d7</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Forest</se:Name>\n     <se:Description>\n      <se:Title>Forest</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>forest</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#009d0a</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Grass / Meadow</se:Name>\n     <se:Description>\n      <se:Title>Grass / Meadow</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>grass</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>meadow</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>village_green</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#00ed0f</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Nursery / Garden</se:Name>\n     <se:Description>\n      <se:Title>Nursery / Garden</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:Or>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>plant_nursery</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n       <ogc:PropertyIsEqualTo>\n        <ogc:PropertyName>osm_type</ogc:PropertyName>\n        <ogc:Literal>allotments</ogc:Literal>\n       </ogc:PropertyIsEqualTo>\n      </ogc:Or>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#30c911</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:GraphicFill>\n        <se:Graphic>\n         <se:Mark>\n          <se:WellKnownName>horline</se:WellKnownName>\n          <se:Stroke>\n           <se:SvgParameter name="stroke">#1b772c</se:SvgParameter>\n           <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n          </se:Stroke>\n         </se:Mark>\n         <se:Size>18</se:Size>\n         <se:Rotation>\n          <ogc:Literal>45</ogc:Literal>\n         </se:Rotation>\n        </se:Graphic>\n       </se:GraphicFill>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Industrial</se:Name>\n     <se:Description>\n      <se:Title>Industrial</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>industrial</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#d77cca</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Landfill</se:Name>\n     <se:Description>\n      <se:Title>Landfill</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>landfill</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#cc607b</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:GraphicFill>\n        <se:Graphic>\n         <se:Mark>\n          <se:WellKnownName>horline</se:WellKnownName>\n          <se:Stroke>\n           <se:SvgParameter name="stroke">#490109</se:SvgParameter>\n           <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n          </se:Stroke>\n         </se:Mark>\n         <se:Size>18</se:Size>\n         <se:Rotation/>\n        </se:Graphic>\n       </se:GraphicFill>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>military</se:Name>\n     <se:Description>\n      <se:Title>military</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>military</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#c715ea</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>railway</se:Name>\n     <se:Description>\n      <se:Title>railway</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>railway</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#77d936</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Brownfield</se:Name>\n     <se:Description>\n      <se:Title>Brownfield</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>brownfield</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#b07714</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Construction</se:Name>\n     <se:Description>\n      <se:Title>Construction</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>construction</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#cd8a17</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Vacant</se:Name>\n     <se:Description>\n      <se:Title>Vacant</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>vacant</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#e4b556</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Recreation Ground</se:Name>\n     <se:Description>\n      <se:Title>Recreation Ground</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>recreation_ground</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#82e79c</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Traffic Island</se:Name>\n     <se:Description>\n      <se:Title>Traffic Island</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>osm_type</ogc:PropertyName>\n       <ogc:Literal>traffic_island</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#717273</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#000000</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Unknown Landuse</se:Name>\n     <se:Description>\n      <se:Title>Unknown Landuse</se:Title>\n     </se:Description>\n     <!--Parser Error: \nsyntax error, unexpected ELSE - Expression was: ELSE-->\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#1fb3d8</se:SvgParameter>\n      </se:Fill>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n   </se:FeatureTypeStyle>\n  </UserStyle>\n </NamedLayer>\n</StyledLayerDescriptor>\n	t	OpenStreetMap place styling for use with PgOSM-Flex styles.	rustprooflabs	\N	2021-01-22 00:15:29.509659	\N
4	pgosm	osm	vplace_polygon	geom	place_polygon	<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>\n<qgis hasScaleBasedVisibilityFlag="0" styleCategories="AllStyleCategories" labelsEnabled="1" version="3.20.2-Odense" minScale="100000000" simplifyLocal="1" simplifyDrawingHints="1" simplifyAlgorithm="0" simplifyDrawingTol="1" readOnly="0" maxScale="0" simplifyMaxScale="1">\n <flags>\n  <Identifiable>1</Identifiable>\n  <Removable>1</Removable>\n  <Searchable>1</Searchable>\n  <Private>0</Private>\n </flags>\n <temporal accumulate="0" endField="" fixedDuration="0" durationUnit="min" startField="" durationField="" mode="0" startExpression="" enabled="0" endExpression="">\n  <fixedRange>\n   <start></start>\n   <end></end>\n  </fixedRange>\n </temporal>\n <renderer-v2 forceraster="0" enableorderby="0" symbollevels="0" type="RuleRenderer">\n  <rules key="{9087a027-2f0e-4877-9737-a2d3f22af713}">\n   <rule label="Ward" filter="&quot;admin_level&quot; = 9" symbol="0" key="{4a0dd2ce-c012-45c8-ae30-20469e65b25d}" scalemaxdenom="125000"/>\n   <rule label="Town" filter="&quot;admin_level&quot; = 8" key="{c69a53a9-8799-4a24-b5aa-63d3cfa941de}">\n    <rule label="0 - 1000" symbol="1" key="{11f1f23d-272b-4f50-9fb3-efe66086b307}" scalemaxdenom="1000"/>\n    <rule label="1000 - 125000" scalemindenom="1000" symbol="2" key="{80aee74a-f135-456e-9b75-95d050ec1188}" scalemaxdenom="125000"/>\n    <rule label="50000 - 100000" scalemindenom="125000" symbol="3" key="{ad9a3a87-553a-4a21-82e6-d06fec5190fa}" scalemaxdenom="500000"/>\n   </rule>\n   <rule label="Township" filter="&quot;admin_level&quot; = 7" symbol="4" key="{110e75c4-d718-4389-b3ce-6efcd7730667}"/>\n   <rule label="County" filter="&quot;admin_level&quot; = 6" key="{403ff5da-ce53-4a3d-a925-48a87d2a1ed5}">\n    <rule label="0 - 50000" symbol="5" key="{974fef68-1cf3-4a34-8346-c6f5e930e847}" scalemaxdenom="50000"/>\n    <rule label="50000 - 100000" scalemindenom="50000" symbol="6" key="{65711cf9-ffc1-4de3-bb4b-05859687671a}" scalemaxdenom="100000"/>\n    <rule label="100000 - 500000" scalemindenom="100000" symbol="7" key="{e971d135-ea2a-48bd-8d61-bd8defdd91d5}" scalemaxdenom="500000"/>\n    <rule label="500000 - 10000000" scalemindenom="500000" symbol="8" key="{2cfa838a-452d-4f2c-b06e-d25ba378deba}" scalemaxdenom="10000000"/>\n    <rule label="1e+07 - 0" scalemindenom="10000000" symbol="9" key="{bdc6ce4f-1685-485a-b42a-422111142f35}"/>\n   </rule>\n   <rule checkstate="0" label="Other" filter="ELSE" symbol="10" key="{91ce39d2-a52b-4a77-a35b-7529db747157}"/>\n  </rules>\n  <symbols>\n   <symbol force_rhr="0" alpha="1" type="fill" name="0" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,228,177,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,228,177,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="1" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,228,177,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,228,177,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="10" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,248,205,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,248,205,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="2" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,228,177,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,228,177,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="3" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,228,177,9" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.26" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,228,177,9" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="4" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,228,177,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,228,177,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="5" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,248,205,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,248,205,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="6" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,248,205,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,248,205,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="7" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,248,205,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.66" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,248,205,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.66" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="8" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,248,205,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.26" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,248,205,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n   <symbol force_rhr="0" alpha="1" type="fill" name="9" clip_to_extent="1">\n    <data_defined_properties>\n     <Option type="Map">\n      <Option type="QString" value="" name="name"/>\n      <Option name="properties"/>\n      <Option type="QString" value="collection" name="type"/>\n     </Option>\n    </data_defined_properties>\n    <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n     <Option type="Map">\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n      <Option type="QString" value="255,248,205,51" name="color"/>\n      <Option type="QString" value="bevel" name="joinstyle"/>\n      <Option type="QString" value="0,0" name="offset"/>\n      <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n      <Option type="QString" value="MM" name="offset_unit"/>\n      <Option type="QString" value="35,35,35,143" name="outline_color"/>\n      <Option type="QString" value="solid" name="outline_style"/>\n      <Option type="QString" value="0.26" name="outline_width"/>\n      <Option type="QString" value="MM" name="outline_width_unit"/>\n      <Option type="QString" value="solid" name="style"/>\n     </Option>\n     <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n     <prop v="255,248,205,51" k="color"/>\n     <prop v="bevel" k="joinstyle"/>\n     <prop v="0,0" k="offset"/>\n     <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n     <prop v="MM" k="offset_unit"/>\n     <prop v="35,35,35,143" k="outline_color"/>\n     <prop v="solid" k="outline_style"/>\n     <prop v="0.26" k="outline_width"/>\n     <prop v="MM" k="outline_width_unit"/>\n     <prop v="solid" k="style"/>\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n    </layer>\n   </symbol>\n  </symbols>\n </renderer-v2>\n <labeling type="rule-based">\n  <rules key="{9d437193-f766-493a-a315-e177e4d40518}">\n   <rule filter=" &quot;admin_level&quot; > 6" key="{4d64d9ca-5800-4129-a362-94b025ea5c77}" scalemaxdenom="300000">\n    <settings calloutType="simple">\n     <text-style fontUnderline="0" fontWeight="50" multilineHeight="1" fontItalic="1" useSubstitutions="0" blendMode="0" previewBkgrdColor="255,255,255,255" namedStyle="Italic" isExpression="0" legendString="Aa" fontSize="12" fontSizeUnit="Point" textOrientation="horizontal" fieldName="name" fontKerning="1" textColor="50,50,50,255" textOpacity="1" fontLetterSpacing="0" fontStrikeout="0" fontSizeMapUnitScale="3x:0,0,0,0,0,0" capitalization="0" fontWordSpacing="0" fontFamily="Liberation Sans" allowHtml="0">\n      <families/>\n      <text-buffer bufferSize="1" bufferNoFill="1" bufferOpacity="1" bufferColor="250,250,250,255" bufferSizeUnits="MM" bufferSizeMapUnitScale="3x:0,0,0,0,0,0" bufferDraw="0" bufferBlendMode="0" bufferJoinStyle="128"/>\n      <text-mask maskSizeMapUnitScale="3x:0,0,0,0,0,0" maskType="0" maskSizeUnits="MM" maskOpacity="1" maskEnabled="0" maskJoinStyle="128" maskSize="0" maskedSymbolLayers=""/>\n      <background shapeRadiiY="0" shapeSizeType="0" shapeJoinStyle="64" shapeRadiiX="0" shapeDraw="0" shapeOffsetX="0" shapeSizeY="0" shapeOffsetMapUnitScale="3x:0,0,0,0,0,0" shapeFillColor="255,255,255,255" shapeSizeUnit="Point" shapeSizeX="0" shapeSizeMapUnitScale="3x:0,0,0,0,0,0" shapeBlendMode="0" shapeRotation="0" shapeRadiiMapUnitScale="3x:0,0,0,0,0,0" shapeType="0" shapeBorderWidthMapUnitScale="3x:0,0,0,0,0,0" shapeSVGFile="" shapeRadiiUnit="Point" shapeOffsetUnit="Point" shapeOpacity="1" shapeRotationType="0" shapeBorderColor="128,128,128,255" shapeBorderWidth="0" shapeBorderWidthUnit="Point" shapeOffsetY="0">\n       <symbol force_rhr="0" alpha="1" type="marker" name="markerSymbol" clip_to_extent="1">\n        <data_defined_properties>\n         <Option type="Map">\n          <Option type="QString" value="" name="name"/>\n          <Option name="properties"/>\n          <Option type="QString" value="collection" name="type"/>\n         </Option>\n        </data_defined_properties>\n        <layer locked="0" pass="0" class="SimpleMarker" enabled="1">\n         <Option type="Map">\n          <Option type="QString" value="0" name="angle"/>\n          <Option type="QString" value="square" name="cap_style"/>\n          <Option type="QString" value="255,158,23,255" name="color"/>\n          <Option type="QString" value="1" name="horizontal_anchor_point"/>\n          <Option type="QString" value="bevel" name="joinstyle"/>\n          <Option type="QString" value="circle" name="name"/>\n          <Option type="QString" value="0,0" name="offset"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n          <Option type="QString" value="MM" name="offset_unit"/>\n          <Option type="QString" value="35,35,35,255" name="outline_color"/>\n          <Option type="QString" value="solid" name="outline_style"/>\n          <Option type="QString" value="0" name="outline_width"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="outline_width_map_unit_scale"/>\n          <Option type="QString" value="MM" name="outline_width_unit"/>\n          <Option type="QString" value="diameter" name="scale_method"/>\n          <Option type="QString" value="2" name="size"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="size_map_unit_scale"/>\n          <Option type="QString" value="MM" name="size_unit"/>\n          <Option type="QString" value="1" name="vertical_anchor_point"/>\n         </Option>\n         <prop v="0" k="angle"/>\n         <prop v="square" k="cap_style"/>\n         <prop v="255,158,23,255" k="color"/>\n         <prop v="1" k="horizontal_anchor_point"/>\n         <prop v="bevel" k="joinstyle"/>\n         <prop v="circle" k="name"/>\n         <prop v="0,0" k="offset"/>\n         <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n         <prop v="MM" k="offset_unit"/>\n         <prop v="35,35,35,255" k="outline_color"/>\n         <prop v="solid" k="outline_style"/>\n         <prop v="0" k="outline_width"/>\n         <prop v="3x:0,0,0,0,0,0" k="outline_width_map_unit_scale"/>\n         <prop v="MM" k="outline_width_unit"/>\n         <prop v="diameter" k="scale_method"/>\n         <prop v="2" k="size"/>\n         <prop v="3x:0,0,0,0,0,0" k="size_map_unit_scale"/>\n         <prop v="MM" k="size_unit"/>\n         <prop v="1" k="vertical_anchor_point"/>\n         <data_defined_properties>\n          <Option type="Map">\n           <Option type="QString" value="" name="name"/>\n           <Option name="properties"/>\n           <Option type="QString" value="collection" name="type"/>\n          </Option>\n         </data_defined_properties>\n        </layer>\n       </symbol>\n       <symbol force_rhr="0" alpha="1" type="fill" name="fillSymbol" clip_to_extent="1">\n        <data_defined_properties>\n         <Option type="Map">\n          <Option type="QString" value="" name="name"/>\n          <Option name="properties"/>\n          <Option type="QString" value="collection" name="type"/>\n         </Option>\n        </data_defined_properties>\n        <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n         <Option type="Map">\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n          <Option type="QString" value="255,255,255,255" name="color"/>\n          <Option type="QString" value="bevel" name="joinstyle"/>\n          <Option type="QString" value="0,0" name="offset"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n          <Option type="QString" value="MM" name="offset_unit"/>\n          <Option type="QString" value="128,128,128,255" name="outline_color"/>\n          <Option type="QString" value="no" name="outline_style"/>\n          <Option type="QString" value="0" name="outline_width"/>\n          <Option type="QString" value="Point" name="outline_width_unit"/>\n          <Option type="QString" value="solid" name="style"/>\n         </Option>\n         <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n         <prop v="255,255,255,255" k="color"/>\n         <prop v="bevel" k="joinstyle"/>\n         <prop v="0,0" k="offset"/>\n         <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n         <prop v="MM" k="offset_unit"/>\n         <prop v="128,128,128,255" k="outline_color"/>\n         <prop v="no" k="outline_style"/>\n         <prop v="0" k="outline_width"/>\n         <prop v="Point" k="outline_width_unit"/>\n         <prop v="solid" k="style"/>\n         <data_defined_properties>\n          <Option type="Map">\n           <Option type="QString" value="" name="name"/>\n           <Option name="properties"/>\n           <Option type="QString" value="collection" name="type"/>\n          </Option>\n         </data_defined_properties>\n        </layer>\n       </symbol>\n      </background>\n      <shadow shadowUnder="0" shadowColor="0,0,0,255" shadowOffsetAngle="135" shadowOffsetUnit="MM" shadowRadiusAlphaOnly="0" shadowOffsetDist="1" shadowOffsetGlobal="1" shadowScale="100" shadowRadiusUnit="MM" shadowRadiusMapUnitScale="3x:0,0,0,0,0,0" shadowDraw="0" shadowBlendMode="6" shadowRadius="1.5" shadowOffsetMapUnitScale="3x:0,0,0,0,0,0" shadowOpacity="0.69999999999999996"/>\n      <dd_properties>\n       <Option type="Map">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n      </dd_properties>\n      <substitutions/>\n     </text-style>\n     <text-format multilineAlign="3" wrapChar="" reverseDirectionSymbol="0" plussign="0" rightDirectionSymbol=">" formatNumbers="0" useMaxLineLengthForAutoWrap="1" leftDirectionSymbol="&lt;" placeDirectionSymbol="0" autoWrapLength="0" addDirectionSymbol="0" decimals="3"/>\n     <placement placementFlags="10" maxCurvedCharAngleIn="25" offsetUnits="MM" geometryGeneratorEnabled="0" yOffset="0" repeatDistanceUnits="MM" repeatDistanceMapUnitScale="3x:0,0,0,0,0,0" geometryGeneratorType="PointGeometry" polygonPlacementFlags="2" fitInPolygonOnly="0" centroidInside="0" overrunDistance="0" priority="5" rotationAngle="0" distUnits="MM" placement="0" quadOffset="4" maxCurvedCharAngleOut="-25" overrunDistanceUnit="MM" distMapUnitScale="3x:0,0,0,0,0,0" xOffset="0" centroidWhole="0" overrunDistanceMapUnitScale="3x:0,0,0,0,0,0" lineAnchorType="0" repeatDistance="0" layerType="PolygonGeometry" geometryGenerator="" offsetType="0" predefinedPositionOrder="TR,TL,BR,BL,R,L,TSR,BSR" preserveRotation="1" lineAnchorPercent="0.5" dist="0" lineAnchorClipping="0" labelOffsetMapUnitScale="3x:0,0,0,0,0,0"/>\n     <rendering labelPerPart="0" fontMaxPixelSize="10000" displayAll="0" unplacedVisibility="0" fontMinPixelSize="3" fontLimitPixelSize="0" maxNumLabels="2000" obstacleType="1" mergeLines="0" obstacleFactor="1" minFeatureSize="0" upsidedownLabels="0" drawLabels="1" limitNumLabels="0" scaleVisibility="0" scaleMin="0" zIndex="0" scaleMax="0" obstacle="1"/>\n     <dd_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </dd_properties>\n     <callout type="simple">\n      <Option type="Map">\n       <Option type="QString" value="pole_of_inaccessibility" name="anchorPoint"/>\n       <Option type="int" value="0" name="blendMode"/>\n       <Option type="Map" name="ddProperties">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n       <Option type="bool" value="false" name="drawToAllParts"/>\n       <Option type="QString" value="0" name="enabled"/>\n       <Option type="QString" value="point_on_exterior" name="labelAnchorPoint"/>\n       <Option type="QString" value="&lt;symbol force_rhr=&quot;0&quot; alpha=&quot;1&quot; type=&quot;line&quot; name=&quot;symbol&quot; clip_to_extent=&quot;1&quot;>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;&quot; name=&quot;name&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;collection&quot; name=&quot;type&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;layer locked=&quot;0&quot; pass=&quot;0&quot; class=&quot;SimpleLine&quot; enabled=&quot;1&quot;>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;align_dash_pattern&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;square&quot; name=&quot;capstyle&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;5;2&quot; name=&quot;customdash&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;customdash_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;customdash_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;dash_pattern_offset&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;dash_pattern_offset_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;dash_pattern_offset_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;draw_inside_polygon&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;bevel&quot; name=&quot;joinstyle&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;60,60,60,255&quot; name=&quot;line_color&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;solid&quot; name=&quot;line_style&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0.3&quot; name=&quot;line_width&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;line_width_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;offset&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;offset_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;offset_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;ring_filter&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;trim_distance_end&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;trim_distance_end_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;trim_distance_end_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;trim_distance_start&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;trim_distance_start_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;trim_distance_start_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;tweak_dash_pattern_on_corners&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;use_custom_dash&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;width_map_unit_scale&quot;/>&lt;/Option>&lt;prop v=&quot;0&quot; k=&quot;align_dash_pattern&quot;/>&lt;prop v=&quot;square&quot; k=&quot;capstyle&quot;/>&lt;prop v=&quot;5;2&quot; k=&quot;customdash&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;customdash_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;customdash_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;dash_pattern_offset&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;dash_pattern_offset_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;dash_pattern_offset_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;draw_inside_polygon&quot;/>&lt;prop v=&quot;bevel&quot; k=&quot;joinstyle&quot;/>&lt;prop v=&quot;60,60,60,255&quot; k=&quot;line_color&quot;/>&lt;prop v=&quot;solid&quot; k=&quot;line_style&quot;/>&lt;prop v=&quot;0.3&quot; k=&quot;line_width&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;line_width_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;offset&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;offset_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;offset_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;ring_filter&quot;/>&lt;prop v=&quot;0&quot; k=&quot;trim_distance_end&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;trim_distance_end_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;trim_distance_end_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;trim_distance_start&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;trim_distance_start_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;trim_distance_start_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;tweak_dash_pattern_on_corners&quot;/>&lt;prop v=&quot;0&quot; k=&quot;use_custom_dash&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;width_map_unit_scale&quot;/>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;&quot; name=&quot;name&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;collection&quot; name=&quot;type&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;/layer>&lt;/symbol>" name="lineSymbol"/>\n       <Option type="double" value="0" name="minLength"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="minLengthMapUnitScale"/>\n       <Option type="QString" value="MM" name="minLengthUnit"/>\n       <Option type="double" value="0" name="offsetFromAnchor"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offsetFromAnchorMapUnitScale"/>\n       <Option type="QString" value="MM" name="offsetFromAnchorUnit"/>\n       <Option type="double" value="0" name="offsetFromLabel"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offsetFromLabelMapUnitScale"/>\n       <Option type="QString" value="MM" name="offsetFromLabelUnit"/>\n      </Option>\n     </callout>\n    </settings>\n   </rule>\n   <rule filter=" &quot;admin_level&quot; &lt;= 6" scalemindenom="100000" key="{0c208548-98eb-47db-a977-c5ee71f9c9bc}">\n    <settings calloutType="simple">\n     <text-style fontUnderline="0" fontWeight="75" multilineHeight="1" fontItalic="1" useSubstitutions="0" blendMode="0" previewBkgrdColor="255,255,255,255" namedStyle="Bold Italic" isExpression="0" legendString="Aa" fontSize="13" fontSizeUnit="Point" textOrientation="horizontal" fieldName="name" fontKerning="1" textColor="50,50,50,255" textOpacity="1" fontLetterSpacing="0" fontStrikeout="0" fontSizeMapUnitScale="3x:0,0,0,0,0,0" capitalization="0" fontWordSpacing="0" fontFamily="Liberation Sans" allowHtml="0">\n      <families/>\n      <text-buffer bufferSize="1" bufferNoFill="1" bufferOpacity="1" bufferColor="250,250,250,255" bufferSizeUnits="MM" bufferSizeMapUnitScale="3x:0,0,0,0,0,0" bufferDraw="0" bufferBlendMode="0" bufferJoinStyle="128"/>\n      <text-mask maskSizeMapUnitScale="3x:0,0,0,0,0,0" maskType="0" maskSizeUnits="MM" maskOpacity="1" maskEnabled="0" maskJoinStyle="128" maskSize="0" maskedSymbolLayers=""/>\n      <background shapeRadiiY="0" shapeSizeType="0" shapeJoinStyle="64" shapeRadiiX="0" shapeDraw="0" shapeOffsetX="0" shapeSizeY="0" shapeOffsetMapUnitScale="3x:0,0,0,0,0,0" shapeFillColor="255,255,255,255" shapeSizeUnit="Point" shapeSizeX="0" shapeSizeMapUnitScale="3x:0,0,0,0,0,0" shapeBlendMode="0" shapeRotation="0" shapeRadiiMapUnitScale="3x:0,0,0,0,0,0" shapeType="0" shapeBorderWidthMapUnitScale="3x:0,0,0,0,0,0" shapeSVGFile="" shapeRadiiUnit="Point" shapeOffsetUnit="Point" shapeOpacity="1" shapeRotationType="0" shapeBorderColor="128,128,128,255" shapeBorderWidth="0" shapeBorderWidthUnit="Point" shapeOffsetY="0">\n       <symbol force_rhr="0" alpha="1" type="marker" name="markerSymbol" clip_to_extent="1">\n        <data_defined_properties>\n         <Option type="Map">\n          <Option type="QString" value="" name="name"/>\n          <Option name="properties"/>\n          <Option type="QString" value="collection" name="type"/>\n         </Option>\n        </data_defined_properties>\n        <layer locked="0" pass="0" class="SimpleMarker" enabled="1">\n         <Option type="Map">\n          <Option type="QString" value="0" name="angle"/>\n          <Option type="QString" value="square" name="cap_style"/>\n          <Option type="QString" value="213,180,60,255" name="color"/>\n          <Option type="QString" value="1" name="horizontal_anchor_point"/>\n          <Option type="QString" value="bevel" name="joinstyle"/>\n          <Option type="QString" value="circle" name="name"/>\n          <Option type="QString" value="0,0" name="offset"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n          <Option type="QString" value="MM" name="offset_unit"/>\n          <Option type="QString" value="35,35,35,255" name="outline_color"/>\n          <Option type="QString" value="solid" name="outline_style"/>\n          <Option type="QString" value="0" name="outline_width"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="outline_width_map_unit_scale"/>\n          <Option type="QString" value="MM" name="outline_width_unit"/>\n          <Option type="QString" value="diameter" name="scale_method"/>\n          <Option type="QString" value="2" name="size"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="size_map_unit_scale"/>\n          <Option type="QString" value="MM" name="size_unit"/>\n          <Option type="QString" value="1" name="vertical_anchor_point"/>\n         </Option>\n         <prop v="0" k="angle"/>\n         <prop v="square" k="cap_style"/>\n         <prop v="213,180,60,255" k="color"/>\n         <prop v="1" k="horizontal_anchor_point"/>\n         <prop v="bevel" k="joinstyle"/>\n         <prop v="circle" k="name"/>\n         <prop v="0,0" k="offset"/>\n         <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n         <prop v="MM" k="offset_unit"/>\n         <prop v="35,35,35,255" k="outline_color"/>\n         <prop v="solid" k="outline_style"/>\n         <prop v="0" k="outline_width"/>\n         <prop v="3x:0,0,0,0,0,0" k="outline_width_map_unit_scale"/>\n         <prop v="MM" k="outline_width_unit"/>\n         <prop v="diameter" k="scale_method"/>\n         <prop v="2" k="size"/>\n         <prop v="3x:0,0,0,0,0,0" k="size_map_unit_scale"/>\n         <prop v="MM" k="size_unit"/>\n         <prop v="1" k="vertical_anchor_point"/>\n         <data_defined_properties>\n          <Option type="Map">\n           <Option type="QString" value="" name="name"/>\n           <Option name="properties"/>\n           <Option type="QString" value="collection" name="type"/>\n          </Option>\n         </data_defined_properties>\n        </layer>\n       </symbol>\n       <symbol force_rhr="0" alpha="1" type="fill" name="fillSymbol" clip_to_extent="1">\n        <data_defined_properties>\n         <Option type="Map">\n          <Option type="QString" value="" name="name"/>\n          <Option name="properties"/>\n          <Option type="QString" value="collection" name="type"/>\n         </Option>\n        </data_defined_properties>\n        <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n         <Option type="Map">\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n          <Option type="QString" value="255,255,255,255" name="color"/>\n          <Option type="QString" value="bevel" name="joinstyle"/>\n          <Option type="QString" value="0,0" name="offset"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n          <Option type="QString" value="MM" name="offset_unit"/>\n          <Option type="QString" value="128,128,128,255" name="outline_color"/>\n          <Option type="QString" value="no" name="outline_style"/>\n          <Option type="QString" value="0" name="outline_width"/>\n          <Option type="QString" value="Point" name="outline_width_unit"/>\n          <Option type="QString" value="solid" name="style"/>\n         </Option>\n         <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n         <prop v="255,255,255,255" k="color"/>\n         <prop v="bevel" k="joinstyle"/>\n         <prop v="0,0" k="offset"/>\n         <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n         <prop v="MM" k="offset_unit"/>\n         <prop v="128,128,128,255" k="outline_color"/>\n         <prop v="no" k="outline_style"/>\n         <prop v="0" k="outline_width"/>\n         <prop v="Point" k="outline_width_unit"/>\n         <prop v="solid" k="style"/>\n         <data_defined_properties>\n          <Option type="Map">\n           <Option type="QString" value="" name="name"/>\n           <Option name="properties"/>\n           <Option type="QString" value="collection" name="type"/>\n          </Option>\n         </data_defined_properties>\n        </layer>\n       </symbol>\n      </background>\n      <shadow shadowUnder="0" shadowColor="0,0,0,255" shadowOffsetAngle="135" shadowOffsetUnit="MM" shadowRadiusAlphaOnly="0" shadowOffsetDist="1" shadowOffsetGlobal="1" shadowScale="100" shadowRadiusUnit="MM" shadowRadiusMapUnitScale="3x:0,0,0,0,0,0" shadowDraw="0" shadowBlendMode="6" shadowRadius="1.5" shadowOffsetMapUnitScale="3x:0,0,0,0,0,0" shadowOpacity="0.69999999999999996"/>\n      <dd_properties>\n       <Option type="Map">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n      </dd_properties>\n      <substitutions/>\n     </text-style>\n     <text-format multilineAlign="3" wrapChar="" reverseDirectionSymbol="0" plussign="0" rightDirectionSymbol=">" formatNumbers="0" useMaxLineLengthForAutoWrap="1" leftDirectionSymbol="&lt;" placeDirectionSymbol="0" autoWrapLength="0" addDirectionSymbol="0" decimals="3"/>\n     <placement placementFlags="10" maxCurvedCharAngleIn="25" offsetUnits="MM" geometryGeneratorEnabled="0" yOffset="0" repeatDistanceUnits="MM" repeatDistanceMapUnitScale="3x:0,0,0,0,0,0" geometryGeneratorType="PointGeometry" polygonPlacementFlags="2" fitInPolygonOnly="0" centroidInside="0" overrunDistance="0" priority="5" rotationAngle="0" distUnits="MM" placement="0" quadOffset="4" maxCurvedCharAngleOut="-25" overrunDistanceUnit="MM" distMapUnitScale="3x:0,0,0,0,0,0" xOffset="0" centroidWhole="0" overrunDistanceMapUnitScale="3x:0,0,0,0,0,0" lineAnchorType="0" repeatDistance="0" layerType="PolygonGeometry" geometryGenerator="" offsetType="0" predefinedPositionOrder="TR,TL,BR,BL,R,L,TSR,BSR" preserveRotation="1" lineAnchorPercent="0.5" dist="0" lineAnchorClipping="0" labelOffsetMapUnitScale="3x:0,0,0,0,0,0"/>\n     <rendering labelPerPart="0" fontMaxPixelSize="10000" displayAll="0" unplacedVisibility="0" fontMinPixelSize="3" fontLimitPixelSize="0" maxNumLabels="2000" obstacleType="1" mergeLines="0" obstacleFactor="1" minFeatureSize="0" upsidedownLabels="0" drawLabels="1" limitNumLabels="0" scaleVisibility="0" scaleMin="0" zIndex="0" scaleMax="0" obstacle="1"/>\n     <dd_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </dd_properties>\n     <callout type="simple">\n      <Option type="Map">\n       <Option type="QString" value="pole_of_inaccessibility" name="anchorPoint"/>\n       <Option type="int" value="0" name="blendMode"/>\n       <Option type="Map" name="ddProperties">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n       <Option type="bool" value="false" name="drawToAllParts"/>\n       <Option type="QString" value="0" name="enabled"/>\n       <Option type="QString" value="point_on_exterior" name="labelAnchorPoint"/>\n       <Option type="QString" value="&lt;symbol force_rhr=&quot;0&quot; alpha=&quot;1&quot; type=&quot;line&quot; name=&quot;symbol&quot; clip_to_extent=&quot;1&quot;>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;&quot; name=&quot;name&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;collection&quot; name=&quot;type&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;layer locked=&quot;0&quot; pass=&quot;0&quot; class=&quot;SimpleLine&quot; enabled=&quot;1&quot;>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;align_dash_pattern&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;square&quot; name=&quot;capstyle&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;5;2&quot; name=&quot;customdash&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;customdash_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;customdash_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;dash_pattern_offset&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;dash_pattern_offset_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;dash_pattern_offset_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;draw_inside_polygon&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;bevel&quot; name=&quot;joinstyle&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;60,60,60,255&quot; name=&quot;line_color&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;solid&quot; name=&quot;line_style&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0.3&quot; name=&quot;line_width&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;line_width_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;offset&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;offset_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;offset_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;ring_filter&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;trim_distance_end&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;trim_distance_end_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;trim_distance_end_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;trim_distance_start&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;trim_distance_start_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;trim_distance_start_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;tweak_dash_pattern_on_corners&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;use_custom_dash&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;width_map_unit_scale&quot;/>&lt;/Option>&lt;prop v=&quot;0&quot; k=&quot;align_dash_pattern&quot;/>&lt;prop v=&quot;square&quot; k=&quot;capstyle&quot;/>&lt;prop v=&quot;5;2&quot; k=&quot;customdash&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;customdash_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;customdash_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;dash_pattern_offset&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;dash_pattern_offset_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;dash_pattern_offset_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;draw_inside_polygon&quot;/>&lt;prop v=&quot;bevel&quot; k=&quot;joinstyle&quot;/>&lt;prop v=&quot;60,60,60,255&quot; k=&quot;line_color&quot;/>&lt;prop v=&quot;solid&quot; k=&quot;line_style&quot;/>&lt;prop v=&quot;0.3&quot; k=&quot;line_width&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;line_width_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;offset&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;offset_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;offset_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;ring_filter&quot;/>&lt;prop v=&quot;0&quot; k=&quot;trim_distance_end&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;trim_distance_end_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;trim_distance_end_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;trim_distance_start&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;trim_distance_start_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;trim_distance_start_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;tweak_dash_pattern_on_corners&quot;/>&lt;prop v=&quot;0&quot; k=&quot;use_custom_dash&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;width_map_unit_scale&quot;/>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;&quot; name=&quot;name&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;collection&quot; name=&quot;type&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;/layer>&lt;/symbol>" name="lineSymbol"/>\n       <Option type="double" value="0" name="minLength"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="minLengthMapUnitScale"/>\n       <Option type="QString" value="MM" name="minLengthUnit"/>\n       <Option type="double" value="0" name="offsetFromAnchor"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offsetFromAnchorMapUnitScale"/>\n       <Option type="QString" value="MM" name="offsetFromAnchorUnit"/>\n       <Option type="double" value="0" name="offsetFromLabel"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offsetFromLabelMapUnitScale"/>\n       <Option type="QString" value="MM" name="offsetFromLabelUnit"/>\n      </Option>\n     </callout>\n    </settings>\n   </rule>\n   <rule filter="ELSE" active="0" key="{e63b81c3-3c16-444e-8460-c7d004594c22}">\n    <settings calloutType="simple">\n     <text-style fontUnderline="0" fontWeight="50" multilineHeight="1" fontItalic="0" useSubstitutions="0" blendMode="0" previewBkgrdColor="255,255,255,255" namedStyle="Regular" isExpression="0" legendString="Aa" fontSize="10" fontSizeUnit="Point" textOrientation="horizontal" fieldName="name" fontKerning="1" textColor="50,50,50,255" textOpacity="1" fontLetterSpacing="0" fontStrikeout="0" fontSizeMapUnitScale="3x:0,0,0,0,0,0" capitalization="0" fontWordSpacing="0" fontFamily="Liberation Sans" allowHtml="0">\n      <families/>\n      <text-buffer bufferSize="1" bufferNoFill="1" bufferOpacity="1" bufferColor="250,250,250,255" bufferSizeUnits="MM" bufferSizeMapUnitScale="3x:0,0,0,0,0,0" bufferDraw="0" bufferBlendMode="0" bufferJoinStyle="128"/>\n      <text-mask maskSizeMapUnitScale="3x:0,0,0,0,0,0" maskType="0" maskSizeUnits="MM" maskOpacity="1" maskEnabled="0" maskJoinStyle="128" maskSize="0" maskedSymbolLayers=""/>\n      <background shapeRadiiY="0" shapeSizeType="0" shapeJoinStyle="64" shapeRadiiX="0" shapeDraw="0" shapeOffsetX="0" shapeSizeY="0" shapeOffsetMapUnitScale="3x:0,0,0,0,0,0" shapeFillColor="255,255,255,255" shapeSizeUnit="Point" shapeSizeX="0" shapeSizeMapUnitScale="3x:0,0,0,0,0,0" shapeBlendMode="0" shapeRotation="0" shapeRadiiMapUnitScale="3x:0,0,0,0,0,0" shapeType="0" shapeBorderWidthMapUnitScale="3x:0,0,0,0,0,0" shapeSVGFile="" shapeRadiiUnit="Point" shapeOffsetUnit="Point" shapeOpacity="1" shapeRotationType="0" shapeBorderColor="128,128,128,255" shapeBorderWidth="0" shapeBorderWidthUnit="Point" shapeOffsetY="0">\n       <symbol force_rhr="0" alpha="1" type="marker" name="markerSymbol" clip_to_extent="1">\n        <data_defined_properties>\n         <Option type="Map">\n          <Option type="QString" value="" name="name"/>\n          <Option name="properties"/>\n          <Option type="QString" value="collection" name="type"/>\n         </Option>\n        </data_defined_properties>\n        <layer locked="0" pass="0" class="SimpleMarker" enabled="1">\n         <Option type="Map">\n          <Option type="QString" value="0" name="angle"/>\n          <Option type="QString" value="square" name="cap_style"/>\n          <Option type="QString" value="164,113,88,255" name="color"/>\n          <Option type="QString" value="1" name="horizontal_anchor_point"/>\n          <Option type="QString" value="bevel" name="joinstyle"/>\n          <Option type="QString" value="circle" name="name"/>\n          <Option type="QString" value="0,0" name="offset"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n          <Option type="QString" value="MM" name="offset_unit"/>\n          <Option type="QString" value="35,35,35,255" name="outline_color"/>\n          <Option type="QString" value="solid" name="outline_style"/>\n          <Option type="QString" value="0" name="outline_width"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="outline_width_map_unit_scale"/>\n          <Option type="QString" value="MM" name="outline_width_unit"/>\n          <Option type="QString" value="diameter" name="scale_method"/>\n          <Option type="QString" value="2" name="size"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="size_map_unit_scale"/>\n          <Option type="QString" value="MM" name="size_unit"/>\n          <Option type="QString" value="1" name="vertical_anchor_point"/>\n         </Option>\n         <prop v="0" k="angle"/>\n         <prop v="square" k="cap_style"/>\n         <prop v="164,113,88,255" k="color"/>\n         <prop v="1" k="horizontal_anchor_point"/>\n         <prop v="bevel" k="joinstyle"/>\n         <prop v="circle" k="name"/>\n         <prop v="0,0" k="offset"/>\n         <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n         <prop v="MM" k="offset_unit"/>\n         <prop v="35,35,35,255" k="outline_color"/>\n         <prop v="solid" k="outline_style"/>\n         <prop v="0" k="outline_width"/>\n         <prop v="3x:0,0,0,0,0,0" k="outline_width_map_unit_scale"/>\n         <prop v="MM" k="outline_width_unit"/>\n         <prop v="diameter" k="scale_method"/>\n         <prop v="2" k="size"/>\n         <prop v="3x:0,0,0,0,0,0" k="size_map_unit_scale"/>\n         <prop v="MM" k="size_unit"/>\n         <prop v="1" k="vertical_anchor_point"/>\n         <data_defined_properties>\n          <Option type="Map">\n           <Option type="QString" value="" name="name"/>\n           <Option name="properties"/>\n           <Option type="QString" value="collection" name="type"/>\n          </Option>\n         </data_defined_properties>\n        </layer>\n       </symbol>\n       <symbol force_rhr="0" alpha="1" type="fill" name="fillSymbol" clip_to_extent="1">\n        <data_defined_properties>\n         <Option type="Map">\n          <Option type="QString" value="" name="name"/>\n          <Option name="properties"/>\n          <Option type="QString" value="collection" name="type"/>\n         </Option>\n        </data_defined_properties>\n        <layer locked="0" pass="0" class="SimpleFill" enabled="1">\n         <Option type="Map">\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="border_width_map_unit_scale"/>\n          <Option type="QString" value="255,255,255,255" name="color"/>\n          <Option type="QString" value="bevel" name="joinstyle"/>\n          <Option type="QString" value="0,0" name="offset"/>\n          <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n          <Option type="QString" value="MM" name="offset_unit"/>\n          <Option type="QString" value="128,128,128,255" name="outline_color"/>\n          <Option type="QString" value="no" name="outline_style"/>\n          <Option type="QString" value="0" name="outline_width"/>\n          <Option type="QString" value="Point" name="outline_width_unit"/>\n          <Option type="QString" value="solid" name="style"/>\n         </Option>\n         <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>\n         <prop v="255,255,255,255" k="color"/>\n         <prop v="bevel" k="joinstyle"/>\n         <prop v="0,0" k="offset"/>\n         <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n         <prop v="MM" k="offset_unit"/>\n         <prop v="128,128,128,255" k="outline_color"/>\n         <prop v="no" k="outline_style"/>\n         <prop v="0" k="outline_width"/>\n         <prop v="Point" k="outline_width_unit"/>\n         <prop v="solid" k="style"/>\n         <data_defined_properties>\n          <Option type="Map">\n           <Option type="QString" value="" name="name"/>\n           <Option name="properties"/>\n           <Option type="QString" value="collection" name="type"/>\n          </Option>\n         </data_defined_properties>\n        </layer>\n       </symbol>\n      </background>\n      <shadow shadowUnder="0" shadowColor="0,0,0,255" shadowOffsetAngle="135" shadowOffsetUnit="MM" shadowRadiusAlphaOnly="0" shadowOffsetDist="1" shadowOffsetGlobal="1" shadowScale="100" shadowRadiusUnit="MM" shadowRadiusMapUnitScale="3x:0,0,0,0,0,0" shadowDraw="0" shadowBlendMode="6" shadowRadius="1.5" shadowOffsetMapUnitScale="3x:0,0,0,0,0,0" shadowOpacity="0.69999999999999996"/>\n      <dd_properties>\n       <Option type="Map">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n      </dd_properties>\n      <substitutions/>\n     </text-style>\n     <text-format multilineAlign="3" wrapChar="" reverseDirectionSymbol="0" plussign="0" rightDirectionSymbol=">" formatNumbers="0" useMaxLineLengthForAutoWrap="1" leftDirectionSymbol="&lt;" placeDirectionSymbol="0" autoWrapLength="0" addDirectionSymbol="0" decimals="3"/>\n     <placement placementFlags="10" maxCurvedCharAngleIn="25" offsetUnits="MM" geometryGeneratorEnabled="0" yOffset="0" repeatDistanceUnits="MM" repeatDistanceMapUnitScale="3x:0,0,0,0,0,0" geometryGeneratorType="PointGeometry" polygonPlacementFlags="2" fitInPolygonOnly="0" centroidInside="0" overrunDistance="0" priority="5" rotationAngle="0" distUnits="MM" placement="0" quadOffset="4" maxCurvedCharAngleOut="-25" overrunDistanceUnit="MM" distMapUnitScale="3x:0,0,0,0,0,0" xOffset="0" centroidWhole="0" overrunDistanceMapUnitScale="3x:0,0,0,0,0,0" lineAnchorType="0" repeatDistance="0" layerType="PolygonGeometry" geometryGenerator="" offsetType="0" predefinedPositionOrder="TR,TL,BR,BL,R,L,TSR,BSR" preserveRotation="1" lineAnchorPercent="0.5" dist="0" lineAnchorClipping="0" labelOffsetMapUnitScale="3x:0,0,0,0,0,0"/>\n     <rendering labelPerPart="0" fontMaxPixelSize="10000" displayAll="0" unplacedVisibility="0" fontMinPixelSize="3" fontLimitPixelSize="0" maxNumLabels="2000" obstacleType="1" mergeLines="0" obstacleFactor="1" minFeatureSize="0" upsidedownLabels="0" drawLabels="1" limitNumLabels="0" scaleVisibility="0" scaleMin="0" zIndex="0" scaleMax="0" obstacle="1"/>\n     <dd_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </dd_properties>\n     <callout type="simple">\n      <Option type="Map">\n       <Option type="QString" value="pole_of_inaccessibility" name="anchorPoint"/>\n       <Option type="int" value="0" name="blendMode"/>\n       <Option type="Map" name="ddProperties">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n       <Option type="bool" value="false" name="drawToAllParts"/>\n       <Option type="QString" value="0" name="enabled"/>\n       <Option type="QString" value="point_on_exterior" name="labelAnchorPoint"/>\n       <Option type="QString" value="&lt;symbol force_rhr=&quot;0&quot; alpha=&quot;1&quot; type=&quot;line&quot; name=&quot;symbol&quot; clip_to_extent=&quot;1&quot;>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;&quot; name=&quot;name&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;collection&quot; name=&quot;type&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;layer locked=&quot;0&quot; pass=&quot;0&quot; class=&quot;SimpleLine&quot; enabled=&quot;1&quot;>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;align_dash_pattern&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;square&quot; name=&quot;capstyle&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;5;2&quot; name=&quot;customdash&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;customdash_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;customdash_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;dash_pattern_offset&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;dash_pattern_offset_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;dash_pattern_offset_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;draw_inside_polygon&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;bevel&quot; name=&quot;joinstyle&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;60,60,60,255&quot; name=&quot;line_color&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;solid&quot; name=&quot;line_style&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0.3&quot; name=&quot;line_width&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;line_width_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;offset&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;offset_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;offset_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;ring_filter&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;trim_distance_end&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;trim_distance_end_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;trim_distance_end_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;trim_distance_start&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;trim_distance_start_map_unit_scale&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;MM&quot; name=&quot;trim_distance_start_unit&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;tweak_dash_pattern_on_corners&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;0&quot; name=&quot;use_custom_dash&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;3x:0,0,0,0,0,0&quot; name=&quot;width_map_unit_scale&quot;/>&lt;/Option>&lt;prop v=&quot;0&quot; k=&quot;align_dash_pattern&quot;/>&lt;prop v=&quot;square&quot; k=&quot;capstyle&quot;/>&lt;prop v=&quot;5;2&quot; k=&quot;customdash&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;customdash_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;customdash_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;dash_pattern_offset&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;dash_pattern_offset_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;dash_pattern_offset_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;draw_inside_polygon&quot;/>&lt;prop v=&quot;bevel&quot; k=&quot;joinstyle&quot;/>&lt;prop v=&quot;60,60,60,255&quot; k=&quot;line_color&quot;/>&lt;prop v=&quot;solid&quot; k=&quot;line_style&quot;/>&lt;prop v=&quot;0.3&quot; k=&quot;line_width&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;line_width_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;offset&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;offset_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;offset_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;ring_filter&quot;/>&lt;prop v=&quot;0&quot; k=&quot;trim_distance_end&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;trim_distance_end_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;trim_distance_end_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;trim_distance_start&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;trim_distance_start_map_unit_scale&quot;/>&lt;prop v=&quot;MM&quot; k=&quot;trim_distance_start_unit&quot;/>&lt;prop v=&quot;0&quot; k=&quot;tweak_dash_pattern_on_corners&quot;/>&lt;prop v=&quot;0&quot; k=&quot;use_custom_dash&quot;/>&lt;prop v=&quot;3x:0,0,0,0,0,0&quot; k=&quot;width_map_unit_scale&quot;/>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; value=&quot;&quot; name=&quot;name&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; value=&quot;collection&quot; name=&quot;type&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;/layer>&lt;/symbol>" name="lineSymbol"/>\n       <Option type="double" value="0" name="minLength"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="minLengthMapUnitScale"/>\n       <Option type="QString" value="MM" name="minLengthUnit"/>\n       <Option type="double" value="0" name="offsetFromAnchor"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offsetFromAnchorMapUnitScale"/>\n       <Option type="QString" value="MM" name="offsetFromAnchorUnit"/>\n       <Option type="double" value="0" name="offsetFromLabel"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offsetFromLabelMapUnitScale"/>\n       <Option type="QString" value="MM" name="offsetFromLabelUnit"/>\n      </Option>\n     </callout>\n    </settings>\n   </rule>\n  </rules>\n </labeling>\n <customproperties>\n  <Option type="Map">\n   <Option type="List" name="dualview/previewExpressions">\n    <Option type="QString" value="&quot;name&quot;"/>\n   </Option>\n   <Option type="int" value="0" name="embeddedWidgets/count"/>\n   <Option name="variableNames"/>\n   <Option name="variableValues"/>\n  </Option>\n </customproperties>\n <blendMode>0</blendMode>\n <featureBlendMode>0</featureBlendMode>\n <layerOpacity>1</layerOpacity>\n <SingleCategoryDiagramRenderer diagramType="Histogram" attributeLegend="1">\n  <DiagramCategory minScaleDenominator="0" width="15" rotationOffset="270" penWidth="0" barWidth="5" spacingUnitScale="3x:0,0,0,0,0,0" spacingUnit="MM" penColor="#000000" diagramOrientation="Up" height="15" opacity="1" labelPlacementMethod="XHeight" showAxis="1" spacing="5" maxScaleDenominator="1e+08" scaleBasedVisibility="0" direction="0" scaleDependency="Area" minimumSize="0" lineSizeType="MM" sizeScale="3x:0,0,0,0,0,0" lineSizeScale="3x:0,0,0,0,0,0" enabled="0" penAlpha="255" sizeType="MM" backgroundColor="#ffffff" backgroundAlpha="255">\n   <fontProperties style="" description="Fira Sans Semi-Light,10,-1,5,50,0,0,0,0,0"/>\n   <axisSymbol>\n    <symbol force_rhr="0" alpha="1" type="line" name="" clip_to_extent="1">\n     <data_defined_properties>\n      <Option type="Map">\n       <Option type="QString" value="" name="name"/>\n       <Option name="properties"/>\n       <Option type="QString" value="collection" name="type"/>\n      </Option>\n     </data_defined_properties>\n     <layer locked="0" pass="0" class="SimpleLine" enabled="1">\n      <Option type="Map">\n       <Option type="QString" value="0" name="align_dash_pattern"/>\n       <Option type="QString" value="square" name="capstyle"/>\n       <Option type="QString" value="5;2" name="customdash"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="customdash_map_unit_scale"/>\n       <Option type="QString" value="MM" name="customdash_unit"/>\n       <Option type="QString" value="0" name="dash_pattern_offset"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="dash_pattern_offset_map_unit_scale"/>\n       <Option type="QString" value="MM" name="dash_pattern_offset_unit"/>\n       <Option type="QString" value="0" name="draw_inside_polygon"/>\n       <Option type="QString" value="bevel" name="joinstyle"/>\n       <Option type="QString" value="35,35,35,255" name="line_color"/>\n       <Option type="QString" value="solid" name="line_style"/>\n       <Option type="QString" value="0.26" name="line_width"/>\n       <Option type="QString" value="MM" name="line_width_unit"/>\n       <Option type="QString" value="0" name="offset"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="offset_map_unit_scale"/>\n       <Option type="QString" value="MM" name="offset_unit"/>\n       <Option type="QString" value="0" name="ring_filter"/>\n       <Option type="QString" value="0" name="trim_distance_end"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="trim_distance_end_map_unit_scale"/>\n       <Option type="QString" value="MM" name="trim_distance_end_unit"/>\n       <Option type="QString" value="0" name="trim_distance_start"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="trim_distance_start_map_unit_scale"/>\n       <Option type="QString" value="MM" name="trim_distance_start_unit"/>\n       <Option type="QString" value="0" name="tweak_dash_pattern_on_corners"/>\n       <Option type="QString" value="0" name="use_custom_dash"/>\n       <Option type="QString" value="3x:0,0,0,0,0,0" name="width_map_unit_scale"/>\n      </Option>\n      <prop v="0" k="align_dash_pattern"/>\n      <prop v="square" k="capstyle"/>\n      <prop v="5;2" k="customdash"/>\n      <prop v="3x:0,0,0,0,0,0" k="customdash_map_unit_scale"/>\n      <prop v="MM" k="customdash_unit"/>\n      <prop v="0" k="dash_pattern_offset"/>\n      <prop v="3x:0,0,0,0,0,0" k="dash_pattern_offset_map_unit_scale"/>\n      <prop v="MM" k="dash_pattern_offset_unit"/>\n      <prop v="0" k="draw_inside_polygon"/>\n      <prop v="bevel" k="joinstyle"/>\n      <prop v="35,35,35,255" k="line_color"/>\n      <prop v="solid" k="line_style"/>\n      <prop v="0.26" k="line_width"/>\n      <prop v="MM" k="line_width_unit"/>\n      <prop v="0" k="offset"/>\n      <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>\n      <prop v="MM" k="offset_unit"/>\n      <prop v="0" k="ring_filter"/>\n      <prop v="0" k="trim_distance_end"/>\n      <prop v="3x:0,0,0,0,0,0" k="trim_distance_end_map_unit_scale"/>\n      <prop v="MM" k="trim_distance_end_unit"/>\n      <prop v="0" k="trim_distance_start"/>\n      <prop v="3x:0,0,0,0,0,0" k="trim_distance_start_map_unit_scale"/>\n      <prop v="MM" k="trim_distance_start_unit"/>\n      <prop v="0" k="tweak_dash_pattern_on_corners"/>\n      <prop v="0" k="use_custom_dash"/>\n      <prop v="3x:0,0,0,0,0,0" k="width_map_unit_scale"/>\n      <data_defined_properties>\n       <Option type="Map">\n        <Option type="QString" value="" name="name"/>\n        <Option name="properties"/>\n        <Option type="QString" value="collection" name="type"/>\n       </Option>\n      </data_defined_properties>\n     </layer>\n    </symbol>\n   </axisSymbol>\n  </DiagramCategory>\n </SingleCategoryDiagramRenderer>\n <DiagramLayerSettings zIndex="0" showAll="1" priority="0" dist="0" placement="1" linePlacementFlags="18" obstacle="0">\n  <properties>\n   <Option type="Map">\n    <Option type="QString" value="" name="name"/>\n    <Option name="properties"/>\n    <Option type="QString" value="collection" name="type"/>\n   </Option>\n  </properties>\n </DiagramLayerSettings>\n <geometryOptions geometryPrecision="0" removeDuplicateNodes="0">\n  <activeChecks/>\n  <checkConfiguration type="Map">\n   <Option type="Map" name="QgsGeometryGapCheck">\n    <Option type="double" value="0" name="allowedGapsBuffer"/>\n    <Option type="bool" value="false" name="allowedGapsEnabled"/>\n    <Option type="QString" value="" name="allowedGapsLayer"/>\n   </Option>\n  </checkConfiguration>\n </geometryOptions>\n <legend showLabelLegend="0" type="default-vector"/>\n <referencedLayers/>\n <fieldConfiguration>\n  <field configurationFlags="None" name="osm_id">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="osm_type">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="boundary">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="admin_level">\n   <editWidget type="Range">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="name">\n   <editWidget type="TextEdit">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n  <field configurationFlags="None" name="member_ids">\n   <editWidget type="KeyValue">\n    <config>\n     <Option/>\n    </config>\n   </editWidget>\n  </field>\n </fieldConfiguration>\n <aliases>\n  <alias index="0" field="osm_id" name=""/>\n  <alias index="1" field="osm_type" name=""/>\n  <alias index="2" field="boundary" name=""/>\n  <alias index="3" field="admin_level" name=""/>\n  <alias index="4" field="name" name=""/>\n  <alias index="5" field="member_ids" name=""/>\n </aliases>\n <defaults>\n  <default applyOnUpdate="0" field="osm_id" expression=""/>\n  <default applyOnUpdate="0" field="osm_type" expression=""/>\n  <default applyOnUpdate="0" field="boundary" expression=""/>\n  <default applyOnUpdate="0" field="admin_level" expression=""/>\n  <default applyOnUpdate="0" field="name" expression=""/>\n  <default applyOnUpdate="0" field="member_ids" expression=""/>\n </defaults>\n <constraints>\n  <constraint field="osm_id" constraints="3" unique_strength="1" notnull_strength="1" exp_strength="0"/>\n  <constraint field="osm_type" constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0"/>\n  <constraint field="boundary" constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0"/>\n  <constraint field="admin_level" constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0"/>\n  <constraint field="name" constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0"/>\n  <constraint field="member_ids" constraints="0" unique_strength="0" notnull_strength="0" exp_strength="0"/>\n </constraints>\n <constraintExpressions>\n  <constraint field="osm_id" desc="" exp=""/>\n  <constraint field="osm_type" desc="" exp=""/>\n  <constraint field="boundary" desc="" exp=""/>\n  <constraint field="admin_level" desc="" exp=""/>\n  <constraint field="name" desc="" exp=""/>\n  <constraint field="member_ids" desc="" exp=""/>\n </constraintExpressions>\n <expressionfields/>\n <attributeactions>\n  <defaultAction key="Canvas" value="{00000000-0000-0000-0000-000000000000}"/>\n </attributeactions>\n <attributetableconfig actionWidgetStyle="dropDown" sortExpression="" sortOrder="0">\n  <columns>\n   <column width="-1" type="field" name="osm_id" hidden="0"/>\n   <column width="-1" type="field" name="osm_type" hidden="0"/>\n   <column width="-1" type="field" name="boundary" hidden="0"/>\n   <column width="-1" type="field" name="admin_level" hidden="0"/>\n   <column width="-1" type="field" name="name" hidden="0"/>\n   <column width="-1" type="field" name="member_ids" hidden="0"/>\n   <column width="-1" type="actions" hidden="1"/>\n  </columns>\n </attributetableconfig>\n <conditionalstyles>\n  <rowstyles/>\n  <fieldstyles/>\n </conditionalstyles>\n <storedexpressions/>\n <editform tolerant="1"></editform>\n <editforminit/>\n <editforminitcodesource>0</editforminitcodesource>\n <editforminitfilepath></editforminitfilepath>\n <editforminitcode><![CDATA[# -*- coding: utf-8 -*-\n"""\nQGIS forms can have a Python function that is called when the form is\nopened.\n\nUse this function to add extra logic to your forms.\n\nEnter the name of the function in the "Python Init function"\nfield.\nAn example follows:\n"""\nfrom qgis.PyQt.QtWidgets import QWidget\n\ndef my_form_open(dialog, layer, feature):\n\tgeom = feature.geometry()\n\tcontrol = dialog.findChild(QWidget, "MyLineEdit")\n]]></editforminitcode>\n <featformsuppress>0</featformsuppress>\n <editorlayout>generatedlayout</editorlayout>\n <editable>\n  <field editable="1" name="admin_level"/>\n  <field editable="1" name="boundary"/>\n  <field editable="1" name="member_ids"/>\n  <field editable="1" name="name"/>\n  <field editable="1" name="osm_id"/>\n  <field editable="1" name="osm_type"/>\n </editable>\n <labelOnTop>\n  <field labelOnTop="0" name="admin_level"/>\n  <field labelOnTop="0" name="boundary"/>\n  <field labelOnTop="0" name="member_ids"/>\n  <field labelOnTop="0" name="name"/>\n  <field labelOnTop="0" name="osm_id"/>\n  <field labelOnTop="0" name="osm_type"/>\n </labelOnTop>\n <reuseLastValue>\n  <field reuseLastValue="0" name="admin_level"/>\n  <field reuseLastValue="0" name="boundary"/>\n  <field reuseLastValue="0" name="member_ids"/>\n  <field reuseLastValue="0" name="name"/>\n  <field reuseLastValue="0" name="osm_id"/>\n  <field reuseLastValue="0" name="osm_type"/>\n </reuseLastValue>\n <dataDefinedFieldProperties/>\n <widgets/>\n <previewExpression>"name"</previewExpression>\n <mapTip></mapTip>\n <layerGeometryType>2</layerGeometryType>\n</qgis>\n	<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:ogc="http://www.opengis.net/ogc" xmlns:se="http://www.opengis.net/se" xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.1.0/StyledLayerDescriptor.xsd" version="1.1.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n <NamedLayer>\n  <se:Name>vplace_polygon</se:Name>\n  <UserStyle>\n   <se:Name>vplace_polygon</se:Name>\n   <se:FeatureTypeStyle>\n    <se:Rule>\n     <se:Name>Ward</se:Name>\n     <se:Description>\n      <se:Title>Ward</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>9</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>125000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#ffe4b1</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>0 - 1000</se:Name>\n     <se:Description>\n      <se:Title>0 - 1000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>8</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>1000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#ffe4b1</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>1000 - 125000</se:Name>\n     <se:Description>\n      <se:Title>1000 - 125000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>8</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>1000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>125000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#ffe4b1</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>50000 - 100000</se:Name>\n     <se:Description>\n      <se:Title>50000 - 100000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>8</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>125000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>500000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#ffe4b1</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.035</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Township</se:Name>\n     <se:Description>\n      <se:Title>Township</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>7</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#ffe4b1</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>0 - 50000</se:Name>\n     <se:Description>\n      <se:Title>0 - 50000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>50000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#fff8cd</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>50000 - 100000</se:Name>\n     <se:Description>\n      <se:Title>50000 - 100000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>50000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>100000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#fff8cd</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>100000 - 500000</se:Name>\n     <se:Description>\n      <se:Title>100000 - 500000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>100000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>500000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#fff8cd</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>500000 - 10000000</se:Name>\n     <se:Description>\n      <se:Title>500000 - 10000000</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>500000</se:MinScaleDenominator>\n     <se:MaxScaleDenominator>10000000</se:MaxScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#fff8cd</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>1e+07 - 0</se:Name>\n     <se:Description>\n      <se:Title>1e+07 - 0</se:Title>\n     </se:Description>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>10000000</se:MinScaleDenominator>\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#fff8cd</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">1</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <se:Name>Other</se:Name>\n     <se:Description>\n      <se:Title>Other</se:Title>\n     </se:Description>\n     <!--Parser Error: \nsyntax error, unexpected ELSE - Expression was: ELSE-->\n     <se:PolygonSymbolizer>\n      <se:Fill>\n       <se:SvgParameter name="fill">#fff8cd</se:SvgParameter>\n       <se:SvgParameter name="fill-opacity">0.2</se:SvgParameter>\n      </se:Fill>\n      <se:Stroke>\n       <se:SvgParameter name="stroke">#232323</se:SvgParameter>\n       <se:SvgParameter name="stroke-opacity">0.56</se:SvgParameter>\n       <se:SvgParameter name="stroke-width">2</se:SvgParameter>\n       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>\n      </se:Stroke>\n     </se:PolygonSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsGreaterThan>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsGreaterThan>\n     </ogc:Filter>\n     <se:MaxScaleDenominator>300000</se:MaxScaleDenominator>\n     <se:TextSymbolizer>\n      <se:Label>\n       <ogc:PropertyName>name</ogc:PropertyName>\n      </se:Label>\n      <se:Font>\n       <se:SvgParameter name="font-family">Liberation Sans</se:SvgParameter>\n       <se:SvgParameter name="font-size">15</se:SvgParameter>\n       <se:SvgParameter name="font-style">italic</se:SvgParameter>\n      </se:Font>\n      <se:LabelPlacement>\n       <se:PointPlacement>\n        <se:AnchorPoint>\n         <se:AnchorPointX>0</se:AnchorPointX>\n         <se:AnchorPointY>0.5</se:AnchorPointY>\n        </se:AnchorPoint>\n       </se:PointPlacement>\n      </se:LabelPlacement>\n      <se:Fill>\n       <se:SvgParameter name="fill">#323232</se:SvgParameter>\n      </se:Fill>\n      <se:VendorOption name="maxDisplacement">1</se:VendorOption>\n     </se:TextSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">\n      <ogc:PropertyIsLessThanOrEqualTo>\n       <ogc:PropertyName>admin_level</ogc:PropertyName>\n       <ogc:Literal>6</ogc:Literal>\n      </ogc:PropertyIsLessThanOrEqualTo>\n     </ogc:Filter>\n     <se:MinScaleDenominator>100000</se:MinScaleDenominator>\n     <se:TextSymbolizer>\n      <se:Label>\n       <ogc:PropertyName>name</ogc:PropertyName>\n      </se:Label>\n      <se:Font>\n       <se:SvgParameter name="font-family">Liberation Sans</se:SvgParameter>\n       <se:SvgParameter name="font-size">16</se:SvgParameter>\n       <se:SvgParameter name="font-style">italic</se:SvgParameter>\n       <se:SvgParameter name="font-weight">bold</se:SvgParameter>\n      </se:Font>\n      <se:LabelPlacement>\n       <se:PointPlacement>\n        <se:AnchorPoint>\n         <se:AnchorPointX>0</se:AnchorPointX>\n         <se:AnchorPointY>0.5</se:AnchorPointY>\n        </se:AnchorPoint>\n       </se:PointPlacement>\n      </se:LabelPlacement>\n      <se:Fill>\n       <se:SvgParameter name="fill">#323232</se:SvgParameter>\n      </se:Fill>\n      <se:VendorOption name="maxDisplacement">1</se:VendorOption>\n     </se:TextSymbolizer>\n    </se:Rule>\n    <se:Rule>\n     <!--Parser Error: \nsyntax error, unexpected ELSE - Expression was: ELSE-->\n     <se:TextSymbolizer>\n      <se:Label>\n       <ogc:PropertyName>name</ogc:PropertyName>\n      </se:Label>\n      <se:Font>\n       <se:SvgParameter name="font-family">Liberation Sans</se:SvgParameter>\n       <se:SvgParameter name="font-size">13</se:SvgParameter>\n      </se:Font>\n      <se:LabelPlacement>\n       <se:PointPlacement>\n        <se:AnchorPoint>\n         <se:AnchorPointX>0</se:AnchorPointX>\n         <se:AnchorPointY>0.5</se:AnchorPointY>\n        </se:AnchorPoint>\n       </se:PointPlacement>\n      </se:LabelPlacement>\n      <se:Fill>\n       <se:SvgParameter name="fill">#323232</se:SvgParameter>\n      </se:Fill>\n      <se:VendorOption name="maxDisplacement">1</se:VendorOption>\n     </se:TextSymbolizer>\n    </se:Rule>\n   </se:FeatureTypeStyle>\n  </UserStyle>\n </NamedLayer>\n</StyledLayerDescriptor>\n	t	Basic place styling with scale based visibility and labels.	rustprooflabs	\N	2021-09-12 00:44:51.464497	\N
\.


--
-- Data for Name: layer_styles_staging; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.layer_styles_staging (id, f_table_catalog, f_table_schema, f_table_name, f_geometry_column, stylename, styleqml, stylesld, useasdefault, description, owner, ui, update_time, type) FROM stdin;
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Name: pgosm_flex_id_seq; Type: SEQUENCE SET; Schema: osm; Owner: postgres
--

SELECT pg_catalog.setval('osm.pgosm_flex_id_seq', 1, true);


--
-- Name: road_id_seq; Type: SEQUENCE SET; Schema: pgosm; Owner: postgres
--

SELECT pg_catalog.setval('pgosm.road_id_seq', 25, true);


--
-- Name: layer_styles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.layer_styles_id_seq', 4, true);


--
-- Name: amenity_line pk_osm_amenity_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.amenity_line
    ADD CONSTRAINT pk_osm_amenity_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: amenity_point pk_osm_amenity_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.amenity_point
    ADD CONSTRAINT pk_osm_amenity_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: amenity_polygon pk_osm_amenity_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.amenity_polygon
    ADD CONSTRAINT pk_osm_amenity_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: building_polygon pk_osm_building_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.building_polygon
    ADD CONSTRAINT pk_osm_building_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: indoor_line pk_osm_indoor_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.indoor_line
    ADD CONSTRAINT pk_osm_indoor_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: indoor_point pk_osm_indoor_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.indoor_point
    ADD CONSTRAINT pk_osm_indoor_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: indoor_polygon pk_osm_indoor_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.indoor_polygon
    ADD CONSTRAINT pk_osm_indoor_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: infrastructure_point pk_osm_infrastructure_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.infrastructure_point
    ADD CONSTRAINT pk_osm_infrastructure_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: landuse_point pk_osm_landuse_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.landuse_point
    ADD CONSTRAINT pk_osm_landuse_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: landuse_polygon pk_osm_landuse_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.landuse_polygon
    ADD CONSTRAINT pk_osm_landuse_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: leisure_point pk_osm_leisure_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.leisure_point
    ADD CONSTRAINT pk_osm_leisure_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: leisure_polygon pk_osm_leisure_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.leisure_polygon
    ADD CONSTRAINT pk_osm_leisure_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: natural_line pk_osm_natural_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.natural_line
    ADD CONSTRAINT pk_osm_natural_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: natural_point pk_osm_natural_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.natural_point
    ADD CONSTRAINT pk_osm_natural_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: natural_polygon pk_osm_natural_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.natural_polygon
    ADD CONSTRAINT pk_osm_natural_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: pgosm_flex pk_osm_pgosm_flex; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.pgosm_flex
    ADD CONSTRAINT pk_osm_pgosm_flex PRIMARY KEY (id);


--
-- Name: place_line pk_osm_place_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.place_line
    ADD CONSTRAINT pk_osm_place_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: place_point pk_osm_place_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.place_point
    ADD CONSTRAINT pk_osm_place_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: place_polygon pk_osm_place_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.place_polygon
    ADD CONSTRAINT pk_osm_place_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: poi_line pk_osm_poi_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.poi_line
    ADD CONSTRAINT pk_osm_poi_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: poi_point pk_osm_poi_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.poi_point
    ADD CONSTRAINT pk_osm_poi_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: poi_polygon pk_osm_poi_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.poi_polygon
    ADD CONSTRAINT pk_osm_poi_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: public_transport_line pk_osm_public_transport_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.public_transport_line
    ADD CONSTRAINT pk_osm_public_transport_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: public_transport_point pk_osm_public_transport_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.public_transport_point
    ADD CONSTRAINT pk_osm_public_transport_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: public_transport_polygon pk_osm_public_transport_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.public_transport_polygon
    ADD CONSTRAINT pk_osm_public_transport_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: road_line pk_osm_road_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.road_line
    ADD CONSTRAINT pk_osm_road_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: road_point pk_osm_road_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.road_point
    ADD CONSTRAINT pk_osm_road_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: shop_point pk_osm_shop_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.shop_point
    ADD CONSTRAINT pk_osm_shop_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: shop_polygon pk_osm_shop_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.shop_polygon
    ADD CONSTRAINT pk_osm_shop_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: tags pk_osm_tags_osm_id_type; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.tags
    ADD CONSTRAINT pk_osm_tags_osm_id_type PRIMARY KEY (osm_id, geom_type);


--
-- Name: traffic_point pk_osm_traffic_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.traffic_point
    ADD CONSTRAINT pk_osm_traffic_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: water_line pk_osm_water_line_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.water_line
    ADD CONSTRAINT pk_osm_water_line_osm_id PRIMARY KEY (osm_id);


--
-- Name: water_point pk_osm_water_point_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.water_point
    ADD CONSTRAINT pk_osm_water_point_osm_id PRIMARY KEY (osm_id);


--
-- Name: water_polygon pk_osm_water_polygon_osm_id; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.water_polygon
    ADD CONSTRAINT pk_osm_water_polygon_osm_id PRIMARY KEY (osm_id);


--
-- Name: place_polygon_nested place_polygon_nested_pkey; Type: CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.place_polygon_nested
    ADD CONSTRAINT place_polygon_nested_pkey PRIMARY KEY (osm_id);


--
-- Name: road road_pkey; Type: CONSTRAINT; Schema: pgosm; Owner: postgres
--

ALTER TABLE ONLY pgosm.road
    ADD CONSTRAINT road_pkey PRIMARY KEY (id);


--
-- Name: road uq_pgosm_routable_code; Type: CONSTRAINT; Schema: pgosm; Owner: postgres
--

ALTER TABLE ONLY pgosm.road
    ADD CONSTRAINT uq_pgosm_routable_code UNIQUE (region, osm_type);


--
-- Name: layer_styles layer_styles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.layer_styles
    ADD CONSTRAINT layer_styles_pkey PRIMARY KEY (id);


--
-- Name: amenity_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX amenity_line_geom_idx ON osm.amenity_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: amenity_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX amenity_point_geom_idx ON osm.amenity_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: amenity_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX amenity_polygon_geom_idx ON osm.amenity_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: building_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX building_point_geom_idx ON osm.building_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: building_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX building_polygon_geom_idx ON osm.building_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: gix_osm_vplace_polygon; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX gix_osm_vplace_polygon ON osm.vplace_polygon USING gist (geom);


--
-- Name: gix_osm_vplace_polygon_subdivide; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX gix_osm_vplace_polygon_subdivide ON osm.vplace_polygon_subdivide USING gist (geom);


--
-- Name: gix_osm_vpoi_all; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX gix_osm_vpoi_all ON osm.vpoi_all USING gist (geom);


--
-- Name: indoor_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX indoor_line_geom_idx ON osm.indoor_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: indoor_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX indoor_point_geom_idx ON osm.indoor_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: indoor_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX indoor_polygon_geom_idx ON osm.indoor_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: infrastructure_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX infrastructure_line_geom_idx ON osm.infrastructure_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: infrastructure_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX infrastructure_point_geom_idx ON osm.infrastructure_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: infrastructure_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX infrastructure_polygon_geom_idx ON osm.infrastructure_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: ix_osm_amenity_line_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_amenity_line_type ON osm.amenity_line USING btree (osm_type);


--
-- Name: ix_osm_amenity_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_amenity_point_type ON osm.amenity_point USING btree (osm_type);


--
-- Name: ix_osm_amenity_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_amenity_polygon_type ON osm.amenity_polygon USING btree (osm_type);


--
-- Name: ix_osm_building_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_building_polygon_type ON osm.building_polygon USING btree (osm_type);


--
-- Name: ix_osm_infrastructure_point_highway; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_infrastructure_point_highway ON osm.infrastructure_point USING btree (osm_type);


--
-- Name: ix_osm_landuse_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_landuse_point_type ON osm.landuse_point USING btree (osm_type);


--
-- Name: ix_osm_landuse_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_landuse_polygon_type ON osm.landuse_polygon USING btree (osm_type);


--
-- Name: ix_osm_leisure_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_leisure_point_type ON osm.leisure_point USING btree (osm_type);


--
-- Name: ix_osm_leisure_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_leisure_polygon_type ON osm.leisure_polygon USING btree (osm_type);


--
-- Name: ix_osm_natural_line_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_natural_line_type ON osm.natural_line USING btree (osm_type);


--
-- Name: ix_osm_natural_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_natural_point_type ON osm.natural_point USING btree (osm_type);


--
-- Name: ix_osm_natural_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_natural_polygon_type ON osm.natural_polygon USING btree (osm_type);


--
-- Name: ix_osm_place_line_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_place_line_type ON osm.place_line USING btree (osm_type);


--
-- Name: ix_osm_place_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_place_point_type ON osm.place_point USING btree (osm_type);


--
-- Name: ix_osm_place_polygon_nested_name_path; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_place_polygon_nested_name_path ON osm.place_polygon_nested USING gin (name_path);


--
-- Name: ix_osm_place_polygon_nested_osm_id; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_place_polygon_nested_osm_id ON osm.place_polygon_nested USING btree (osm_id);


--
-- Name: ix_osm_place_polygon_nested_osm_id_path; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_place_polygon_nested_osm_id_path ON osm.place_polygon_nested USING gin (osm_id_path);


--
-- Name: ix_osm_place_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_place_polygon_type ON osm.place_polygon USING btree (osm_type);


--
-- Name: ix_osm_poi_line_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_poi_line_type ON osm.poi_line USING btree (osm_type);


--
-- Name: ix_osm_poi_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_poi_point_type ON osm.poi_point USING btree (osm_type);


--
-- Name: ix_osm_poi_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_poi_polygon_type ON osm.poi_polygon USING btree (osm_type);


--
-- Name: ix_osm_public_transport_line_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_public_transport_line_type ON osm.public_transport_line USING btree (osm_type);


--
-- Name: ix_osm_public_transport_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_public_transport_point_type ON osm.public_transport_point USING btree (osm_type);


--
-- Name: ix_osm_public_transport_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_public_transport_polygon_type ON osm.public_transport_polygon USING btree (osm_type);


--
-- Name: ix_osm_road_line_highway; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_road_line_highway ON osm.road_line USING btree (osm_type);


--
-- Name: ix_osm_road_line_major; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_road_line_major ON osm.road_line USING btree (major) WHERE major;


--
-- Name: ix_osm_road_point_highway; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_road_point_highway ON osm.road_point USING btree (osm_type);


--
-- Name: ix_osm_shop_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_shop_point_type ON osm.shop_point USING btree (osm_subtype);


--
-- Name: ix_osm_shop_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_shop_polygon_type ON osm.shop_polygon USING btree (osm_subtype);


--
-- Name: ix_osm_traffic_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_traffic_point_type ON osm.traffic_point USING btree (osm_type);


--
-- Name: ix_osm_vpoi_all_osm_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_vpoi_all_osm_type ON osm.vpoi_all USING btree (osm_type);


--
-- Name: ix_osm_water_line_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_water_line_type ON osm.water_line USING btree (osm_subtype);


--
-- Name: ix_osm_water_point_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_water_point_type ON osm.water_point USING btree (osm_subtype);


--
-- Name: ix_osm_water_polygon_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX ix_osm_water_polygon_type ON osm.water_polygon USING btree (osm_subtype);


--
-- Name: landuse_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX landuse_point_geom_idx ON osm.landuse_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: landuse_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX landuse_polygon_geom_idx ON osm.landuse_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: leisure_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX leisure_point_geom_idx ON osm.leisure_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: leisure_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX leisure_polygon_geom_idx ON osm.leisure_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: natural_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX natural_line_geom_idx ON osm.natural_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: natural_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX natural_point_geom_idx ON osm.natural_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: natural_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX natural_polygon_geom_idx ON osm.natural_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: place_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX place_line_geom_idx ON osm.place_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: place_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX place_point_geom_idx ON osm.place_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: place_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX place_polygon_geom_idx ON osm.place_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: poi_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX poi_line_geom_idx ON osm.poi_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: poi_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX poi_point_geom_idx ON osm.poi_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: poi_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX poi_polygon_geom_idx ON osm.poi_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: public_transport_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX public_transport_line_geom_idx ON osm.public_transport_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: public_transport_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX public_transport_point_geom_idx ON osm.public_transport_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: public_transport_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX public_transport_polygon_geom_idx ON osm.public_transport_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: road_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX road_line_geom_idx ON osm.road_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: road_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX road_point_geom_idx ON osm.road_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: road_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX road_polygon_geom_idx ON osm.road_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: shop_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX shop_point_geom_idx ON osm.shop_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: shop_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX shop_polygon_geom_idx ON osm.shop_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: traffic_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX traffic_line_geom_idx ON osm.traffic_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: traffic_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX traffic_point_geom_idx ON osm.traffic_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: traffic_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX traffic_polygon_geom_idx ON osm.traffic_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: uix_osm_vplace_polygon_osm_id; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE UNIQUE INDEX uix_osm_vplace_polygon_osm_id ON osm.vplace_polygon USING btree (osm_id);


--
-- Name: uix_osm_vpoi_all_osm_id_geom_type; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE UNIQUE INDEX uix_osm_vpoi_all_osm_id_geom_type ON osm.vpoi_all USING btree (osm_id, geom_type);


--
-- Name: water_line_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX water_line_geom_idx ON osm.water_line USING gist (geom) WITH (fillfactor='100');


--
-- Name: water_point_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX water_point_geom_idx ON osm.water_point USING gist (geom) WITH (fillfactor='100');


--
-- Name: water_polygon_geom_idx; Type: INDEX; Schema: osm; Owner: postgres
--

CREATE INDEX water_polygon_geom_idx ON osm.water_polygon USING gist (geom) WITH (fillfactor='100');


--
-- Name: place_polygon_nested fk_place_polygon_nested; Type: FK CONSTRAINT; Schema: osm; Owner: postgres
--

ALTER TABLE ONLY osm.place_polygon_nested
    ADD CONSTRAINT fk_place_polygon_nested FOREIGN KEY (osm_id) REFERENCES osm.place_polygon(osm_id);


--
-- Name: vplace_polygon; Type: MATERIALIZED VIEW DATA; Schema: osm; Owner: postgres
--

REFRESH MATERIALIZED VIEW osm.vplace_polygon;


--
-- Name: vplace_polygon_subdivide; Type: MATERIALIZED VIEW DATA; Schema: osm; Owner: postgres
--

REFRESH MATERIALIZED VIEW osm.vplace_polygon_subdivide;


--
-- Name: vpoi_all; Type: MATERIALIZED VIEW DATA; Schema: osm; Owner: postgres
--

REFRESH MATERIALIZED VIEW osm.vpoi_all;


--
-- PostgreSQL database dump complete
--

