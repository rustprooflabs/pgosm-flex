COMMENT ON TABLE osm.road_major IS 'OpenStreetMap roads - Major only. Classification handled by helpers.major_road(). Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road_major.lua';
COMMENT ON COLUMN osm.road_major.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, etc.';
COMMENT ON COLUMN osm.road_major.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/kr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


ALTER TABLE osm.road_major
	ADD CONSTRAINT pk_osm_road_major_osm_id
    PRIMARY KEY (osm_id)
;

CREATE INDEX ix_osm_road_major_type ON osm.road_major (osm_type);
