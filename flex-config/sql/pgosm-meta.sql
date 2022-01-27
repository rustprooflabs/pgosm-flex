COMMENT ON SCHEMA osm IS 'Schema populated by PgOSM-Flex.  SELECT * FROM osm.pgosm_flex; for details.';
COMMENT ON TABLE osm.pgosm_flex IS 'Provides meta information on the PgOSM-Flex project including version and SRID used during the import. One row per import.';

COMMENT ON COLUMN osm.pgosm_flex.imported IS 'Indicates when the import was ran.';
COMMENT ON COLUMN osm.pgosm_flex.osm_date IS 'Indicates the date of the OpenStreetMap data loaded.  Recommended to set PGOSM_DATE env var at runtime, otherwise defaults to the date PgOSM-Flex was run.';
COMMENT ON COLUMN osm.pgosm_flex.default_date IS 'If true, the value in osm_date represents the date PgOSM-Flex was ran.  If False, the date was set via env var and should indicate the date the OpenStreetMap data is from.';
COMMENT ON COLUMN osm.pgosm_flex.project_url IS 'PgOSM-Flex project URL.';
COMMENT ON COLUMN osm.pgosm_flex.srid IS 'SRID of imported data.';
COMMENT ON COLUMN osm.pgosm_flex.pgosm_flex_version IS 'Version of PgOSM-Flex used to generate schema.';
COMMENT ON COLUMN osm.pgosm_flex.osm2pgsql_version IS 'Version of osm2pgsql used to load data.';
COMMENT ON COLUMN osm.pgosm_flex.region IS 'Region specified at run time via env var PGOSM_REGION.';
COMMENT ON COLUMN osm.pgosm_flex.language IS 'Preferred language specified at run time via env var PGOSM_LANGUAGE.  Empty string when not defined.';
COMMENT ON COLUMN osm.pgosm_flex.osm2pgsql_mode IS 'Indicates which osm2pgsql mode was used, create or append.';



-- Helper Procedures for allowing updates via osm2pgsql-replication or similar


CREATE OR REPLACE PROCEDURE osm.append_data_start()
 LANGUAGE plpgsql
 AS $$

 BEGIN

    RAISE NOTICE 'Truncating table osm.place_polygon_nested;';
    TRUNCATE TABLE osm.place_polygon_nested;

END $$;




CREATE OR REPLACE PROCEDURE osm.append_data_finish(skip_nested BOOLEAN = False)
 LANGUAGE plpgsql
 AS $$
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


END $$;

