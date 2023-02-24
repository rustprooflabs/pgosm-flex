# Configure Postgres inside Docker

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
