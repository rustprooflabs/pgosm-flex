require "helpers"

local tables = {}


tables.building_point = osm2pgsql.define_table({
    name = 'building_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = true},
        { column = 'name',     type = 'text' },
        { column = 'levels',  type = 'int'},
        { column = 'height',  type = 'numeric'},
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'wheelchair', type = 'bool'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'point', projection = srid},
    }
})


tables.building_polygon = osm2pgsql.define_table({
    name = 'building_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = true},
        { column = 'name',     type = 'text' },
        { column = 'levels',  type = 'int'},
        { column = 'height',  type = 'numeric'},
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'wheelchair', type = 'bool'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'multipolygon', projection = srid},
    }
})


function address_only_building(tags)
    -- Cannot have any of these tags
    if tags.shop
        or tags.amenity
        or tags.building
        or tags.landuse
        or tags.leisure
        or tags.tourism then
            return false
    end

    -- Looking for any addr: tag might be too wide of a net.
    for k, v in pairs(tags) do
        if k ~= nil then
            if starts_with(k, "addr:") then
                return true
            end
        end
    end
    return false
end


function building_process_node(object)
    local address_only = address_only_building(object.tags)

    if not object.tags.building
            and not object.tags['building:part']
            and not address_only
            then
        return
    end

    local osm_type

    if object.tags.building then
        osm_type = object:grab_tag('building')
    elseif object.tags['building:part'] then
        osm_type = 'building_part'
    elseif address_only then
        osm_type = 'address'
    else
        osm_type = 'unknown'
    end

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local address = get_address(object.tags)
    local wheelchair = object:grab_tag('wheelchair')
    local levels = object:grab_tag('building:levels')
    local height = parse_to_meters(object.tags['height'])
    local operator  = object:grab_tag('operator')

    tables.building_point:add_row({
        osm_type = osm_type,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        address = address,
        wheelchair = wheelchair,
        levels = levels,
        height = height,
        operator = operator,
        geom = { create = 'point' }
    })


end


function building_process_way(object)
    local address_only = address_only_building(object.tags)

    if not object.tags.building
            and not object.tags['building:part']
            and not address_only
            then
        return
    end

    if not object.is_closed then
        return
    end

    local osm_type
    if object.tags.building then
        osm_type = object:grab_tag('building')
    elseif object.tags['building:part'] then
        osm_type = 'building_part'
    elseif address_only then
        osm_type = 'address'
    else
        osm_type = 'unknown'
    end

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local address = get_address(object.tags)
    local wheelchair = object:grab_tag('wheelchair')
    local levels = object:grab_tag('building:levels')
    local height = parse_to_meters(object.tags['height'])
    local operator  = object:grab_tag('operator')

    tables.building_polygon:add_row({
        osm_type = osm_type,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        address = address,
        wheelchair = wheelchair,
        levels = levels,
        height = height,
        operator = operator,
        geom = { create = 'area' }
    })


end



if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = building_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        building_process_way(object_copy)
    end
end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = building_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        building_process_node(object_copy)
    end
end
