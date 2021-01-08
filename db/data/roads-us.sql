-- Road lookup details for generic default-
-- Region:  United States
INSERT INTO pgosm.road (region, osm_type, route_motor, route_foot, route_cycle, maxspeed)
    VALUES ('United States', 'motorway', True, False, False, 104.60736),
        ('United States', 'motorway_link', True, False, False, 104.60736),
        ('United States', 'trunk', True, False, True, 96.56064),
        ('United States', 'trunk_link', True, False, True, 96.56064),
        ('United States', 'primary', True, False, True, 96.56064),
        ('United States', 'primary_link', True, False, True, 96.56064),
        ('United States', 'secondary', True, False, True, 72.42048),
        ('United States', 'secondary_link', True, False, True, 72.42048),
        ('United States', 'tertiary', True, False, True, 72.42048),
        ('United States', 'tertiary_link', True, False, True, 72.42048),
        ('United States', 'residential', True, True, True, 40.2336),
        ('United States', 'service', True, True, True, 40.2336),
        ('United States', 'unclassified', True, True, True, 30),
        ('United States', 'proposed', False, False, False, -1),
        ('United States', 'planned', False, False, False, -1),
        ('United States', 'path', False, True, True, 4),
        ('United States', 'footway', False, True, False, 4),
        ('United States', 'track', False, True, True, 2),
        ('United States', 'pedestrian', False, True, False, 4),
        ('United States', 'cycleway', False, True, True, 32),
        ('United States', 'crossing', False, True, True, 2),
        ('United States', 'platform', False, True, False, 2),
        ('United States', 'social_path', False, True, False, 3),
        ('United States', 'steps', False, True, False, 2),
        ('United States', 'trailhead', False, True, True, 3)
;
