# PgOSM Flex: Dump and reload data

> These manual procedures (outside of Docker) are not regularly tested or reviewed. The recommended way to use PgOSM Flex is through the Docker image.  The Docker image is capable of renaming the schema and running pg_dump when desired.

----

To move data loaded on one Postgres instance to another, use `pg_dump`.
The import from PBF to PostGIS is far more taxing on resources than general
querying of the data requires.  One common approach is to use a temporary cloud
server with additional resources to process and prepare the data, then dump
and restore the data onto a production Postgres instance for use.

## (optional) Rename schema 

If the desired schema name is different from `osm` the schema can be renamed
at this point.  If the schema is renamed, adjust the following `pg_dump`
to change `--schema=` as well.


```sql
ALTER SCHEMA osm RENAME TO some_other_schema_name;
```


## pg_dump

Create a directory to export.  Using `-Fd` for directory format to allow using
`pg_dump`/`pg_restore` with multiple processes (`-j 4`).  For the small data set for
Washington D.C. used here this isn't necessary, though can seriously speed up with larger areas, e.g. Europe or North America.

```bash
mkdir -p ~/tmp/osm_dc
pg_dump --schema=osm --schema=pgosm \
    -d pgosm \
    -Fd -j 4 \
    -f ~/tmp/osm_dc
tar -cvf osm_dc.tar -C ~/tmp osm_dc
```

## pg_restore

Move the `.tar` if needed.  Untar and restore.


```bash
tar -xvf osm_eu.tar
pg_restore -j 4 -d pgosm_eu -Fd osm_eu/
```

