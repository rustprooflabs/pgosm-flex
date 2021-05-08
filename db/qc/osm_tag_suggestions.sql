

SELECT geom_type, osm_id,
        'Update to: amenity=bicycle_parking per https://wiki.openstreetmap.org/wiki/Key:bicycle_parking'::TEXT
            AS suggestion,
        osm_url, tags
    FROM osm.tags
    WHERE tags->>'bicycle_parking' IS NOT NULL
        AND tags->>'amenity' IS NULL
UNION
SELECT t.geom_type, t.osm_id,
        'Invald bench value. Valid values for `bench` are "yes" and "no" per https://wiki.openstreetmap.org/wiki/Key:bench'::TEXT
            AS suggestion,
        t.osm_url, t.tags
    FROM osm.tags t
    WHERE t.tags->>'amenity' IS NULL
        AND t.tags->>'bench' IS NOT NULL
        AND t.tags->>'bench' NOT IN ('yes', 'no')
UNION
SELECT t.geom_type, t.osm_id,
        'Invald wheelchair value. Valid values for `wheelchar` are "yes", "no" and "limited" per https://wiki.openstreetmap.org/wiki/Key:wheelchair'::TEXT
            AS suggestion,
        t.osm_url, t.tags
    FROM osm.tags t
    WHERE tags->>'wheelchair' IS NOT NULL
        AND tags->>'wheelchair' NOT IN ('yes', 'no', 'limited')
;

