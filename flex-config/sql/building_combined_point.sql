

COMMENT ON TABLE osm.building_combined_point IS 'Combined building data as points.  Building polygons are converted in osm2pgsql to points with centroid().';
COMMENT ON COLUMN osm.building_combined_point.address IS 'Address combined from address parts in helpers.get_address().';

COMMENT ON COLUMN osm.building_combined_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.building_combined_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';
COMMENT ON COLUMN osm.building_combined_point.levels IS 'Number (#) of levels in the building.';
COMMENT ON COLUMN osm.building_combined_point.height IS 'Object height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';
COMMENT ON COLUMN osm.building_combined_point.wheelchair IS 'Indicates if building is wheelchair accessible.';
COMMENT ON COLUMN osm.building_combined_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';
COMMENT ON COLUMN osm.building_combined_point.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';
COMMENT ON COLUMN osm.building_combined_point.geom IS 'Geometry loaded by osm2pgsql.';
COMMENT ON COLUMN osm.building_combined_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';

COMMENT ON COLUMN osm.building_combined_point.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building.lua';
COMMENT ON COLUMN osm.building_combined_point.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';

COMMENT ON COLUMN osm.building_point.housenumber IS 'Value from addr:housenumber tag';
COMMENT ON COLUMN osm.building_point.street IS 'Value from addr:street tag';
COMMENT ON COLUMN osm.building_point.city IS 'Value from addr:city tag';
COMMENT ON COLUMN osm.building_point.state IS 'Value from addr:state tag';
COMMENT ON COLUMN osm.building_point.postcode IS 'Value from addr:postcode tag';
