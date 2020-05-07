# Copyright 2018-2020 The OpenEBS Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# The images can be pushed to any docker/image registeries
# like docker hub, quay. The registries are specified in 
# the `build/push` script.
#
# The images of a project or company can then be grouped
# or hosted under a unique organization key like `openebs`
#
# Each component (container) will be pushed to a unique 
# repository under an organization. 
# Putting all this together, an unique uri for a given 
# image comprises of:
#   <registry url>/<image org>/<image repo>:<image-tag>
#
# IMAGE_ORG can be used to customize the organization 
# under which images should be pushed. 
# By default the organization name is `openebs`. 

# Output registry and image names for operator image
# Set env to override this value


# Output registry and image names for operator image
# Set env to override this value
ifeq (${REGISTRY}, )
  REGISTRY:=openebs
endif

export REGISTRY
# Determine the arch/os
ifeq (${XC_OS}, )
  XC_OS:=$(shell go env GOOS)
endif
export XC_OS

ifeq (${XC_ARCH}, )
  XC_ARCH:=$(shell go env GOARCH)
endif
export XC_ARCH

ARCH:=${XC_OS}_${XC_ARCH}
export ARCH

ifeq (${BASEIMAGE}, )
ifeq ($(ARCH),linux_arm64)
  BASEIMAGE:=arm64v8/ubuntu:18.04
else
	BASEIMAGE:=ubuntu:16.04
endif
endif
export BASEIMAGE

# Specify the docker arg for repository url
ifeq (${DBUILD_REPO_URL}, )
  DBUILD_REPO_URL="https://github.com/openebs/jiva-csi"
  export DBUILD_REPO_URL
endif

# Specify the docker arg for website url
ifeq (${DBUILD_SITE_URL}, )
  DBUILD_SITE_URL="https://openebs.io"
  export DBUILD_SITE_URL
endif

DBUILD_DATE ?= $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')

# Output operator name and its image name and tag
OPERATOR_NAME=jiva-operator
OPERATOR_TAG=ci

export DBUILD_ARGS=--build-arg DBUILD_DATE=${DBUILD_DATE} --build-arg DBUILD_REPO_URL=${DBUILD_REPO_URL} --build-arg DBUILD_SITE_URL=${DBUILD_SITE_URL} --build-arg ARCH=${ARCH}

# Tools required for different make targets or for development purposes
EXTERNAL_TOOLS=\
	golang.org/x/tools/cmd/cover \
	github.com/axw/gocov/gocov \
	github.com/ugorji/go/codec/codecgen \

# Lint our code. Reference: https://golang.org/cmd/vet/
VETARGS?=-asmdecl -atomic -bool -buildtags -copylocks -methods \
         -nilfunc -printf -rangeloops -shift -structtag -unsafeptr

GIT_BRANCH = $(shell git rev-parse --abbrev-ref HEAD | sed -e "s/.*\\///")
GIT_TAG = $(shell git describe --tags)

# use git branch as default version if not set by env variable, if HEAD is detached that use the most recent tag
VERSION ?= $(if $(subst HEAD,,${GIT_BRANCH}),$(GIT_BRANCH),$(GIT_TAG))
COMMIT ?= $(shell git rev-parse HEAD | cut -c 1-7)

ifeq ($(GIT_TAG),)
	GIT_TAG := $(COMMIT)
endif

ifeq (${TRAVIS_TAG}, )
  GIT_TAG = $(COMMIT)
	export GIT_TAG
else
  GIT_TAG = ${TRAVIS_TAG}
	export GIT_TAG
endif

PACKAGES = $(shell go list ./... | grep -v 'vendor')

LDFLAGS ?= \
        -extldflags "-static" \
	-X github.com/openebs/jiva-operator/version/version.Version=${VERSION} \
	-X github.com/openebs/jiva-operator/version/version.Commit=${COMMIT} \
	-X github.com/openebs/jiva-operator/version/version.DateTime=${DBUILD_DATE}


.PHONY: all
all:
	@echo "Available commands:"
	@echo "  build                           - build operator source code"
	@echo "  image                           - build operator container image"
	@echo "  push                            - push operator to dockerhub registry (${REGISTRY})"
	@echo ""
	@make print-variables --no-print-directory

.PHONY: print-variables
print-variables:
	@echo "Variables:"
	@echo "  VERSION:    ${VERSION}"
	@echo "  GIT_BRANCH: ${GIT_BRANCH}"
	@echo "  GIT_TAG:    ${GIT_TAG}"
	@echo "  COMMIT:     ${COMMIT}"
	@echo "Testing variables:"
	@echo " Produced Image: ${OPERATOR_NAME}:${OPERATOR_TAG}"
	@echo " REGISTRY: ${REGISTRY}"


# Bootstrap the build by downloading additional tools
bootstrap:
	@for tool in  $(EXTERNAL_TOOLS) ; do \
		echo "+ Installing $$tool" ; \
		go get -u $$tool; \
	done

.get:
	rm -rf ./build/_output/bin/
	go mod download

vet:
	@go vet 2>/dev/null ; if [ $$? -eq 3 ]; then \
		go get golang.org/x/tools/cmd/vet; \
	fi
	@echo "--> Running go tool vet ..."
	@go vet $(VETARGS) ${PACKAGES} ; if [ $$? -eq 1 ]; then \
		echo ""; \
		echo "[LINT] Vet found suspicious constructs. Please check the reported constructs"; \
		echo "and fix them if necessary before submitting the code for review."; \
	fi

	@git grep -n `echo "log"".Print"` | grep -v 'vendor/' ; if [ $$? -eq 0 ]; then \
		echo "[LINT] Found "log"".Printf" calls. These should use Maya's logger instead."; \
	fi

deps: .get
	go mod vendor

build: deps test
	@echo "--> Build binary $(OPERATOR_NAME) ..."
	GOOS=linux go build -a -ldflags '$(LDFLAGS)' -o ./build/_output/bin/${ARCH}/$(OPERATOR_NAME) ./cmd/manager/main.go

.PHONY: Dockerfile.jo
Dockerfile.jo: ./build/Dockerfile
	sed -e 's|@BASEIMAGE@|$(BASEIMAGE)|g' $< >$@

image: build Dockerfile.jo
	@echo "--> Build image $(REGISTRY)/$(OPERATOR_NAME):$(OPERATOR_TAG) ..."
	docker build -f Dockerfile.jo -t $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(OPERATOR_TAG) $(DBUILD_ARGS) .

generate:
	@echo "--> Generate CR ..."
	operator-sdk generate k8s --verbose

operator:
	@echo "--> Build using operator-sdk ..."
	operator-sdk build $(REGISTRY)/$(OPERATOR_NAME):$(OPERATOR_TAG) --verbose

push-image: image
	@echo "--> Push image $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(OPERATOR_TAG) ..."
	docker push $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(OPERATOR_TAG)

push:
	@echo "--> Push image $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(OPERATOR_TAG) ..."
	@DIMAGE=$(REGISTRY)/$(OPERATOR_NAME)-$(ARCH) ./build/push

tag:
	@echo "--> Tag image $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(OPERATOR_TAG) to $(REGISTRY)/$(OPERATOR_NAME):$(GIT_TAG) ..."
	docker tag $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(OPERATOR_TAG) $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(GIT_TAG)

push-tag: tag push
	@echo "--> Push image $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(GIT_TAG) ..."
	docker push $(REGISTRY)/$(OPERATOR_NAME)-$(ARCH):$(GIT_TAG)

clean:
	rm -rf ./build/_output/bin/
	go mod tidy

format: clean
	@echo "--> Running go fmt"
	@go fmt $(PACKAGES)

test: format vet
	@echo "--> Running go test" ;
	@go test -v --cover $(PACKAGES)
