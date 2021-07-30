# Run Unit tests

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
coverage report -m webapp/*.py
```


