print('Hello!!')
local inifile = require('inifile')
local driver = require('luasql.postgres')
local env = driver.postgres()

local pgosm_conn_env = os.getenv("PGOSM_CONN")
local pgosm_conn = nil

if pgosm_conn_env then
    pgosm_conn = pgosm_conn_env
else
    error('ENV VAR PGOSM_CONN must be set.')
end


conf = inifile.parse('default.ini')


local function post_processing(layerset)
	print(string.format('Post-processing %s', layerset))
	local filename = string.format('sql/%s.sql', layerset)
    local sql_file = io.open(filename, 'r')
    sql_raw = sql_file:read( '*all' )
    sql_file:close()
    local result = con:execute(sql_raw)
    --print(result) -- Returns 0.0 on success?  nil on error?
end



-- Establish connection to Postgres
con = assert (env:connect(pgosm_conn))

-- simple query to verify connection
cur = con:execute"SELECT version() AS pg_version;"

row = cur:fetch ({}, "a")
while row do
  print(string.format("Postgres version: %s", row.pg_version))
  -- reusing the table of results
  row = cur:fetch (row, "a")
end


if conf['layerset']['road'] then
    post_processing('road')
end

if conf['layerset']['road_major'] then
    post_processing('road_major')
end

if conf['layerset']['tags'] then
    post_processing('tags')
end

if conf['layerset']['unitable'] then
    post_processing('unitable')
end



-- close everything
cur:close()
con:close()
env:close()
