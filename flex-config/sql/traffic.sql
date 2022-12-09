COMMENT ON TABLE osm.traffic_point IS 'OpenStreetMap traffic related points.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';
COMMENT ON TABLE osm.traffic_line IS 'OpenStreetMap traffic related lines.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';
COMMENT ON TABLE osm.traffic_polygon IS 'OpenStreetMap traffic related polygons.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';

COMMENT ON COLUMN osm.traffic_point.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';
COMMENT ON COLUMN osm.traffic_line.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';
COMMENT ON COLUMN osm.traffic_polygon.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';

COMMENT ON COLUMN osm.traffic_point.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';
COMMENT ON COLUMN osm.traffic_line.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';
COMMENT ON COLUMN osm.traffic_polygon.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway".';


ALTER TABLE osm.traffic_point
    ADD CONSTRAINT pk_osm_traffic_point_osm_id
    PRIMARY KEY (osm_id)
;


COMMENT ON COLUMN osm.traffic_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.traffic_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.traffic_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';

COMMENT ON COLUMN osm.traffic_point.geom IS 'Geometry loaded by osm2pgsql.';
COMMENT ON COLUMN osm.traffic_line.geom IS 'Geometry loaded by osm2pgsql.';
COMMENT ON COLUMN osm.traffic_polygon.geom IS 'Geometry loaded by osm2pgsql.';
