-- helpers.lua provides commonly used functions 
-- and sets customizable params, e.g. SRID and schema name.
local inifile = require('inifile')

local srid_env = os.getenv("PGOSM_SRID")
if srid_env then
    srid = srid_env
    print('Custom SRID: ' .. srid)
else
    srid = 3857
    print('Default SRID: ' .. srid)
end


local pgosm_date_env = os.getenv("PGOSM_DATE")
if pgosm_date_env then
    pgosm_date = pgosm_date_env
    default_date = false
    print('Explicit Date: ' .. pgosm_date)
else
    pgosm_date = os.date("%Y-%m-%d")
    default_date = true
    print('Default Date (today): ' .. pgosm_date)
end



local pgosm_language_env = os.getenv("PGOSM_LANGUAGE")
if pgosm_language_env then
    pgosm_language = pgosm_language_env
    print('INFO - Language Code set to ' .. pgosm_language)
else
    pgosm_language = ''
    print('INFO - Default language not set. Using OSM Wiki priority for name. Set PGOSM_LANGUAGE to customize.')
end


local gist_type_env = os.getenv("PGOSM_GIST_TYPE")
if gist_type_env then
    gist_type = gist_type_env
else
    gist_type = 'gist'
end

if gist_type ~= 'gist' and gist_type ~= 'spgist' then
    error('Invalid PGOSM_GIST_TYPE.  Must be gist or spgist. Value: ' .. gist_type)
end
print('Spatial index type: ' .. gist_type)


-- Best way to change schema name is post-processing.
-- Use ALTER SCHEMA osm RENAME TO your_schema;
schema_name = 'osm'


-- deep_copy based on copy2: https://gist.github.com/tylerneylon/81333721109155b2d244
function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end


-- Function make_check_in_list_func from: https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/compatible.lua
function make_check_in_list_func(list)
    local h = {}
    for _, k in ipairs(list) do
        h[k] = true
    end
    return function(tags)
        for k, _ in pairs(tags) do
            if h[k] then
                return true
            end
        end
        return false
    end
end


-- Parse a tag value like "1800", "1955 m" or "8001 ft" and return a number in meters
function parse_to_meters(input)
    if not input then
        return nil
    end

    local num1 = tonumber(input)

    -- If num1 is a number, it is in meters
    if num1 then
        return num1
    end

    -- If there is an 'm ' at the end, strip off and return number
    if input:sub(-1) == 'm' then
        local num2 = tonumber(input:sub(1, -2))
        if num2 then
            return num2
        end
    end

    -- If there is an 'ft' at the end, convert to meters and return
    if input:sub(-2) == 'ft' then
        local num3 = tonumber(input:sub(1, -3))
        if num3 then
            return num3 * 0.3048
        end
    end

    return nil
end


-- Parse a maxspeed value like "30" or "55 mph" and return a number in km/h
-- from osm2pgsql/flex-config/data-types.lua
function parse_speed(input)
    if not input then
        return nil
    end

    local maxspeed = tonumber(input)

    -- If maxspeed is just a number, it is in km/h, so just return it
    if maxspeed then
        return maxspeed
    end

    -- If there is an 'mph' at the end, convert to km/h and return
    if input:sub(-3) == 'mph' then
        local num = tonumber(input:sub(1, -4))
        if num then
            return math.floor(num * 1.60934)
        end
    end

    return nil
end


function parse_layer_value(input)
    -- Quick return
    if not input then
        return 0
    end

    -- Try getting a number
    local layer = tonumber(input)
    if layer then
        return layer
    end

    -- Fallback
    return 0
end


-- Checks highway tag to determine if major road or not.
function major_road(highway)
    if (highway == 'motorway'
        or highway == 'motorway_link'
        or highway == 'primary'
        or highway == 'primary_link'
        or highway == 'secondary'
        or highway == 'secondary_link'
        or highway == 'tertiary'
        or highway == 'tertiary_link'
        or highway == 'trunk'
        or highway == 'trunk_link')
            then
        return true
    end

    return false

    end

-- From https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/places.lua
function starts_with(str, start)
   return str:sub(1, #start) == start
end

-- From http://lua-users.org/wiki/StringRecipes
function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end


-- Returns a single "best" name for each object when possible.
-- First check is if name::<pgosm_language> exists, return it if it does...
-- If pgosm_language is not set, or not found...
--    the first name type tag it encounters in order of priority
--    Priority based on OSM Wiki: https://wiki.openstreetmap.org/wiki/Names
function get_name(tags)
    local best_name
    if pgosm_language ~= nil then
        best_name = tags['name:' .. pgosm_language]
    end

    -- I tried nesting this logic above but it always resulted in nil values
    -- Probably a better way...
    if best_name ~= nil then
        return best_name
    end

    if tags.name then
        best_name = tags.name
    elseif tags.short_name then
        best_name = tags.short_name
    elseif tags.alt_name then
        best_name = tags.alt_name
    elseif tags.loc_name then
        best_name = tags.loc_name
    else
        best_name = get_name_last_ditch(tags)
    end

    return best_name

end

-- Uses tags.old_name first if exists.
-- Looks for any name tag associated with a colon.
-- Gives zero priority, simply the first found value.
-- And empty string for real last ditch.
function get_name_last_ditch(tags)
    if tags.old_name then
        return tags.old_name
    end

    for k, v in pairs(tags) do
        if starts_with(k, "name:")
            or ends_with(k, ":NAME")
                then
            return v
        end
    end

    return ''
end


function get_wheelchair_desc(tags)
    local wheelchair_desc = tags['wheelchair:description']
    return wheelchair_desc
end


-- Returns a single "best" ref for each object when possible.
-- * Returns nil if ref not set
function get_ref(tags)
    local best_ref

    if tags.local_ref then
        best_ref = tags.local_ref
    elseif tags.route_ref then
        best_ref = tags.route_ref
    elseif tags.nat_ref then
        best_ref = tags.nat_ref
    elseif tags.ref then
        best_ref = tags.ref
    elseif tags.alt_ref then
        best_ref = tags.alt_ref
    elseif tags.old_ref then
        best_ref = tags.old_ref
    else
        best_ref = nil
    end

    return best_ref
end

function parse_admin_level(input)
    -- Quick return
    if not input then
        return
    end

    -- Try getting a number
    local admin_level = tonumber(input)
    if admin_level then
        return admin_level
    end

    -- Fallback
    return
end

function routable_foot(tags)
    if (tags.access == 'no'
            or tags.access == 'private'
            or tags.foot == 'no'
            or tags.foot == 'private')
            then
        return false
    elseif (tags.highway == 'footway'
            or tags.footway
            or tags.foot == 'yes'
            or tags.foot == 'permissive'
            or tags.foot == 'designated'
            or tags.highway == 'pedestrian'
            or tags.highway == 'crossing'
            or tags.highway == 'platform'
            or tags.highway == 'social_path'
            or tags.highway == 'steps'
            or tags.highway == 'trailhead'
            or tags.highway == 'track'
            or tags.highway == 'path'
            or tags.highway == 'unclassified'
            or tags.highway == 'service'
            or tags.highway == 'residential'
            or tags.highway == 'living_street'
            or tags.highway == 'elevator'
            or tags.highway == 'corridor'
            or tags.highway == 'foot')
            then
        return true
    end

    return false
end

-- https://wiki.openstreetmap.org/wiki/Bicycle
function routable_cycle(tags)
    if (tags.access == 'no'
            or tags.access == 'private'
            or tags.bicycle == 'no'
            or tags.bicycle == 'private'
            )
            then
        return false
    elseif (tags.cycleway
            or tags.bicycle == 'yes'
            or tags.bicycle == 'designated'
            or tags.bicycle == 'permissive'
            or tags.highway == 'cycleway'
            or tags.highway == 'track'
            or tags.highway == 'path'
            or tags.highway == 'unclassified'
            or tags.highway == 'service'
            or tags.highway == 'residential'
            or tags.highway == 'tertiary'
            or tags.highway == 'tertiary_link'
            or tags.highway == 'secondary'
            or tags.highway == 'secondary_link'
            or tags.highway == 'living_street'
            )
            then
        return true
    end

    return false
end

function routable_motor(tags)
    if (tags.access == 'no'
            or tags.access == 'private'
            or tags.motor_vehicle == 'no'
            or tags.motor_vehicle == 'private')
            then
        return false
    elseif (tags.highway == 'motorway'
            or tags.highway == 'motorway_link'
            or tags.highway == 'trunk'
            or tags.highway == 'trunk_link'
            or tags.highway == 'primary'
            or tags.highway == 'primary_link'
            or tags.highway == 'secondary'
            or tags.highway == 'secondary_link'
            or tags.highway == 'tertiary'
            or tags.highway == 'tertiary_link'
            or tags.highway == 'residential'
            or tags.highway == 'service'
            or tags.highway == 'unclassified'
            or tags.highway == 'living_street'
            or tags.highway == 'rest_area'
            or tags.highway == 'raceway'
            or tags.motor_vehicle == 'yes'
            or tags.motor_vehicle == 'permissive')
            then
        return true
    end

    return false
end



function get_address(tags)
    local housenumber  = tags['addr:housenumber']
    local street = tags['addr:street']
    local city = tags['addr:city']
    local state = tags['addr:state']
    local postcode = tags['addr:postcode']

    local housenumber_street = ''

    if housenumber ~= nil and street ~= nil then
        housenumber_street = housenumber  .. ' ' .. street
    elseif housenumber == nil and street == nil then
        housenumber_street = ''
    elseif housenumber == nil then
        housenumber_street = street
    else
        housenumber_street = housenumber
    end

    if city == nil then
        city = ''
    end

    if state == nil then
        state = ''
    end

    if postcode == nil then
        postcode = ''
    end

    local all_but_state_postcode = ''

    if housenumber_street ~= '' and city ~= '' then
        all_but_state_postcode = housenumber_street .. ', ' .. city
    else
        all_but_state_postcode = housenumber_street .. city
    end

    local all_but_postcode = ''

    if all_but_state_postcode ~= '' and state ~= '' then
        all_but_postcode = all_but_state_postcode .. ', ' .. state
    else
        all_but_postcode = all_but_state_postcode .. state
    end

    local address = ''

    if all_but_postcode ~= '' and postcode ~= '' then
        address = all_but_postcode .. ', ' .. postcode
    else
        address = all_but_postcode .. postcode
    end

    return address

end


function get_indexes_from_spec(index_spec_file)
    print('Loading config: ' .. index_spec_file)
    local index_config = inifile.parse(index_spec_file)

    -------------------------------------------------
    -- Parse through index options
    -------------------------------------------------
    local index_geom = index_config['indexes']['index_geom']
    if index_geom == nil then
        index_geom = false
    end

    local gist_type = index_config['indexes']['gist_type']
    if gist_type == nil then
        gist_type = 'gist'
    end

    local index_osm_type = index_config['indexes']['index_osm_type']
    if index_osm_type == nil then
        index_osm_type = false
    end

    local index_osm_subtype = index_config['indexes']['index_osm_subtype']
    if index_osm_subtype == nil then
        index_osm_subtype = false
    end

    local index_name = index_config['indexes']['index_name']
    if index_name == nil then
        index_name = false
    end

    local index_boundary = index_config['indexes']['index_boundary']
    if index_boundary == nil then
        index_boundary = false
    end

    local index_admin_level = index_config['indexes']['index_admin_level']
    if index_admin_level == nil then
        index_admin_level = false
    end


    -------------------------------------------------
    -- Build indexes table
    -------------------------------------------------
    local indexes = {}
    local next_index_id = 1

    if index_geom then
        indexes[next_index_id] = { column = 'geom', method = gist_type }
        next_index_id = next_index_id + 1
    end

    if index_osm_type then
        indexes[next_index_id] = {column = 'osm_type', method = 'btree' }
        next_index_id = next_index_id + 1
    end

    if index_osm_subtype then
        indexes[next_index_id] = {column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL ' }
        next_index_id = next_index_id + 1
    end

    if index_name then
        indexes[next_index_id] = { column = 'name', method = 'btree', where = 'name IS NOT NULL ' }
        next_index_id = next_index_id + 1
    end

    if index_boundary then
        indexes[next_index_id] = { column = 'boundary', method = 'btree', where = 'boundary IS NOT NULL ' }
        next_index_id = next_index_id + 1
    end

    if index_admin_level then
        indexes[next_index_id] = { column = 'admin_level', method = 'btree', where = 'admin_level IS NOT NULL ' }
        next_index_id = next_index_id + 1
    end

    return indexes
end
