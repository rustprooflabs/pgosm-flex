require "helpers"

local driver = require('luasql.postgres')
local env = driver.postgres()

local pgosm_conn_env = os.getenv("PGOSM_CONN")
local pgosm_conn = nil

if pgosm_conn_env then
    pgosm_conn = pgosm_conn_env
else
    error('ENV VAR PGOSM_CONN must be set.')
end

local pgosm_replication_env = os.getenv("PGOSM_REPLICATION")

if pgosm_replication_env then
    pgosm_replication = pgosm_replication_env
else
    error('ENV VAR PGOSM_REPLICATION must be set')
end

local import_uuid = os.getenv("PGOSM_IMPORT_UUID")

local tables = {}


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
print ('FIXME - This section is moving to Python to be tracked in the DB!')
print ('PgOSM-Flex version:', git_tag, commit_hash)

local osm2pgsql_version = osm2pgsql.version
local osm2pgsql_mode = osm2pgsql.mode

local pgosm_flex_version = git_tag .. '-' .. commit_hash

