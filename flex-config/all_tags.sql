COMMENT ON TABLE osm.tags IS 'OpenStreetMap tag data for all OpenStreetMap objects.  tags column in JSONB.';

ALTER TABLE osm.tags
    ADD CONSTRAINT pk_osm_tags_osm_id
    PRIMARY KEY (osm_id)
;
