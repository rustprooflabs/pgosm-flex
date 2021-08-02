.PHONY: docker-clean
docker-clean:
	# when docker runs as a demon the mounted folders have permissions and cannot be deleted by the current user
	# so to avoid an annoying "sudo" step another docker container is created to get similar permissions
	docker run \
		--rm \
		-v $(shell pwd)/pgosm-data:/app/output \
		rustprooflabs/pgosm-flex \
		bash -c "rm -rf /app/output/*"
	rmdir pgosm-data|| echo "folder pgosm-data did not exist"
	@docker stop pgosm > /dev/null 2>&1 && echo "pgosm container removed"|| echo "pgosm container not present, nothing to remove"

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

	docker exec -it \
		-e POSTGRES_PASSWORD=mysecretpassword \
		-e POSTGRES_USER=postgres \
		pgosm python3 docker/pgosm_flex.py  \
		--layerset=run-all \
		--ram=8 \
		--region=north-america/us \
		--subregion=district-of-columbia