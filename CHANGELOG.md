# Changelog

All notable changes to the PMP Skada rewrite are documented here.

## 1.0.0 - 2026-09-01

### Added

- Stable Vanilla 1.12.1 and ClassicAPI combat-meter release.
- Damage, healing, threat, mitigation, utility, aura, and death analysis.
- Multiple independently configured meter windows and native settings.
- Automated test validation and tag-driven release packaging.

### Changed

- Organized runtime modules into subsystem directories with qualified
  filenames.
- Split the test suite into ordered domain suites behind a single
  orchestrator with a stubbed environment and shared harness.
- Limited the install archive to runtime files, media, the TOC, and consolidated
  license notices.
- Reworked the interface, threat handling, segment navigation, documentation,
  licensing, and third-party attribution for the PMP release.

### Fixed

- Corrected parser diagnostics, boss targeting, short-segment timing, saved-fight
  selection, mitigation observations, cast targets, reset initialization, aura
  uptime bounds, and periodic callback isolation.
