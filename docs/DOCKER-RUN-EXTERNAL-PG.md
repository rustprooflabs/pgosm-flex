# Experimental: PgOSM Flex in Docker with External Postgres connection

----


WARNING: Using PgOSM Flex in this manner is experimental and results
may differ from expecations.

----


Optional, set Postgres host outside of Docker image.  Warning: experimental!

```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword
export POSTGRES_HOST=your-host-or-ip
export POSTGRES_DB=your_db_name
export POSTGRES_PORT=5432
```

Create the database.

```sql
CREATE DATABASE your_db_name;"
```

The target database needs the `postgis` extension and the `osm` schema created.


```sql
CREATE EXTENSION postgis;
CREATE SCHEMA osm;"
```


WARNING:  DB Name and Port are currently hard coded to `pgosm` and `5432`.
The above setting is for planned, not yet implemented, behavior.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -e POSTGRES_HOST=$POSTGRES_HOST \
    -e POSTGRES_DB=$POSTGRES_DB \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

Either setup DB following manual steps OR Run PgOSM Flex Docker one time normally.
After the database is setup (and should no longer be dropped!), add the
`--skip-db-prep` switch to `docker exec`.



```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --skip-db-prep
```



