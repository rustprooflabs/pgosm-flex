# Postgres permissions for PgOSM Flex

These instructions show an example of setting up a database
for use with PgOSM Flex.  This should work for both
[MANUAL-STEPS-RUN.md](MANUAL-STEPS-RUN.md) and
[DOCKER-RUN.md](DOCKER-RUN.md) instructions.

## Create database and PostGIS

These first steps require elevated permissions within Postgres.
`CREATE DATABASE` requires the `CREATEDB` permission, however
creating the PostGIS extension requires
[Postgres superuser permissions](https://blog.rustprooflabs.com/2021/12/postgis-permissions-required).


In the target Postgres instance, create your database.

```sql
CREATE DATABASE your_db_name;
```

In `your_db_name` create the PostGIS extension.


```sql
CREATE EXTENSION postgis;
```


## Runtime permissions

Your target database needs to have an `osm` schema and the database user
requires the ability to create and populate tables in `osm`.

The following commands show one approach to granting permissions
required for PgOSM Flex to run on an external database.
Do not simply run this assuming this is the proper approach
for your database security!



```sql
CREATE ROLE pgosm_flex WITH LOGIN PASSWORD 'mysecretpassword';
CREATE SCHEMA osm AUTHORIZATION pgosm_flex;
GRANT CREATE ON DATABASE your_db_name
    TO pgosm_flex;
```

These permissions should allow the full PgOSM Flex process to run.


`GRANT CREATE` is required to allow the sqitch process to run and create the `pgosm` schema.



## Reduced permissions

`GRANT CREATE` gives the `pgosm_flex` role far more permissions than
it really needs in many cases. 
Running `docker exec` with `--data-only` skips these steps and would make the `GRANT CREATE` permission unnessecary for the `pgosm_flex` role.

It also is often desired to not make
a login role the owner of database objects. This example reduces the
scope of permissions.


```sql
CREATE ROLE pgosm_flex;
CREATE SCHEMA osm AUTHORIZATION pgosm_flex;
GRANT pgosm_flex TO your_login_role;
```

