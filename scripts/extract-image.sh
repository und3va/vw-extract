#!/usr/bin/env bash
# Extract a release's matching binary and web vault without using moving tags.
set -euo pipefail

release_version=${1:?release version required}
variant=${2:?alpine or debian required}
arch=${3:?architecture required}
platform=${4:?Docker platform required}
version=${release_version#v}

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid release version: $release_version" >&2
    exit 1
fi
case "$variant" in
    alpine) image="vaultwarden/server:${version}-alpine" ;;
    debian) image="vaultwarden/server:${version}" ;;
    *) echo "Unsupported image variant: $variant" >&2; exit 1 ;;
esac
case "$arch:$platform" in
    amd64:linux/amd64|arm64:linux/arm64|armv7:linux/arm/v7|armv6:linux/arm/v6) ;;
    *) echo "Unsupported architecture/platform: $arch / $platform" >&2; exit 1 ;;
esac

docker pull --platform "$platform" "$image"
image_digest=$(docker image inspect "$image" --format '{{index .RepoDigests 0}}')
if [[ ! "$image_digest" =~ ^vaultwarden/server@sha256:[a-f0-9]{64}$ ]]; then
    echo "Unable to resolve the source image digest for $image" >&2
    exit 1
fi

# Create from the resolved digest so extraction uses the image just pulled.
container_id=$(docker create --platform "$platform" "$image_digest")
trap 'docker rm "$container_id" >/dev/null' EXIT
output_dir="extracted-${variant}-${arch}"
mkdir -p "$output_dir"
docker cp "$container_id:/vaultwarden" "$output_dir/"
docker cp "$container_id:/web-vault" "$output_dir/"
test -s "$output_dir/vaultwarden"
test -d "$output_dir/web-vault"

jq -n --arg release "$release_version" --arg image "$image" \
    --arg digest "$image_digest" --arg platform "$platform" \
    '{release: $release, image: $image, digest: $digest, platform: $platform}' \
    > "$output_dir/source-image.json"
