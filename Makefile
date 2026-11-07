# The app builds from Warble.xcodeproj through scripts/xcodebuild.sh, into build/DerivedData. Package.swift holds only
# WarbleModel, for its tests on Linux (make test-linux).

INSTALL_DIR ?= /Applications
# Extra xcodebuild arguments, e.g. ARGS=-onlyUsePackageVersionsFromResolvedFile in CI.
ARGS ?=
# One suite or test, e.g. ONLY=WarbleModelTests/HoverTests or ONLY='WarbleModelTests/notchSitsBetweenTheMenuBarAreas()'.
ONLY ?=
# CI builds the tests in one step and runs them in the next, with TEST_ACTION=test-without-building.
TEST_ACTION ?= test
XCODEBUILD := scripts/xcodebuild.sh
DESTINATION := -destination 'platform=macOS,arch=$(shell uname -m)'

.PHONY: build build-tests test test-install test-uninstall coverage test-linux perf lint strings bundle app run dist icon clean

build:
	$(XCODEBUILD) -scheme Warble -configuration Debug $(DESTINATION) -quiet build $(ARGS)

# Not -quiet: with it, Xcode 27 reports some test files that compiled fine as failed "with exit code 0".
build-tests:
	$(XCODEBUILD) -scheme Warble $(DESTINATION) build-for-testing $(ARGS)

# WarbleModel's and WarbleCore's tests, from Tests/Warble.xctestplan. PerfTests skip themselves there.
test:
	$(XCODEBUILD) -scheme Warble $(DESTINATION) $(TEST_ACTION) $(if $(ONLY),-only-testing:'$(ONLY)') $(ARGS)

# Runs site/public/install.sh against a local folder standing in for the GitHub release.
test-install:
	scripts/test-install.sh

# Runs site/public/uninstall.sh against a fake home folder.
test-uninstall:
	scripts/test-uninstall.sh

# Line coverage per file for WarbleModel and WarbleCore, lowest first. Not a gate: it shows where tests are missing.
coverage:
	scripts/coverage.sh $(ARGS)

# The performance budgets, alone and one test at a time, so other tests don't skew the timings. Tests/Perf.xctestplan
# sets WARBLE_PERF, which PerfTests needs to run. Budgets and baselines: docs/performance.md.
perf:
	$(XCODEBUILD) -scheme Warble $(DESTINATION) -testPlan Perf $(TEST_ACTION) -only-testing:WarbleCoreTests/PerfTests $(ARGS)

# WarbleModel's tests on Linux, as CI's linux job runs them. Needs Docker; keep the image in step with ci.yml.
test-linux:
	docker run --rm -v "$(CURDIR)":/src -w /src swift:6.3 swift test --scratch-path .build/linux

# On a Mac, also checks Resources/Localizable.xcstrings has every string the app shows; CI's linux job can't.
lint:
	scripts/lint.sh
ifeq ($(shell uname),Darwin)
	$(MAKE) build
	scripts/strings.sh --check
endif

# Adds new strings to Resources/Localizable.xcstrings and drops ones the source no longer uses.
strings: build
	scripts/strings.sh

bundle:
	scripts/bundle.sh

app: bundle
	scripts/install.sh "$(INSTALL_DIR)"

run: app
	pkill -x WarbleDev || true
	while pgrep -x WarbleDev >/dev/null; do sleep 0.1; done
	open "$(INSTALL_DIR)/WarbleDev.app"

dist: export WARBLE_RELEASE = 1
dist: bundle
	ditto -c -k --keepParent build/Warble.app build/Warble.zip
	@echo "Wrote build/Warble.zip"

icon:
	mkdir -p build
	cat Sources/WarbleModel/Design/IconBars.swift scripts/make-icon.swift > build/make-icon.swift
	swift build/make-icon.swift .

clean:
	rm -rf .build build
