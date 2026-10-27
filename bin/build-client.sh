#!/usr/bin/env bash
# Build one client at one ref, cached by commit. Always in a throwaway worktree, so the
# submodule's checkout and any local edits in it never leak into a measured build.
#
#   bin/build-client.sh rskj    <ref>            -> state/builds/rskj-<sha>.jar
#   bin/build-client.sh rustock <ref> <platform> -> state/builds/rustock-<sha>-<platform>
#        platform: darwin-arm64 (host, for development), linux-arm64 (this Mac's Docker),
#                  linux-amd64 (Boton, Ubuntu 22.04 glibc)
#
# Prints the artifact path on the last line.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CLIENT="${1:?usage: build-client.sh rskj|rustock <ref> [platform]}"; REF="${2:?ref}"
REPO="$LAB/clients/$CLIENT"
SHA=$(git -C "$REPO" rev-parse --verify "$REF^{commit}")

# A jar missing its natives does not fail: RSKj silently falls back to Bouncy Castle /
# JavaAltBN128 and measures a different program. This Mac's Docker is arm64, Boton amd64.
check_natives() {
  local list want; list=$(unzip -l "$1")
  for want in librocksdbjni-linux-aarch64.so librocksdbjni-linux64.so \
              co/rsk/altbn128/cloudflare/native/linux/arm64/libbn128.so \
              co/rsk/altbn128/cloudflare/native/linux/amd64/libbn128.so; do
    case "$list" in *"$want"*) ;; *) echo "jar $1 is missing $want" >&2; return 1 ;; esac
  done
}

worktree() {  # worktree <dir>
  rm -rf "$1"; git -C "$REPO" worktree prune
  git -C "$REPO" worktree add -q --detach "$1" "$SHA"
}

case "$CLIENT" in
rskj)
  OUT="$STATE/builds/rskj-$SHA.jar"
  [ -s "$OUT" ] && { echo "$OUT"; exit 0; }
  WT="$STATE/worktrees/rskj-${SHA:0:12}"; worktree "$WT"
  trap 'git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true' EXIT
  # Two things a fresh RSKj worktree lacks: the untracked gradle wrapper jar, and the
  # mavenLocal filter that lets the locally built co.rsk:native SNAPSHOT resolve.
  cp "$LAB/clients/rskj-build/gradle-wrapper.jar" "$WT/gradle/wrapper/"
  grep -q 'includeModule("co.rsk", "native")' "$WT/rskj-core/build.gradle" \
    || git -C "$WT" apply "$LAB/clients/rskj-build/build-gradle-mavenlocal.patch"
  ( cd "$WT" && ./gradlew :rskj-core:fatJar -x test --console=plain -q ) >&2
  cp "$(ls -t "$WT"/rskj-core/build/libs/*-all.jar | head -1)" "$OUT.tmp"
  check_natives "$OUT.tmp" || { rm -f "$OUT.tmp"; exit 1; }
  mv "$OUT.tmp" "$OUT"
  ;;
rustock)
  PLAT="${3:?platform: darwin-arm64 | linux-arm64 | linux-amd64}"
  OUT="$STATE/builds/rustock-$SHA-$PLAT"
  [ -s "$OUT" ] && { echo "$OUT"; exit 0; }
  WT="$STATE/worktrees/rustock-${SHA:0:12}"; worktree "$WT"
  trap 'git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true' EXIT
  case "$PLAT" in
    darwin-arm64)
      # Its own target dir per worktree would rebuild RocksDB from scratch every time.
      ( cd "$WT" && CARGO_TARGET_DIR="$STATE/cargo-target" cargo build --release --locked -p rustock-cli ) >&2
      cp "$STATE/cargo-target/release/rustock-cli" "$OUT.tmp" ;;
    linux-arm64|linux-amd64)
      # Built inside Ubuntu 22.04 so the binary runs on the Boton boxes' glibc, and the
      # Docker image the campaign runs is the same build.
      docker build -q --platform "linux/${PLAT#linux-}" -f "$LAB/docker/rustock.Dockerfile" \
        -t "clientslab-rustock:${SHA:0:12}-$PLAT" "$WT" >&2
      CT=$(docker create --platform "linux/${PLAT#linux-}" "clientslab-rustock:${SHA:0:12}-$PLAT")
      docker cp "$CT:/usr/local/bin/rustock-cli" "$OUT.tmp"; docker rm "$CT" >/dev/null ;;
    *) echo "unknown platform $PLAT" >&2; exit 1 ;;
  esac
  mv "$OUT.tmp" "$OUT"
  ;;
*) echo "unknown client $CLIENT" >&2; exit 1 ;;
esac
echo "$OUT"
