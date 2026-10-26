#!/usr/bin/env bash
# Exercise real workflow shell blocks without network access or Docker.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow="$root/.github/workflows/vaultwarden-dual-extractor.yml"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
export COMMAND_LOG="$scratch/commands" GITHUB_OUTPUT="$scratch/outputs"
export GITHUB_REPOSITORY=test/vw-extract GH_TOKEN=test-token RELEASE_ID=42 RELEASE_VERSION=1.37.4
export PATH="$scratch/bin:$PATH"
cat > "$scratch/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
{ printf '%s' "$name"; printf ' <%s>' "$@"; printf '\n'; } >> "$COMMAND_LOG"
case "$name" in
  gh)
    if [[ ${GH_EXIT:-0} != 0 ]]; then exit "$GH_EXIT"; fi
    if [[ "$*" == *repos/dani-garcia/vaultwarden/releases/latest* ]]; then
      printf '%s\n' "${FAKE_VERSION:-1.37.4}"
    else
      [[ "$*" == *--paginate* ]] || exit 99
      printf '%s\n' "${ASSET_NAMES:-}"
    fi ;;
  curl)
    output= upload= fail=false
    while (($#)); do
      case "$1" in
        --output) output=$2; shift ;; -T) upload=$2; shift ;; --fail-with-body) fail=true ;;
      esac
      shift
    done
    status=${HTTP_STATUS:-200}
    if [[ -n "$output" ]]; then
      if [[ ${RELEASE_BODY+x} ]]; then printf '%s' "$RELEASE_BODY" > "$output"
      else printf '{"id":42}' > "$output"; fi
      printf '%s' "$status"
    else
      [[ -f "$upload" ]] || exit 99
      if [[ "$fail" == true && "$status" -ge 400 ]]; then exit 22; fi
      printf '{"id":7}\n'
    fi ;;
  docker)
    case "$1" in
      pull) exit "${PULL_EXIT:-0}" ;;
      image) printf '%s\n' "${IMAGE_DIGEST-vaultwarden/server@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" ;;
      create) printf 'test-container\n' ;;
      cp)
        item=${2#*:}
        [[ ${COPY_FAIL:-} != "$item" ]] || exit 1
        case "$item" in
          /vaultwarden) printf 'test binary' > "$3/vaultwarden" ;;
          /web-vault) mkdir -p "$3/web-vault"; printf 'test web vault' > "$3/web-vault/index.html" ;;
          *) exit 99 ;;
        esac ;;
      rm) : ;; *) exit 99 ;;
    esac ;;
  *) exit 99 ;;
esac
MOCK
chmod +x "$scratch/bin/mock"
for name in gh curl docker; do ln -s mock "$scratch/bin/$name"; done
cd "$scratch"
checks=0
pass() { checks=$((checks + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$scratch/stderr" >&2; exit 1; }
expect_pass() {
  if "$@" > "$scratch/stdout" 2> "$scratch/stderr"; then pass; else fail "$*"; fi
}
expect_fail() {
  if "$@" > "$scratch/stdout" 2> "$scratch/stderr"; then fail "Unexpected success: $*"; else pass; fi
}
# Extract literal run blocks using this workflow's indentation. This harness
# tests shell behavior; it does not replace GitHub's YAML/schema validation.
block() {
  awk -v job="$1" -v step="$2" '
    $0 == "  " job ":" { in_job=1; next }
    in_job && /^  [^ ]/ { in_job=0 }
    in_job && $0 == "      - name: " step { in_step=1; next }
    in_step && /^      - / { exit }
    in_step && $0 == "        run: |" { in_run=1; next }
    in_run && /^          / { print substr($0, 11); next }
    in_run && /^[[:space:]]*$/ { print ""; next }
    in_run { exit }
  ' "$workflow"
}
render() {
  sed -e 's/${{ matrix.arch }}/arm64/g' \
      -e 's|${{ matrix.platform }}|linux/arm64|g' \
      -e 's/${{ secrets.GITHUB_TOKEN }}/test-token/g' \
      -e 's|${{ github.repository }}|test/vw-extract|g' \
      -e 's/${{ needs.check-and-prepare.outputs.alpine_release_id }}/42/g' \
      -e 's/${{ needs.check-and-prepare.outputs.debian_release_id }}/42/g' \
      -e 's/${{ steps.create_alpine_release.outputs.id }}/42/g' \
      -e 's/${{ steps.create_debian_release.outputs.id }}/42/g'
}
run_step() {
  local script
  script=$(block "$1" "$2" | render)
  [[ -n "$script" ]] || return 99
  bash -euo pipefail -c "$script"
}
expect_pass bash -n "$root/scripts/extract-image.sh"
expect_pass run_step check-and-prepare 'Get latest release version'
for version in null latest 1.37.4-invalid; do
  export FAKE_VERSION=$version
  expect_fail run_step check-and-prepare 'Get latest release version'
done
unset FAKE_VERSION
export GH_EXIT=1
expect_fail run_step check-and-prepare 'Get latest release version'
unset GH_EXIT
for variant in alpine debian; do
  title="$(printf '%s' "$variant" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }')"
  expect_pass run_step check-and-prepare "Check if $title release exists"
  [[ $(tail -n1 "$GITHUB_OUTPUT") == RELEASE_ID=42 ]] || fail 'Missing release ID'
  export HTTP_STATUS=404
  expect_pass run_step check-and-prepare "Check if $title release exists"
  [[ $(tail -n1 "$GITHUB_OUTPUT") == exists=false ]] || fail '404 was not treated as absence'
  for status in 403 429 500; do
    export HTTP_STATUS=$status
    expect_fail run_step check-and-prepare "Check if $title release exists"
  done
  unset HTTP_STATUS
  export RELEASE_BODY='{"id":null}'
  expect_fail run_step check-and-prepare "Check if $title release exists"
  unset RELEASE_BODY
  target="vaultwarden-${variant}-arm64-extracted.zip"
  for names in '' "$target.old" "vaultwarden-${variant}-amd64-extracted.zip"; do
    export ASSET_NAMES=$names
    expect_pass run_step "update-existing-$variant-release" "Check if $title asset exists"
    [[ $(tail -n1 "$GITHUB_OUTPUT") == exists=false ]] || fail 'Nonmatching asset reported present'
  done
  export ASSET_NAMES="other.zip
$target"
  expect_pass run_step "update-existing-$variant-release" "Check if $title asset exists"
  [[ $(tail -n1 "$GITHUB_OUTPUT") == exists=true ]] || fail 'Exact asset not found'
  export GH_EXIT=1
  expect_fail run_step "update-existing-$variant-release" "Check if $title asset exists"
  unset GH_EXIT ASSET_NAMES
  for arch in amd64 arm64 armv7 armv6; do
    case "$arch" in
      amd64) platform=linux/amd64 ;; arm64) platform=linux/arm64 ;;
      armv7) platform=linux/arm/v7 ;; armv6) platform=linux/arm/v6 ;;
    esac
    expect_pass bash "$root/scripts/extract-image.sh" v1.37.4 "$variant" "$arch" "$platform"
    image=vaultwarden/server:1.37.4
    [[ "$variant" != alpine ]] || image=$image-alpine
    expect_pass jq -e --arg image "$image" --arg platform "$platform" \
      '.image == $image and .platform == $platform and (.digest | test("^vaultwarden/server@sha256:[a-f0-9]{64}$"))' \
      "extracted-$variant-$arch/source-image.json"
    [[ -s "extracted-$variant-$arch/vaultwarden" && -f "extracted-$variant-$arch/web-vault/index.html" ]] || fail 'Missing extracted components'
    grep -Fq "docker <create> <--platform> <$platform> <vaultwarden/server@sha256:" "$COMMAND_LOG" || fail 'Container was not created by digest'
  done
  for job in "extract-$variant" "update-existing-$variant-release"; do
    expect_pass run_step "$job" "Zip extracted $title files"
    unzip -Z1 "$target" > "$scratch/zip-contents"
    for member in vaultwarden web-vault/index.html source-image.json; do
      grep -Fxq "$member" "$scratch/zip-contents" || fail "Missing ZIP member: $member"
    done
  done
  expect_pass run_step "update-existing-$variant-release" "Upload $title Release Asset"
  grep -Fq "assets?name=$target>" "$COMMAND_LOG" || fail 'Wrong repair-upload filename'
  export HTTP_STATUS=422
  expect_fail run_step "update-existing-$variant-release" "Upload $title Release Asset"
  unset HTTP_STATUS
  for arch in amd64 arm64 armv7 armv6; do
    dir="$variant-artifacts/vaultwarden-$variant-$arch-extracted"
    mkdir -p "$dir"
    printf 'archive' > "$dir/vaultwarden-$variant-$arch-extracted.zip"
  done
  : > "$COMMAND_LOG"
  expect_pass run_step "create-$variant-release" "Upload $title Release Assets"
  [[ $(grep -c '^curl ' "$COMMAND_LOG") == 4 ]] || fail 'Expected four release uploads'
  : > "$COMMAND_LOG"
  export HTTP_STATUS=422
  expect_fail run_step "create-$variant-release" "Upload $title Release Assets"
  [[ $(grep -c '^curl ' "$COMMAND_LOG") == 1 ]] || fail 'Uploads continued after HTTP error'
  unset HTTP_STATUS
done
export PULL_EXIT=1
expect_fail bash "$root/scripts/extract-image.sh" 1.37.4 alpine amd64 linux/amd64
unset PULL_EXIT
export IMAGE_DIGEST=''
expect_fail bash "$root/scripts/extract-image.sh" 1.37.4 alpine amd64 linux/amd64
unset IMAGE_DIGEST
export COPY_FAIL=/web-vault
expect_fail bash "$root/scripts/extract-image.sh" 1.37.4 alpine amd64 linux/amd64
grep -Fq 'docker <rm> <test-container>' "$COMMAND_LOG" || fail 'Container cleanup missing'
unset COPY_FAIL
expect_fail bash "$root/scripts/extract-image.sh" latest alpine amd64 linux/amd64
printf 'Passed %s checks (mocked Docker/GitHub; no network or publication).\n' "$checks"
