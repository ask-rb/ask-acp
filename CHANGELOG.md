# Changelog

All notable changes to ask-acp are documented here, following
the keep-a-changelog format.

## [Unreleased]

## [0.1.2] - 2026-09-04

### Fixed

- Repository hygiene: added CI workflow (Ruby 3.2–3.4 matrix) and
  release docs to match the other ask-rb gems.

## [0.1.0] - 2026-08-11

### Added

- Ruby implementation of the Agent Client Protocol (ACP): JSON-RPC 2.0
  over stdio, following the v0.11.3 protocol schema.
- Client that drives an ACP-compliant coding agent as a subprocess.
- Server base class for making a Ruby agent speak ACP.
- Replay client for deterministic testing.
