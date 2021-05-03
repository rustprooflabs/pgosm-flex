#!/bin/bash
echo "Running PgOSM-Flex extra region loads"

set -e

if [ -z $PGOSM_CONN ]; then
  PGOSM_CONN=pgosm_tests
else
  PGOSM_CONN=$PGOSM_CONN
fi

if [ -z $PGOSM_CONN_PG ]; then
  PGOSM_CONN_PG=postgres
else
  PGOSM_CONN_PG=$PGOSM_CONN_PG
fi

DATA_PATH=data/extra-regions

for filename in ${DATA_PATH}/*.osm.pbf; do
    #file_base=$(basename "${filename}" .osm.pbf)
    #echo $file_base
    echo $filename

    echo 'Dropping test DB pgosm_tests'
    psql -d $PGOSM_CONN_PG -c "DROP DATABASE pgosm_tests;" || true

    echo 'Creating test DB pgosm_tests'
    psql -d $PGOSM_CONN_PG -c "CREATE DATABASE pgosm_tests;"
    psql -d $PGOSM_CONN -c "CREATE EXTENSION postgis; CREATE SCHEMA osm;"

    original_dir=$PWD
    echo $original_dir

    cd ../flex-config
    osm2pgsql --slim --drop -d ${PGOSM_CONN} \
        --output=flex --style=run-all.lua \
        ../tests/${filename}

    cd $original_dir

done

