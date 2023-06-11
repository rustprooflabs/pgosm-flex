
COMMENT ON TABLE osm.shop_combined_point IS 'Combines point and polygon shops as points.  Polygons are converted to point in osm2pgsql with centroid().';

COMMENT ON COLUMN osm.shop_combined_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';
COMMENT ON COLUMN osm.shop_combined_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';
COMMENT ON COLUMN osm.shop_combined_point.osm_subtype IS 'Value detail describing the key (osm_type).';
COMMENT ON COLUMN osm.shop_combined_point.address IS 'Address combined from address parts in helpers.get_address().';
COMMENT ON COLUMN osm.shop_combined_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';
COMMENT ON COLUMN osm.shop_combined_point.geom IS 'Geometry, mix of points loaded by osm2pgsql and points calculated from the ST_Centroid() of the polygons loaded by osm2pgsql.';

COMMENT ON COLUMN osm.shop_combined_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';
COMMENT ON COLUMN osm.shop_combined_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';
COMMENT ON COLUMN osm.shop_combined_point.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';
COMMENT ON COLUMN osm.shop_combined_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';
COMMENT ON COLUMN osm.shop_combined_point.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';
COMMENT ON COLUMN osm.shop_combined_point.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';
COMMENT ON COLUMN osm.shop_combined_point.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';

COMMENT ON COLUMN osm.shop_combined_point.housenumber IS 'Value from addr:housenumber tag';
COMMENT ON COLUMN osm.shop_combined_point.street IS 'Value from addr:street tag';
COMMENT ON COLUMN osm.shop_combined_point.city IS 'Value from addr:city tag';
COMMENT ON COLUMN osm.shop_combined_point.state IS 'Value from addr:state tag';
COMMENT ON COLUMN osm.shop_combined_point.postcode IS 'Value from addr:postcode tag';

ALTER TABLE osm.shop_combined_point
    ADD CONSTRAINT pk_osm_shop_point_osm_id_geom_type
    PRIMARY KEY (osm_id, geom_type)
;
