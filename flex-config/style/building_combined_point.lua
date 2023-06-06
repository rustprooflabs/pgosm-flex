require "helpers"
require "style.building_helpers"


local tables = {}


tables.building_combined_point = osm2pgsql.define_table({
    name = 'building_combined_point',
    schema = schema_name,
    ids = { type = 'any', id_column = 'osm_id', type_column = 'geom_type' },
    columns = {
        { column = 'osm_type', type = 'text' , not_null = true},
        { column = 'osm_subtype', type = 'text'},
        { column = 'name', type = 'text' },
        { column = 'levels', type = 'int'},
        { column = 'height', sql_type = 'numeric'},
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'operator', type = 'text'},
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = gist_type },
        { column = 'osm_type', method = 'btree' },
        { column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL' },
    }
})

function building_combined_point_process_node(object)
    local address_only = address_only_building(object.tags)

    if not is_first_level_building(object.tags)
            and not address_only
            then
        return
    end

    local osm_types = get_osm_type_subtype_building(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local levels = object.tags['building:levels']
    local height = parse_to_meters(object.tags['height'])
    local operator  = object.tags.operator

    tables.building_combined_point:insert({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        wheelchair = wheelchair,
        wheelchair_desc = wheelchair_desc,
        levels = levels,
        height = height,
        operator = operator,
        geom = object:as_point()
    })
end


function building_combined_point_process_way(object)
    local address_only = address_only_building(object.tags)

    if not is_first_level_building(object.tags)
            and not address_only
            then
        return
    end

    if not object.is_closed then
        return
    end
    local osm_types = get_osm_type_subtype_building(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local levels = object.tags['building:levels']
    local height = parse_to_meters(object.tags['height'])
    local operator  = object.tags.operator

    tables.building_combined_point:insert({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        wheelchair = wheelchair,
        wheelchair_desc = wheelchair_desc,
        levels = levels,
        height = height,
        operator = operator,
        geom = object:as_polygon():centroid()
    })

end


function building_combined_point_process_relation(object)
    local address_only = address_only_building(object.tags)

    if not is_first_level_building(object.tags)
            and not address_only
            then
        return
    end

    local osm_types = get_osm_type_subtype_building(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local levels = object.tags['building:levels']
    local height = parse_to_meters(object.tags['height'])
    local operator  = object.tags.operator

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        tables.building_combined_point:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            wheelchair = wheelchair,
            wheelchair_desc = wheelchair_desc,
            levels = levels,
            height = height,
            operator = operator,
            geom = object:as_multipolygon():centroid()
        })
    end

end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = building_combined_point_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        building_combined_point_process_way(object_copy)
    end
end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = building_combined_point_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        building_combined_point_process_node(object_copy)
    end
end

if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = building_combined_point_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        building_combined_point_process_relation(object_copy)
    end
end
