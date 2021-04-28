SELECT osm_type, COUNT(*)
    FROM osm.amenity_point
    GROUP BY osm_type
    ORDER BY osm_type
;