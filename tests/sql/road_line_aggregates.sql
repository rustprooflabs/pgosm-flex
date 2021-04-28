SELECT COUNT(*),
        COUNT(*) FILTER (WHERE maxspeed IS NOT NULL),
        COUNT(*) FILTER (WHERE major),
        COUNT(*) FILTER (WHERE route_foot),
        COUNT(*) FILTER (WHERE route_cycle),
        COUNT(*) FILTER (WHERE route_motor)
    FROM osm.road_line
;
