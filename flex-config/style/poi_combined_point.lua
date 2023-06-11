require "helpers"
require "style.poi_helpers"

local tables = {}


tables.poi_combined_point = osm2pgsql.define_table({
    name = 'poi_combined_point',
    schema = schema_name,
    ids = { type = 'any', id_column = 'osm_id', type_column = 'geom_type' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'operator', type = 'text'},
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = gist_type },
        { column = 'osm_type', method = 'btree' },
        { column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL ' },
    }
})




function poi_process_node_combined(object)
    -- Quickly remove any that don't match the 1st level of checks
    if not is_first_level_poi(object.tags) then
        return
    end

    if not second_level_tag_check_poi(object) then
        return
    end

    local osm_types = get_osm_type_subtype_poi(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)

    local operator  = object:grab_tag('operator')

    tables.poi_combined_point:insert({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        operator = operator,
        geom = object:as_point()
    })

end


function poi_process_way_combined(object)
    -- Quickly remove any that don't match the 1st level of checks
    if not is_first_level_poi(object.tags) then
        return
    end

    if not second_level_tag_check_poi(object) then
        return
    end

    local osm_types = get_osm_type_subtype_poi(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local operator  = object:grab_tag('operator')

    if object.is_closed then
        tables.poi_combined_point:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            operator = operator,
            geom = object:as_polygon():centroid()
        })
    else
        tables.poi_combined_point:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            operator = operator,
            geom = object:as_linestring():centroid()
        })
    end

end



function poi_process_relation_combined(object)
    -- Quickly remove any that don't match the 1st level of checks
    if not is_first_level_poi(object.tags) then
        return
    end

    if not second_level_tag_check_poi(object) then
        return
    end


    -- Gets osm_type and osm_subtype
    local osm_types = get_osm_type_subtype_poi(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local operator  = object:grab_tag('operator')

    local member_ids = osm2pgsql.way_member_ids(object)

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        tables.poi_combined_point:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            operator = operator,
            member_ids = member_ids,
            geom = object:as_multipolygon():centroid()
        })
    end

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = poi_process_node_combined
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        poi_process_node_combined(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = poi_process_way_combined
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        poi_process_way_combined(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = poi_process_relation_combined
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        poi_process_relation_combined(object_copy)
    end
end

