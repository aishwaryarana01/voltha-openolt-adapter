#
# Copyright 2016 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ifeq ($(TAG),)
TAG := latest
endif

ifeq ($(TARGET_TAG),)
TARGET_TAG := latest
endif

# If no DOCKER_HOST_IP is specified grab a v4 IP address associated with
# the default gateway
ifeq ($(DOCKER_HOST_IP),)
DOCKER_HOST_IP := $(shell ifconfig $$(netstat -rn | grep -E '^(default|0.0.0.0)' | head -1 | awk '{print $$NF}') | grep inet | awk '{print $$2}' | sed -e 's/addr://g')
endif


ifneq ($(http_proxy)$(https_proxy),)
# Include proxies from the environment
DOCKER_PROXY_ARGS = \
       --build-arg http_proxy=$(http_proxy) \
       --build-arg https_proxy=$(https_proxy) \
       --build-arg ftp_proxy=$(ftp_proxy) \
       --build-arg no_proxy=$(no_proxy) \
       --build-arg HTTP_PROXY=$(HTTP_PROXY) \
       --build-arg HTTPS_PROXY=$(HTTPS_PROXY) \
       --build-arg FTP_PROXY=$(FTP_PROXY) \
       --build-arg NO_PROXY=$(NO_PROXY)
endif

DOCKER_BUILD_ARGS = \
	--build-arg TAG=$(TAG) \
	--build-arg REGISTRY=$(REGISTRY) \
	--build-arg REPOSITORY=$(REPOSITORY) \
	$(DOCKER_PROXY_ARGS) $(DOCKER_CACHE_ARG) \
	 --rm --force-rm \
	$(DOCKER_BUILD_EXTRA_ARGS)

DOCKER_IMAGE_LIST = \
	openolt-adapter-go


.PHONY: $(DIRS) $(DIRS_CLEAN) $(DIRS_FLAKE8) adapters 

# This should to be the first and default target in this Makefile
help:
	@echo "Usage: make [<target>]"
	@echo "where available targets are:"
	@echo
	@echo "build        : Build the docker images.\n\
               If this is the first time you are building, choose \"make build\" option."
	@echo


# Parallel Build
$(DIRS):
	@echo "    MK $@"
	$(Q)$(MAKE) -C $@

# Parallel Clean
DIRS_CLEAN = $(addsuffix .clean,$(DIRS))
$(DIRS_CLEAN):
	@echo "    CLEAN $(basename $@)"
	$(Q)$(MAKE) -C $(basename $@) clean

build: containers

containers: adapter_openolt_go

adapter_openolt_go:
ifdef LOCAL_PROTOS
	mkdir -p vendor/github.com/opencord/voltha-protos/go
	cp -rf ${GOPATH}/src/github.com/opencord/voltha-protos/go/ vendor/github.com/opencord/voltha-protos
endif
ifdef LOCAL_VOLTHAGO
	mkdir -p vendor/github.com/opencord/voltha-go/
	cp -rf ${GOPATH}/src/github.com/opencord/voltha-go/ vendor/github.com/opencord/
	rm -rf vendor/github.com/opencord/voltha-go/vendor
endif
	docker build $(DOCKER_BUILD_ARGS) -t ${REGISTRY}${REPOSITORY}voltha-openolt-adapter-go:${TAG} -f docker/Dockerfile.openolt .

lint-style:
ifeq (,$(shell which gofmt))
	go get -u github.com/golang/go/src/cmd/gofmt
endif
	@echo "Running style check..."
	@gofmt_out="$$(gofmt -l $$(find . -name '*.go' -not -path './vendor/*'))" ;\
	if [ ! -z "$$gofmt_out" ]; then \
	  echo "$$gofmt_out" ;\
	  echo "Style check failed on one or more files ^, run 'go fmt' to fix." ;\
	  exit 1 ;\
	fi
	@echo "Style check OK"

lint-sanity:
	@echo "Running sanity check..."
	@go vet ./...
	@echo "Sanity check OK"

lint-dep:
	@echo "Running dependency check..."
	@dep check
	@echo "Dependency check OK"

lint: lint-style lint-sanity lint-dep

GO_JUNIT_REPORT:=$(shell which go-junit-report)
GOCOVER_COBERTURA:=$(shell which gocover-cobertura)
test:
ifeq (,$(GO_JUNIT_REPORT))
	go get -u github.com/jstemmer/go-junit-report
	@GO_JUNIT_REPORT=$(GOPATH)/bin/go-junit-report
endif

ifeq (,$(GOCOVER_COBERTURA))
	go get -u github.com/t-yuki/gocover-cobertura
	@GOCOVER_COBERTURA=$(GOPATH)/bin/gocover-cobertura
endif

	@mkdir -p ./tests/results

	@go test -v -coverprofile ./tests/results/go-test-coverage.out -covermode count ./... 2>&1 | tee ./tests/results/go-test-results.out ;\
	RETURN=$$? ;\
	$(GO_JUNIT_REPORT) < ./tests/results/go-test-results.out > ./tests/results/go-test-results.xml ;\
	$(GOCOVER_COBERTURA) < ./tests/results/go-test-coverage.out > ./tests/results/go-test-coverage.xml ;\
	exit $$RETURN

# end file
