# Siyarix v1.1.0 — Release Readiness & Distribution Improvements

**Release Date:** 2026-07-10
**Version:** 1.1.0
**Status:** Stable Release

## Overview

Siyarix v1.1.0 focuses on release readiness and platform distribution quality. This release improves installer and uninstaller presentation, aligns package and repository version metadata, strengthens release workflow checks, and resolves known CI failures related to spelling checks and Pages deployment conditions.

## Highlights

- Synchronized version tags to `1.1.0` across runtime metadata, installers/uninstallers, and package manifests.
- Improved installer/uninstaller professionalism with clearer banners and consistent installer one-liner command paths.
- Updated release/distribution references for Docker, DEB, Winget, Homebrew, and Chocolatey assets.
- Hardened GitHub Pages docs deployment behavior to avoid invalid deploy contexts.
- Extended workflow version consistency validation to cover additional installer and package sources.
- Fixed typo detection pipeline failure by updating flagged wording in changelog history.

## Upgrade Notes

- Standard users can continue to upgrade via `pip install -U siyarix`.
- Distribution maintainers should publish refreshed package artifacts and checksums for v1.1.0 before external repository submission.
- Winget installer hash should be regenerated once the v1.1.0 installer artifact is published.

## Validation Summary

- Version consistency aligned across key release metadata files.
- Changelog and release notes updated for v1.1.0.
- CI workflow guardrails improved for release readiness.
