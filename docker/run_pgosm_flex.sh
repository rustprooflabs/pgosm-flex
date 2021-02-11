#!/bin/bash
# Run with:  
#   ./run_pgosm_flex.sh \
#       north-america/us \
#       district-of-columbia \
#       4000 \
#       run-all
#
# $1 - Region - e.g. north-america/us
# $2 - Subregion - e.g. district-of-columbia 
# $3 - Cache (mb) - e.g. 4000
# $4 - Layers to load - must match flex-config/$4.lua and flex-config/$4.sql

BASE_PATH=/app/
SQITCH_PATH=/app/db/
OUT_PATH=/app/output/
FLEX_PATH=/app/flex-config

# Naming scheme must match Geofabrik's for MD5 sums to validatate
PBF_FILE=$OUT_PATH$2-latest.osm.pbf
MD5_FILE=$OUT_PATH$2-latest.osm.pbf.md5

LOG_FILE=$OUT_PATH$2.log

echo "Monitor $LOG_FILE for progress..."
echo "If paths setup as outlined in README.md, use:"
echo "    tail -f ~/pgosm-data/$2.log"

ALWAYS_DOWNLOAD=${PGOSM_ALWAYS_DOWNLOAD:-0}


echo "" >> $LOG_FILE
echo "---------------------------------" >> $LOG_FILE
echo "Start PgOSM-Flex processing" >> $LOG_FILE
echo "Region:  $1" >> $LOG_FILE
echo "Sub-Region:  $2" >> $LOG_FILE
echo "Cache: $3" >> $LOG_FILE
echo "PgOSM Flex Style: $4" >> $LOG_FILE


if [ $ALWAYS_DOWNLOAD == "1" ]; then
  echo 'Removing PBF and md5 files if exists...' >> $LOG_FILE
  BE_NICE = 'NOTE: Be nice to Geofabrik''s download server!'
  echo "$BE_NICE" >> $LOG_FILE
  echo "$BE_NICE"
  rm $PBF_FILE
  rm $MD5_FILE
fi

if [ -f $PBF_FILE ]; then
    echo "$PBF_FILE exists. Not downloading."  >> $LOG_FILE
else 
    echo "$PBF_FILE does not exist.  Downloading..."  >> $LOG_FILE
    wget https://download.geofabrik.de/$1/$2-latest.osm.pbf -O $PBF_FILE --quiet &>> $LOG_FILE
fi

if [ -f $MD5_FILE ]; then
  echo "$MD5_FILE exists. Not downloading."  >> $LOG_FILE
else
  echo "$MD5_FILE does not exist.  Downloading..." >> $LOG_FILE
  wget https://download.geofabrik.de/$1/$2-latest.osm.pbf.md5 -O $MD5_FILE --quiet &>> $LOG_FILE
fi


if [ -z $PGOSM_DATA_SCHEMA_ONLY ]; then
  echo "DATA_SCHEMA_ONLY NOT SET"
  DATA_SCHEMA_ONLY=false
else
  DATA_SCHEMA_ONLY=$PGOSM_DATA_SCHEMA_ONLY
  echo "DATA_SCHEMA_ONLY set to $DATA_SCHEMA_ONLY"
fi

if [ -z $PGOSM_DATA_SCHEMA_NAME ]; then
  echo "PGOSM_DATA_SCHEMA_NAME NOT SET"
  DATA_SCHEMA_NAME="osm"
else
  DATA_SCHEMA_NAME=$PGOSM_DATA_SCHEMA_NAME
  echo "DATA_SCHEMA_NAME set to $DATA_SCHEMA_NAME"
fi

if cd $OUT_PATH && md5sum -c $MD5_FILE; then
    echo 'MD5 checksum validated' >> $LOG_FILE
else
    ERR_MSG = 'ERROR - MD5 sum did not match.  Try re-running with PGOSM_ALWAYS_DOWNLOAD=1'
    echo "$ERR_MSG" >> $LOG_FILE
    echo "$ERR_MSG"
    exit 1
fi


echo "Create empty pgosm database with extensions..." >> $LOG_FILE
psql -U postgres -c "DROP DATABASE IF EXISTS pgosm;" >> $LOG_FILE
psql -U postgres -c "CREATE DATABASE pgosm;" >> $LOG_FILE
psql -U postgres -d pgosm -c "CREATE EXTENSION postgis;" >> $LOG_FILE
psql -U postgres -d pgosm -c "CREATE SCHEMA osm;" >> $LOG_FILE

echo "Deploy schema via Sqitch..." >> $LOG_FILE
cd $SQITCH_PATH
su -c "sqitch deploy db:pg:pgosm" postgres >> $LOG_FILE
echo "Loading US Roads helper data" >> $LOG_FILE
psql -U postgres -d pgosm -f data/roads-us.sql >> $LOG_FILE


REGION="$1--$2"
echo "Setting PGOSM_REGION to $REGION" >> $LOG_FILE
export PGOSM_REGION=$REGION

osm2pgsql --version >> $LOG_FILE

echo "Running osm2pgsql..." >> $LOG_FILE
cd $FLEX_PATH
osm2pgsql -U postgres --create --slim --drop \
  --cache $3 \
  --output=flex --style=./$4.lua \
  -d pgosm  $PBF_FILE &>> $LOG_FILE

echo "Running post-processing SQL script..." >> $LOG_FILE
psql -U postgres -d pgosm -f $4.sql >> $LOG_FILE

if [ $DATA_SCHEMA_NAME != "osm" ]; then
    echo "Changing schema name from osm to $DATA_SCHEMA_NAME" >> $LOG_FILE
    psql -U postgres -d pgosm \
      -c "ALTER SCHEMA osm RENAME TO $DATA_SCHEMA_NAME;"
fi

cd $BASE_PATH

OUT_NAME="pgosm-flex-$2-$4.sql"
OUT_PATH="/app/output/$OUT_NAME"

if $DATA_SCHEMA_ONLY; then
  echo "Running pg_dump, only data schema..." >> $LOG_FILE
  pg_dump -U postgres -d pgosm \
     --schema=$DATA_SCHEMA_NAME > $OUT_PATH
else
  echo "Running pg_dump including pgosm schema..." >> $LOG_FILE
  pg_dump -U postgres -d pgosm \
     --schema=$DATA_SCHEMA_NAME --schema=pgosm > $OUT_PATH
fi

echo "PgOSM processing complete. Final output file: $OUT_PATH" >> $LOG_FILE
echo "PgOSM processing complete. Final output file: $OUT_PATH"
echo "If you followed the README.md it is at: ~/pgosm-data/$OUT_NAME"

exit 0