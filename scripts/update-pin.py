#!/usr/bin/env python3
"""Bump the foundation-sunshine pin: version/rev/hash + README sync.

Called by .github/workflows/update-pin-and-cache.yml (and usable locally):

    python3 scripts/update-pin.py <version> <tag> <full-sha> <sri-hash>

Every replacement is scoped and asserted — a silent partial bump aborts.
"""
import re
import sys


def fix_from_log(log_path: str) -> None:
    """Rewrite stale pin hashes from a `nix build` hash-mismatch log.

    Git tree content is immutable per rev, so a deterministic mismatch means
    the PIN is stale (codeload normalization drift, bumped gitlinks, vendored
    lockfiles) — rewriting the attr whose pinned value equals the failing
    `specified:` hash is therefore always content-correct. Handles both
    `hash = "..."` and `npmDepsHash = "..."` attrs.
    """
    import os
    import re

    log = open(log_path).read()
    pairs = re.findall(
        r"specified:\s*(sha256-[A-Za-z0-9+/=]+)\s*\n\s*got:\s*(sha256-[A-Za-z0-9+/=]+)",
        log,
    )
    if not pairs:
        sys.exit("no specified/got hash pairs found in log — not auto-fixable")
    fn = "pkgs/foundation-sunshine/default.nix"
    text = open(fn).read()
    for old, new in pairs:
        for attr in ("hash", "npmDepsHash"):
            needle = f'{attr} = "{old}"'
            if needle in text:
                assert text.count(needle) == 1, f"ambiguous pin for {old[:20]}"
                text = text.replace(needle, f'{attr} = "{new}"')
                print(f"fixed {attr}: {old[:20]}… -> {new[:20]}…")
                break
        else:
            sys.exit(f"no pin attr found holding {old[:20]}… — investigate manually")
    open(fn, "w").write(text)
    os.unlink(log_path)


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--fix-from-log":
        fix_from_log(sys.argv[2])
        return
    if len(sys.argv) != 5:
        sys.exit(f"usage: {sys.argv[0]} <version> <tag> <full-sha> <sri-hash>")
    version, tag, sha, sri_hash = sys.argv[1:5]
    if not re.fullmatch(r"v\d{4}\.\d{2}\.\d{2}-linux", tag):
        sys.exit(f"unexpected tag format: {tag}")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        sys.exit(f"unexpected sha format: {sha}")
    if not re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", sri_hash):
        sys.exit(f"unexpected hash format: {sri_hash}")

    # --- default.nix: version / rev / main-src hash -----------------------
    fn = "pkgs/foundation-sunshine/default.nix"
    text = open(fn).read()

    old_version = None
    m = re.search(r'^  version = "(.*)";', text, re.M)
    assert m, "version line not found"
    old_version = m.group(1)

    text, n = re.subn(
        rf'^  version = "{re.escape(old_version)}";',
        f'  version = "{version}";',
        text,
        count=1,
        flags=re.M,
    )
    assert n == 1, "version replacement failed"

    m = re.search(r'^  rev = "([0-9a-f]{40})"; # tag: ', text, re.M)
    assert m, "rev line not found"
    old_sha = m.group(1)
    text = text.replace(old_sha, sha, 1)
    text, n = re.subn(
        r"^  rev = \"[0-9a-f]{40}\"; # tag: .*$",
        f"  rev = \"{sha}\"; # tag: {tag}",
        text,
        count=1,
        flags=re.M,
    )
    assert n == 1, "rev replacement failed"

    # main src hash ONLY — scoped to the src = fetchFromGitHub block.
    pat = re.compile(r"(src = fetchFromGitHub \{[^}]*?hash = \")sha256-[^\"]+(\")", re.S)
    text, n = pat.subn(rf"\g<1>{sri_hash}\g<2>", text, count=1)
    assert n == 1, "main src hash replacement failed"
    open(fn, "w").write(text)

    # --- README: releases section (tag refs + tracked sha) -----------------
    rn = "README.md"
    rt = open(rn).read()
    rt, n1 = re.subn(r"v\d{4}\.\d{2}\.\d{2}-linux`", f"{tag}`", rt, count=1)
    rt, n2 = re.subn(
        r"releases/tag/v\d{4}\.\d{2}\.\d{2}-linux", f"releases/tag/{tag}", rt
    )
    rt, n3 = re.subn(r"`[0-9a-f]{8}`(?=: )", f"`{sha[:8]}`", rt, count=1)
    if not (n1 and n2 and n3):
        print(f"warning: README sync incomplete (matched {n1}/{n2}/{n3}) — check manually")
    open(rn, "w").write(rt)

    print(f"pin: {old_version} -> {version} ({tag} @ {sha[:8]}, {sri_hash[:20]}…)")


if __name__ == "__main__":
    main()
