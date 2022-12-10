ALTER TABLE osm.public_transport_line ADD COLUMN member_ids JSONB;
ALTER TABLE osm.public_transport_polygon ADD COLUMN member_ids JSONB;
ALTER TABLE osm.road_line ADD COLUMN member_ids JSONB;
ALTER TABLE osm.road_polygon ADD COLUMN member_ids JSONB;
ALTER TABLE osm.water_line ADD COLUMN member_ids JSONB;
ALTER TABLE osm.water_polygon ADD COLUMN member_ids JSONB;

DROP VIEW osm.places_in_relations CASCADE;