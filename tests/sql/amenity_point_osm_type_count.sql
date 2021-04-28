SELECT osm_type COLLATE "C", COUNT(*)
    FROM osm.amenity_point
    GROUP BY osm_type COLLATE "C"
    ORDER BY osm_type COLLATE "C"
;