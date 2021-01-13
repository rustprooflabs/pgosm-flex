require "helpers"

local tables = {}

local pgosm_flex_version = '0.0.6-dev'
local project_url = 'https://github.com/rustprooflabs/pgosm-flex'


tables.pgosm_flex_meta = osm2pgsql.define_table({
    name = 'pgosm_flex',
    schema = schema_name,
    columns = {
        { column = 'pgosm_flex_version',     type = 'text', not_null = true },
        { column = 'srid',     type = 'text', not_null = true },
        { column = 'project_url',     type = 'text', not_null = true },
    }
})


-- Couldn't find a better way to only add one row from Lua, adds one row then flips meta_added.
local meta_added = false
function pgosm_meta_load_row(object)
    if meta_added then
        return
    end

    tables.pgosm_flex_meta:add_row({
        pgosm_flex_version = pgosm_flex_version,
        srid = srid,
        project_url = project_url
    })

    meta_added = true
end

-- Choice of way was arbitrary.  Could use relation or node.
if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = pgosm_meta_load_row
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        pgosm_meta_load_row(object_copy)
    end
end
