
-- Keys to include for further checking.  Not all values from each key will be preserved
local poi_first_level_keys = {
    'building',
    'shop',
    'amenity',
    'leisure',
    'man_made',
    'tourism',
    'landuse',
    'natural',
    'historic'
}

is_first_level_poi = make_check_in_list_func(poi_first_level_keys)


local function building_poi(object)
    local bldg_name = get_name(object.tags)
    if (bldg_name ~= '' or object.tags.operator) then
        return true
    end

    return false
end


local function landuse_poi(object)
    if (object.tags.landuse == 'cemetery'
            or object.tags.landuse == 'orchard'
            or object.tags.landuse == 'railway'
            or object.tags.landuse == 'village_green'
            or object.tags.landuse == 'vineyard') then
        return true
    end

    return false

end


local function man_made_poi(object)
    if (object.tags.man_made == 'beacon'
            or object.tags.man_made == 'chimney'
            or object.tags.man_made == 'communications_tower'
            or object.tags.man_made == 'crane'
            or object.tags.man_made == 'flagpole'
            or object.tags.man_made == 'lighthouse'
            or object.tags.man_made == 'mast'
            or object.tags.man_made == 'obelisk'
            or object.tags.man_made == 'observatory'
            or object.tags.man_made == 'offshore_platform'
            or object.tags.man_made == 'pier'
            or object.tags.man_made == 'silo'
            or object.tags.man_made == 'survey_point'
            or object.tags.man_made == 'telescope'
            or object.tags.man_made == 'tower'
            or object.tags.man_made == 'water_tap'
            or object.tags.man_made == 'water_tower'
            or object.tags.man_made == 'water_well'
            or object.tags.man_made == 'windmill'
            or object.tags.man_made == 'works'
            ) then
        return true
    end

    return false
end

local function natural_poi(object)
    if (object.tags.natural == 'peak'
            or object.tags.natural == 'glacier'
            or object.tags.natural == 'reef'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'bay') then
        return true
    end

    return false
end


function second_level_tag_check(object)
    if (object.tags.natural and not natural_poi(object)) then
        return false
    end

    if (object.tags.landuse and not landuse_poi(object)) then
        return false
    end

    if (object.tags.building and not building_poi(object)) then
        return false
    end

    if (object.tags.man_made and not man_made_poi(object)) then
        return false
    end

    return true
end


function get_osm_type_subtype_poi(object)
    local osm_type_table = {}

    if object.tags.shop then
        osm_type_table['osm_type'] = 'shop'
        osm_type_table['osm_subtype'] = object:grab_tag('shop')
    elseif object.tags.amenity then
        osm_type_table['osm_type'] = 'amenity'
        osm_type_table['osm_subtype'] = object:grab_tag('amenity')
    elseif object.tags.building then
        osm_type_table['osm_type'] = 'building'
        osm_type_table['osm_subtype'] = object:grab_tag('building')
    elseif object.tags.leisure then
        osm_type_table['osm_type'] = 'leisure'
        osm_type_table['osm_subtype'] = object:grab_tag('leisure')
    elseif object.tags.landuse then
        osm_type_table['osm_type'] = 'landuse'
        osm_type_table['osm_subtype'] = object:grab_tag('landuse')
    elseif object.tags.natural then
        osm_type_table['osm_type'] = 'natural'
        osm_type_table['osm_subtype'] = object:grab_tag('natural')
    elseif object.tags.man_made then
        osm_type_table['osm_type'] = 'man_made'
        osm_type_table['osm_subtype'] = object:grab_tag('man_made')
    elseif object.tags.tourism then
        osm_type_table['osm_type'] = 'tourism'
        osm_type_table['osm_subtype'] = object:grab_tag('tourism')
    elseif object.tags.historic then
        osm_type_table['osm_type'] = 'historic'
        osm_type_table['osm_subtype'] = object.tags['historic']
    else
        -- Cannot be NULL
        osm_type_table['osm_type'] = 'Unknown'
        osm_type_table['osm_subtype'] = 'Unknown'
    end

    return osm_type_table
end
