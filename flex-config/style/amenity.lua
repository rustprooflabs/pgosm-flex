require "helpers"

local index_spec_file = 'indexes/amenity.ini'
local indexes_point = get_indexes_from_spec(index_spec_file, 'point')
local indexes_line = get_indexes_from_spec(index_spec_file, 'line')
local indexes_polygon = get_indexes_from_spec(index_spec_file, 'polygon')

local tables = {}

tables.amenity_point = osm2pgsql.define_table({
    name = 'amenity_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    },
    indexes = indexes_point
})

tables.amenity_line = osm2pgsql.define_table({
    name = 'amenity_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'geom', type = 'linestring', projection = srid, not_null = true},
    },
    indexes = indexes_line
})


tables.amenity_polygon = osm2pgsql.define_table({
    name = 'amenity_polygon',
    schema = schema_name,
    ids = { type = 'area', id_column = 'osm_id', create_index = 'unique'},
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    },
    indexes = indexes_polygon
})


-- Keys to include for further checking.  Not all values from each key will be preserved
local amenity_first_level_keys = {
    'amenity',
    'bench',
    'brewery'
}

local is_first_level_amenity = make_check_in_list_func(amenity_first_level_keys)


local function get_osm_type_subtype(object)
    -- This function knowingly returns nil osm_type.
    -- This allows filtering out bench=no records (and similar) in later logic
    local osm_type_table = {}
    local amenity = object.tags.amenity
    local osm_type = nil
    local osm_subtype = nil

    if amenity == nil and object.tags.bench == 'yes' then
        osm_type = 'bench'
    elseif amenity == nil and object.tags.brewery then
        osm_type = 'brewery'
    elseif (amenity == 'restaurant' or amenity == 'fast_food' or amenity == 'cafe') then
        osm_type = amenity
        osm_subtype = object.tags.cuisine
    elseif amenity == 'shelter' then
        osm_type = amenity
        osm_subtype = object.tags.shelter_type
    elseif amenity ~= nil and osm_type == nil then
        osm_type = amenity
    end

    osm_type_table['osm_type'] = osm_type
    osm_type_table['osm_subtype'] = osm_subtype
    return osm_type_table
end


function amenity_process_node(object)
    if not is_first_level_amenity(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    if osm_types['osm_type'] == nil then
        return
    end

    local name = get_name(object.tags)

    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)

    tables.amenity_point:insert({
        osm_type = osm_types['osm_type'],
        osm_subtype = osm_types['osm_subtype'],
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        wheelchair = wheelchair,
        wheelchair_desc = wheelchair_desc,
        geom = object:as_point()
    })

end

-- Change function name here
function amenity_process_way(object)
    if not is_first_level_amenity(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    if osm_types['osm_type'] == nil then
        return
    end

    local name = get_name(object.tags)

    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)

    if object.is_closed then
        tables.amenity_polygon:insert({
            osm_type = osm_types['osm_type'],
            osm_subtype = osm_types['osm_subtype'],
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            wheelchair = wheelchair,
            wheelchair_desc = wheelchair_desc,
            geom = object:as_polygon()
        })
    else
        tables.amenity_line:insert({
            osm_type = osm_types['osm_type'],
            osm_subtype = osm_types['osm_subtype'],
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            wheelchair = wheelchair,
            wheelchair_desc = wheelchair_desc,
            geom = object:as_linestring()
        })
    end
    
end


function amenity_process_relation(object)
    if not is_first_level_amenity(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    if osm_types['osm_type'] == nil then
        return
    end

    local name = get_name(object.tags)
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)

    tables.amenity_polygon:insert({
        osm_type = osm_types['osm_type'],
        osm_subtype = osm_types['osm_subtype'],
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        wheelchair = wheelchair,
        wheelchair_desc = wheelchair_desc,
        geom = object:as_multipolygon()
    })

end



if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = amenity_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        amenity_process_node(object_copy)
    end
end



if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = amenity_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        amenity_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = amenity_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        amenity_process_relation(object_copy)
    end
end
