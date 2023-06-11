CREATE PRIMARY KEY pk_osm_poi_combined_point_osm_id_geom_type
    ON osm.poi_combined_point (osm_id, geom_type);
CREATE INDEX gix_osm_poi_combined_point
    ON osm.poi_combined_point USING GIST (geom);

CREATE INDEX ix_osm_poi_combined_point_osm_type ON osm.poi_combined_point (osm_type);



COMMENT ON TABLE osm.poi_combined_point IS 'Combined POI data as points. Lines and polygons converted to point in osm2pgsql with centroid().';

COMMENT ON COLUMN osm.poi_combined_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';
COMMENT ON COLUMN osm.poi_combined_point.address IS 'Address combined from address parts in helpers.get_address(). See base tables for individual address parts';
COMMENT ON COLUMN osm.poi_combined_point.geom_type IS 'Indicates source table, N (point) L (line) W (polygon).  Using L for line differs from how osm2pgsql classifies lines ("W") in order to provide a direct link to which table the data comes from.';
COMMENT ON COLUMN osm.poi_combined_point.osm_subtype IS 'Value detail describing the key (osm_type).';

