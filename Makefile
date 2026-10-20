# pepper developer commands.
#
# Run `make` or `make help` for the target list.

SHELL := /bin/sh

DART ?= dart
NPM ?= npm
EXAMPLE := example/relic_vault
DOCS := docs
BENCH_RUNS ?= 3
EXAMPLE_SEED_COUNT ?= 50000
BENCH_BIN := build/bench
BENCH_SOURCES := bench/bench.dart $(shell find lib -name '*.dart' -type f)
BENCH_PORT ?= 18080
BENCH_QUICK_PORT ?= 18081
BENCH_LOCK ?= /tmp/pepper-benchmark.lock

.DEFAULT_GOAL := help

.PHONY: help setup setup-core setup-example setup-example-deps setup-docs \
	test test-core test-example test-coverage analyze analyze-core analyze-example \
	format format-check check ci doc publish-dry \
	bench bench-core bench-core-once bench-all bench-example bench-example-full \
	example-build example-seed example-seed-reset example-trace run-example run-example-bin \
	docs-dev docs-build docs-preview docs-install docs-clean \
	clean clean-core clean-example clean-docs clean-all all \
	setup\:core setup\:example setup\:example\:deps setup\:docs \
	test\:core test\:example test\:coverage analyze\:core analyze\:example format\:check \
	publish\:dry bench\:core bench\:core\:once bench\:all bench\:example bench\:example\:full \
	example\:build example\:seed example\:seed\:reset example\:trace run\:example run\:example\:bin \
	docs\:dev docs\:build docs\:preview docs\:install docs\:clean \
	clean\:core clean\:example clean\:docs clean\:all

help: ## Show this help.
	@printf '\nUsage: make <target>\n\n'
	@printf 'Setup:\n'
	@printf '  %-28s %s\n' 'setup' 'Install all dependencies and seed the demo'
	@printf '  %-28s %s\n' 'setup:core' 'Install core Dart dependencies'
	@printf '  %-28s %s\n' 'setup:example' 'Install Relic Vault and seed the demo database'
	@printf '  %-28s %s\n' 'setup:docs' 'Install VitePress dependencies'
	@printf '\nChecks:\n'
	@printf '  %-28s %s\n' 'test' 'Run core and example tests'
	@printf '  %-28s %s\n' 'test:core' 'Run core tests'
	@printf '  %-28s %s\n' 'test:example' 'Run Relic Vault tests'
	@printf '  %-28s %s\n' 'test:coverage' 'Run core tests with LCOV coverage'
	@printf '  %-28s %s\n' 'analyze' 'Analyze core and example packages'
	@printf '  %-28s %s\n' 'format' 'Format all Dart sources'
	@printf '  %-28s %s\n' 'format:check' 'Check formatting without changing files'
	@printf '  %-28s %s\n' 'check' 'Format check, analyze, and test'
	@printf '  %-28s %s\n' 'ci' 'Run checks, build docs, and build the demo server'
	@printf '\nBenchmarks:\n'
	@printf '  %-28s %s\n' 'bench' 'Core microbenchmarks, averaged over 3 runs'
	@printf '  %-28s %s\n' 'bench:core:once' 'Run the core microbenchmark once'
	@printf '  %-28s %s\n' 'bench:example' 'Quick Relic Vault benchmark (1 run)'
	@printf '  %-28s %s\n' 'bench:example:full' 'Full Relic Vault benchmark (3 runs per scenario)'
	@printf '  %-28s %s\n' 'bench:all' 'Core averages plus the full Relic Vault matrix'
	@printf '\nRelic Vault:\n'
	@printf '  %-28s %s\n' 'example:seed' 'Seed the demo database if needed'
	@printf '  %-28s %s\n' 'example:seed:reset' 'Drop and reseed the demo database'
	@printf '  %-28s %s\n' 'example:trace' 'Regenerate the benchmark URL trace'
	@printf '  %-28s %s\n' 'example:build' 'Build the AOT Relic Vault server'
	@printf '  %-28s %s\n' 'run:example' 'Run the server from source'
	@printf '  %-28s %s\n' 'run:example:bin' 'Run the AOT server'
	@printf '\nDocumentation:\n'
	@printf '  %-28s %s\n' 'docs:dev' 'Start the VitePress dev server'
	@printf '  %-28s %s\n' 'docs:build' 'Build the VitePress site'
	@printf '  %-28s %s\n' 'docs:preview' 'Preview the built VitePress site'
	@printf '  %-28s %s\n' 'docs:install' 'Install VitePress dependencies'
	@printf '  %-28s %s\n' 'docs:clean' 'Remove VitePress build output and cache'
	@printf '\nHousekeeping:\n'
	@printf '  %-28s %s\n' 'clean' 'Remove generated local artifacts'
	@printf '  %-28s %s\n' 'clean:all' 'Also remove docs node_modules'
	@printf '  %-28s %s\n' 'all' 'Run checks and build the docs'
	@printf '\nOverrides:\n'
	@printf '  %-28s %s\n' 'BENCH_RUNS=5 make bench' 'Average five core benchmark runs'
	@printf '  %-28s %s\n' 'EXAMPLE_SEED_COUNT=10000' 'Seed size for setup:example'
	@printf '  %-28s %s\n' 'DART=/path/to/dart' 'Use a specific Dart SDK'
	@printf '  %-28s %s\n' 'NPM=/path/to/npm' 'Use a specific npm'
	@printf '\n'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup: setup-core setup-example setup-docs ## Install all dependencies and seed the demo.

setup-core: ## Install core Dart dependencies.
	$(DART) pub get

setup-example-deps: ## Install Relic Vault dependencies.
	cd $(EXAMPLE) && $(DART) pub get

example-seed: setup-example-deps ## Seed the demo database if needed.
	cd $(EXAMPLE) && $(DART) run bin/seed.dart --db=data/relics.db --count=$(EXAMPLE_SEED_COUNT)

setup-example: setup-example-deps example-seed ## Install and seed the Relic Vault demo.

setup-docs: docs/node_modules ## Install VitePress dependencies.

docs/node_modules: docs/package-lock.json
	cd $(DOCS) && $(NPM) ci

# ---------------------------------------------------------------------------
# Tests and checks
# ---------------------------------------------------------------------------

test: test-core test-example ## Run core and example tests.

test-core: setup-core ## Run core tests.
	$(DART) test

test-example: setup-example-deps ## Run Relic Vault tests.
	cd $(EXAMPLE) && $(DART) test

test-coverage: setup-core ## Run core tests and produce coverage/lcov.info.
	$(DART) test --coverage=coverage
	$(DART) run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --base-directory .

analyze: analyze-core analyze-example ## Analyze core and example packages.

analyze-core: setup-core ## Analyze the core package.
	$(DART) analyze --fatal-infos

analyze-example: setup-example-deps ## Analyze the Relic Vault package.
	cd $(EXAMPLE) && $(DART) analyze --fatal-infos

format: ## Format all Dart sources.
	$(DART) format .

format-check: ## Check formatting without changing files.
	$(DART) format --output=none --set-exit-if-changed .

check: format-check analyze test ## Format check, analyze, and test everything.
ci: check docs-build example-build ## Run the main CI checks locally.

doc: setup-core ## Generate core API docs.
	$(DART) doc

publish-dry: ## Run dart pub publish --dry-run.
	$(DART) pub publish --dry-run

# ---------------------------------------------------------------------------
# Core benchmarks
# ---------------------------------------------------------------------------

$(BENCH_BIN): $(BENCH_SOURCES)
	@mkdir -p $(dir $(BENCH_BIN))
	$(DART) compile exe bench/bench.dart -o $(BENCH_BIN)

bench: bench-core ## Core microbenchmarks, averaged over BENCH_RUNS (default 3).

bench-core: setup-core $(BENCH_BIN) ## Core microbenchmarks, averaged over BENCH_RUNS.
	@$(DART) run bench/bench_avg.dart --runs=$(BENCH_RUNS) $(BENCH_BIN)

bench-core-once: setup-core $(BENCH_BIN) ## Run the core microbenchmark once.
	@./$(BENCH_BIN)

bench-all: bench bench-example-full ## Core averages plus the full Relic Vault matrix.

# ---------------------------------------------------------------------------
# Relic Vault example
# ---------------------------------------------------------------------------

example-seed-reset: setup-example-deps ## Drop and reseed the demo database.
	cd $(EXAMPLE) && $(DART) run bin/seed.dart --db=data/relics.db --count=$(EXAMPLE_SEED_COUNT) --reset

example-trace: setup-example-deps ## Regenerate the example benchmark URL trace.
	cd $(EXAMPLE) && $(DART) run bench/gen_trace.dart

example-build: setup-example-deps ## Build the AOT Relic Vault server.
	cd $(EXAMPLE) && $(DART) build cli --target=bin/server.dart -o build/server

run-example: setup-example ## Run the Relic Vault server from source.
	cd $(EXAMPLE) && $(DART) run bin/server.dart --db=data/relics.db

run-example-bin: setup-example example-build ## Run the AOT Relic Vault server.
	cd $(EXAMPLE) && ./build/server/bundle/bin/server --db=data/relics.db

bench-example: setup-example-deps ## Quick Relic Vault benchmark (1 run).
	@if ! mkdir "$(BENCH_LOCK)" 2>/dev/null; then \
		echo "another benchmark is running (remove $(BENCH_LOCK) if stale)"; \
		exit 1; \
	fi; \
	trap 'rmdir "$(BENCH_LOCK)"' EXIT; \
	cd $(EXAMPLE) && $(DART) run bench/run.dart \
		--profile=quick \
		--port=$(BENCH_QUICK_PORT) \
		--trace=bench/results/raw-quick/trace.txt \
		--out=bench/results/quick.md \
		--json=bench/results/quick.json \
		--raw-dir=bench/results/raw-quick

bench-example-full: setup-example-deps ## Full Relic Vault benchmark (3 runs per scenario).
	@if ! mkdir "$(BENCH_LOCK)" 2>/dev/null; then \
		echo "another benchmark is running (remove $(BENCH_LOCK) if stale)"; \
		exit 1; \
	fi; \
	trap 'rmdir "$(BENCH_LOCK)"' EXIT; \
	cd $(EXAMPLE) && $(DART) run bench/run.dart \
		--profile=full \
		--port=$(BENCH_PORT) \
		--out=bench/results/latest.md \
		--json=bench/results/latest.json

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

docs-dev: docs/node_modules ## Start the VitePress dev server.
	cd $(DOCS) && $(NPM) run docs:dev

docs-build: docs/node_modules ## Build the VitePress site.
	cd $(DOCS) && $(NPM) run docs:build

docs-preview: docs/node_modules ## Preview the built VitePress site.
	cd $(DOCS) && $(NPM) run docs:preview

docs-install: setup-docs ## Alias for setup-docs.

docs-clean: ## Remove VitePress build output and cache.
	rm -rf $(DOCS)/.vitepress/dist $(DOCS)/.vitepress/cache

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

clean: clean-core clean-example clean-docs ## Remove generated local artifacts.

clean-core: ## Remove core build, coverage and package state.
	rm -rf .dart_tool build coverage

clean-example: ## Remove example builds, generated data and raw benchmark output.
	rm -rf $(EXAMPLE)/.dart_tool $(EXAMPLE)/build $(EXAMPLE)/data \
		$(EXAMPLE)/bench/trace.txt $(EXAMPLE)/bench/results/raw

clean-docs: ## Remove VitePress build output and cache.
	rm -rf $(DOCS)/.vitepress/dist $(DOCS)/.vitepress/cache

clean-all: clean ## Also remove docs node_modules.
	rm -rf $(DOCS)/node_modules

all: check docs-build ## Run checks and build the docs.

# ---------------------------------------------------------------------------
# Colon aliases
#
# GNU Make treats ':' as a target/prerequisite separator. These aliases keep
# the convenient `make bench:example` style while the real targets use hyphens.
# ---------------------------------------------------------------------------

setup\:core:
	@$(MAKE) setup-core

setup\:example:
	@$(MAKE) setup-example

setup\:example\:deps:
	@$(MAKE) setup-example-deps

setup\:docs:
	@$(MAKE) setup-docs

test\:core:
	@$(MAKE) test-core

test\:example:
	@$(MAKE) test-example

test\:coverage:
	@$(MAKE) test-coverage

analyze\:core:
	@$(MAKE) analyze-core

analyze\:example:
	@$(MAKE) analyze-example

format\:check:
	@$(MAKE) format-check

publish\:dry:
	@$(MAKE) publish-dry

bench\:core:
	@$(MAKE) bench-core

bench\:core\:once:
	@$(MAKE) bench-core-once

bench\:all:
	@$(MAKE) bench-all

bench\:example:
	@$(MAKE) bench-example

bench\:example\:full:
	@$(MAKE) bench-example-full

example\:seed:
	@$(MAKE) example-seed

example\:seed\:reset:
	@$(MAKE) example-seed-reset

example\:trace:
	@$(MAKE) example-trace

example\:build:
	@$(MAKE) example-build

run\:example:
	@$(MAKE) run-example

run\:example\:bin:
	@$(MAKE) run-example-bin

docs\:dev:
	@$(MAKE) docs-dev

docs\:build:
	@$(MAKE) docs-build

docs\:preview:
	@$(MAKE) docs-preview

docs\:install:
	@$(MAKE) docs-install

docs\:clean:
	@$(MAKE) docs-clean

clean\:core:
	@$(MAKE) clean-core

clean\:example:
	@$(MAKE) clean-example

clean\:docs:
	@$(MAKE) clean-docs

clean\:all:
	@$(MAKE) clean-all
