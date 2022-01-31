require "helpers"

local tables = {}

-- Rows with any of the following keys will be treated as possible infrastructure
local infrastructure_keys = {
    'aeroway',
    'amenity',
    'emergency',
    'highway',
    'man_made',
    'power',
    'utility'
}

local is_infrastructure = make_check_in_list_func(infrastructure_keys)

tables.infrastructure_point = osm2pgsql.define_table({
    name = 'infrastructure_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',   type = 'text'},
        { column = 'name',     type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height',  sql_type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})

tables.infrastructure_line = osm2pgsql.define_table({
    name = 'infrastructure_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',   type = 'text'},
        { column = 'name',     type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height',  sql_type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom',     type = 'linestring' , projection = srid},
    }
})


tables.infrastructure_polygon = osm2pgsql.define_table({
    name = 'infrastructure_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',   type = 'text'},
        { column = 'name',     type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height',  sql_type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom',     type = 'multipolygon' , projection = srid},
    }
})

local function get_osm_type_subtype(object)
    local osm_type_table = {}

    if object.tags.amenity == 'fire_hydrant'
            or object.tags.emergency == 'fire_hydrant' then
        osm_type_table['osm_type'] = 'fire_hydrant'
        osm_type_table['osm_subtype'] = nil
    elseif object.tags.amenity == 'emergency_phone'
            or object.tags.emergency == 'phone' then
        osm_type_table['osm_type'] = 'emergency_phone'
        osm_type_table['osm_subtype'] = nil
    elseif object.tags.highway == 'emergency_access_point' then
        osm_type_table['osm_type'] = 'emergency_access'
        osm_type_table['osm_subtype'] = nil
    elseif object.tags.man_made == 'tower'
            or object.tags.man_made == 'communications_tower'
            or object.tags.man_made == 'mast'
            or object.tags.man_made == 'lighthouse'
            or object.tags.man_made == 'flagpole'
            then
        osm_type_table['osm_type'] = object.tags.man_made
        osm_type_table['osm_subtype'] = object.tags['tower:type']

    elseif object.tags.man_made == 'silo'
            or object.tags.man_made == 'storage_tank'
            or object.tags.man_made == 'water_tower'
            or object.tags.man_made == 'reservoir_covered'
            then
        osm_type_table['osm_type'] = object.tags.man_made
        osm_type_table['osm_subtype'] = object.tags['content']
    elseif object.tags.power
            then
        osm_type_table['osm_type'] = 'power'
        osm_type_table['osm_subtype'] = object.tags['power']
    elseif object.tags.utility then
        osm_type_table['osm_type'] = 'utility'
        osm_type_table['osm_subtype'] = nil
    elseif object.tags.aeroway == 'aerodrome' then
        osm_type_table['osm_type'] = 'aeroway'
        osm_type_table['osm_subtype'] = nil
    else
        osm_type_table['osm_type'] = 'unknown'
        osm_type_table['osm_subtype'] = nil
    end

    return osm_type_table
end



function infrastructure_process_node(object)
    -- We are only interested in some tags
    if not is_infrastructure(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    if osm_types.osm_type == 'unknown' then
        return
    end

    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)
    local height = parse_to_meters(object.tags['height'])
    local operator = object.tags.operator
    local material = object.tags.material

    tables.infrastructure_point:add_row({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        ele = ele,
        height = height,
        operator = operator,
        material = material,
        geom = { create = 'point' }
    })

end


function infrastructure_process_way(object)
    -- We are only interested in some tags
    if not is_infrastructure(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    if osm_types.osm_type == 'unknown' then
        return
    end

    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)
    local height = parse_to_meters(object.tags['height'])
    local operator = object.tags.operator
    local material = object.tags.material

    if object.is_closed then
        tables.infrastructure_polygon:add_row({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = { create = 'area' }
        })
    else
        tables.infrastructure_line:add_row({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = { create = 'line' }
        })
    end

end



if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = infrastructure_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        infrastructure_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = infrastructure_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        infrastructure_process_way(object_copy)
    end
end
