# Sill — top-level orchestration.
# Rust workspace builds sill-core (static C ABI lib + rlib) and the sill CLI.
# The macOS app is a SwiftPM executable packaged by apps/macos/bundle.sh.

CARGO ?= cargo
SWIFT ?= swift

.PHONY: all core cli test app bundle run bench clean fmt lint

all: core cli

core:
	$(CARGO) build -p sill-core

cli:
	$(CARGO) build -p sill

test:
	$(CARGO) test --workspace

app:
	cd apps/macos && $(SWIFT) build

bundle: app
	cd apps/macos && ./bundle.sh

run: bundle
	open dist/Sill.app

bench: cli
	./target/debug/sill bench --suite=v1

fmt:
	$(CARGO) fmt --all
	cd apps/macos && find Sources -name '*.swift' -exec xcrun swift-format format -i {} + 2>/dev/null || true

lint:
	$(CARGO) clippy --workspace -- -D warnings

clean:
	$(CARGO) clean
	rm -rf dist apps/macos/.build
