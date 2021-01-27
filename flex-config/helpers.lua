-- helpers.lua provides commonly used functions 
-- and sets customizable params, e.g. SRID and schema name.


local srid_env = os.getenv("PGOSM_SRID")
if srid_env then
    srid = srid_env
    print('Custom SRID: ' .. srid)
else
    srid = 3857
    print('Default SRID: ' .. srid)
end

local schema_env = os.getenv("PGOSM_SCHEMA")
if schema_env then
    schema_name = schema_env
    print('Custom Schema: ' .. schema_name)
else
    schema_name = 'osm'
    print('Default Schema: ' .. schema_name)
end


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
local function starts_with(str, start)
   return str:sub(1, #start) == start
end

-- From http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end


-- returns the first name type tag it encounters in order of priority
--   Per: https://wiki.openstreetmap.org/wiki/Names
function get_name(tags)
    if tags.name then
        return tags.name
    elseif tags.short_name then
        return tags.short_name
    elseif tags.alt_name then
        return tags.alt_name
    elseif tags.loc_name then
        return tags.loc_name
    end

    for k, v in pairs(tags) do
        if starts_with(k, "name:")
            or ends_with(k, ":NAME")
                then
            return v
        end
    end

    if tags.old_name then
        return tags.old_name
    end
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
    if (tags.highway == 'footway'
            or tags.footway
            or tags.foot == 'yes'
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
            or tags.highway == 'residential')
            then
        return true
    end

    return false
end

-- https://wiki.openstreetmap.org/wiki/Bicycle
function routable_cycle(tags)
    if (tags.cycleway
            or tags.bicycle == 'yes'
            or tags.bicycle == 'designated'
            or tags.bicycle == 'permissive'
            or tags.highway == 'track'
            or tags.highway == 'path'
            or tags.highway == 'unclassified'
            or tags.highway == 'service'
            or tags.highway == 'residential'
            or tags.highway == 'tertiary'
            or tags.highway == 'tertiary_link'
            or tags.highway == 'secondary'
            or tags.highway == 'secondary_link'
            )
            then
        return true
    end

    return false
end

function routable_motor(tags)
    if (tags.highway == 'motorway'
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
            or tags.highway == 'unclassified')
            then
        return true
    end

    return false
end


