# The bindings compiled for the browser, which is a different artefact from the
# native library rather than a variant of it: a browser loads a WebAssembly
# module next to its JavaScript glue, and `dlopen` never enters the picture.
#
# Upstream builds this with `flutter_rust_bridge_codegen build-web`, which is a
# Dart program that shells out to `wasm-pack`. Running `wasm-pack` ourselves
# skips a Dart toolchain and a pub cache in the build, at the price of passing
# the flags that wrapper would have passed — see `frbVersion` below.
{
  binaryen,
  buildPackages,
  callPackage,
  cargo,
  lib,
  removeReferencesTo,
  rustPlatform,
  rustc,
  stdenv,
  symlinkJoin,
  wasm-bindgen-cli_0_2_100,
  wasm-pack,
  writableTmpDirAsHomeHook,
}:

let
  source = callPackage ./source.nix { };

  # The `cdylib` the crate builds, and so the stem of every file `wasm-bindgen`
  # writes. The Dart package looks the pair up under this name.
  crate = "vodozemac_bindings_dart";

  # `wasm-pack` looks for the standard library's sources in its own sysroot and
  # ignores `RUST_SRC_PATH`, so it gets a sysroot that has them.
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

    # Rebuilding `std` means resolving `std`'s own dependencies, which the
    # crate's lockfile knows nothing about. nixpkgs keeps them vendored for
    # exactly this case; both vendors replace the same registry, so they merge
    # into the one directory the join produced.
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
    # The module uses threads, and threads need a standard library compiled for
    # them, which no released `wasm32-unknown-unknown` ships — hence the rebuild
    # below. Building `std` is a nightly feature; this grants it to the stable
    # toolchain instead of pulling a second one in for this package alone.
    RUSTC_BOOTSTRAP = 1;

    RUSTFLAGS = "-C target-feature=+atomics,+bulk-memory,+mutable-globals";
  };

  # The version of `flutter_rust_bridge` whose `build_web/executor.dart` the
  # flags here were read off. It has changed them before — later versions add
  # linker arguments for shared memory — and a module built without them fails
  # in the browser rather than here, which is why the crate is held to it.
  frbVersion = "2.11.1";

  # `no-modules`, because the glue is loaded by a plain script tag from a Flutter
  # web application rather than by a bundler.
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

  # Debug paths in the module would otherwise keep a compiler in the closure of
  # every site that ships it.
  preFixup = ''
    find $out -name '*.wasm' -exec remove-references-to -t ${sysroot} {} +
  '';

  meta = source.meta // {
    license = lib.licenses.asl20;
  };
}
