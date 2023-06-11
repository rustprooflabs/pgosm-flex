SELECT osm_type COLLATE "C", osm_subtype COLLATE "C", COUNT(*)
    FROM osm.poi_line
    GROUP BY osm_type COLLATE "C", osm_subtype COLLATE "C"
    ORDER BY osm_type COLLATE "C", osm_subtype COLLATE "C"
;