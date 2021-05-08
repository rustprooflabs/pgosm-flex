SELECT osm_type COLLATE "C", COUNT(*)
    FROM osm.indoor_polygon
    GROUP BY osm_type COLLATE "C"
    ORDER BY osm_type COLLATE "C"
;