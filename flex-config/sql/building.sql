COMMENT ON TABLE osm.building_polygon IS 'OpenStreetMap building polygons - all polygons with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';
COMMENT ON TABLE osm.building_point IS 'OpenStreetMap building points - all points with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';

COMMENT ON COLUMN osm.building_polygon.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';
COMMENT ON COLUMN osm.building_point.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';

COMMENT ON COLUMN osm.building_polygon.levels IS 'Number (#) of levels in the building.';
COMMENT ON COLUMN osm.building_point.levels IS 'Number (#) of levels in the building.';
COMMENT ON COLUMN osm.building_polygon.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';
COMMENT ON COLUMN osm.building_point.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';

COMMENT ON COLUMN osm.building_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';
COMMENT ON COLUMN osm.building_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';

COMMENT ON COLUMN osm.building_point.housenumber IS 'Value from addr:housenumber tag';
COMMENT ON COLUMN osm.building_point.street IS 'Value from addr:street tag';
COMMENT ON COLUMN osm.building_point.city IS 'Value from addr:city tag';
COMMENT ON COLUMN osm.building_point.state IS 'Value from addr:state tag';
COMMENT ON COLUMN osm.building_point.postcode IS 'Value from addr:postcode tag';

COMMENT ON COLUMN osm.building_polygon.housenumber IS 'Value from addr:housenumber tag';
COMMENT ON COLUMN osm.building_polygon.street IS 'Value from addr:street tag';
COMMENT ON COLUMN osm.building_polygon.city IS 'Value from addr:city tag';
COMMENT ON COLUMN osm.building_polygon.state IS 'Value from addr:state tag';
COMMENT ON COLUMN osm.building_polygon.postcode IS 'Value from addr:postcode tag';

COMMENT ON COLUMN osm.building_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';
COMMENT ON COLUMN osm.building_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';

COMMENT ON COLUMN osm.building_point.geom IS 'Geometry loaded by osm2pgsql.';
COMMENT ON COLUMN osm.building_polygon.geom IS 'Geometry loaded by osm2pgsql.';

COMMENT ON COLUMN osm.building_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';
COMMENT ON COLUMN osm.building_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';



COMMENT ON COLUMN osm.building_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.building_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';

COMMENT ON COLUMN osm.building_point.address IS 'Address combined from address parts in helpers.get_address().';
COMMENT ON COLUMN osm.building_polygon.address IS 'Address combined from address parts in helpers.get_address().';


COMMENT ON COLUMN osm.building_point.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building_helpers.lua';
COMMENT ON COLUMN osm.building_polygon.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building_helpers.lua';

COMMENT ON COLUMN osm.building_point.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';
COMMENT ON COLUMN osm.building_polygon.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';
