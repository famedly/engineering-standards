## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# A program wrapping our release script, usable in projects using rust
# with a Cargo.toml and git-cliff based release flow.
#
# The script is written in nushell, parsing Cargo.toml natively.
{
  lib,

  makeBinaryWrapper,
  runCommand,

  cargo,
  git,
  git-cliff,
  gnused,
  nushell,
}:

runCommand "cargo-release"
  {
    nativeBuildInputs = [ makeBinaryWrapper ];

    meta = {
      description = "Prepare a cargo release: bump version, update changelog and tag";
      mainProgram = "cargo-release";
    };
  }
  ''
    mkdir -p $out/bin $out/libexec
    install -m755 ${./cargo-release.nu} $out/libexec/cargo-release.nu

    # The script is run through nushell, with the runtime tools
    # (git, git-cliff, cargo and sed) available on its PATH.
    makeWrapper ${lib.getExe nushell} $out/bin/cargo-release \
      --prefix PATH : ${
        lib.makeBinPath [
          cargo
          git
          git-cliff
          gnused
        ]
      } \
      --add-flags $out/libexec/cargo-release.nu
  ''
