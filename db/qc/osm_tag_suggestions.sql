

SELECT geom_type, osm_id,
        'Update to: amenity=bicycle_parking per https://wiki.openstreetmap.org/wiki/Key:bicycle_parking'::TEXT AS suggestion,
        osm_url, tags
    FROM osm.tags
    WHERE tags->>'bicycle_parking' IS NOT NULL
        AND tags->>'amenity' IS NULL
;

