# mcp-snippetslab — build-system interface (R07/N31)
#
# CI binds to these targets rather than raw swift commands. This is a Local
# (stdio-only) server, so the optional `e2e` / `container-image` targets are NOT
# declared (they do not apply) and are never invoked by CI (N31).

APP_NAME      := mcp-snippetslab
COVERAGE_GATE := 95

.PHONY: all lint test build coverage mutation secret-scan thread-sanitize clean

all: lint test build

## Lint — swiftlint --strict, 0 violations required
lint:
	swiftlint --strict

## Unit tests — fail on any failure (TDD workflow, T01)
test:
	swift test

## Release build (B01/B02). Build metadata (APP_VERSION/APP_COMMIT/APP_TIMESTAMP)
## is read at runtime from the environment or the current git checkout.
build:
	swift build -c release

## Coverage gate — fails below $(COVERAGE_GATE)% (C01/N06)
coverage:
	@set -e; \
	swift test --enable-code-coverage; \
	BIN=".build/debug/$(APP_NAME)PackageTests.xctest/Contents/MacOS/$(APP_NAME)PackageTests"; \
	if [ ! -f "$$BIN" ]; then BIN=".build/debug/$(APP_NAME)PackageTests.xctest/Contents/MacOS/$(APP_NAME)PackageTests"; fi; \
	TOTAL=$$(xcrun llvm-cov report "$$BIN" \
	  --instr-profile=.build/debug/codecov/default.profdata \
	  -ignore-filename-regex="\.build|Tests" \
	  | awk '/TOTAL/{print $$(NF-1)}' | tr -d '%'); \
	echo "Coverage: $${TOTAL}%"; \
	awk -v t="$${TOTAL}" -v gate="$(COVERAGE_GATE)" \
	  'BEGIN{ if (t+0 < gate+0) { printf "Coverage %.2f%% below %d%% gate\n", t, gate; exit 1 } }'

## Mutation testing hard gate (C02/N15)
mutation:
	muter --run-tests-command "swift test"

## Secret scan over git history (C03/N28)
secret-scan:
	gitleaks detect --source . --redact --verbose

## Thread sanitizer (Swift profile — data-race safety)
thread-sanitize:
	swift test --sanitize=thread

## Clean build artifacts
clean:
	swift package clean
