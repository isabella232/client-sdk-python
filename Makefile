# Copyright (c) The Diem Core Contributors
# SPDX-License-Identifier: Apache-2.0

init:
	python3 -m venv ./venv

	./venv/bin/pip install --upgrade pip wheel setuptools
	./venv/bin/pip install -r requirements.txt
	./venv/bin/python setup.py develop

black:
	./venv/bin/python -m black --check src tests

lint:
	./venv/bin/pylama src tests examples
	./venv/bin/pyre --search-path ./venv/lib/python*/site-packages check

format:
	./venv/bin/python -m black src tests examples

test: format runtest

runtest:
	DMW_SELF_CHECK=Y ./venv/bin/pytest src/diem/testing/suites tests examples -k "$(t)" $(args)

profile:
	./venv/bin/python -m profile -m pytest tests examples -k "$(t)" $(args)

cover:
	./venv/bin/pytest --cov-report html --cov=src tests/test_* examples/*

build: black lint runtest

diemtypes:
	(cd diem && cargo build -p transaction-builder-generator)
	"diem/target/debug/generate-transaction-builders" \
		--language python3 \
		--module-name stdlib \
		--with-diem-types "diem/testsuite/generate-format/tests/staged/diem.yaml" \
		--serde-package-name diem \
		--diem-package-name diem \
		--target-source-dir src/diem \
		--with-custom-diem-code diem-types-ext/*.py \
		-- "diem/language/diem-framework/releases/legacy" \
		"diem/language/diem-framework/releases/artifacts/current"

protobuf:
	mkdir -p src/diem/jsonrpc
	protoc --plugin=protoc-gen-mypy=venv/bin/protoc-gen-mypy \
		-Idiem/json-rpc/types/src/proto --python_out=src/diem/jsonrpc --mypy_out=src/diem/jsonrpc \
		jsonrpc.proto

gen: diemtypes protobuf format


dist:
	rm -rf build dist
	./venv/bin/python setup.py -q sdist bdist_wheel


publish: dist
	./venv/bin/pip install --upgrade twine
	./venv/bin/python3 -m twine upload dist/*

docs: init _docs

_docs:
	rm -rf docs/diem
	rm -rf docs/examples
	./venv/bin/python3 -m pdoc diem --html -o docs
	./venv/bin/python3 -m pdoc examples --html -o docs
	rm -rf docs/examples/tests

server:
	examples/vasp/server.sh -p 8080

docker:
	docker-compose -f diem/docker/compose/validator-testnet/docker-compose.yaml up --detach

docker-down:
	docker-compose -f diem/docker/compose/validator-testnet/docker-compose.yaml down -v

docker-stop:
	docker-compose -f diem/docker/compose/validator-testnet/docker-compose.yaml stop


docker-test: docker-test-up docker-test-run docker-test-down

docker-test-up:
	DIEM_JSON_RPC_URL="http://validator:8080" DIEM_FAUCET_URL="http://faucet:8000/mint" \
	docker-compose \
		-p dmw \
		-f diem/docker/compose/validator-testnet/docker-compose.yaml \
		-f docker-compose/mini-wallet-service.yaml \
		up --detach

docker-test-down:
	docker-compose \
		-p dmw \
		-f diem/docker/compose/validator-testnet/docker-compose.yaml \
		-f docker-compose/mini-wallet-service.yaml \
		down

docker-test-run:
	docker run \
		--name dmw-test-runner \
		--network diem-docker-compose-shared \
		--rm \
		-t \
		-p "8889:8889" \
		"python:3.8" \
		/bin/bash -c "apt-get update && \
			pip install diem[all] && \
			dmw test \
			--jsonrpc http://validator:8080/v1 \
			--faucet http://faucet:8000/mint \
			--target http://mini-wallet:8888 \
			--stub-bind-host 0.0.0.0 \
			--stub-bind-port 8889 \
			--stub-diem-account-base-url http://dmw-test-runner:8889"


.PHONY: init lint format test cover build diemtypes protobuf gen dist docs server docker docker-down docker-stop docker-test docker-test-up docker-test-down docker-test-run
