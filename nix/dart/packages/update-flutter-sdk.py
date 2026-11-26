## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

#! /usr/bin/env python3
"""
Update flutter-sdk-data.json and dart-sdk.nix to the latest stable Flutter.

Designed to be run twice — once on each platform — then merged:

  # On x86_64-linux:
  python3 update-flutter-sdk.py --output linux.json

  # On aarch64-darwin:
  python3 update-flutter-sdk.py --output darwin.json

  # Merge both into the final files:
  python3 update-flutter-sdk.py --merge linux.json darwin.json
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

REPO_ROOT = Path(__file__).resolve().parents[3]
DATA_FILE = REPO_ROOT / "nix/dart/packages/flutter-sdk-data.json"
DART_SDK_NIX = REPO_ROOT / "nix/dart/packages/dart-sdk.nix"

# Platforms we actually care about (what our CI runners are).
# aarch64-linux, fuchsia, windows are intentionally omitted.
ARTIFACT_PLATFORMS = ["android", "ios", "linux", "macos", "universal", "web"]
SYSTEM_PLATFORMS = ["x86_64-linux", "aarch64-darwin"]


# ---------------------------------------------------------------------------
# Nix helpers
# ---------------------------------------------------------------------------

def nixpkgs_path():
    lock = json.loads((REPO_ROOT / "flake.lock").read_text())
    rev = lock["nodes"]["nixpkgs"]["locked"]["rev"]
    result = subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr",
         f'builtins.getFlake "github:NixOS/nixpkgs/{rev}"'],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"Could not resolve nixpkgs: {result.stderr.strip()}")
    return result.stdout.strip()


NIXPKGS = None


def get_nixpkgs():
    global NIXPKGS
    if not NIXPKGS:
        print("Resolving pinned nixpkgs...", flush=True)
        NIXPKGS = nixpkgs_path()
    return NIXPKGS


def nix_build_to_fail(expr):
    """Build a nix expr, expecting failure; return stderr (contains 'got:' hashes)."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".nix", delete=False) as f:
        f.write(expr)
        tmp = f.name
    proc = subprocess.run(
        ["nix-build", "--impure", "--keep-going", "--no-link",
         "--expr", f"with import {get_nixpkgs()} {{}}; callPackage {tmp} {{}}"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    Path(tmp).unlink(missing_ok=True)
    return proc.stderr


def nix_build(expr):
    """Build a nix expr successfully; return first output store path."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".nix", delete=False) as f:
        f.write(expr)
        tmp = f.name
    proc = subprocess.run(
        ["nix-build", "--impure", "--no-out-link",
         "--expr", f"with import {get_nixpkgs()} {{}}; callPackage {tmp} {{}}"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    Path(tmp).unlink(missing_ok=True)
    if proc.returncode != 0:
        sys.exit(f"nix build failed:\n{proc.stderr}")
    return proc.stdout.strip().splitlines()[0]


def got_hashes(stderr):
    return re.findall(r"got:\s+(sha256-\S+)", stderr)


# ---------------------------------------------------------------------------
# Fetchers
# ---------------------------------------------------------------------------

def get_flutter_hash(version):
    stderr = nix_build_to_fail(f"""
{{ fetchFromGitHub }}: fetchFromGitHub {{
  owner = "flutter"; repo = "flutter"; tag = "{version}"; hash = "{FAKE_HASH}";
}}""")
    hashes = got_hashes(stderr)
    if not hashes:
        sys.exit(f"Could not get flutter source hash for {version}")
    return hashes[0]


def get_dart_hashes(dart_version):
    systems = {
        "x86_64-linux": "linux-x64",
        "aarch64-linux": "linux-arm64",
        "aarch64-darwin": "macos-arm64",
    }
    result = {}
    for nix_sys, dart_sys in systems.items():
        stderr = nix_build_to_fail(f"""
{{ fetchurl }}: fetchurl {{
  url = "https://storage.googleapis.com/dart-archive/channels/stable/release/{dart_version}/sdk/dartsdk-{dart_sys}-release.zip";
  hash = "{FAKE_HASH}";
}}""")
        hashes = got_hashes(stderr)
        if not hashes:
            sys.exit(f"Could not get dart hash for {nix_sys}")
        result[nix_sys] = hashes[0]
    return result


def get_swiftshader_rev(engine_version):
    with urllib.request.urlopen(
        f"https://raw.githubusercontent.com/flutter/flutter/{engine_version}/DEPS"
    ) as r:
        deps = r.read().decode()
    # Find 40-char hex hash on the line containing 'swiftshader' + '@'
    for line in deps.splitlines():
        if "swiftshader" in line.lower() and "@" in line:
            m = re.search(r"[0-9a-f]{40}", line)
            if m:
                return m.group(0)
    sys.exit("Could not find SwiftShader rev in DEPS")


def get_swiftshader_hash(rev):
    stderr = nix_build_to_fail(f"""
{{ fetchgit }}: fetchgit {{
  url = "https://swiftshader.googlesource.com/SwiftShader.git";
  rev = "{rev}";
  postFetch = ''rm -rf $out/third_party/llvm-project'';
  hash = "{FAKE_HASH}";
}}""")
    hashes = got_hashes(stderr)
    if not hashes:
        sys.exit(f"Could not get SwiftShader hash for {rev}")
    return hashes[0]


def get_pubspec_lock(flutter_version, dart_version, dart_hashes):
    import platform
    machine = platform.machine().lower()
    sys_name = platform.system().lower()
    if "darwin" in sys_name:
        nix_sys = "aarch64-darwin"
    elif "arm" in machine or "aarch64" in machine:
        nix_sys = "aarch64-linux"
    else:
        nix_sys = "x86_64-linux"

    dart_hash = dart_hashes[nix_sys]

    # First pass: get the lock file hash
    expr_tmpl = """
{{ dart-bin, stdenv, writableTmpDirAsHomeHook, cacert }}:
let
  dart = (dart-bin.overrideAttrs (old: {{
    version = "{dart_version}";
    __intentionallyOverridingVersion = true;
  }})).overrideAttrs (old: {{
    src = old.src.overrideAttrs (_: {{ hash = "{dart_hash}"; }});
  }});
in stdenv.mkDerivation {{
  name = "pubspec-lock";
  src = builtins.fetchGit {{
    url = "https://github.com/flutter/flutter";
    ref = "refs/tags/{flutter_version}";
    allRefs = true;
  }};
  nativeBuildInputs = [ dart writableTmpDirAsHomeHook cacert ];
  outputHashAlgo = "sha256"; outputHashMode = "recursive"; outputHash = "{output_hash}";
  buildPhase = "cd packages/flutter_tools && dart --root-certs-file=${{cacert}}/etc/ssl/certs/ca-bundle.crt pub get";
  installPhase = "cp pubspec.lock $out";
}}"""

    stderr = nix_build_to_fail(expr_tmpl.format(
        dart_version=dart_version, dart_hash=dart_hash,
        flutter_version=flutter_version, output_hash=FAKE_HASH,
    ))
    hashes = got_hashes(stderr)
    if not hashes:
        sys.exit("Could not get pubspec.lock hash")

    lock_path = nix_build(expr_tmpl.format(
        dart_version=dart_version, dart_hash=dart_hash,
        flutter_version=flutter_version, output_hash=hashes[0],
    ))

    try:
        import yaml
    except ImportError:
        sys.exit("pyyaml required: nix shell nixpkgs#python3Packages.pyyaml")

    with open(lock_path) as f:
        return yaml.safe_load(f)


def get_artifact_hashes(flutter_version, engine_version, dart_version,
                        dart_hashes, flutter_hash, swiftshader_hash,
                        swiftshader_rev, pubspec_lock):
    """
    Build a wrapped flutter with fake artifact hashes; nix reports the real ones.
    Only fetches hashes for the current host platform.
    """
    dart_hash_nix = "\n      ".join(
        f'"{k}" = "{v}";' for k, v in dart_hashes.items()
    )
    pubspec_json = json.dumps(pubspec_lock)
    platforms_nix = "\n      ".join(
        f'{p} = {{ "x86_64-linux" = "{FAKE_HASH}"; "aarch64-linux" = "{FAKE_HASH}"; "aarch64-darwin" = "{FAKE_HASH}"; }};'
        for p in ARTIFACT_PLATFORMS
    )

    stderr = nix_build_to_fail(f"""
{{ flutterPackages, lib }}:
let
  pubspecLock = builtins.fromJSON ''{pubspec_json}'';
  flutter = flutterPackages.mkFlutter {{
    version = "{flutter_version}";
    engineVersion = "{engine_version}";
    engineSwiftShaderHash = "{swiftshader_hash}";
    engineSwiftShaderRev = "{swiftshader_rev}";
    engineHashes = {{}};
    enginePatches = [];
    dartVersion = "{dart_version}";
    flutterHash = "{flutter_hash}";
    dartHash = {{ {dart_hash_nix} }};
    patches = [];
    inherit pubspecLock;
    artifactHashes = {{ {platforms_nix} }};
    channel = "stable";
  }};
in flutterPackages.wrapFlutter flutter""")

    result = {}
    # Match the full name after flutter-artifacts- and look for got: on the same
    # or next line (a 'specified:' line may appear in between).
    for m in re.finditer(
        r"flutter-artifacts-(\S+?)\.drv[^\n]*\n(?:[^\n]*\n)?[^\n]*got:\s+(sha256-\S+)",
        stderr,
    ):
        name, hash_ = m.groups()
        for platform in ARTIFACT_PLATFORMS:
            for system in SYSTEM_PLATFORMS:
                if name == f"{platform}-{system}":
                    result.setdefault(platform, {})[system] = hash_
    return result


# ---------------------------------------------------------------------------
# Release discovery
# ---------------------------------------------------------------------------

def find_latest_stable(forced_version=None):
    with urllib.request.urlopen(
        "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
    ) as r:
        releases = json.load(r)

    if forced_version:
        release = next(
            (r for r in releases["releases"] if r["version"] == forced_version), None
        )
        if not release:
            sys.exit(f"Version {forced_version} not found in releases")
    else:
        latest = releases["current_release"]["stable"]
        release = next(r for r in releases["releases"] if r["hash"] == latest)

    flutter_version = release["version"]
    dart_version = release["dart_sdk_version"].split()[0].rstrip(";")

    with urllib.request.urlopen(
        f"https://raw.githubusercontent.com/flutter/flutter/{flutter_version}/bin/internal/engine.version"
    ) as r:
        engine_version = r.read().decode().strip()

    return flutter_version, dart_version, engine_version


# ---------------------------------------------------------------------------
# dart-sdk.nix update
# ---------------------------------------------------------------------------

def update_dart_sdk_nix(dart_version, dart_hashes):
    text = DART_SDK_NIX.read_text()
    # Update version
    text = re.sub(r'version = "[^"]+";', f'version = "{dart_version}";', text, count=1)
    # Update hashes
    for system, hash_ in dart_hashes.items():
        text = re.sub(
            rf'({re.escape(system)} = ")sha256-[^"]+(")',
            rf'\g<1>{hash_}\g<2>',
            text,
        )
    DART_SDK_NIX.write_text(text)
    print(f"Updated {DART_SDK_NIX.relative_to(REPO_ROOT)}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", metavar="FILE",
                        help="Write this platform's data to FILE (default: <platform>.json)")
    parser.add_argument("--merge", nargs=2, metavar=("LINUX", "DARWIN"),
                        help="Merge two partial outputs and write final files")
    parser.add_argument("--version", help="Force a specific Flutter version")
    args = parser.parse_args()

    if args.merge:
        merge(args.merge[0], args.merge[1])
        return

    flutter_version, dart_version, engine_version = find_latest_stable(args.version)

    if DATA_FILE.exists() and not args.version:
        current = json.loads(DATA_FILE.read_text())
        if current.get("version") == flutter_version:
            print(f"Already at Flutter {flutter_version}, nothing to do.")
            sys.exit(0)

    print(f"Flutter {flutter_version}  Dart {dart_version}  Engine {engine_version[:12]}…")

    import platform
    is_darwin = "darwin" in platform.system().lower()
    host = "aarch64-darwin" if is_darwin else "x86_64-linux"

    if is_darwin:
        # On macOS we only need artifact hashes — the linux job gets everything else.
        # Load the existing or partial linux data for flutter/dart/swiftshader info.
        if not DATA_FILE.exists():
            sys.exit("Run the linux job first (need flutter-sdk-data.json with base data).")
        base = json.loads(DATA_FILE.read_text())
        print(f"Getting darwin artifact hashes for Flutter {flutter_version}…")
        hashes = get_artifact_hashes(
            flutter_version, engine_version, dart_version,
            base["dartHash"], base["flutterHash"],
            base["engineSwiftShaderHash"], base["engineSwiftShaderRev"],
            base["pubspecLock"],
        )
        result = {"artifactHashes": hashes}
    else:
        # Linux: get everything
        print("Getting flutter source hash…")
        flutter_hash = get_flutter_hash(flutter_version)

        print("Getting dart SDK hashes…")
        dart_hashes = get_dart_hashes(dart_version)

        print("Getting SwiftShader rev…")
        swiftshader_rev = get_swiftshader_rev(engine_version)
        print(f"  rev: {swiftshader_rev[:12]}…")

        print("Getting SwiftShader hash…")
        swiftshader_hash = get_swiftshader_hash(swiftshader_rev)

        print("Getting pubspec.lock…")
        pubspec_lock = get_pubspec_lock(flutter_version, dart_version, dart_hashes)

        print("Getting linux artifact hashes…")
        artifact_hashes = get_artifact_hashes(
            flutter_version, engine_version, dart_version,
            dart_hashes, flutter_hash, swiftshader_hash, swiftshader_rev, pubspec_lock,
        )

        result = {
            "version": flutter_version,
            "engineVersion": engine_version,
            "engineSwiftShaderHash": swiftshader_hash,
            "engineSwiftShaderRev": swiftshader_rev,
            "channel": "stable",
            "engineHashes": {},
            "dartVersion": dart_version,
            "dartHash": dart_hashes,
            "flutterHash": flutter_hash,
            "artifactHashes": artifact_hashes,
            "pubspecLock": pubspec_lock,
        }

    out = args.output or f"{host}.json"
    Path(out).write_text(json.dumps(result, indent=2))
    print(f"Written → {out}")


def merge(linux_path, darwin_path):
    linux = json.loads(Path(linux_path).read_text())
    darwin = json.loads(Path(darwin_path).read_text())

    for platform, sys_hashes in darwin.get("artifactHashes", {}).items():
        linux.setdefault("artifactHashes", {}).setdefault(platform, {}).update(sys_hashes)

    # Remove platforms with no hashes on either side
    linux["artifactHashes"] = {
        p: h for p, h in linux["artifactHashes"].items() if h
    }

    DATA_FILE.write_text(json.dumps(linux, indent="\t") + "\n")
    print(f"Written → {DATA_FILE.relative_to(REPO_ROOT)}")

    # Update dart-sdk.nix too
    update_dart_sdk_nix(linux["dartVersion"], linux["dartHash"])


if __name__ == "__main__":
    main()
