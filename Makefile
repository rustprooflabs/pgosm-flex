CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)
TODAY := $(shell date +'%Y-%m-%d')

.PHONY: all
all: docker-clean build-run-docker

.PHONY: docker-clean
docker-clean:
	@docker stop pgosm > /dev/null 2>&1 && echo "pgosm container removed"|| echo "pgosm container not present, nothing to remove"
	rm -rvf pgosm-data|| echo "folder pgosm-data did not exist"


.PHONY: build-run-docker
build-run-docker:
	docker build -t rustprooflabs/pgosm-flex .
	docker run --name pgosm \
		--rm \
		-v $(shell pwd)/pgosm-data:/app/output \
		-v /etc/localtime:/etc/localtime:ro \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-p 5433:5432 \
		-d \
		rustprooflabs/pgosm-flex
	# copy the test data pretending it's latest to avoid downloading each time
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf \
		pgosm:/app/output/district-of-columbia-$(TODAY).osm.pbf
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf.md5 \
		pgosm:/app/output/district-of-columbia-$(TODAY).osm.pbf.md5
	# TODO this double copy should not be needed, once the python script
	# moves the files
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf \
		pgosm:/app/output/district-of-columbia-latest.osm.pbf
	docker cp tests/data/district-of-columbia-2021-01-13.osm.pbf.md5 \
		pgosm:/app/output/district-of-columbia-latest.osm.pbf.md5

	# allow files created in later step to be created
	docker exec -it pgosm \
		chown $(CURRENT_UID):$(CURRENT_GID) /app/output/

	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		-u $(CURRENT_UID):$(CURRENT_GID) \
		pgosm python3 docker/pgosm_flex.py  \
		--layerset=run-all \
		--ram=8 \
		--region=north-america/us \
		--subregion=district-of-columbia