-- Road lookup details for generic default-
-- Region:  United States
INSERT INTO pgosm.road (
            region, osm_type, route_motor, route_foot, route_cycle, maxspeed
            , traffic_penalty_normal
        )
    VALUES ('United States', 'motorway', True, False, False, 104.60736, 0.75),
        ('United States', 'motorway_link', True, False, False, 104.60736, 0.72),
        ('United States', 'trunk', True, False, True, 96.56064, 0.75),
        ('United States', 'trunk_link', True, False, True, 96.56064, 0.72),
        ('United States', 'primary', True, False, True, 96.56064, 0.6),
        ('United States', 'primary_link', True, False, True, 96.56064, 0.6),
        ('United States', 'secondary', True, False, True, 72.42048, 0.6),
        ('United States', 'secondary_link', True, False, True, 72.42048, 0.6),
        ('United States', 'tertiary', True, False, True, 72.42048, 0.6),
        ('United States', 'tertiary_link', True, False, True, 72.42048, 0.6),
        ('United States', 'residential', True, True, True, 40.2336, 0.95),
        ('United States', 'service', True, True, True, 40.2336, 0.95),
        ('United States', 'unclassified', True, True, True, 30, 0.95),
        ('United States', 'proposed', False, False, False, -1, 1.0),
        ('United States', 'planned', False, False, False, -1, 1.0),
        ('United States', 'path', False, True, True, 4, 1.0),
        ('United States', 'footway', False, True, False, 4, 1.0),
        ('United States', 'track', False, True, True, 2, 1.0),
        ('United States', 'pedestrian', False, True, False, 4, 1.0),
        ('United States', 'cycleway', False, True, True, 32, 0.95),
        ('United States', 'crossing', False, True, True, 2, 0.3),
        ('United States', 'platform', False, True, False, 2, 0.3),
        ('United States', 'social_path', False, True, False, 3, 0.7),
        ('United States', 'steps', False, True, False, 2, 0.9),
        ('United States', 'trailhead', False, True, True, 3, 0.9)
    -- Doing nothing allows users to safely customize this table
    ON CONFLICT (region, osm_type) DO UPDATE
    SET maxspeed = EXCLUDED.maxspeed
        , traffic_penalty_normal = EXCLUDED.traffic_penalty_normal
;
