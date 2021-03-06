# PgOSM-Flex Standard Import

These instructions show how to manually run the PgOSM-Flex process.
This is the best option for scaling to larger regions (North America, Europe, etc.)
due to the need to customize a number of configurations.  Review the
`docker/run_pgosm_flex.sh` for a starting point to automating the process.

This basic working example uses Washington D.C. for a small, fast test of the
process.

> Loading the full data set with `run-all` as shown here results in a lot of data.  See [the instructions in LOAD-DATA.md](LOAD-DATA.md) for more ways to use and customize PgOSM-Flex.

## Ubuntu Pre-reqs

This section covers installation of prerequisites required to install Postgres,
osm2pgsql, and PgOSM-Flex on Ubuntu 20.04.

```bash
sudo apt update
sudo apt install -y \
        sqitch wget curl ca-certificates \
        git make cmake g++ \
        libboost-dev libboost-system-dev \
        libboost-filesystem-dev libexpat1-dev zlib1g-dev \
        libbz2-dev libpq-dev libproj-dev lua5.2 liblua5.2-dev
```

Install osm2pgsql from source.

```bash
git clone git://github.com/openstreetmap/osm2pgsql.git
mkdir osm2pgsql/build
cd osm2pgsql/build
cmake ..
make
sudo make install
```

Add PGDG repo and install Postgres.  More [on Postgres Wiki](https://wiki.postgresql.org/wiki/Apt).

```bash
curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - 
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo apt-get update
sudo apt-get install postgresql-13 \
    postgresql-13-postgis-3 \
    postgresql-13-postgis-3-scripts
```

See the [osm2pgsql documentation](https://osm2pgsql.org/doc/manual.html#preparing-the-database) for advice on tuning Postgres configuration
for running osm2pgsql and Postgres on the same host.


## Download data

Download the PBF file and MD5 from Geofabrik.

```bash
mkdir ~/pgosm-data
cd ~/pgosm-data
wget https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf
wget https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf.md5
```

Verify integrity of the downloaded PBF file using `md5sum -c`.

```bash
md5sum -c district-of-columbia-latest.osm.pbf
district-of-columbia-latest.osm.pbf: OK
```

## Prepare database

The typical use case is to run osm2pgsql and Postgres/PostGIS on the same node.
When using Postgres locally, only add the database name to the connection strings.

```bash
export PGOSM_CONN_PG="postgres"
export PGOSM_CONN="pgosm"
```

To run with a non-local Postgres connection, use a connection string such as:

```bash
export PGOSM_CONN_PG="postgresql://your_user:password@your_postgres_host/postgres"
export PGOSM_CONN="postgresql://your_user:password@your_postgres_host/pgosm"
```

Create the `pgosm` database.

```bash
psql -d $PGOSM_CONN_PG -c "CREATE DATABASE pgosm;"
```

Create the `postgis` extension and the `osm` schema.

```bash
psql -d $PGOSM_CONN -c "CREATE EXTENSION postgis; CREATE SCHEMA osm;"
```


## Prepare PgOSM-Flex

The PgOSM-Flex styles from this project are required to run the following.
Clone the repo and change into the directory containing
the `.lua` and `.sql` scripts.


```bash
mkdir ~/git
cd ~/git
git clone https://github.com/rustprooflabs/pgosm-flex.git
cd pgosm-flex/flex-config
```


## Set PgOSM variables

*(Recommended)* 

Set the `PGOSM_DATE` and `PGOSM_REGION` env vars to indicate the
date and region of the downloaded OpenStreetMap data.
This data is saved in the `osm.pgosm_flex` table to allow end users in the resulting
data to know what each dataset should contain.


```bash
export PGOSM_DATE='2021-03-14'
export PGOSM_REGION='north-america/us--district-of-columbia'
```

These values show up in the `osm.pgosm_flex` table.

```sql
SELECT osm_date, region FROM osm.pgosm_flex;
```

```bash
┌────────────┬────────────────────────────────────────┐
│  osm_date  │                 region                 │
╞════════════╪════════════════════════════════════════╡
│ 2021-03-14 │ north-america/us--district-of-columbia │
└────────────┴────────────────────────────────────────┘
```

> Note:  See the [Customize PgOSM on the main README.md](https://github.com/rustprooflabs/pgosm-flex#customize-pgosm) for all runtime customization options.


## Run osm2pgsql w/ PgOSM-Flex

The `run-all.lua` script provides the most complete set of OpenStreetMap
data.  The list of main tables in PgOSM-Flex will continue to grow and evolve.
See [LOAD-DATA.md](LOAD-DATA.md) for more about loading data.



```bash
cd pgosm-flex/flex-config

osm2pgsql --slim --drop \
    --output=flex --style=./run-all.lua \
    -d $PGOSM_CONN \
    ~/pgosm-data/district-of-columbia-latest.osm.pbf
```

## Run post-processing SQL

Each `.lua` script as an associated `.sql` script to create 
primary keys, indexes, comments, views and more.


```bash
psql -d $PGOSM_CONN -f ./run-all.sql
```

> Note: The `run-all` scripts exclude `unitable` and `road_major`.


## Generated nested place polygons

*(Recommended)*

The post-processing SQL scripts create a procedure to calculate the nested place polygon data.  It does not run by default in the previous step because it can be expensive (slow) on large regions.


```bash
psql -d $PGOSM_CONN -c "CALL osm.build_nested_admin_polygons();"
```


# More options


## Load main tables, No Tags

As seen above, the `run_all.lua` style includes the tags table and then includes
`run-no-tags` to load the rest of the data.  If you want the main data
**without the full tags** table, use the `run-no-tags.lua` and `.sql` scripts instead.


```bash
osm2pgsql --slim --drop \
    --output=flex --style=./run-no-tags.lua \
    -d $PGOSM_CONN \
    ~/tmp/district-of-columbia-latest.osm.pbf

psql -d $PGOSM_CONN -f ./run-no-tags.sql
```


## Load individual layers

One layer at a time can be added with commands such as this.  This example includes
the `road_major` style followed by the `pgosm-meta` style to track osm2pgsql
and PgOSM-Flex versions used to load the data.

```bash
osm2pgsql --slim --drop \
    --output=flex --style=./style/road_major.lua \
    -d $PGOSM_CONN \
    ~/tmp/district-of-columbia-latest.osm.pbf

psql -d $PGOSM_CONN -f ./sql/road_major.sql
```



> WARNING:  Running multiple `osm2pgsql` commands requires processing the source PBF multiple times. This can waste considerable time on larger imports.  Further, attempting to define multiple styles with additional `--style=style.lua` switches results in only the last style being processed.  To mix and match multiple styles, create a custom Lua script similar to `run-all.lua` or `run-no-tags.lua`.



## Additional structure and helper data

**Optional**

Deploying the additional table structure is done via [sqitch](https://sqitch.org/).

Assumes this repo is cloned under `~/git/pgosm-flex/` and a local Postgres
DB named `pgosm` has been created with the `postgis` extension installed.

```bash
cd ~/git/pgosm-flex/db
sqitch deploy db:pg:pgosm
```

With the structures created, load helper road data.

```bash
cd ~/git/pgosm-flex/db
psql -d pgosm -f data/roads-us.sql
```


Currently only U.S. region drafted, more regions with local `maxspeed` are welcome via PR!

