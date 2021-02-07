require "helpers"

local tables = {}

-- Rows with any of the following keys will be treated as possible infrastructure
local infrastructure_keys = {
    'aeroway',
    'amenity',
    'emergency',
    'highway',
    'man_made',
    'power'
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
        { column = 'height',  type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'material', type = 'text'},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})



function infrastructure_process_node(object)
    -- We are only interested in some tags
    if not is_infrastructure(object.tags) then
        return
    end

    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)
    local height = parse_to_meters(object.tags['height'])
    local operator = object.tags.operator

    if object.tags.amenity == 'fire_hydrant'
            or object.tags.emergency == 'fire_hydrant' then
        local osm_type = 'fire_hydrant'

        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    elseif object.tags.amenity == 'emergency_phone'
            or object.tags.emergency == 'phone' then
        local osm_type = 'emergency_phone'
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    elseif object.tags.highway == 'emergency_access_point'
            then
        local osm_type = 'emergency_access'
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    elseif object.tags.man_made == 'tower'
            or object.tags.man_made == 'communications_tower'
            or object.tags.man_made == 'mast'
            or object.tags.man_made == 'lighthouse'
            or object.tags.man_made == 'flagpole'
            then
        local osm_type = object.tags.man_made
        local osm_subtype = object.tags['tower:type']
        local material = object.tags.material
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = { create = 'point' }
        })

    elseif object.tags.man_made == 'silo'
            or object.tags.man_made == 'storage_tank'
            or object.tags.man_made == 'water_tower'
            or object.tags.man_made == 'reservoir_covered'
            then
        local osm_type = object.tags.man_made
        local osm_subtype = object.tags['content']
        local material = object.tags.material
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = { create = 'point' }
        })

    elseif object.tags.power
            then
        local osm_type = 'power'
        local osm_subtype = object.tags['power']
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            material = material,
            geom = { create = 'point' }
        })

    end

end



if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = infrastructure_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        infrastructure_process_node(object_copy)
    end
end

