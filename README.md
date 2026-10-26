# vw-extract

A GitHub Action workflow to automatically extract Vaultwarden binaries from the official Docker images (Alpine and Debian variants) for multiple architectures.

## Overview

This project extracts and provides standalone Vaultwarden binaries for various architectures:
- amd64 (x86_64)
- arm64 (aarch64)
- armv7
- armv6

Binaries are extracted from both Alpine and Debian-based Docker images, giving users the choice of which variant to use based on their environment.

## How It Works

The workflow runs weekly on Sunday at 00:00 UTC (or manually), checks for new Vaultwarden releases, and:
1. Pulls the matching versioned official image for each variant and architecture, then resolves its image digest
2. Extracts the Vaultwarden binary and web-vault files from a container created using that digest
3. Packages both components and `source-image.json` (release, source tag, digest, and platform) into platform-specific zip archives
4. Creates GitHub releases, or repairs missing assets on an existing release by matching exact filenames

The workflow fails on API/upload errors instead of treating them as missing releases or successful uploads. Existing release assets are left unchanged; the new version matching and provenance metadata apply to newly extracted assets. Docker runs on the GitHub Actions runner, not on the machine using the extracted files. Runtime libraries and the service configuration remain the destination host's responsibility.

The shared `scripts/extract-image.sh` helper keeps version and digest handling consistent across new-release and missing-asset jobs. It runs only on the GitHub Actions runner, using Bash, Docker, and `jq`, which the workflow already uses. There is nothing to install on the Vaultwarden host.

## Validation

Run `bash tests/workflow_test.sh` to exercise extraction, archive contents, API checks, and upload failures with mocked commands. The tests use Bash and the existing command-line tools (`jq`, `zip`, `unzip`, and standard Unix utilities); they do not pull images or publish releases. No Ruby or package installation is required.

## Credits

This project is based on the work done in [czyt/vaultwarden-binary](https://github.com/czyt/vaultwarden-binary) and extends the functionality to support multiple architectures and both Alpine and Debian variants.
