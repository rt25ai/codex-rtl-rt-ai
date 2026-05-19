# Security Policy

## Supported versions

The latest tagged release is the only supported version. Pre-release commits
on `main` are not officially supported and may change without notice.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| < latest| :x:                |

## Reporting a vulnerability

If you find a security issue, please report it **privately** so users are
protected during triage:

- Preferred: open a GitHub
  [Security Advisory draft](https://github.com/rt25ai/codex-rtl-rt-ai/security/advisories/new)
  on this repository.
- Alternative: email `roi@rt-ai.co.il` with the subject line
  `[security] codex-rtl-rt-ai`. Please include a clear reproduction, the
  affected version (release tag), and your suggested mitigation if any.

I will acknowledge within 72 hours, work with you on a fix, and credit you
in the release notes if you'd like.

**Please do not** open a public issue for sensitive disclosures.

## Trust model

The one-line installers pin to a **signed release tag**, not the `main`
branch. A compromised `main` branch cannot silently affect users who run
the published one-liner.

If you intentionally want the bleeding-edge code from `main`, pass
`-Branch main` (PowerShell) or `RT_AI_CODEX_BRANCH=main` (bash). Do this
only if you understand the implications.

## What is in scope

- Remote code execution paths in the install / uninstall scripts.
- Privilege escalation via the patcher (the patcher is designed to run as
  the current user without admin; bypasses are a concern).
- Insecure handling of downloaded payloads, archives, or fuses.
- Path traversal or directory deletion outside the documented locations.

## What is out of scope

- The fact that the patched Codex copy is no longer MSIX-signed (Windows)
  or carries only an ad-hoc signature (macOS) - this is required by the
  patch and documented in the README.
- The fact that disabling the ASAR integrity fuse is required to load the
  modified `app.asar` - also documented.
- Issues caused by passing `-Branch main` or otherwise overriding the
  default pinned release tag.
- The behaviour of `npx --yes @electron/asar` / `@electron/fuses` - those
  are upstream Electron packages; report issues to the
  [@electron](https://github.com/electron) organisation.
