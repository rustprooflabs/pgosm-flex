
---------------------------------------------
-- Drop indexes previously created
--
-- Uses IF EXISTS to avoid failure with different layersets
DROP INDEX IF EXISTS osm.ix_osm_amenity_point_type;
DROP INDEX IF EXISTS osm.ix_osm_amenity_line_type;
DROP INDEX IF EXISTS osm.ix_osm_amenity_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_building_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_infrastructure_point_highway;
DROP INDEX IF EXISTS osm.ix_osm_landuse_point_type;
DROP INDEX IF EXISTS osm.ix_osm_landuse_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_leisure_point_type;
DROP INDEX IF EXISTS osm.ix_osm_leisure_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_natural_point_type;
DROP INDEX IF EXISTS osm.ix_osm_natural_line_type;
DROP INDEX IF EXISTS osm.ix_osm_natural_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_place_point_type;
DROP INDEX IF EXISTS osm.ix_osm_place_line_type;
DROP INDEX IF EXISTS osm.ix_osm_place_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_poi_point_type;
DROP INDEX IF EXISTS osm.ix_osm_poi_line_type;
DROP INDEX IF EXISTS osm.ix_osm_poi_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_public_transport_point_type;
DROP INDEX IF EXISTS osm.ix_osm_public_transport_line_type;
DROP INDEX IF EXISTS osm.ix_osm_public_transport_polygon_type;
DROP INDEX IF EXISTS osm.ix_osm_road_point_highway;
DROP INDEX IF EXISTS osm.ix_osm_road_line_highway;
DROP INDEX IF EXISTS osm.ix_osm_road_line_major;
DROP INDEX IF EXISTS osm.ix_osm_traffic_point_type;
DROP INDEX IF EXISTS osm.ix_osm_water_point_type;
DROP INDEX IF EXISTS osm.ix_osm_water_line_type;
DROP INDEX IF EXISTS osm.ix_osm_water_polygon_type;


---------------------------------------------
-- Create newly named indexes
--
-- MANUAL CLEANUP REQUIRED
-- If you are using a layerset other than the built-in default, you will need
-- to adjust the create index commands to suit your layerset.

CREATE INDEX amenity_line_osm_subtype_idx ON osm.amenity_line USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX amenity_line_osm_type_idx ON osm.amenity_line USING btree (osm_type);
CREATE INDEX amenity_point_osm_subtype_idx ON osm.amenity_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX amenity_point_osm_type_idx ON osm.amenity_point USING btree (osm_type);
CREATE INDEX amenity_polygon_osm_subtype_idx ON osm.amenity_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX amenity_polygon_osm_type_idx ON osm.amenity_polygon USING btree (osm_type);
CREATE INDEX building_point_osm_subtype_idx ON osm.building_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX building_point_osm_type_idx ON osm.building_point USING btree (osm_type);
CREATE INDEX building_polygon_osm_subtype_idx ON osm.building_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX indoor_line_osm_type_idx ON osm.indoor_line USING btree (osm_type);
CREATE INDEX indoor_point_osm_type_idx ON osm.indoor_point USING btree (osm_type);
CREATE INDEX indoor_polygon_osm_type_idx ON osm.indoor_polygon USING btree (osm_type);
CREATE INDEX infrastructure_line_osm_subtype_idx ON osm.infrastructure_line USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX infrastructure_line_osm_type_idx ON osm.infrastructure_line USING btree (osm_type);
CREATE INDEX infrastructure_point_osm_subtype_idx ON osm.infrastructure_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX infrastructure_point_osm_type_idx ON osm.infrastructure_point USING btree (osm_type);
CREATE INDEX infrastructure_polygon_osm_subtype_idx ON osm.infrastructure_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX infrastructure_polygon_osm_type_idx ON osm.infrastructure_polygon USING btree (osm_type);
CREATE INDEX landuse_point_osm_type_idx ON osm.landuse_point USING btree (osm_type);
CREATE INDEX landuse_polygon_osm_type_idx ON osm.landuse_polygon USING btree (osm_type);
CREATE INDEX leisure_point_osm_type_idx ON osm.leisure_point USING btree (osm_type);
CREATE INDEX leisure_polygon_osm_type_idx ON osm.leisure_polygon USING btree (osm_type);
CREATE INDEX natural_line_osm_type_idx ON osm.natural_line USING btree (osm_type);
CREATE INDEX natural_point_osm_type_idx ON osm.natural_point USING btree (osm_type);
CREATE INDEX natural_polygon_osm_type_idx ON osm.natural_polygon USING btree (osm_type);
CREATE INDEX place_line_admin_level_idx ON osm.place_line USING btree (admin_level) WHERE (admin_level IS NOT NULL);
CREATE INDEX place_line_boundary_idx ON osm.place_line USING btree (boundary) WHERE (boundary IS NOT NULL);
CREATE INDEX place_line_name_idx ON osm.place_line USING btree (name) WHERE (name IS NOT NULL);
CREATE INDEX place_line_osm_type_idx ON osm.place_line USING btree (osm_type);
CREATE INDEX place_point_admin_level_idx ON osm.place_point USING btree (admin_level) WHERE (admin_level IS NOT NULL);
CREATE INDEX place_point_boundary_idx ON osm.place_point USING btree (boundary) WHERE (boundary IS NOT NULL);
CREATE INDEX place_point_name_idx ON osm.place_point USING btree (name) WHERE (name IS NOT NULL);
CREATE INDEX place_point_osm_type_idx ON osm.place_point USING btree (osm_type);
CREATE INDEX place_polygon_admin_level_idx ON osm.place_polygon USING btree (admin_level) WHERE (admin_level IS NOT NULL);
CREATE INDEX place_polygon_boundary_idx ON osm.place_polygon USING btree (boundary) WHERE (boundary IS NOT NULL);
CREATE INDEX place_polygon_name_idx ON osm.place_polygon USING btree (name) WHERE (name IS NOT NULL);
CREATE INDEX place_polygon_osm_type_idx ON osm.place_polygon USING btree (osm_type);
CREATE INDEX poi_line_osm_subtype_idx ON osm.poi_line USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX poi_line_osm_type_idx ON osm.poi_line USING btree (osm_type);
CREATE INDEX poi_point_osm_subtype_idx ON osm.poi_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX poi_point_osm_type_idx ON osm.poi_point USING btree (osm_type);
CREATE INDEX poi_polygon_osm_subtype_idx ON osm.poi_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX poi_polygon_osm_type_idx ON osm.poi_polygon USING btree (osm_type);
CREATE INDEX public_transport_line_osm_subtype_idx ON osm.public_transport_line USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX public_transport_line_osm_type_idx ON osm.public_transport_line USING btree (osm_type);
CREATE INDEX public_transport_point_osm_subtype_idx ON osm.public_transport_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX public_transport_point_osm_type_idx ON osm.public_transport_point USING btree (osm_type);
CREATE INDEX public_transport_polygon_osm_subtype_idx ON osm.public_transport_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX public_transport_polygon_osm_type_idx ON osm.public_transport_polygon USING btree (osm_type);
CREATE INDEX road_line_major_idx ON osm.road_line USING btree (major) WHERE major;
CREATE INDEX road_line_osm_type_idx ON osm.road_line USING btree (osm_type);
CREATE INDEX road_line_ref_idx ON osm.road_line USING btree (ref);
CREATE INDEX road_major_osm_type_idx ON osm.road_major USING btree (osm_type);
CREATE INDEX road_major_ref_idx ON osm.road_major USING btree (ref);
CREATE INDEX road_point_osm_type_idx ON osm.road_point USING btree (osm_type);
CREATE INDEX road_point_ref_idx ON osm.road_point USING btree (ref);
CREATE INDEX road_polygon_major_idx ON osm.road_polygon USING btree (major) WHERE major;
CREATE INDEX road_polygon_osm_type_idx ON osm.road_polygon USING btree (osm_type);
CREATE INDEX road_polygon_ref_idx ON osm.road_polygon USING btree (ref);
CREATE INDEX shop_point_osm_subtype_idx ON osm.shop_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX shop_point_osm_type_idx ON osm.shop_point USING btree (osm_type);
CREATE INDEX shop_polygon_osm_subtype_idx ON osm.shop_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX shop_polygon_osm_type_idx ON osm.shop_polygon USING btree (osm_type);
CREATE INDEX traffic_line_osm_subtype_idx ON osm.traffic_line USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX traffic_line_osm_type_idx ON osm.traffic_line USING btree (osm_type);
CREATE INDEX traffic_point_osm_subtype_idx ON osm.traffic_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX traffic_point_osm_type_idx ON osm.traffic_point USING btree (osm_type);
CREATE INDEX traffic_polygon_osm_subtype_idx ON osm.traffic_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX traffic_polygon_osm_type_idx ON osm.traffic_polygon USING btree (osm_type);
CREATE INDEX water_line_osm_subtype_idx ON osm.water_line USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX water_line_osm_type_idx ON osm.water_line USING btree (osm_type);
CREATE INDEX water_point_osm_subtype_idx ON osm.water_point USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX water_point_osm_type_idx ON osm.water_point USING btree (osm_type);
CREATE INDEX water_polygon_osm_subtype_idx ON osm.water_polygon USING btree (osm_subtype) WHERE (osm_subtype IS NOT NULL);
CREATE INDEX water_polygon_osm_type_idx ON osm.water_polygon USING btree (osm_type);
