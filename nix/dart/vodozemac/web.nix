## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The bindings compiled for the browser. This is a different artefact from
# the native library, not a variant of it.
#
# Upstream drives `wasm-pack` through a Dart wrapper. We call it directly,
# which keeps a Dart toolchain and a pub cache out of the build at the price
# of passing the flags that wrapper would have. See `frbVersion` below.
{
  binaryen,
  buildPackages,
  cargo,
  lib,
  removeReferencesTo,
  rustPlatform,
  rustc,
  source,
  stdenv,
  symlinkJoin,
  wasm-bindgen-cli_0_2_100,
  wasm-pack,
  writableTmpDirAsHomeHook,
}:

let
  # The stem `wasm-bindgen` writes, and the name the Dart package looks up.
  crate = "vodozemac_bindings_dart";

  # `wasm-pack` ignores `RUST_SRC_PATH` and looks for std's sources in its own
  # sysroot, so it gets one that has them.
  sysroot = symlinkJoin {
    name = "rustc-with-lib-src";
    paths = [ buildPackages.rustc.unwrapped ];
    postBuild = ''
      mkdir -p $out/lib/rustlib/src/rust
      ln -s ${rustPlatform.rustLibSrc} $out/lib/rustlib/src/rust/library
    '';
  };
in
stdenv.mkDerivation {
  pname = "famedly-vodozemac-web";

  inherit (source) version src sourceRoot;

  cargoDeps = symlinkJoin {
    name = "famedly-vodozemac-web-cargo-deps";
    paths = [
      (rustPlatform.fetchCargoVendor {
        inherit (source) src sourceRoot;
        hash = source.cargoHash;
      })
    ];

    # Rebuilding `std` needs std's own dependencies, which the crate's
    # lockfile doesn't carry. Both vendors replace the same registry, so they
    # merge.
    postBuild = ''
      cp -rsn ${rustPlatform.rustVendorSrc}/* $out/*/
    '';
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    (buildPackages.rustc.override { inherit sysroot; })

    binaryen
    cargo
    removeReferencesTo
    rustc.llvmPackages.lld
    wasm-bindgen-cli_0_2_100
    wasm-pack
    writableTmpDirAsHomeHook
  ];

  env = {
    # Threads need a `std` compiled for them, which no released
    # `wasm32-unknown-unknown` ships. Rebuilding it is nightly-only, and this
    # grants that to the stable toolchain rather than adding a second one.
    RUSTC_BOOTSTRAP = 1;

    RUSTFLAGS = "-C target-feature=+atomics,+bulk-memory,+mutable-globals";
  };

  # The `flutter_rust_bridge` release whose `build_web/executor.dart` we read
  # the flags below off. They have changed before, and a module built without
  # them fails in the browser rather than here.
  frbVersion = "2.11.1";

  # We use `no-modules` because the glue is loaded by a plain script tag from
  # a Flutter web application rather than by a bundler.
  buildPhase = ''
    runHook preBuild

    if ! grep -A1 '^name = "flutter_rust_bridge"$' Cargo.lock |
    	grep -qxF "version = \"$frbVersion\""; then
    	echo "error: the crate no longer pins flutter_rust_bridge $frbVersion." >&2
    	echo "       Re-read that version's build_web/executor.dart and update" >&2
    	echo "       the flags in nix/dart/vodozemac/web.nix." >&2
    	exit 1
    fi

    wasm-pack build \
    	--target no-modules \
    	--out-dir pkg \
    	--out-name ${crate} \
    	--no-typescript \
    	. \
    	-- -Z build-std=std,panic_abort

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm444 -t $out pkg/${crate}*

    runHook postInstall
  '';

  # Otherwise the debug paths keep a compiler in the closure of every site
  # that ships this.
  preFixup = ''
    find $out -name '*.wasm' -exec remove-references-to -t ${sysroot} {} +
  '';

  meta = source.meta // {
    license = lib.licenses.asl20;
  };
}
