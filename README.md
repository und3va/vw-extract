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

The workflow runs every 12 hours, checks for new Vaultwarden releases, and:
1. Creates Docker containers for each architecture
2. Extracts the Vaultwarden binary and web-vault files
3. Packages the files into platform-specific zip archives
4. Creates GitHub releases with the extracted binaries

## Credits

This project is based on the work done in [czyt/vaultwarden-binary](https://github.com/czyt/vaultwarden-binary) and extends the functionality to support multiple architectures and both Alpine and Debian variants.