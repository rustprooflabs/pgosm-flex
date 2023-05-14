# Force Load

PgOSM Flex attempts to avoid accidentally overwriting existing data
when using a database
[external to](./postgres-external.md) the PgOSM Flex Docker container.

> Added in PgOSM Flex 0.8.1.


## PgOSM Tries to be Safe

Assumes you have followed the instructions on the
[Postgres External section](./postgres-external.md).



```bash
source ~/.pgosm-db-myproject

docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -e POSTGRES_HOST=$POSTGRES_HOST \
    -e POSTGRES_DB=$POSTGRES_DB \
    -e POSTGRES_PORT=$POSTGRES_PORT \
    -p 5433:5432 -d rustprooflabs/pgosm-flex

docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```

Running the `docker exec` step a second time would result in
the following error.

```bash
2023-05-14 14:59:33,145:WARNING:pgosm-flex:import_mode:A prior import exists.
Not okay to run PgOSM Flex. Exiting
```

To overwrite and reload data, use the `--force` option.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --force
```

## Using `--force`

This outputs the following message during import.

```
2023-05-14 15:09:12,457:WARNING:pgosm-flex:import_mode:Using --force, kiss existing data goodbye
```



