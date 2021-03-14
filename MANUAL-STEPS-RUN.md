

## Standard Import

These instructions show how to manually run the PgOSM-Flex process.
This is the best option for scaling to larger regions (North America, Europe, etc.)
due to the need to customize a number of configurations.  Review the
`docker/run_pgosm_flex.sh` for a starting point to automating the process.

This basic working example uses Washington D.C. for a small, fast test of the
process.

> Loading the full data set with `run-all` as shown here results in a lot of data.  See [the instructions in LOAD-DATA.md](LOAD-DATA.md) for more ways to use and customize PgOSM-Flex.

### Ubuntu Pre-reqs

This section covers installation of prerequisites required to install Postgres,
osm2pgsql, and PgOSM-Flex on Ubuntu 20.04.  The only pre-req specific to PgOSM-Flex
itself is `lua-dkjson` to allow loading the `tags` column to Postgres
using the built-in `JSONB` data type instead of using the legacy `HSTORE` extension.
See the blog post
[Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis)
for more on this decision.
If you do not want to install / use JSON you can skip the tags table by
using `run-no-tags` instead of `run-all`.


```bash
sudo apt update
sudo apt install -y \
        sqitch wget curl ca-certificates \
        git make cmake g++ \
        libboost-dev libboost-system-dev \
        libboost-filesystem-dev libexpat1-dev zlib1g-dev \
        libbz2-dev libpq-dev libproj-dev lua5.2 liblua5.2-dev \
        lua-dkjson
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

### Prepare data / database

Download the PBF file and MD5 from Geofabrik.

```bash
mkdir ~/tmp
cd ~/tmp
wget https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf
wget https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf.md5
```

Verify integrity of the downloaded PBF file using `md5sum -c`.

```bash
md5sum -c district-of-columbia-latest.osm.pbf
district-of-columbia-latest.osm.pbf: OK
```

Prepare the `pgosm` database in Postgres.
Need to create the `postgis` extension and the `osm` schema.

```bash
psql -c "CREATE DATABASE pgosm;"
psql -d pgosm -c "CREATE EXTENSION postgis; CREATE SCHEMA osm;"
```


### Run osm2pgsql w/ PgOSM-Flex

The PgOSM-Flex styles from this project are required to run the following.
Clone the repo and change into the directory containing
the `.lua` and `.sql` scripts.


```bash
mkdir ~/git
cd ~/git
git clone https://github.com/rustprooflabs/pgosm-flex.git
cd pgosm-flex/flex-config
```

(Optional) Set the `PGOSM_DATE` env var to indicate the date the OpenStreetMap
data was sourced.  This is most helpful when the PBF file was saved
more than a couple days ago to indicate to users of the data when the data was from.  The default is to use the current date.

```bash
export PGOSM_DATE='2021-01-27'
```

The date is in the `osm.pgosm_flex` table.

```sql
SELECT osm_date FROM osm.pgosm_flex;
```

```bash
osm_date  |
----------|
2021-01-27|
```



The `run-all.lua` script provides the most complete set of OpenStreetMap
data.  The list of main tables in PgOSM-Flex will continue to grow and evolve.
See [LOAD-DATA.md](LOAD-DATA.md) for more about loading data.


```bash
cd pgosm-flex/flex-config

osm2pgsql --slim --drop \
    --output=flex --style=./run-all.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

After osm2pgsql completes the main load, run the matching SQL scripts. 
Each `.lua` has a matching `.sql` to create primary keys, indexes, comments,
views and more.

```bash
psql -d pgosm -f ./run-all.sql
```

> Note: The `run-all` scripts exclude `unitable` and `road_major`.

