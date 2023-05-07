# Stay Updated with Replication

The `--replication` option of PgOSM Flex enables `osm2pgsql-replication`
to provide an easy and quick way to keep your OpenStreetMap data refreshed.


> The `--replication` mode is stable as of 0.7.0.  It was added as an experimental feature in 0.4, originally under the `--append` option.


PgOSM Flex's `--replication` mode wraps around the `osm2pgsql-replication` package
included with `osm2pgsql`.  The first time running an import with `--replication`
mode runs osm2pgsql normally, with `--slim` mode and without `--drop`.
After osm2pgsql completes, `osm2pgsql-replication init ...` is ran to setup
the DB for updates.
This mode of operation results in larger database as the intermediate osm2pgsql
tables (`--slim`) must be left in the database (no `--drop`).


> Important:  The original `--append` option is now under `--replication`. The `--append` option was removed in PgOSM Flex 0.7.0.  See [#275](https://github.com/rustprooflabs/pgosm-flex/issues/275) for context.


When using replication you need to pin your process to a specific PgOSM Flex version
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
    -d rustprooflabs/pgosm-flex:{{ pgosm_flex_version }} \
        -c max_connections=300
```


Run the `docker exec` step with `--replication`.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --pgosm-date 2022-12-30 \
    --replication
```

Running the above command a second time will detect that the target database
has `osm2pgsql-replication` setup and load data via the defined replication
service.

> Note:  The `--pgosm-date` parameter is ignored during subsequent imports using `--replication`.

