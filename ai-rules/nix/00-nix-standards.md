# Nix Standards

## Flake Architecture

### Use flake-parts (MUST)

All flakes MUST use [flake-parts](https://flake.parts/) with `perSystem`. Do NOT use `flake-utils`. Do NOT use manual `lib.genAttrs` over systems.

```nix
outputs = { flake-parts, ... }@inputs:
  flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    perSystem = { pkgs, lib, ... }: { ... };
  };
```

### Shared inputs with .follows (MUST)

For any inputs not taken from the shared engineering-standards flake, MUST override shared inputs (nixpkgs, flake-parts) with `.follows`:

```nix
fenix = {
  url = "github:nix-community/fenix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Default package (MUST)

Set `packages.default` as the primary output of every project. Use `pkgs.symlinkJoin` to merge multiple outputs:

```nix
packages.default = pkgs.symlinkJoin {
  name = "my-project";
  paths = [ packageA packageB ];
};
```

## Code Style

### Do NOT use `with` (MUST NOT)

`with` obscures variable origins. Do NOT use `with pkgs;`, `with lib;`, etc. The only tolerated exception is `with lib.sourceTypes;` or `with lib.licenses;` inside `meta` blocks.

```nix
# WRONG
packages = with pkgs; [ nil nixfmt ];

# CORRECT
packages = [ pkgs.nil pkgs.nixfmt ];
```

### Do NOT set LD_LIBRARY_PATH (MUST NOT)

Nix handles library paths through `buildInputs` and `nativeBuildInputs`. Setting `LD_LIBRARY_PATH` breaks dependency tracking and reproducibility.

### Do NOT commit .envrc (MUST NOT)

The `.envrc` file MUST NOT be committed. Document the recommended content (`use flake`) in your project's README or adopting docs instead.

## Dev Shells

### Use `packages`, not `buildInputs` (MUST)

In `mkShell`, use `packages` for adding tools to a shell environment:

```nix
devShells.default = pkgs.mkShell {
  packages = [ pkgs.cargo pkgs.rustc ];
};
```

## Shell Scripts

### Use writeShellApplication (MUST)

Use `writeShellApplication` instead of `writeShellScriptBin` or `writeShellScript`. It enforces `set -euo pipefail`, runs ShellCheck, and supports `runtimeInputs`:

```nix
# WRONG
pkgs.writeShellScriptBin "my-script" ''
  set -euo pipefail
  echo "hello"
'';

# CORRECT
pkgs.writeShellApplication {
  name = "my-script";
  runtimeInputs = [ pkgs.curl ];
  text = ''
    echo "hello"
  '';
};
```

## Derivations

### Meta attributes are mandatory (MUST)

Every derivation MUST include `meta`. Required fields: `description`, `homepage`, `license`, `sourceProvenance`, `maintainers`. Recommended: `changelog`, `mainProgram`.

```nix
meta = {
  description = "Short description";
  homepage = "https://github.com/famedly/repo";
  changelog = "https://github.com/famedly/repo/blob/main/CHANGELOG.md";
  license = lib.licenses.asl20;
  sourceProvenance = with lib.sourceTypes; [ fromSource ];
  mainProgram = "my-binary";
  maintainers = [
    {
      name = "Famedly GmbH";
      email = "info@famedly.com";
      github = "famedly";
      githubId = 46558835;
    }
  ];
};
```

Use `binaryNativeCode` only for pre-built binaries. Default to `fromSource`.

Reference: https://nixos.org/manual/nixpkgs/stable/#sec-standard-meta-attributes

### Read Cargo.toml from Nix (SHOULD)

Use `builtins.fromTOML` to access `Cargo.toml` properties instead of duplicating values:

```nix
let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
  version = cargoToml.package.version;
  # workspaces:
  version = cargoToml.workspace.package.version;
in
```

### Use lib.fileset for source filtering (SHOULD)

Use `lib.fileset` to include only relevant source files and prevent spurious rebuilds:

```nix
src = lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.unions [
    ./Cargo.toml
    ./Cargo.lock
    ./src
  ];
};
```

When using crane, `craneLib.cleanCargoSource` is an acceptable alternative.

## Docker Images

### Use streamLayeredImage (SHOULD)

Prefer `pkgs.dockerTools.streamLayeredImage` over `buildImage` or `buildLayeredImage` — it streams the image without writing a full tarball to the Nix store:

```nix
pkgs.dockerTools.streamLayeredImage {
  name = "my-app";
  tag = version;
  contents = [ myPackage ];
  config.Cmd = [ (lib.getExe myPackage) ];
};
```

Load with: `$(nix build .#docker --print-out-paths) | docker load`

## CI & Quality

### nix flake check as CI (MUST)

`nix flake check` is the single CI entry point. All checks (formatting, linting, tests, builds) MUST be wired into the `checks` output.

### Cachix in CI (MUST)

CI workflows MUST use `cachix/install-nix-action` and `cachix/cachix-action`. Use the shared `nixSetupStep` from `nix/modules/workflows/lib.nix`.

### Formatting with treefmt-nix (SHOULD)

Use [treefmt-nix](https://github.com/numtide/treefmt-nix) for consistent formatting across all file types. It provides `nix fmt` and adds a formatting check to `nix flake check` automatically:

```nix
treefmt = {
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.prettier.enable = true;
};
```

### Linting (SHOULD)

Use [statix](https://github.com/nerdypepper/statix) for Nix antipattern detection and [deadnix](https://github.com/astro/deadnix) for finding unused code. Both SHOULD be integrated as checks in `nix flake check`.

### .gitignore (MUST)

Every project MUST have a `.gitignore` that excludes Nix build artifacts:

```
result
result-*
.direnv/
```
