# Using PgOSM Flex

This README provides details about running PgOSM Flex using the image defined
in `Dockerfile` and the script loaded from `docker/pgosm_flex.py`.



## Use custom layersets

See [LAYERSETS.md](LAYERSETS.md) for details about creating custom layersets.


## Skip nested place polygons

The nested place polygon calculation
([explained in this post](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis))
adds minimal overhead to smaller regions, e.g. Colorado with a 225 MB PBF input file.
Larger regions, such as North America (12 GB PBF),
are impacted more severely as a difference in processing time.
Calculating nested place polygons for Colorado adds less than 30 seconds on an 8 minute process,
taking about 5% longer.
A larger region, such as North America, can take 33% longer adding more than
an hour and a half to the total processing time.
See [docs/PERFORMANCE.md](PERFORMANCE.md) for more details.


Use `--skip-nested` to bypass the calculation of nested admin polygons.


## Use `--pg-dump` to export data

> The `--pg-dump` option was added in 0.7.0.  Prior versions defaulted to using `pg_dump` and provided a `--skip-dump` option to override.  The default now is to only use `pg_dump` when requested.  See [#266](https://github.com/rustprooflabs/pgosm-flex/issues/266) for more.


A `.sql` file can be created using `pg_dump` as part of the processing
for easy loading into one or more external Postgres databases.
Add `--pg-dump` to the `docker exec` command to enable this feature.

The following example
creates an empty `myosm` database to load the processed and dumped OpenStreetMap
data.


```bash
psql -d postgres -c "CREATE DATABASE myosm;"
psql -d myosm -c "CREATE EXTENSION postgis;"

psql -d myosm \
    -f ~/pgosm-data/pgosm-flex-north-america-us-district-of-columbia-default-2023-01-21.sql
```

> The above assumes a database user with `superuser` permissions is used. See [docs/POSTGRES-PERMISSIONS.md](POSTGRES-PERMISSIONS.md) for a more granular approach to permissions.


## Configure Postgres inside Docker

Add customizations with the `-c` switch, e.g. `-c shared_buffers=1GB`,
to customize Postgres' configuration at run-time in Docker.
See the [osm2pgsql documentation](https://osm2pgsql.org/doc/manual.html#preparing-the-database)
for recommendations on a server with 64 GB of RAM.

This `docker run` command has been tested with 16GB RAM and 4 CPU (8 threads) with the Colorado
subregion.  Configuring Postgres in-Docker runs 7-14% faster than the default
Postgres in-Docker configuration.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex \
    -c shared_buffers=512MB \
    -c work_mem=50MB \
    -c maintenance_work_mem=4GB \
    -c checkpoint_timeout=300min \
    -c max_wal_senders=0 -c wal_level=minimal \
    -c max_wal_size=10GB \
    -c checkpoint_completion_target=0.9 \
    -c random_page_cost=1.0
```


The `docker exec` command used for the timings.

```bash
time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=colorado \
    --layerset=basic \
    --pgosm-date=2021-10-08
```


## Monitoring the import

You can track the query activity in the database being loaded using the
`pg_stat_activity` view from `pg_catalog`.  Database connections use
`application_name = 'pgosm_flex'`.


```sql
SELECT *
    FROM pg_catalog.pg_stat_activity
    WHERE application_name = 'pgosm-flex'
;
```


