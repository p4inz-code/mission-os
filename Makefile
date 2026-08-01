# Mission OS — Top-Level Makefile
#
# Orchestrates builds across both Rust (Cargo) and C++ (CMake) components,
# plus Nightly ISO generation and packaging targets.

SHELL := /bin/bash
CMAKE_BUILD_DIR := build

.PHONY: all libs check test clean fmt ci cmake-configure cmake-build cargo-audit \
        nightly package validate-iso securityd-service

all: libs

libs: cargo-build cmake-build

CARGO_FLAGS :=

cargo-build:
	cargo build $(CARGO_FLAGS)

cmake-configure:
	mkdir -p $(CMAKE_BUILD_DIR) && \
	cd $(CMAKE_BUILD_DIR) && \
	cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON

cmake-build: cmake-configure
	cmake --build $(CMAKE_BUILD_DIR)

test: cargo-test cmake-test

cargo-test:
	cargo test $(CARGO_FLAGS)

cmake-test: cmake-build
	cd $(CMAKE_BUILD_DIR) && ctest --output-on-failure

fmt: cargo-fmt

cargo-fmt:
	cargo fmt

check: cargo-check cargo-clippy cargo-fmt-check cmake-build

cargo-check:
	cargo check $(CARGO_FLAGS)

cargo-clippy:
	cargo clippy $(CARGO_FLAGS) -- -D warnings

cargo-fmt-check:
	cargo fmt --check

cargo-audit:
	cargo audit --deny warnings 2>/dev/null || \
		(echo "⚠️  cargo-audit not installed. Install: cargo install cargo-audit --locked" && false)

# ── Nightly Build Targets ──────────────────────────────────────────

## Build all packages and generate ISO (Linux only)
nightly:
	./build/build-nightly.sh

## Build packages (debhelper) — requires Linux
package:
	@echo "Building Mission OS packages..."
	@for pkg in mission-core mission-crypto mission-securityd mission-driverd; do \
		echo "  Building $$pkg..."; \
		(cd packages/$$pkg && dpkg-buildpackage -b -uc -us 2>&1) || echo "  ⚠️  Package build failed (requires Linux build environment)"; \
	done

## Validate ISO structure
validate-iso:
	@echo "Validating ISO..."
	@for iso in build/images/*.iso; do \
		if [ -f "$$iso" ]; then \
			./build/validate-iso.sh "$$iso"; \
		fi; \
	done

## Generate version metadata
version:
	./build/nightly-version.sh

## Verify all deployment files exist
verify-deployment:
	@echo "Verifying deployment files..."
	@FAIL=0; \
	for f in \
	src/services/securityd/deploy/mission-securityd.service \
	src/services/securityd/deploy/org.mission.Security1.conf \
	src/services/securityd/deploy/org.mission.security.policy \
	src/services/securityd/deploy/securityd.toml \
	src/services/driverd/deploy/mission-driverd.service \
	src/services/driverd/deploy/org.mission.Driver1.conf \
	src/services/driverd/deploy/org.mission.driver.policy \
	src/services/driverd/deploy/driverd.toml \
		installer/mission-first-boot.sh \
		build/mission-first-boot.service \
		VERSION; do \
		if [ -f "$$f" ]; then \
			echo "  ✅ $$f"; \
		else \
			echo "  ❌ MISSING: $$f"; \
			FAIL=1; \
		fi; \
	done; \
	if [ "$$FAIL" -eq 0 ]; then \
		echo "✅ All deployment files present"; \
	else \
		echo "❌ Some deployment files are missing"; \
		exit 1; \
	fi

# ── Clean Targets ──────────────────────────────────────────────────

clean: cargo-clean cmake-clean

cargo-clean:
	cargo clean

cmake-clean:
	rm -rf $(CMAKE_BUILD_DIR)

# ── CI Target ──────────────────────────────────────────────────────

ci: check test cargo-audit verify-deployment
	@echo "✅ CI pipeline passed"

help:
	@echo "Mission OS Build Targets"
	@echo "  make all             — Build everything"
	@echo "  make libs            — Build all shared libraries"
	@echo "  make check           — Run linters and static analysis"
	@echo "  make test            — Run all tests"
	@echo "  make fmt             — Format all Rust code"
	@echo "  make clean           — Remove build artifacts"
	@echo "  make ci              — Run full CI pipeline"
	@echo "  make nightly         — Build Nightly ISO (Linux only)"
	@echo "  make package         — Build Debian packages (Linux only)"
	@echo "  make validate-iso    — Validate ISO artifacts"
	@echo "  make version         — Generate version metadata"
	@echo "  make verify-deployment — Verify deployment files exist"
