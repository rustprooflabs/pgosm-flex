# Troubleshoot errors in osm2pgsql processing

This section contains rough notes about how to troubleshoot errors in PgOSM Flex.

## Reduce `--ram`

If you encounter an unusual failure during the `osm2pgsql` step of PgOSM Flex,
try reducing the `--ram` value.  Choosing a `--ram` option too high can cause
the process to fail with a variety of unexpected errors.  If that isn't the problem,
continue reading. 


## Docker logs

Output such as this.

```bash
2023-02-26 22:14:31,760:INFO:pgosm-flex:helpers:Processing: Node(10k 10.0k/s) Way(0k 0.00k/s) Relation(0Processing: Node(84760k 277.9k/s) Way(0k 0.00k/s) Relation(0 0.0/s)
2023-02-26 22:14:31,774:ERROR:pgosm-flex:pgosm_flex:Failed to run osm2pgsql. Return code: -9
Failed to run osm2pgsql. Return code: -9 - Check the log output for details
```


Checking logs from Docker might shed light on issue.

```bash
docker logs pgosm
```

```
2023-02-26 22:14:31.777 UTC [114] LOG:  incomplete message from client
2023-02-26 22:14:31.777 UTC [114] CONTEXT:  COPY tags, line 1
2023-02-26 22:14:31.777 UTC [114] STATEMENT:  COPY "osm"."tags" ("geom_type","osm_id","tags") FROM STDIN
2023-02-26 22:14:31.807 UTC [114] ERROR:  unexpected EOF on client connection with an open transaction
2023-02-26 22:14:31.807 UTC [114] CONTEXT:  COPY tags, line 1
2023-02-26 22:14:31.807 UTC [114] STATEMENT:  COPY "osm"."tags" ("geom_type","osm_id","tags") FROM STDIN
2023-02-26 22:14:31.812 UTC [114] FATAL:  terminating connection because protocol synchronization was lost
2023-02-26 22:14:31.822 UTC [114] LOG:  could not send data to client: Broken pipe
```

## Troubleshoot within Docker

Enter the docker container into `/bin/bash`.

```bash
docker exec -it pgosm /bin/bash
```

Set environment variables required for PgOSM Flex's operation.

```bash
export PGOSM_CONN=postgresql://postgres:mysecretpassword@localhost:5432/pgosm?application_name=pgosm-flex
export PGOSM_REPLICATION=False
export PGOSM_IMPORT_UUID=this-is-not-a-real-uuid
export PGOSM_LAYERSET=minimal
```

Run `osm2pgsql` manually.  Start with a simple operation shown below,
consider adding adding `-v` and/or `--log-sql-data` to the `osm2pgsql` command
to dig deeper.

```bash
osm2pgsql -d $PGOSM_CONN \
    --create --output=flex --style=./run.lua \
    /app/output/district-of-columbia-latest.osm.pbf
```

## Configure more things

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex:{{ pgosm_flex_version }} \
    -c shared_buffers=1GB \
    -c work_mem=50MB \
    -c maintenance_work_mem=10GB \
    -c autovacuum_work_mem=2GB \
    -c checkpoint_timeout=300min \
    -c max_wal_senders=0 -c wal_level=minimal \
    -c max_wal_size=10GB \
    -c checkpoint_completion_target=0.9 \
    -c random_page_cost=1.0 \
    -c full_page_writes=off \
    -c fsync=off \
    -c log_statement=all \
    -c log_duration=on
```


