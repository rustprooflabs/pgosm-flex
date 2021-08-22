COMMENT ON TABLE osm.public_transport_point IS 'OpenStreetMap public transport points - all points with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';
COMMENT ON TABLE osm.public_transport_line IS 'OpenStreetMap public transport lines - all lines with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';
COMMENT ON TABLE osm.public_transport_polygon IS 'OpenStreetMap public transport polygons - all polygons with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


ALTER TABLE osm.public_transport_point
    ADD CONSTRAINT pk_osm_public_transport_point_osm_id
    PRIMARY KEY (osm_id)
;
ALTER TABLE osm.public_transport_line
    ADD CONSTRAINT pk_osm_public_transport_line_osm_id
    PRIMARY KEY (osm_id)
;
ALTER TABLE osm.public_transport_polygon
    ADD CONSTRAINT pk_osm_public_transport_polygon_osm_id
    PRIMARY KEY (osm_id)
;


CREATE INDEX ix_osm_public_transport_point_type ON osm.public_transport_point (osm_type);
CREATE INDEX ix_osm_public_transport_line_type ON osm.public_transport_line (osm_type);
CREATE INDEX ix_osm_public_transport_polygon_type ON osm.public_transport_polygon (osm_type);


COMMENT ON COLUMN osm.public_transport_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.public_transport_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.public_transport_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';

COMMENT ON COLUMN osm.public_transport_point.geom IS 'Geometry loaded by osm2pgsql.';
COMMENT ON COLUMN osm.public_transport_line.geom IS 'Geometry loaded by osm2pgsql.';
COMMENT ON COLUMN osm.public_transport_polygon.geom IS 'Geometry loaded by osm2pgsql.';

COMMENT ON COLUMN osm.public_transport_point.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';
COMMENT ON COLUMN osm.public_transport_line.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';
COMMENT ON COLUMN osm.public_transport_polygon.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';

COMMENT ON COLUMN osm.public_transport_point.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';
COMMENT ON COLUMN osm.public_transport_line.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';
COMMENT ON COLUMN osm.public_transport_polygon.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';

COMMENT ON COLUMN osm.public_transport_point.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';
COMMENT ON COLUMN osm.public_transport_line.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';
COMMENT ON COLUMN osm.public_transport_polygon.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';

COMMENT ON COLUMN osm.public_transport_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';
COMMENT ON COLUMN osm.public_transport_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';
COMMENT ON COLUMN osm.public_transport_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';

COMMENT ON COLUMN osm.public_transport_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';
COMMENT ON COLUMN osm.public_transport_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';
COMMENT ON COLUMN osm.public_transport_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';

COMMENT ON COLUMN osm.public_transport_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';
COMMENT ON COLUMN osm.public_transport_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';
COMMENT ON COLUMN osm.public_transport_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';

COMMENT ON COLUMN osm.public_transport_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';
COMMENT ON COLUMN osm.public_transport_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';
COMMENT ON COLUMN osm.public_transport_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';

COMMENT ON COLUMN osm.public_transport_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';
COMMENT ON COLUMN osm.public_transport_line.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';
COMMENT ON COLUMN osm.public_transport_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';

COMMENT ON COLUMN osm.public_transport_point.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';
COMMENT ON COLUMN osm.public_transport_line.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';
COMMENT ON COLUMN osm.public_transport_polygon.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';

