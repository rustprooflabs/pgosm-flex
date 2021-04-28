#!/bin/bash
# Runs basic queries against PgOSM-Flex data in PostGIS.

echo "Running PgOSM-Flex test queries"

if [ ! -d tmp ]; then
  mkdir -p tmp;
fi

if [ -z $PGOSM_CONN ]; then
  PGOSM_CONN=pgosm
  echo "Env var not set: PGOSM_CONN. Using default: $PGOSM_CONN"
else
  PGOSM_CONN=$PGOSM_CONN
  echo "PGOSM_CONN set to $PGOSM_CONN"
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
        failed=true
    else
        # no reason to keep empty files around
        rm ${diff_file}
    fi

done

if $failed; then
    echo "One or more tests failed."
else
    echo "Tests completed successfully."
fi