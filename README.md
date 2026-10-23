<!--
SPDX-FileCopyrightText: 2026 Famedly GmbH

SPDX-License-Identifier: Apache-2.0
-->

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
   - We recommend starting out with the included example `.envrc`. Run
     `cp .envrc.example .envrc` to get it.
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

      perSystem = { config, ... }: {
        # Specify a default devshell for the project; other options are
        # documented in the devshells section below.
        #
        # This is the devshell the standards assemble for *this* repository,
        # carrying the toolchain the configuration below asks for. Taking it
        # from the standards flake instead would get you the one that repository
        # uses on itself, which pins none of your tools.
        #
        # devShells.default = config.devShells.standards;

        famedly.standards = {
          # Read module documentation for further details, but most
          # likely you want one of the following:
          #
          # dart.projects."." = { };                  # Flutter: { flutter = true; }
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

| Name      | Purpose                                                                              |
| --------- | ------------------------------------------------------------------------------------ |
| standards | Contains basic tools and configuration used by all famedly projects.                 |
| rust      | Contains the Famedly Rust toolchain, and everything required to build Rust projects. |
| k8s       | Contains miscellaneous k8s-related utilities, especially useful on MacOS.            |

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

### REUSE

Engineering Standards sets up the [REUSE](https://reuse.software/) lint by default.
For non-FOSS repositories, you must create a custom "All rights reserved" license like so:

```bash
echo "All rights reserved" > LICENSES/LicenseRef-private.txt
```

You can then use the SPDX header

<!-- REUSE-IgnoreStart -->

```
## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: LicenseRef-private
```

<!-- REUSE-IgnoreEnd -->

### Commits and releases

`famedly.standards.commitMessages.enable` checks every commit, and `famedly.standards.release.enable` publishes a GitHub release for every version tag.

#### Writing commits

Every commit follows [Conventional Commits](https://www.conventionalcommits.org/), with one of the types in `famedly.standards.commitMessages.types`.

A breaking change needs both `!` after the type or scope and a `BREAKING CHANGE:` footer that says how to migrate. Either one alone fails the check. The optional trailers fill in the "Breaking changes and migration" section of the release notes, and `Deprecated:` adds an entry to its "Deprecations" section:

```text
feat(api)!: drop the v1 login endpoint

Clients have been able to log in through /v2/login since 0.4.0.

BREAKING CHANGE: Call /v2/login instead of /v1/login. The request
body is the same.
Affected: mobile and web clients
Security-Relevant: no
Schema-Diff: none
Removed-In: 0.6.0
Deprecated: the login_v1 config key, use login instead
```

`prek install` sets up a pre-push hook that runs `check-commits` on the commits being pushed, and the "Make sure all commit messages are conventional" workflow runs the same command on every pull request. `check-commits main..HEAD` checks a given range. `SKIP=check-commits git push` skips the hook for one push, but CI still checks the commits.

Commits from before the rule was adopted are only read by the first release's notes. To skip validation for older commits that would fail, list their hashes in `.cliffignore`.

#### Releasing

Push a tag named after the version, e.g. `v0.5.0`. To preview the next version and its notes before tagging:

```console
$ git cliff --offline --unreleased --bump --strip all
```

The release workflow renders the notes from the commits since the previous version and publishes them as the release. A tag with a hyphen, e.g. `v0.5.0-rc.1`, becomes a prerelease whose notes cover everything since the last final version.

`publish-release` in the devshell does this for the next version. Run from an up-to-date default branch, it picks the version with `git cliff --bumped-version`, prints the notes the release workflow will publish, and after you confirm, creates a signed tag and pushes it. It never picks 1.0.0 or a prerelease, so tag those by hand.

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

Pre-commit hooks are intended to be _very_ fast to execute. These
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
