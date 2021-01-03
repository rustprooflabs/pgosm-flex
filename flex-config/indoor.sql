COMMENT ON TABLE osm.indoor_point IS 'OpenStreetMap indoor related points. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';
COMMENT ON TABLE osm.indoor_line IS 'OpenStreetMap indoor related lines. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';
COMMENT ON TABLE osm.indoor_polygon IS 'OpenStreetMap indoor related polygons. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';

COMMENT ON COLUMN osm.indoor_point.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';
COMMENT ON COLUMN osm.indoor_line.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';
COMMENT ON COLUMN osm.indoor_polygon.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';

COMMENT ON COLUMN osm.indoor_point.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';
COMMENT ON COLUMN osm.indoor_line.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';
COMMENT ON COLUMN osm.indoor_polygon.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';

COMMENT ON COLUMN osm.indoor_point.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_line.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_polygon.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';

COMMENT ON COLUMN osm.indoor_point.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_line.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_polygon.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';

COMMENT ON COLUMN osm.indoor_point.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_line.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_polygon.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';

COMMENT ON COLUMN osm.indoor_point.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_line.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_polygon.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';

COMMENT ON COLUMN osm.indoor_point.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_line.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_polygon.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';

COMMENT ON COLUMN osm.indoor_point.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_line.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';
COMMENT ON COLUMN osm.indoor_polygon.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


