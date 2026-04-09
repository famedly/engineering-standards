#!/usr/bin/env python3
# Update nix/sdk-versions.nix with the latest stable Dart and Flutter releases.
#
# Usage:
#   nix run .#updateSdkVersions
#
# Fetches current stable versions from official APIs, prefetches all
# platform binaries, and rewrites sdk-versions.nix.

import json
import subprocess
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SDK_VERSIONS_FILE = SCRIPT_DIR.parent / "sdk-versions.nix"

DART_PLATFORMS = {
    "x86_64-linux": "linux-x64",
    "aarch64-linux": "linux-arm64",
    "x86_64-darwin": "macos-x64",
    "aarch64-darwin": "macos-arm64",
}

FLUTTER_ARCHIVES = {
    "x86_64-linux": ("linux", "flutter_linux_{version}-stable.tar.xz"),
    "x86_64-darwin": ("macos", "flutter_macos_{version}-stable.zip"),
    "aarch64-darwin": ("macos", "flutter_macos_arm64_{version}-stable.zip"),
}


def fetch_json(url: str) -> dict:
    print(f"  Fetching {url}")
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def prefetch_sri(url: str) -> str:
    print(f"  Prefetching {url}")
    result = subprocess.run(
        ["nix-prefetch-url", url, "--type", "sha256"],
        capture_output=True,
        text=True,
        check=True,
    )
    base32 = result.stdout.strip()
    sri = subprocess.run(
        ["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri", base32],
        capture_output=True,
        text=True,
        check=True,
    )
    return sri.stdout.strip()


def get_dart_version() -> str:
    data = fetch_json(
        "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION"
    )
    return data["version"]


def get_flutter_version() -> str:
    data = fetch_json(
        "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
    )
    current = data["current_release"]["stable"]
    release = next(r for r in data["releases"] if r["hash"] == current)
    return release["version"]


def dart_hashes(version: str) -> dict[str, str]:
    result = {}
    for nix_sys, archive_suffix in DART_PLATFORMS.items():
        url = (
            f"https://storage.googleapis.com/dart-archive/channels/stable/release"
            f"/{version}/sdk/dartsdk-{archive_suffix}-release.zip"
        )
        result[nix_sys] = prefetch_sri(url)
    return result


def flutter_hashes(version: str) -> dict[str, str]:
    result = {}
    for nix_sys, (os_dir, archive_tpl) in FLUTTER_ARCHIVES.items():
        archive = archive_tpl.format(version=version)
        url = (
            f"https://storage.googleapis.com/flutter_infra_release/releases"
            f"/stable/{os_dir}/{archive}"
        )
        result[nix_sys] = prefetch_sri(url)
    return result


def render_nix(dart_ver: str, dart_h: dict, flutter_ver: str, flutter_h: dict) -> str:
    def hashes_block(h: dict, indent: str = "      ") -> str:
        return "\n".join(f'{indent}{k} = "{v}";' for k, v in sorted(h.items()))

    return f"""\
# Central SDK version pins for Dart and Flutter.
#
# These versions are used by both the DevShell (dart.nix) and CI workflows
# (dart-ci.nix) to guarantee identical SDKs locally and in CI.
#
# To update, run: nix run .#updateSdkVersions
#
# Hashes are SHA256 SRI (sha256-<base64>) for official upstream binaries.
{{
  dart = {{
    version = "{dart_ver}";
    hashes = {{
{hashes_block(dart_h)}
    }};
  }};

  # Flutter {flutter_ver} — latest stable.
  # Note: Flutter stable does not publish Linux arm64 binaries.
  flutter = {{
    version = "{flutter_ver}";
    hashes = {{
{hashes_block(flutter_h)}
    }};
  }};
}}
"""


def main() -> None:
    print("==> Fetching latest Dart stable version...")
    dart_ver = get_dart_version()
    print(f"    Dart: {dart_ver}")

    print("==> Fetching latest Flutter stable version...")
    flutter_ver = get_flutter_version()
    print(f"    Flutter: {flutter_ver}")

    print("==> Prefetching Dart hashes...")
    dart_h = dart_hashes(dart_ver)

    print("==> Prefetching Flutter hashes...")
    flutter_h = flutter_hashes(flutter_ver)

    nix_content = render_nix(dart_ver, dart_h, flutter_ver, flutter_h)
    SDK_VERSIONS_FILE.write_text(nix_content)
    print(f"\n==> Written {SDK_VERSIONS_FILE}")
    print(f"    Dart {dart_ver}, Flutter {flutter_ver}")
    print("\nNext: commit the updated sdk-versions.nix and run famedly-regen.")


if __name__ == "__main__":
    main()
