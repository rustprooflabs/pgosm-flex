COMMENT ON TABLE osm.tags IS 'OpenStreetMap tag data for all objects in source file.  Key/value data stored in tags column in JSONB format.';

ALTER TABLE osm.tags
    ADD CONSTRAINT pk_osm_tags_osm_id_type
    PRIMARY KEY (osm_id, geom_type)
;
