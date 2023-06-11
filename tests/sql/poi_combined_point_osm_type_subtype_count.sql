SELECT osm_type COLLATE "C", osm_subtype COLLATE "C", COUNT(*)
    FROM osm.poi_combined_point
    GROUP BY osm_type COLLATE "C", osm_subtype COLLATE "C"
    ORDER BY osm_type COLLATE "C", osm_subtype COLLATE "C"
;