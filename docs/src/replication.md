# Using Replication

The `--replication` option of PgOSM Flex enables `osm2pgsql-replication`
to provide an easy and quick way to keep your OpenStreetMap data refreshed.


PgOSM Flex's `--replication` mode wraps around the `osm2pgsql-replication` package
included with `osm2pgsql`.  The first time running an import with `--replication`
mode runs osm2pgsql normally, with `--slim` mode and without `--drop`.
After osm2pgsql completes, `osm2pgsql-replication init ...` is ran to setup
the DB for updates.
This mode of operation results in larger database as the intermediate osm2pgsql
tables (`--slim`) must be left in the database (no `--drop`).


> Important:  The original `--append` option is now under `--replication`. The `--append` option was removed in PgOSM Flex 0.7.0.  See [#275](https://github.com/rustprooflabs/pgosm-flex/issues/275) for context.

## Use tagged version

When using replication you should pin your process to a specific PgOSM Flex version
in the `docker run` command.  When upgrading to new versions,
be sure to check the release notes for manual upgrade steps for `--replication`.  
The release notes for
[PgOSM Flex 0.6.1](https://github.com/rustprooflabs/pgosm-flex/releases/tag/0.6.1)
are one example.
The notes discussed in the release notes have reference SQL scripts
under `db/data-migration` folder.  

----

**WARNING - Due to the ability to configure custom layersets these data-migration
scripts need manual review, and possibly manual adjustments for
your specific database and process.**

----

## Not tested by `make`

The function exposed by `--replication` is not tested via PgOSM's `Makefile`.



## Max connections

The other important change when using replication is to increase Postgres' `max_connections`.
See [this discussion on osm2pgsql](https://github.com/openstreetmap/osm2pgsql/discussions/1650)
for why this is necessary.

If using the Docker-internal Postgres instance this is done with `-c max_connections=300`
in the `docker run` command.  External database connections must update this
in the appropriate `postgresql.conf` file.


```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword

docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 \
    -d rustprooflabs/pgosm-flex:0.10.0 \
        -c max_connections=300
```

## Using `--replication`


Run the `docker exec` step with `--replication`.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --replication
```

Running the above command a second time will detect that the target database
has `osm2pgsql-replication` setup and load data via the defined replication
service.


## One replication source

Replication with PgOSM Flex is limited to one data source per database.
While it is possible to [load multiple regions](common-customization.html#schema-name),
each into their own schema
using `--schema-name`, replication via osm2pgsql-replication only supports
a single source.  See [this issue](https://github.com/openstreetmap/osm2pgsql/pull/1769)
for details.  Possibly this ability will be supported in the future.


## Resetting Replication

> ⚠️ WARNING! ⚠️ This section is <strong>only suitable for DEVELOPMENT databases</strong>.
> Do NOT USE on production databases!

Replication with PgOSM Flex `--replication` is simply a wrapper around the
`osm2pgsql-replication` tool. If you need to reload a <strong>development</strong>
database after using `--replication` you must remove the data from the
`public.osm2pgsql_properties` table.  If you do not remove this data,
PgOSM Flex will detect the replication setup and attempt to update data, not
load fresh.


```sql
DELETE FROM public.osm2pgsql_properties;
```

> WARNING: This process works as an okay hack when you are using the same layerset
> in the new import as was previously used.  If you use a layerset with fewer
> tables, the original tables from the original layerset will persist and can
> cause confusion about what was loaded.

