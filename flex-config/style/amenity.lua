require "helpers"

local tables = {}

tables.amenity_point = osm2pgsql.define_table({
    name = 'amenity_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})

tables.amenity_line = osm2pgsql.define_table({
    name = 'amenity_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'geom',     type = 'linestring' , projection = srid},
    }
})


tables.amenity_polygon = osm2pgsql.define_table({
    name = 'amenity_polygon',
    schema = schema_name,
    ids = { type = 'area', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'geom',     type = 'multipolygon' , projection = srid},
    }
})


function amenity_process_node(object)
    if not object.tags.amenity then
        return
    end

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local osm_type = object:grab_tag('amenity')
    local name = get_name(object.tags)


    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']

    local address = get_address(object.tags)

    tables.amenity_point:add_row({
        osm_type = osm_type,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        geom = { create = 'point' }
    })

end

-- Change function name here
function amenity_process_way(object)
    if not object.tags.amenity then
        return
    end

    local osm_type = object:grab_tag('amenity')
    local name = get_name(object.tags)

    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']

    local address = get_address(object.tags)

    if object.is_closed then
        tables.amenity_polygon:add_row({
            osm_type = osm_type,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            geom = { create = 'area' }
        })
    else
        tables.amenity_line:add_row({
            osm_type = osm_type,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            geom = { create = 'line' }
        })
    end
    
end


function amenity_process_relation(object)
    if not object.tags.amenity then
        return
    end

    local osm_type = object:grab_tag('amenity')
    local name = get_name(object.tags)

    local address = get_address(object.tags)

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        tables.amenity_polygon:add_row({
            osm_type = osm_type,
            name = name,
            address = address,
            geom = { create = 'area' }
        })
    end
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
