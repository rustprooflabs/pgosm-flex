#!/bin/bash
# Runs basic queries against PgOSM-Flex data in PostGIS.

echo "Running PgOSM-Flex regression tests"

# Ensure tmp/ directory exists


for filename in sql/*.sql; do
    echo "${filename}"

    # Run psql --no-psqlrc -tA > tmp/file.out

    # git diff --no-index tmp/file.out expected/file.out

    # ^^^^ If there's a diff ^^^
    #Report it


    ## If not... :)


done

echo "regression tests complete? (Not really, they don't do anything yet...)"