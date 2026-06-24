# Famedly engineering standards

This repository serves as the central definition for all developer
tooling and configuration that we use.

This includes things such as linter rules, CI workflows, toolchain
versions, editorconfig files, etc. - everything you need to start
working on a Famedly project.

Everything is defined using flake-parts modules, allowing us to easily
spin this up in new projects, or on newly onboarded developers'
machines.

## Using

### Installation

If you want to get started using this, follow these steps:

1. Install lix, following the [upstream
   instructions](https://lix.systems/install/).
2. Once lix is installed, you can enter any Famedly project and run
   `nix develop`. Assuming the project is configured to use the
   engineering standards, the resulting shell will give any further
   instructions.
3. [Optional] use [direnv](https://direnv.net/) to automatically enter
   project shells when entering Famedly project directories.
   - This is especially useful if you use a non-bash shell.
4. [Optional] configure your editor to use the direnv-based shell as
   well
   - Various plugins exist for this. Examples:
     - Vscode: [direnv-vscode](https://github.com/direnv/direnv-vscode)
     - Emacs: [direnv](https://melpa.org/#/direnv)
     - Vim: [direnv.vim](https://github.com/direnv/direnv.vim)

### Starting a new project

To use the standards in a new project, create the following
`flake.nix` file at the root of the project:

```nix
{
  description = "Example project";

  inputs = {
    famedly-engineering-standards.url = "github:famedly/engineering-standards";

    nixpkgs.follows = "famedly-engineering-standards/nixpkgs";
    flake-parts.follows = "famedly-engineering-standards/flake-parts";
  };

  outputs =
    { famedly-engineering-standards, flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ famedly-engineering-standards.flakeModules.default ];

      systems = famedly-engineering-standards.lib.famedlySystems;

      perSystem = { inputs', ... }: {
        # Specify a default devshell for the project; other options are
        # documented in the devshells section below.
        #
        # devShells.default = inputs'.famedly-engineering-standards.devShells.standards;

        famedly.standards = {
          # Read module documentation for further details, but most
          # likely you want one of the following:
          #
          # dart.projects."." = { };
          # rust.projects."." = { };
        };
      };
    };
}
```

After this, follow the [Updating](#updating) section.

### Devshells

Devshells allow setting up development environments for projects. For
the most part, the devshells in this project should contain everything
needed, but some project-specific development utilities and scripts
can make sense to add downstream.

The following basic devshells are available:

| Name      | Purpose |
| --------- | ------- |
| standards | Contains basic tools and configuration used by all famedly projects. |
| rust      | Contains the Famedly Rust toolchain, and everything required to build Rust projects. |
| k8s       | Contains miscellaneous k8s-related utilities, especially useful on MacOS. |

Projects should generally choose one of these to alias to the
projects' `default` devshell - this allows new developers to very
easily get started by just running `nix develop`.

To customize the projects' shell, override the relevant devshell's
settings according to the [upstream documentation](https://numtide.github.io/devshell/modules_schema.html).
For example:

```nix
# flake-parts module
{
  perSystem = { pkgs, lib, ... }: {
    devshells.rust = {
      name = "example-famedly-project";

      commands = [
        {
          name = "project-help";
          help = "print information to help getting started with this project";
          category = "[general commands]";
          command = ''
            ${lib.getExe' pkgs.coreutils "cat"} <<'EOF'
            This is an example project to help show off our engineering standards!

            Normally this would contain some simple build instructions, or maybe some
            hints for testing, but since this is an example there is nothing actually
            here.
            EOF
          '';
        }
      ];
    };
  };
}
```

### Updating

Run these commands:

```console
$ nix flake update famedly-engineering-standards
$ nix run .#filegen-activate
```

Currently, this may introduce breaking changes. We will provide
migrations and generally a better update process in the future, but
while we are iterating on the initial standards large changes are to
be expected.

## Contributing

### Simple changes for non-nix developers

General "standards", i.e. anything that can be defined reasonably
without benefiting from nix module semantics, should live in the
`standards/` directory.

Care will be taken that these can be maintained without involving nix,
to ensure that most developers can interact with this repository.

If you struggle creating a completely new file, ask someone with more
nix experience to help you hook this into the filegen-activate
command.

### Adding pre-commit hooks

Pre-commit hooks are intended to be *very* fast to execute. These
should be ergonomic to run every time you create a git commit - when
doing rebase operations, that can mean dozens in a few 100ms.

As such, these should never contain expensive operations - compiling
code is absolutely not acceptable, and even complex parsing (for
formatting) may be pushing it.

For more expensive operations, add a workflow instead, and let CI
perform the check.

---

To actually add a pre-commit hook, in addition to defining the hook,
any dependencies required **must** be added to the `prek`
wrapper. Assuming the dependency is packaged in nixpkgs, this is quite
easy:

```nix
{
  config.perSystem = { pkgs, ... }: {
    prek-pre-commit.package.runtimePkgs = [ pkgs.foobar ];
  };
}
```

More complex modifications to the `prek` wrapper are possible too,
refer to our [wrapper module provider](https://birdeehub.github.io/nix-wrapper-modules/modules/default.html)
for details.

### Updating the Dart/Flutter SDK versions

The Dart and Flutter SDKs are pinned centrally in
[`nix/dart/sdk-versions.nix`](nix/dart/sdk-versions.nix), so that the
DevShell and CI always use identical toolchain binaries. This file is
generated — do not edit it by hand.

To bump the pins, run:

```console
$ nix run .#updateSdkVersions                     # latest stable of both
$ nix run .#updateSdkVersions -- --dart X.Y.Z     # pin a specific Dart version
$ nix run .#updateSdkVersions -- --flutter X.Y.Z  # pin a specific Flutter version
```

This fetches the requested (or latest stable) versions, prefetches the
SDK archives for every supported platform, records their SHA256 hashes,
and rewrites `sdk-versions.nix`. Review and commit the result.

The versions are resolved from the official release-metadata endpoints
that the Dart and Flutter tooling itself uses
(`dart-archive/.../latest/VERSION` and
`flutter_infra_release/releases/releases_linux.json`).
