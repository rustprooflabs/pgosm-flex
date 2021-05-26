SELECT osm_type COLLATE "C", COUNT(*)
    FROM osm.indoor_point
    GROUP BY osm_type COLLATE "C"
    ORDER BY osm_type COLLATE "C"
;