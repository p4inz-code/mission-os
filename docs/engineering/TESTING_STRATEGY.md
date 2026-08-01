# Mission OS Testing Strategy

**Document ID:** MOS-ENG-TEST-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the complete testing strategy for Mission OS, specifying what to test, how to test it, and what must pass before each release milestone.

---

## 2. Testing Pyramid

```
          ┌──────────┐
          │   E2E    │  ← Full system tests in VM
          │  Tests   │     (UI, accessibility, installation)
         ┌┴──────────┴┐
         │ Integration │  ← Service interaction tests
         │   Tests     │     (D-Bus, IPC, hardware)
        ┌┴────────────┴┐
        │  Component   │  ← Individual service tests
        │   Tests      │     (API, state machine, security)
       ┌┴──────────────┴┐
       │    Unit Tests   │  ← Library + utility tests
       │                 │     (pure function, data structure)
       └─────────────────┘
```

---

## 3. Test Types

### 3.1 Unit Tests

**Scope:** Individual functions, data structures, pure logic

**What to test:**
- All public API functions in mission-core, mission-crypto, mission-ui
- Validation logic
- Data serialization/deserialization
- Error handling paths
- Edge cases (empty inputs, boundary values, null values)

**What NOT to test:**
- External dependencies (system calls, D-Bus, hardware)
- Integration between components
- UI rendering

**Tools:**
- Rust: `cargo test`
- C/C++: `ctest` (CMake)
- QML: Qt Test framework (qmltestrunner)

**Requirements:**
- Code coverage > 80% for mission-core and mission-crypto
- Code coverage > 60% for other components
- No regressions allowed before merge

### 3.2 Component Tests

**Scope:** Individual services tested in isolation

**What to test:**
- Service startup and shutdown
- D-Bus method handlers (with mock bus)
- State machine transitions
- Error responses
- Resource limits

**Tools:**
- Python: pytest with dbusmock
- Rust: integration test directory (tests/)
- systemd: service-level testing with sd_notify

**Requirements:**
- Every D-Bus method tested for success + failure paths
- Every service state tested
- Service recovery from crash tested

### 3.3 Integration Tests

**Scope:** Multiple services interacting

**What to test:**
- IPC flows (application → user service → system service)
- PolKit authorization integration
- Service dependency chains
- Update pipeline (check → download → verify → install → rollback)
- Network configuration (NetworkManager + mission-networkd)
- Hardware detection (udev + mission-driverd)

**Tools:**
- pytest with full D-Bus environment
- System test containers (systemd-nspawn)
- Integration test VMs (libvirt / QEMU)

**Requirements:**
- All integration paths tested at least once per release
- Failure injection: simulate network loss, disk full, service crash
- Authorization bypass attempts tested

### 3.4 End-to-End Tests

**Scope:** Full system scenarios in virtual machine

**What to test:**
- Installation from ISO (all installation types)
- First boot experience
- Application launch and basic operations
- Settings changes across all categories
- Update installation and rollback
- Recovery Center workflows
- Lock screen and authentication
- Workspace management
- File management operations
- Privacy and security center operations
- Diagnostics and health checks
- Accessibility features

**Tools:**
- QEMU/KVM with libvirt
- openQA (automated OS testing)
- Selenium/AT-SPI2 for UI automation (QML)
- Custom test harness

**Requirements:**
- Critical user flows tested on every release
- Full test suite at Release Preview stage
- Test on multiple hardware profiles (2GB RAM, 4GB RAM, 8GB RAM)

### 3.5 Security Tests

**Scope:** Security properties and vulnerability discovery

**What to test:**
- Static analysis (SAST): clippy, flawfinder, cppcheck
- Dependency scanning: cargo-audit, OWASP dependency-check
- Penetration testing: D-Bus interface fuzzing, privilege escalation attempts
- Fuzz testing: configuration parsers, IPC message handlers, package parsers
- Property-based testing: cryptographic operations, permission evaluation

**Tools:**
- Rust: cargo-audit, cargo-fuzz, proptest
- D-Bus: dbus-send fuzzing, bus introspection
- Network: nmap, nftables rule testing
- Kernel: syzkaller (future)

**Requirements:**
- Zero critical/high vulnerabilities before any release
- All dependencies scanned for known CVEs
- Fuzz testing for all input-parsing code paths

### 3.6 Performance Tests

**Scope:** System responsiveness and resource usage

**What to test:**
- Boot time (cold boot, warm boot, resume from suspend)
- Application launch time
- Desktop responsiveness (frame rate, input latency)
- Memory usage under load
- CPU usage during idle and typical workloads
- Disk I/O patterns
- Network throughput with/without VPN

**Tools:**
- bootchart (systemd-analyze)
- perf / flamegraph
- custom metrics collection

**Targets:**
| Metric | Target |
|--------|--------|
| Cold boot to desktop | < 30s (SSD) |
| Application launch | < 2s |
| Desktop frame rate | 60fps (typical) |
| Idle memory (desktop) | < 1.5 GB |
| Idle CPU | < 2% |

### 3.7 Accessibility Tests

**Scope:** WCAG compliance and assistive technology compatibility

**What to test:**
- Keyboard navigation: every interactive element reachable
- Screen reader: correct labels, roles, states, values
- Focus management: logical tab order, visible focus indicators
- High contrast mode: all text readable
- Text scaling: no broken layouts at 200% scaling
- Reduced motion: no animations when enabled
- Color independence: no information conveyed only by color

**Tools:**
- Accessibility inspector (Accerciser / Accessibility Inspector)
- AT-SPI2 interface testing
- Manual screen reader testing (Orca)
- Contrast ratio verification

**Requirements:**
- WCAG 2.2 AA compliance for all standard interfaces
- WCAG 2.2 AAA for critical interfaces (Security Center, Privacy Center, Recovery)

### 3.8 Stress Tests

**Scope:** System behavior under extreme conditions

**What to test:**
- Many open applications (50+ windows)
- Very large directory browsing (100,000+ files)
- Concurrent file operations (copy, move, delete)
- Rapid workspace switching
- Multiple rapid lock/unlock cycles
- Rapid repeated updates
- Disk I/O saturation

**Tools:**
- stress-ng
- custom load generators
- fio (disk I/O)

**Requirements:**
- No crashes under stress conditions
- Graceful degradation (OOM killer only as last resort)
- All operations complete eventually

---

## 4. Testing Infrastructure

### 4.1 CI Integration

All tests integrated into GitHub Actions:

```
PR: Unit + Component tests (fast, <10 min)
Merge to main: Unit + Component + Integration (<30 min)
Nightly: Full suite except E2E (<60 min)
Pre-release: Full suite including E2E in VM (<4 hours)
```

### 4.2 Test Environment

- System tests run in QEMU/KVM virtual machines
- CI runners: GitHub-hosted for basic tests, self-hosted for VM tests
- Test matrix: Debian stable base + several kernel versions
- Hardware test lab for physical hardware testing (future)

### 4.3 Test Fixtures

- Sample files for file manager tests
- Sample packages for store tests
- Mock hardware data for driver tests
- Snapshot data for recovery tests
- Configuration files for settings tests

---

## 5. Test Requirements by Milestone

### 5.1 Milestone Completion

At milestone completion:
- All unit tests pass
- Component tests for affected modules pass
- Integration tests for affected flows pass
- No regressions in existing tests

### 5.2 Alpha

- All unit tests pass (all modules)
- All component tests pass
- Core integration tests pass
- Accessibility tests for critical interfaces pass
- Security scan: no critical/high vulnerabilities

### 5.3 Beta

- Full unit test suite passes
- All component tests pass
- Full integration tests pass
- E2E tests for core flows pass
- Accessibility tests: WCAG AA for all interfaces
- Security: penetration testing complete
- Performance: all targets met

### 5.4 Release Candidate

- Full test suite passes
- E2E tests complete on all target hardware profiles
- Stress tests pass
- Upgrade/migration tests pass
- Recovery tests pass
- Security audit complete
- Accessibility audit complete

### 5.5 Stable

- Release Candidate criteria
- All known issues documented
- Release notes include known limitations

---

## 6. Test Documentation

### 6.1 Test Plan Structure

Every module defines:
```
module_name/
├── TESTS.md                  → Module-specific test plan
├── unit/                     → Unit tests
├── component/                → Component tests
├── integration/              → Integration tests
└── fixtures/                 → Test data/fixtures
```

### 6.2 Bug Verification

Every fixed bug includes:
- Regression test that reproduces the original bug
- Verifies the fix
- Added to automated test suite

---

## 7. Testing Principles

1. **Test the behavior, not the implementation.**
2. **Test failure paths as thoroughly as success paths.**
3. **Tests must be deterministic.** No flaky tests allowed.
4. **Test at the right level of the pyramid.**
5. **Module mocks are acceptable for isolation; integration tests verify real interactions.**
6. **Performance tests are automated and regression-checked.**
7. **Security tests are part of the CI pipeline, not an afterthought.**
8. **Accessibility tests are mandatory, not optional.**

---

**End of Document**
