## ----------------------------------------------------------------------
## This Makefile builds and tests the PgOSM Flex Docker image.
##
## For full build/test use (runs multiple import formats):
##    make
##
## To run region/subregion test + unit tests:
##    make docker-exec-default unit-tests
##
## To cleanup after you are done:
##    make docker-clean
##
## The docker-exec-default target runs the "everything" layerset to
## enable testing the data processing itself.
##
##
## The other targets should define the minimal layerset to reduce processing
## times. Additional targets are testing functionality of the Docker
## processing, not the output data so loading additional data serves
## no benefit.
## ----------------------------------------------------------------------
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)
TODAY := $(shell date +'%Y-%m-%d')
INPUT_FILE_NAME=custom_source_file.osm.pbf
REGION_FILE_NAME=region-dc
RAM=2

# The docker-exec-default and unit-test targets run last
# to make unit test results visible at the end.
.PHONY: all
all: docker-exec-region docker-exec-input-file \
	docker-exec-append-w-input-file \
	docker-exec-default unit-tests

.PHONY: docker-clean
docker-clean:
	# Stops pgosm Docker container and removes local pgosm-data directory
	@docker stop pgosm > /dev/null 2>&1 \
		&& echo "pgosm container removed" \
		|| echo "pgosm container not present, nothing to remove"
	rm -rvf pgosm-data \
		|| echo "folder pgosm-data did not exist"


.PHONY: build-run-docker
build-run-docker: docker-clean
	# Builds and runs PgOSM Flex with D.C. test file
	docker build -t rustprooflabs/pgosm-flex .
	docker run --name pgosm \
		--rm \
		-v $(shell pwd)/pgosm-data:/app/output \
		-v /etc/localtime:/etc/localtime:ro \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-p 5433:5432 \
		-d \
		rustprooflabs/pgosm-flex

.PHONE: docker-exec-default
docker-exec-default: build-run-docker
	# This is the step used by data verification. It must run the everything
	# layerset in order to test as much of the data as possible.

	# copy the test data pretending it's latest to avoid downloading each time
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf \
		pgosm:/app/output/district-of-columbia-$(TODAY).osm.pbf
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf.md5 \
		pgosm:/app/output/district-of-columbia-$(TODAY).osm.pbf.md5

	# allow files created in later step to be created
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/output/
	# Needed for unit-tests
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/docker/

	# run typical processing using built-in file handling
	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm python3 docker/pgosm_flex.py  \
		--layerset=everything \
		--ram=$(RAM) \
		--region=north-america/us \
		--subregion=district-of-columbia


.PHONE: docker-exec-input-file
docker-exec-input-file: build-run-docker

	# copy with arbitrary file name to test --input-file
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf \
		pgosm:/app/output/$(INPUT_FILE_NAME)


	# allow files created in later step to be created
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/output/
	# Needed for unit-tests
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/docker/

	# process it, this time without providing the region but directly the filename
	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm python3 docker/pgosm_flex.py  \
		--layerset=minimal \
		--ram=$(RAM) \
		--input-file=/app/output/$(INPUT_FILE_NAME) \
		--data-only --skip-dump --skip-nested # Make this test run faster



.PHONE: docker-exec-append-w-input-file
docker-exec-append-w-input-file: build-run-docker
	# NOTE: This step tests --append file for an initial load.
	# It does **NOT** test the actual replication process for updating data
	# using append mode. Testing actual replication over time in this format
	# will not be trivial.  The historic file used (2021-01-13) cannot be used
	# to seed a replication process, there is a time limit in upstream software
	# that requires more recency to the source data. This also cannot simply
	# download a file from Geofabrik, as the "latest" file will not have a diff
	# to apply so also will not test the actual replication.
	#
	# Open a PR, Issue, discussion on https://github.com/rustprooflabs/pgosm-flex
	# if you have an idea on how to implement this testing functionality.

	# copy with arbitrary file name to test --input-file
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf \
		pgosm:/app/output/$(INPUT_FILE_NAME)

	# allow files created in later step to be created
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/output/
	# Needed for unit-tests
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/docker/

	# process it, this time without providing the region but directly the filename
	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm python3 docker/pgosm_flex.py  \
		--layerset=minimal \
		--ram=$(RAM) \
		--append \
		--input-file=/app/output/$(INPUT_FILE_NAME) \
		--data-only --skip-dump --skip-nested # Make this test run faster


.PHONE: docker-exec-region
docker-exec-region: build-run-docker
	# copy for simulating region
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf \
		pgosm:/app/output/$(REGION_FILE_NAME)-$(TODAY).osm.pbf
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf.md5 \
		pgosm:/app/output/$(REGION_FILE_NAME)-$(TODAY).osm.pbf.md5

	# allow files created in later step to be created
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/output/
	# Needed for unit-tests
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/docker/

	docker exec -it pgosm \
		sed -i 's/district-of-columbia/$(REGION_FILE_NAME)/' /app/output/$(REGION_FILE_NAME)-$(TODAY).osm.pbf.md5

	# process DC file, pretending its a region instead of subregion
	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm python3 docker/pgosm_flex.py  \
		--layerset=minimal \
		--ram=$(RAM) \
		--region=$(REGION_FILE_NAME) \
		--data-only --skip-dump --skip-nested # Make this test run faster


.PHONY: unit-tests
unit-tests: ## Runs Python unit tests and data import tests
	# Unit tests covering Python runtime
	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm /bin/bash -c "cd docker && coverage run -m unittest tests/*.py || true"

	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm /bin/bash -c "cd docker && coverage report -m ./*.py"

	# Data import tests
	docker cp tests \
		pgosm:/app/tests
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/tests/

	# Errors when running under docker are saved in
	#  /app/tests/tmp/<test_with_error>.diff
	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm /bin/bash -c "cd tests && ./run-output-tests.sh"


help: ## Show this help
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-30s\033[0m %s\n", $$1, $$2}'
