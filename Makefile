# Building with only the Command Line Tools: their default SDK (27) makes SwiftUI's @State a
# macro whose compiler plugin ships with Xcode alone, so pin the newest 26.x SDK when there is one.
# With Xcode selected, the default SDK works and nothing is pinned.
CLT_SDK := $(lastword $(sort $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk)))
ifeq ($(findstring CommandLineTools,$(shell xcode-select -p)),CommandLineTools)
ifneq ($(wildcard $(CLT_SDK)),)
export SDKROOT ?= $(CLT_SDK)
endif
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
endif

INSTALL_DIR ?= /Applications
# Extra `swift test` flags, e.g. ARGS=--skip-build in CI.
ARGS ?=

.PHONY: build test test-linux perf perf-app perf-app-full lint strings bundle app run dist icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(ARGS) --skip PerfTests

# The performance budgets, alone and one test at a time, so other tests don't skew the timings. perf-app measures the
# installed WarbleDev and takes over the pointer for about a minute; perf-app-full adds the CPU and wakeup
# rows for about six and a half. Budgets and baselines: docs/performance.md.
perf:
	swift test $(TEST_FLAGS) $(ARGS) --filter PerfTests

perf-app:
	scripts/perf.sh

perf-app-full:
	PERF_FULL=1 scripts/perf.sh

# WarbleModel's tests on Linux, as CI's linux job runs them. Needs Docker; keep the image in step with ci.yml.
test-linux:
	docker run --rm -v "$(CURDIR)":/src -w /src swift:6.3 swift test --scratch-path .build/linux

# On a Mac, also checks Resources/Localizable.xcstrings has every string the app shows; CI's linux job can't.
lint:
	scripts/lint.sh
ifeq ($(shell uname),Darwin)
	swift build
	scripts/strings.sh --check
endif

# Adds new strings to Resources/Localizable.xcstrings and drops ones the source no longer uses.
strings:
	swift build
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
	mkdir -p .build
	cat Sources/WarbleModel/Design/IconBars.swift scripts/make-icon.swift > .build/make-icon.swift
	swift .build/make-icon.swift .

clean:
	rm -rf .build build
