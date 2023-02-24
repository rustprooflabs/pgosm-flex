# Contributing

We encourage pull requests (PRs) from everyone.

Fork the project into your own repo, create a topic branch there and then make
one or more pull requests back to the main repository targeting the `dev` branch.
Your PR can then be reviewed and discussed.

Helpful: Run `make` in the project root directory and ensure tests pass. If tests are not passing and you need help resolving, please mention this in your PR.


## Adding new feature layers

Checklist for adding new feature layers:

* Create `flex-config/style/<feature>.lua`
* Create `flex-config/sql/<feature>.sql`
* Update `flex-config/run-no-tags.lua`
* Update `flex-config/run-no-tags.sql`
* Update `db/qc/features_not_in_run_all.sql`
* Add relevant `tests/sql/<feature_queries>.sql`
* Add relevant `tests/expected/<feature_queries>.out`
