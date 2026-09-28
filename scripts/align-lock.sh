#!/usr/bin/env bash
# align-lock.sh — make this repo's flake.lock use the NixOS host's nixpkgs rev.
#
# WHY: `flake.nix` deliberately keeps `inputs.nixpkgs.url = …/nixos-unstable`,
# but that is only a BRANCH NAME — what a build actually uses is the `rev`
# recorded in `flake.lock`, and nothing updates it automatically. So this repo
# (last locked 2026-09-08) and the host (2026-09-26) sit on different nixpkgs
# trees, which means different derivations, which means the CI's cache entries
# never match what the host wants to substitute. Aligning the lock is what makes
# the cache hit — without pinning the url.
#
# Reading the host's rev is NOT `grep '"nixpkgs"' flake.lock`: a lock file often
# holds several nixpkgs nodes (the host has a second one for `llm-agents`). This
# script follows `root.inputs.nixpkgs` to the node the host really uses.
#
# Usage:
#   ./scripts/align-lock.sh                        # report only
#   ./scripts/align-lock.sh --host ~/path/to/host   # …against another checkout
#   ./scripts/align-lock.sh --apply                 # rewrite flake.lock (no commit)
#   ./scripts/align-lock.sh --commit                # …and commit
#   ./scripts/align-lock.sh --push                  # …and push (CI poll rebuilds)
#
# NOTE: `nix flake update` here afterwards moves the lock to the branch tip and
# re-introduces the drift. Either re-run this script, or don't update this repo.
set -euo pipefail

HOST="$HOME/Downloads/nixos"
MODE=report
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --apply) MODE=apply; shift ;;
    --commit) MODE=commit; shift ;;
    --push) MODE=push; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

[ -f "$HOST/flake.lock" ] || { echo "no flake.lock under $HOST (pass --host)" >&2; exit 1; }

read_rev() {
  python3 - "$1" <<'PY'
import json, sys

lock = json.load(open(sys.argv[1]))
root = lock["root"]
node = lock["nodes"][root] if isinstance(root, str) else root
ref = node["inputs"]["nixpkgs"]
name = ref if isinstance(ref, str) else ref["node"]
rev = lock["nodes"][name]["locked"]["rev"]
assert len(rev) == 40, rev
print(rev)
PY
}

host_rev=$(read_rev "$HOST/flake.lock")
our_rev=$(read_rev flake.lock)

echo "host  nixpkgs rev: $host_rev"
echo "this  nixpkgs rev: $our_rev"

if [ "$host_rev" = "$our_rev" ]; then
  echo "aligned — the CI's derivation is the one the host substitutes"
  exit 0
fi

echo "DIVERGED — the CI would build a derivation the host never substitutes"
echo "  (url stays nixos-unstable in flake.nix; only the lock rev changes)"

if [ "$MODE" = report ]; then
  echo "would run: nix flake lock --override-input nixpkgs github:NixOS/nixpkgs/$host_rev"
  echo "re-run with --apply (or --commit / --push) to do it"
  exit 0
fi

nix flake lock --override-input nixpkgs "github:NixOS/nixpkgs/$host_rev"

drv=$(nix eval --raw .#foundation-sunshine-upstream.drvPath)
echo "drv after aligning: $drv"
echo "verify it is the host's:"
echo "  nix eval --raw --impure --expr \"let f = builtins.getFlake (toString $HOST); in f.nixosConfigurations.linux.pkgs.foundation-sunshine.drvPath\""

case "$MODE" in
  apply)
    git --no-pager diff --stat
    echo "applied to the working tree (flake.nix untouched)"
    ;;
  commit|push)
    git add flake.lock
    if git diff --cached --quiet; then
      echo "nothing to commit"
    else
      git commit -m "chore(nixpkgs): align flake.lock with host rev ${host_rev:0:8}"
      echo "committed"
    fi
    if [ "$MODE" = push ]; then
      git push
      echo "pushed — the 30-min CI poll rebuilds and republishes for this rev"
    fi
    ;;
esac
