#!/bin/bash
# Runs basic queries against PgOSM-Flex data in PostGIS.

echo "Running PgOSM-Flex test queries"

if [ ! -d tmp ]; then
  mkdir -p tmp;
fi

if [ -z $POSTGRES_USER ]; then
  POSTGRES_USER=postgres
fi

APP_STR="?application_name=pgosm-flex-tests"

if [ -z $POSTGRES_PASSWORD ]; then
  PGOSM_CONN="postgresql://${POSTGRES_USER}@localhost/pgosm${APP_STR}"
else
  PGOSM_CONN="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost/pgosm${APP_STR}"
fi

failed=false

for filename in sql/*.sql; do
    file_base=$(basename "${filename}" .sql)
    tmp_out="tmp/${file_base}.out"
    diff_file="tmp/${file_base}.diff"

    psql -d $PGOSM_CONN --no-psqlrc -tA -f ${filename} > ${tmp_out}

    git diff --no-index \
        expected/${file_base}.out tmp/${file_base}.out \
        > ${diff_file}

    if [ -s tmp/${file_base}.diff ]; then
        echo "FAILED TEST: ${filename} - See ${diff_file}"
        echo "  docker exec -it pgosm /bin/bash -c \"cat /app/tests/${diff_file} \" "
        failed=true
    else
        # no reason to keep empty files around
        rm ${diff_file}
    fi

done

if $failed; then
    echo "One or more data output tests failed."
else
    echo "Data output tests completed successfully."
fi