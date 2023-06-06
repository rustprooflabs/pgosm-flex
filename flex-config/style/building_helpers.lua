-- building_helpers.lua provides commonly used functions 
-- for the building layers


function address_only_building(tags)
    -- Cannot have any of these tags
    if tags.shop
        or tags.amenity
        or tags.building
        or tags['building:part']
        or tags.landuse
        or tags.leisure
        or tags.office
        or tags.tourism
        or tags.boundary -- included in place layer
        or tags.natural
        or tags.aeroway
        or tags.demolished
        then
            return false
    end

    -- Opting to include any addr: tag that was not excluded explicitly above
    --   This might be too wide of a net, but trying to be too picky risks
    --   excluding potentially important data
    for k, v in pairs(tags) do
        if k ~= nil then
            if starts_with(k, "addr:") then
                return true
            end
        end
    end
    return false
end



function get_osm_type_subtype_building(object)
    local osm_type_table = {}
    local address_only = address_only_building(object.tags)

    if object.tags.building then
        osm_type_table['osm_type'] = 'building'
        osm_type_table['osm_subtype'] = object.tags.building
    elseif object.tags['building:part'] then
        osm_type_table['osm_type'] = 'building_part'
        osm_type_table['osm_subtype'] = object.tags['building:part']
    elseif object.tags.office then
        osm_type_table['osm_type'] = 'office'
        osm_type_table['osm_subtype'] = object.tags.office
    elseif address_only then
        osm_type_table['osm_type'] = 'address'
        osm_type_table['osm_subtype'] = nil
    elseif object.tags.entrance then
        osm_type_table['osm_type'] = 'entrance'
        osm_type_table['osm_subtype'] = object.tags.entrance
    elseif object.tags.door then
        osm_type_table['osm_type'] = 'door'
        osm_type_table['osm_subtype'] = object.tags.door
    else
        osm_type_table['osm_type'] = 'unknown'
        osm_type_table['osm_subtype'] = nil
    end

    return osm_type_table
end


local building_first_level_keys = {
    'building',
    'building:part',
    'office',
    'door',
    'entrance'
}

is_first_level_building = make_check_in_list_func(building_first_level_keys)
