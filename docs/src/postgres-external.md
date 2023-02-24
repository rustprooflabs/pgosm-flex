# Using External Postgres Connection



Prepare the database and permissions as described in
[Postgres Permissions](postgres-permissions.md).


Set environment variables to define the connection.  Create a file with the
configuration options.

```bash
touch ~/.pgosm-db-myproject
chmod 0700 ~/.pgosm-db-myproject
nano ~/.pgosm-db-myproject
```

Put in the contents specific to your database connection.

```bash
export POSTGRES_USER=your_login_role
export POSTGRES_PASSWORD=mysecretpassword
export POSTGRES_HOST=your-host-or-ip
export POSTGRES_DB=your_db_name
export POSTGRES_PORT=5432
```

Env vars can be loaded using `source`.

```bash
source ~/.pgosm-db-myproject
```


Run the container with the additional environment variables.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -e POSTGRES_HOST=$POSTGRES_HOST \
    -e POSTGRES_DB=$POSTGRES_DB \
    -e POSTGRES_PORT=$POSTGRES_PORT \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```



The `docker exec` command is the same as when using the internal Postgres instance.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```




## Notes


The `POSTGRES_HOST` value is in relation to the Docker container.
Using `localhost` refers to the Docker container and will use the Postgres instance
within the Docker container, not your host running the Docker container.
Use `ip addr` to find your local host's IP address and provide that.



Setting `POSTGRES_HOST` to anything but `localhost` disables the drop/create database step. This means the target database must be created prior to running PgOSM Flex.

