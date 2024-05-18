require "helpers"

local index_spec_file = 'indexes/infrastructure.ini'
local indexes_point = get_indexes_from_spec(index_spec_file, 'point')
local indexes_line = get_indexes_from_spec(index_spec_file, 'line')
local indexes_polygon = get_indexes_from_spec(index_spec_file, 'polygon')


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
    ids = { type = 'node', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text'},
        { column = 'name', type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height', sql_type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    },
    indexes = indexes_point
})

tables.infrastructure_line = osm2pgsql.define_table({
    name = 'infrastructure_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text'},
        { column = 'name', type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height', sql_type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom', type = 'linestring', projection = srid, not_null = true},
    },
    indexes = indexes_line
})


tables.infrastructure_polygon = osm2pgsql.define_table({
    name = 'infrastructure_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text'},
        { column = 'name', type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height', sql_type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    },
    indexes = indexes_polygon
})

local function get_osm_type_subtype(tags)
    local osm_type_table = {}

    if tags.amenity == 'fire_hydrant'
            or tags.emergency == 'fire_hydrant' then
        osm_type_table['osm_type'] = 'emergency'
        osm_type_table['osm_subtype'] = 'fire_hydrant'
    elseif tags.amenity == 'emergency_phone'
            or tags.emergency == 'phone' then
        osm_type_table['osm_type'] = 'emergency'
        osm_type_table['osm_subtype'] = 'phone'
    elseif tags.emergency then
        osm_type_table['osm_type'] = 'emergency'
        osm_type_table['osm_subtype'] = tags.emergency
    elseif tags.highway == 'emergency_access_point' then
        osm_type_table['osm_type'] = 'emergency'
        osm_type_table['osm_subtype'] = 'highway_access'
    elseif tags.man_made == 'tower'
            or tags.man_made == 'communications_tower'
            or tags.man_made == 'mast'
            or tags.man_made == 'lighthouse'
            or tags.man_made == 'flagpole'
            then
        osm_type_table['osm_type'] = tags.man_made
        osm_type_table['osm_subtype'] = tags['tower:type']

    elseif tags.man_made == 'silo'
            or tags.man_made == 'storage_tank'
            or tags.man_made == 'water_tower'
            or tags.man_made == 'reservoir_covered'
            then
        osm_type_table['osm_type'] = tags.man_made
        osm_type_table['osm_subtype'] = tags['content']
    elseif tags.power
            then
        osm_type_table['osm_type'] = 'power'
        osm_type_table['osm_subtype'] = tags['power']
    elseif tags.utility then
        osm_type_table['osm_type'] = 'utility'
        osm_type_table['osm_subtype'] = nil
    elseif tags.aeroway then
        osm_type_table['osm_type'] = 'aeroway'
        osm_type_table['osm_subtype'] = tags.aeroway
    else
        osm_type_table['osm_type'] = 'unknown'
        osm_type_table['osm_subtype'] = nil
    end

    if osm_type_table['osm_type'] == 'emergency'
            and osm_type_table['osm_subtype'] == 'no' then
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

    local osm_types = get_osm_type_subtype(object.tags)

    if osm_types.osm_type == 'unknown' then
        return
    end

    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)
    local height = parse_to_meters(object.tags['height'])
    local operator = object.tags.operator
    local material = object.tags.material

    tables.infrastructure_point:insert({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        ele = ele,
        height = height,
        operator = operator,
        material = material,
        geom = object:as_point()
    })

end


function infrastructure_process_way(object)
    -- We are only interested in some tags
    if not is_infrastructure(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object.tags)

    if osm_types.osm_type == 'unknown' then
        return
    end

    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)
    local height = parse_to_meters(object.tags['height'])
    local operator = object.tags.operator
    local material = object.tags.material

    if object.is_closed then
        tables.infrastructure_polygon:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = object:as_polygon()
        })
    else
        tables.infrastructure_line:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = object:as_linestring()
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
