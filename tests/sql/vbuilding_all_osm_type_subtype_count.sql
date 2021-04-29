SELECT osm_type COLLATE "C", osm_subtype COLLATE "C", COUNT(*)
    FROM osm.vbuilding_all
    GROUP BY osm_type COLLATE "C", osm_subtype COLLATE "C"
    ORDER BY osm_type COLLATE "C", osm_subtype COLLATE "C"
;