# Ensure Make is run with bash shell as some syntax below is bash-specific
SHELL:=/usr/bin/env bash

# allow overwriting the default `go` value with the custom path to the go executable
GOEXE ?= go

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell $(GOEXE) env GOBIN))
	GOBIN=$(shell $(GOEXE) env GOPATH)/bin
else
	GOBIN=$(shell $(GOEXE) env GOBIN)
endif

GOROOT=$(shell $(GOEXE) env GOROOT)

.PHONY: all test clean lint gosec

all: hello-world

KO_PREFIX ?= ghcr.io/LoicSikidi/test-goreleaser

GOTEST=go test

WEB_DIR := web
SERVER_DIR := cmd/server
SERVER_STATIC_DIR := $(abspath $(SERVER_DIR)/kodata)
SERVER_EMBED_STATIC_DIR := $(abspath $(SERVER_DIR)/static)

# Set version variables for LDFLAGS
GIT_VERSION ?= $(shell git describe --tags --always --dirty)
GIT_HASH ?= $(shell git rev-parse HEAD)

SOURCE_DATE_EPOCH ?= $(shell git log -1 --no-show-signature --pretty=%ct)
ifdef SOURCE_DATE_EPOCH
    BUILD_DATE ?= $(shell date -u -d "@$(SOURCE_DATE_EPOCH)" "$(DATE_FMT)" 2>/dev/null || date -u -r "$(SOURCE_DATE_EPOCH)" "$(DATE_FMT)" 2>/dev/null || date -u "$(DATE_FMT)")
else
    BUILD_DATE ?= $(shell date "$(DATE_FMT)")
endif

gen: ## Generates code
	cp -pr $(SERVER_STATIC_DIR) $(SERVER_EMBED_STATIC_DIR)

lint: ## Runs golangci-lint
	$(GOBIN)/golangci-lint run -v ./...

gosec: ## Runs gosec
	$(GOBIN)/gosec ./...

hello-world: clean-static build-static gen ## Build static site for local tests
	$(GOEXE) build -trimpath -ldflags "$(LDFLAGS)" -tags=embed -o hello-world $(SERVER_DIR)/main.go

test: ## Runs go test
	$(GOTEST) -v -coverprofile=coverage.txt -covermode=atomic ./...

clean: ## Clean the workspace
	rm -rf dist
	rm -rf hello-world
	rm coverage.txt
	rm -rf $(SERVER_STATIC_DIR)

## --------------------------------------
## Modules
## --------------------------------------

.PHONY: modules
modules: ## Runs go mod to ensure modules are up to date.
	$(GOEXE) mod tidy

## --------------------------------------
## Generate static site sources
## --------------------------------------
.PHONY: build-static
build-static: ## Build the static site (frontend)
	cd $(WEB_DIR); npm i && npm run build -- --outDir=$(SERVER_STATIC_DIR)
.PHONY: clean-static
clean-static: ## Clean static site static sources
	rm -rf $(SERVER_STATIC_DIR)


## --------------------------------------
## Images with ko
## --------------------------------------
export KO_DOCKER_REPO=$(KO_PREFIX)

KOCACHE_PATH=/tmp/ko
OCI_LABELS=--image-label org.opencontainers.image.created=$(BUILD_DATE) \
           --image-label org.opencontainers.image.description="Container hosting a static site for demo purposes"
define create_kocache_path
  mkdir -p $(KOCACHE_PATH)
endef

.PHONY: ko
ko: clean-static build-static
	$(create_kocache_path)
	LDFLAGS="$(LDFLAGS)" GIT_HASH=$(GIT_HASH) GIT_VERSION=$(GIT_VERSION) \
	KOCACHE=$(KOCACHE_PATH) ko build --base-import-paths \
		--platform=all --tags $(GIT_VERSION) --tags $(GIT_HASH) \
		$(ARTIFACT_HUB_LABELS) \
		"github.com/LoicSikidi/test-goreleaser/cmd/server"

.PHONY: ko-local
ko-local: clean-static build-static
	$(create_kocache_path)
	KO_DOCKER_REPO=ko.local LDFLAGS="$(LDFLAGS)" GIT_HASH=$(GIT_HASH) GIT_VERSION=$(GIT_VERSION) \
	KOCACHE=$(KOCACHE_PATH) ko build --base-import-paths \
		--platform=linux/amd64 --tags $(GIT_VERSION) --tags $(GIT_HASH) \
		$(ARTIFACT_HUB_LABELS) \
		"github.com/LoicSikidi/test-goreleaser/cmd/server"

##################
# help
##################

help: ## Display help
	@awk -F ':|##' \
		'/^[^\t].+?:.*?##/ {\
			printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
		}' $(MAKEFILE_LIST) | sort

