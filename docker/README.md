# PgOSM Flex in Docker

This readme contains development/testing related notes.

Requires:

* Python 3.7 or newer
* Postgres running locally
* Role with createdb permissions
* Understand `pgosm` database will be dropped/recreated


## Python app

Example running locally.

If `~/.pgpass` is configured, set your user.

```bash
export POSTGRES_USER=your_db_user
```

To set your password via environment variable.

```bash
export POSTGRES_PASSWORD=supersecurepassword123
```



```python
python3 pgosm_flex.py  \
 --layerset=run-all --ram=8 \
 --region=north-america/us \
  --subregion=district-of-columbia \
  --debug
```


## Run Unit tests

Requires Python packages installed by `Dockerfile`. Look for `
RUN pip install` and install those in a `venv` named `pgosm`.

### Run unit tests normally.

```bash
source ~/venv/pgosm/bin/activate
cd  ~/git/pgosm-flex
python -m unittest tests/*.py
```

### Or, run unit tests with coverage.

```bash
source ~/venv/pgosm/bin/activate
cd  ~/git/pgosm-flex
coverage run -m unittest tests/*.py
```

### Run coverage report with % missing calculated.


```bash
coverage report -m ./*.py
```

### Pylint


```bash
pylint --rcfile=./.pylintrc ./*.py
```
