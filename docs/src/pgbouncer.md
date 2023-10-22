# pgBouncer

The PgOSM Flex Docker image now includes pgBouncer.

> Experimental Feature!  pgBouncer was added as an experimental feature in
> PgOSM Flex 0.10.3.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:6432 \ # Port for pgBouncer instead of base Postgres
    -d rustprooflabs/pgosm-flex
```

Running

```bash
time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
        --ram=8 \
        --region=north-america/us \
        --subregion=district-of-columbia \
        --pgbouncer-pool-size=10
```


