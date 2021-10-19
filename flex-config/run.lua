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

local unitable = conf['layerset']['unitable']
local tags = conf['layerset']['tags']



-- Establish connection to Postgres
con = assert (env:connect(pgosm_conn))
cur = con:execute"SELECT version() AS pg_version;"

row = cur:fetch ({}, "a")
while row do
  print(string.format("Postgres version: %s", row.pg_version))
  -- reusing the table of results
  row = cur:fetch (row, "a")
end




if unitable then
    print('Yes unitable')
    require "style.unitable"

    local sql_file = io.open("sql/unitable.sql", "r")
    sql_raw = sql_file:read( "*all" )
    sql_file:close()
    print(sql_raw)
    -- This does not appear to be working yet...
    -- Could be tricky executing scripts with multiple queries... was hoping it would
    -- just work.
    local result = con:execute(sql_raw)
else
    print('no unitable :(')
end

if tags then
    print('Yes tags')
else
    print('no tags :(')
end

require "style.pgosm-meta"








-- close everything
cur:close() -- already closed because all the result set was consumed
con:close()
env:close()
