#!/usr/bin/env bash
# Build a portable tarball from the foundation-sunshine Nix closure.
#
# Why: the Nix build output is bound to /nix/store absolute paths (ELF
# interpreter, RPATH, wrapper shebangs, LD_LIBRARY_PATH). Copying the store
# paths to a non-Nix host does not run ("bad interpreter", "required file
# not found", every lib "not found") — the closure ITSELF must ship.
#
# How: stage the full runtime closure under ONE fixed prefix
#   <PREFIX>/bin,lib,share,...          (the package output)
#   <PREFIX>/nix/store/...              (the closure, relocated)
# then rewrite EVERY /nix/store reference:
#   - text files (wrapper scripts, cmake configs): sed
#   - ELF interpreter + RPATH/RUNPATH: patchelf (per-ELF prefix swap)
#   - store symlinks: re-point into the relocated tree
# Result: a self-contained bundle under /opt/sunshine-portable with its own
# glibc/ld.so; the host needs NOTHING (no patchelf, no Nix, works on older
# distros — glibc 2.42 rides along). TLS uses the host CA bundle
# (/etc/ssl/certs/ca-certificates.crt). Nothing is written outside the prefix.
#
# Install on the target:
#   sudo tar -C / -xzf foundation-sunshine-*-portable-linux-x86_64.tar.gz
#   /opt/sunshine-portable/bin/sunshine
#
# Usage:
#   scripts/make-portable-tarball.sh [OUT.tar.gz] [--store-path <path>] [--prefix <p>]
# Default: builds .#foundation-sunshine (CPU variant) via nix build.
set -euo pipefail

OUT=""
SRC=""
PREFIX="/opt/sunshine-portable"

while [ $# -gt 0 ]; do
  case "$1" in
    --store-path) SRC="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) OUT="$1"; shift ;;
  esac
done
[ -n "$SRC" ] || SRC=$(nix build .#foundation-sunshine --no-link --print-out-paths | tail -1)
[ -d "$SRC/bin" ] || { echo "not a package output: $SRC" >&2; exit 1; }

VERSION=$(ls "$SRC/bin" | grep -oP 'sunshine-\K[0-9.]+$' | head -1)
[ -n "$VERSION" ] || { echo "cannot detect version from $SRC/bin" >&2; exit 1; }
[ -n "$OUT" ] || OUT="foundation-sunshine-${VERSION}-portable-linux-x86_64.tar.gz"

case "$PREFIX" in
  /*) ;; *) echo "prefix must be absolute: $PREFIX" >&2; exit 1 ;;
esac

WORK=$(mktemp -d /tmp/fs-portable.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
PAYLOAD="$WORK$PREFIX"
mkdir -p "$PAYLOAD"

echo "== closure: $SRC"
N_PATHS=$(nix path-info -r "$SRC" | wc -l)
echo "== copying $N_PATHS store paths into \$PREFIX/nix/store"
# tar pipeline, NOT `cp -a -t`: cp dereferences symlinks given as explicit
# argv (cross-package links like libgcc_s.so.1 then vanish as links), tar
# preserves symlinks/hardlinks/modes faithfully.
# GNU tar strips ONE leading '/' from stored members (/nix/store/x ->
# nix/store/x), so extract at the payload ROOT for the tree to land at
# $PAYLOAD/nix/store/x exactly.
nix path-info -r "$SRC" | tr '\n' '\0' | tar -C / --null -T - -cf - | tar -C "$PAYLOAD" -xf -
echo "== copying package output to payload root"
cp -a --no-preserve=ownership "$SRC/." "$PAYLOAD/"
# store entries are r-x; every rewrite step below needs write access
chmod -R u+w "$PAYLOAD" 2>/dev/null || true

echo "== structural sanity (fail fast before the expensive rewrite)"
STAGED=$(find "$PAYLOAD/nix/store" -mindepth 1 -maxdepth 1 | wc -l)
[ "$STAGED" = "$N_PATHS" ] || { echo "staged store entries ($STAGED) != closure paths ($N_PATHS) — copy failed" >&2; exit 1; }
if [ -e "$PAYLOAD/nix/store/nix" ]; then
 echo "nested nix/store/nix — extraction double-prefixed" >&2; exit 1
fi
ldso=$(find "$PAYLOAD/nix/store" -maxdepth 3 -name 'ld-linux-*.so.*' -path '*/lib/*' | head -1)
[ -n "$ldso" ] || { echo "ld.so missing from staged closure — extraction failed" >&2; exit 1; }
echo "  $STAGED store paths staged, ld.so: ${ldso#"$PAYLOAD"}"

echo "== rewriting symlinks that point into the store"
find "$PAYLOAD" -type l -print0 |
while IFS= read -r -d '' l; do
  t=$(readlink "$l")
  case "$t" in
    /nix/store/*) ln -sfn "$PREFIX$t" "$l" ;;
  esac
done
# NOTE: do NOT prune "dangling" links here — every store-pointing link was
# just rewritten to an absolute $PREFIX/... path, which necessarily dangles
# WITHIN the stage and only resolves once the tarball is extracted to /.
# (Pruning here silently deleted libgcc_s.so.1 et al. — the original bug.)

echo "== rewriting text files"
# idempotent: normalize any previous rewrite back, then rewrite once
grep -rlI -F '/nix/store/' "$PAYLOAD" 2>/dev/null |
while IFS= read -r f; do
  chmod u+w "$f"
  sed -i "s|$PREFIX/nix/store/|/nix/store/|g; s|/nix/store/|$PREFIX/nix/store/|g" "$f"
done

echo "== rewriting ELF interpreter + RPATH"
if ! command -v patchelf >/dev/null 2>&1; then
  PATCHELF_BIN=$(nix build nixpkgs#patchelf --no-link --print-out-paths)/bin/patchelf
else
  PATCHELF_BIN=patchelf
fi
find "$PAYLOAD" -type f -print0 |
while IFS= read -r -d '' f; do
  head -c 4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
  interp=$("$PATCHELF_BIN" --print-interpreter "$f" 2>/dev/null || true)
  case "$interp" in
    /nix/store/*) "$PATCHELF_BIN" --set-interpreter "$PREFIX$interp" "$f" ;;
  esac
  rp=$("$PATCHELF_BIN" --print-rpath "$f" 2>/dev/null || true)
  case "$rp" in
    *"/nix/store/"*) "$PATCHELF_BIN" --set-rpath "${rp//\/nix\/store//$PREFIX/nix/store/}" "$f" ;;
  esac
done

echo "== re-pointing store symlinks"
find "$PAYLOAD/nix/store" -type l -print0 |
while IFS= read -r -d '' l; do
  t=$(readlink "$l")
  case "$t" in
    /nix/store/*)
      if [ -e "$PAYLOAD$t" ]; then ln -sfn "$PREFIX$t" "$l"
      else echo "  warn: dangling after rewrite: $l -> $t" >&2; fi ;;
  esac
done

echo "== verifying: no live /nix/store references remain"
# /nix/store/ is a substring of every REWRITTEN ref ($PREFIX/nix/store/...),
# so raw substring checks false-positive on the fix itself. Text: PCRE
# negative lookbehind on the prefix. ELF: strip rewritten refs, then check.
BAD=0
while IFS= read -r f; do
  echo "  leftover text ref: $f" >&2; BAD=1
done < <(grep -rIlP "(?<!${PREFIX})/nix/store/" "$PAYLOAD" 2>/dev/null || true)
find "$PAYLOAD" -type f -print0 |
while IFS= read -r -d '' f; do
  head -c 4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
  i=$("$PATCHELF_BIN" --print-interpreter "$f" 2>/dev/null || true)
  r=$("$PATCHELF_BIN" --print-rpath "$f" 2>/dev/null || true)
  case "${i//"$PREFIX/nix/store/"/}" in *"/nix/store/"*) echo "  leftover interp: $f" >&2; exit 9 ;; esac
  case "${r//"$PREFIX/nix/store/"/}" in *"/nix/store/"*) echo "  leftover rpath: $f" >&2; exit 9 ;; esac
done || BAD=1
[ "$BAD" = 0 ] || { echo "rewrite incomplete" >&2; exit 1; }

echo "== writing README"
cat > "$PAYLOAD/README-portable.txt" <<EOF
Foundation Sunshine $VERSION — portable Linux bundle (x86_64)
=============================================================
Relocated Nix closure: every library (incl. glibc/ld.so) is bundled under
this directory; the host needs nothing. TLS uses the host CA bundle.

Run:
  ${PREFIX}/bin/sunshine

Notes:
- Web UI: http://localhost:47990  (config in ~/.config/sunshine)
- mDNS discovery needs avahi-daemon on the host; manual IP connect works without.
- systemd user unit: ${PREFIX}/lib/systemd/user/sunshine.service
  (NixOS hosts: prefer the flake — do NOT untar into /nix/store.)
- Uninstall: sudo rm -rf ${PREFIX}
EOF

echo "== packing $OUT"
tar -C "$WORK" -czf "$OUT.tmp" "${PREFIX#/}"
mv "$OUT.tmp" "$OUT"
ls -lh "$OUT"
echo "done: $OUT  (install with: sudo tar -C / -xzf $OUT)"
