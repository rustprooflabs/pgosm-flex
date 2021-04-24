require "helpers"

local tables = {}

tables.shop_point = osm2pgsql.define_table({
    name = 'shop_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'phone', type = 'text'},
        { column = 'wheelchair', type = 'bool'},
        { column = 'operator', type = 'text'},
        { column = 'brand', type = 'text'},
        { column = 'website', type = 'text'},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})


tables.shop_polygon = osm2pgsql.define_table({
    name = 'shop_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'phone', type = 'text'},
        { column = 'wheelchair', type = 'bool'},
        { column = 'operator', type = 'text'},
        { column = 'brand', type = 'text'},
        { column = 'website', type = 'text'},
        { column = 'geom',     type = 'multipolygon' , projection = srid},
    }
})


function shop_process_node(object)
    if not object.tags.shop
        and not object.tags.amenity then
        return
    end

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object:grab_tag('wheelchair')
    local phone = object:grab_tag('phone')
    local operator  = object:grab_tag('operator')
    local brand  = object:grab_tag('brand')
    local website  = object:grab_tag('website')

    if object.tags.shop then
        local osm_type = 'shop'
        local osm_subtype = object:grab_tag('shop')

        tables.shop_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            wheelchair = wheelchair,
            phone = phone,
            operator = operator,
            brand = brand,
            website = website,
            geom = { create = 'point' }
        })

    -- This creates overlap between this layer and amenity layer
    elseif object.tags.amenity == 'vending_machine'
            or object.tags.amenity == 'car_rental'
            or object.tags.amenity == 'motorcycle_rental'
            or object.tags.amenity == 'cafe'
            or object.tags.amenity == 'phone_repair'
            or object.tags.amenity == 'music_school'
            or object.tags.amenity == 'pub'
            or object.tags.amenity == 'pharmacy'
            or object.tags.amenity == 'ticket_booth'
            or object.tags.amenity == 'shop'
            then
        local osm_type = 'amenity'
        local osm_subtype = object:grab_tag('amenity')

        tables.shop_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            wheelchair = wheelchair,
            phone = phone,
            operator = operator,
            brand = brand,
            website = website,
            geom = { create = 'point' }
        })

    end


end


function shop_process_way(object)
    if not object.tags.shop
        and not object.tags.amenity then
        return
    end

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object:grab_tag('wheelchair')
    local phone = object:grab_tag('phone')
    local operator = object:grab_tag('operator')
    local brand = object:grab_tag('brand')
    local website = object:grab_tag('website')

    if object.tags.shop then
        local osm_type = 'shop'
        local osm_subtype = object:grab_tag('shop')

        if object.is_closed then
            tables.shop_polygon:add_row({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                housenumber = housenumber,
                street = street,
                city = city,
                state = state,
                postcode = postcode,
                address = address,
                wheelchair = wheelchair,
                phone = phone,
                operator = operator,
                brand = brand,
                website = website,
                geom = { create = 'area' }
            })
        end


    elseif object.tags.amenity == 'vending_machine'
            or object.tags.amenity == 'car_rental'
            or object.tags.amenity == 'motorcycle_rental'
            or object.tags.amenity == 'cafe'
            or object.tags.amenity == 'phone_repair'
            or object.tags.amenity == 'music_school'
            or object.tags.amenity == 'pub'
            or object.tags.amenity == 'pharmacy'
            or object.tags.amenity == 'ticket_booth'
            or object.tags.amenity == 'shop'
            then
        local osm_type = 'amenity'
        local osm_subtype = object:grab_tag('amenity')

        if object.is_closed then
            tables.shop_polygon:add_row({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                housenumber = housenumber,
                street = street,
                city = city,
                state = state,
                postcode = postcode,
                address = address,
                wheelchair = wheelchair,
                phone = phone,
                operator = operator,
                brand = brand,
                website = website,
                geom = { create = 'area' }
            })
        end
    end
end


if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = shop_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        shop_process_node(object_copy)
    end
end



if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = shop_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        shop_process_way(object_copy)
    end
end
