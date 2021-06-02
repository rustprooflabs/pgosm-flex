require "helpers"

local tables = {}


tables.pgosm_flex_meta = osm2pgsql.define_table({
    name = 'pgosm_flex',
    schema = schema_name,
    columns = {
        { column = 'osm_date',            sql_type = 'date', not_null = true },
        { column = 'default_date',        type = 'bool', not_null = true },
        { column = 'region',              type = 'text', not_null = true},
        { column = 'pgosm_flex_version',  type = 'text', not_null = true },
        { column = 'srid',                type = 'text', not_null = true },
        { column = 'project_url',         type = 'text', not_null = true },
        { column = 'osm2pgsql_version',   type = 'text', not_null = true}
    }
})


function pgosm_get_commit_hash()
    local cmd = 'git rev-parse --short HEAD'
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    result = string.gsub(result, "\n", "")
    return result
end

function pgosm_get_latest_tag()
    local cmd = 'git describe --abbrev=0'
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    result = string.gsub(result, "\n", "")
    return result
end


local commit_hash = pgosm_get_commit_hash()
local git_tag = pgosm_get_latest_tag()
local osm2pgsql_version = osm2pgsql.version
print ('PgOSM-Flex version:', git_tag, commit_hash)
local pgosm_flex_version = git_tag .. '-' .. commit_hash
local project_url = 'https://github.com/rustprooflabs/pgosm-flex'


-- Couldn't find a better way to only add one row from Lua, adds one row then flips meta_added.
local meta_added = false
function pgosm_meta_load_row(object)
    if meta_added then
        return
    end

    tables.pgosm_flex_meta:add_row({
        pgosm_flex_version = pgosm_flex_version,
        srid = srid,
        project_url = project_url,
        osm2pgsql_version = osm2pgsql_version,
        osm_date = pgosm_date,
        default_date = default_date,
        region = pgosm_region,
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
