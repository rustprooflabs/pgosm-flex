/*
    This script is intended to guide human efforts in cleaning up and improving
    data in OpenStreetMap.

    WARNING: If you plan on making bulk edits, be sure to follow the "Automated edits"
    guidelines: https://wiki.openstreetmap.org/wiki/Automated_edits

    This should only be used as a guide for humans with further review and discussion in the process.
*/
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
UNION
SELECT t.geom_type, t.osm_id,
        'Invalid shop value.  Consider amenity=cafe for a sit-down coffee shop, or shop=coffee for places without seating.  See https://wiki.openstreetmap.org/wiki/Tag:shop%3Dcoffee.'::TEXT
            AS suggestion,
        t.osm_url, t.tags
    FROM osm.tags  t
    WHERE t.tags->>'shop' = 'cafe'
UNION
SELECT t.geom_type, t.osm_id,
        'Invalid natural value.  Consider highway=street_lamp.  If a light is attached to a tree, consider adding support=tree as well. https://wiki.openstreetmap.org/wiki/Tag:highway%3Dstreet_lamp'::TEXT
            AS suggestion,
        t.osm_url, t.tags
    FROM osm.tags  t
    WHERE t.tags->>'natural' = 'street_lamp'
;
