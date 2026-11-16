## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The one place that says what a commit has to look like and what a release
# says about it: git-cliff reads its configuration both when a push is checked
# and when the notes for a version tag are written.
{ flake-parts-lib, lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }: {
      options.famedly.standards.changelog = {
        enable = lib.mkOption {
          description = ''
            Whether to generate the `cliff.toml` that commits are checked
            against and release notes are rendered from.

            On whenever either of those is, since both read it.
          '';

          type = lib.types.bool;
          default = config.famedly.standards.commitMessages.enable || config.famedly.standards.release.enable;
          defaultText = lib.literalExpression "config.famedly.standards.commitMessages.enable || config.famedly.standards.release.enable";
        };

        settings = lib.mkOption {
          description = ''
            Settings to write to the project's `cliff.toml`.

            See https://git-cliff.org/docs/configuration. Parsers are tried in
            order and the first match wins, so one that is to take precedence
            over ours goes first:

            ```nix
            settings.git.commit_parsers = lib.mkBefore [
              { message = "^chore\\(release\\):"; skip = true; }
            ];
            ```
          '';

          inherit (pkgs.formats.toml { }) type;
          default = { };
        };
      };
    }
  );

  config.perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      cfg = config.famedly.standards.changelog;
      inherit (config.famedly.standards.commitMessages) types;

      miscellaneous = "<!-- 7 -->⚙️ Miscellaneous Tasks";
      updates = "<!-- 2 -->⬆️ Updates";

      groups = {
        feat = "<!-- 0 -->🚀 Features";
        fix = "<!-- 1 -->🐛 Bug Fixes";
        refactor = "<!-- 3 -->🚜 Refactor";
        docs = "<!-- 4 -->📚 Documentation";
        perf = "<!-- 5 -->⚡ Performance";
        test = "<!-- 6 -->🧪 Testing";
        build = miscellaneous;
        chore = miscellaneous;
        ci = miscellaneous;
        style = miscellaneous;
        revert = "<!-- 8 -->◀️ Revert";
        update = updates;
      };

      # Every allowed type gets a parser and nothing else does, which together
      # with `fail_on_unmatched_commit` is what rejects any other type.
      parser = type: {
        message = "^${type}(\\([^)]*\\))?!?:";
        group = groups.${type} or "<!-- 9 -->${type}";
      };

      check-commits = pkgs.writeShellApplication {
        name = "check-commits";
        runtimeInputs = [
          pkgs.git
          pkgs.git-cliff
        ];

        text = ''
          cd "$(git rev-parse --show-toplevel)"

          # Given a range, use it.
          if [ "$#" -gt 0 ]; then
          	range="$1"
          elif [ -n "''${PRE_COMMIT_FROM_REF:-}" ] && [ -n "''${PRE_COMMIT_TO_REF:-}" ]; then
          	range="$PRE_COMMIT_FROM_REF..$PRE_COMMIT_TO_REF"
          else
          	# Otherwise check what no remote has yet. prek leaves the refs unset when
          	# none of the pushed history is on the remote, so this is also
          	# what a first push checks.
          	first="$(git rev-list --reverse HEAD --not --remotes | head -n1)"

          	if [ -z "$first" ]; then
          		exit 0
          	elif git rev-parse --verify --quiet "$first^" >/dev/null; then
          		range="$first^..HEAD"
          	else
          		# Nothing is pushed at all, so all of it is new.
          		range="HEAD"
          	fi
          fi

          # Nothing to check is not a failure, but git-cliff would make it one.
          count="$(git rev-list --count "$range")"
          if [ "$count" -eq 0 ]; then
          	exit 0
          fi

          # Rendering is the check: unconventional subjects, types outside the
          # list and half-marked breaking changes all fail it.
          if ! git cliff --offline "$range" >/dev/null; then
          	printf '\nerror: the commits in %s do not follow the commit rules.\n' "$range"
          	printf '       Reword them with git rebase -i.\n\n'
          	exit 1
          fi
        '';
      };

      publish-release = pkgs.writeShellApplication {
        name = "publish-release";
        runtimeInputs = [
          pkgs.git
          pkgs.git-cliff
        ];

        text = ''
          cd "$(git rev-parse --show-toplevel)"

          # A version is what everyone has, not what is on this machine, and
          # the tags say which ones exist already.
          git fetch -q origin --tags

          if ! branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)"; then
          	echo "origin has no default branch here, run: git remote set-head origin --auto" >&2
          	exit 1
          fi

          if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$branch")" ]; then
          	echo "HEAD must equal $branch" >&2
          	exit 1
          fi

          version="$(git cliff --offline --bumped-version)"

          if [ -n "$(git tag -l "$version")" ]; then
          	echo "nothing to release: $version exists" >&2
          	exit 1
          fi

          git cliff --offline --unreleased --tag "$version" --strip all

          read -rp "Tag and push $version? [y/N] " ok
          [ "$ok" = y ]

          git tag -s "$version" -m "$version"
          git push origin "$version"
        '';
      };
    in
    lib.mkMerge [
      (lib.mkIf cfg.enable {
        famedly.standards.changelog.settings = {
          changelog = {
            body = lib.mkDefault (builtins.readFile ../../standards/cliff-body.tera);

            trim = lib.mkDefault true;

            postprocessors = [
              # Collapse blank lines left by template control flow.
              {
                pattern = "\\n{3,}";
                replace = "\n\n";
              }
              # `trim` also strips the blank line that separates releases.
              {
                pattern = "\\s*\\z";
                replace = "\n\n";
              }
            ];
          };

          git = {
            conventional_commits = lib.mkDefault true;

            # So that a break is never dropped silently along with a commit
            # nobody could parse.
            require_conventional = lib.mkDefault true;
            fail_on_unmatched_commit = lib.mkDefault true;

            # Prevent commits that are breaking from being excluded by commit
            # parsers.
            protect_breaking_commits = lib.mkDefault true;

            commit_parsers = [
              # Skip merge commits.
              {
                message = "^Merge ";
                skip = true;
              }
            ]
            ++ lib.optional (lib.elem "chore" types) {
              message = "^chore\\(deps\\)!?:";
              group = updates;
            }
            ++ map parser types;

            # Only final versions such as v1.2.3 count as releases, so the notes
            # for v1.3.0 cover everything since v1.2.3, including what its
            # release candidates (v1.3.0-rc.1, ...) already listed.
            #
            # `ignore_tags = "-"` would skip the prereleases too, but it also
            # skips a final tag on the same commit as a prerelease tag, e.g.
            # v1.3.0 tagged on top of v1.3.0-rc.2.
            tag_pattern = lib.mkDefault "^v[0-9]+\\.[0-9]+\\.[0-9]+$";

            topo_order_commits = lib.mkDefault true;
          };

          # Only read by `--bump` and `--bumped-version`, for a preview of the
          # next version. Both stay off past 1.0.0 too: the template is what
          # decides whether a bump is big enough.
          bump = {
            breaking_always_bump_major = lib.mkDefault false;
            features_always_bump_minor = lib.mkDefault false;
            initial_tag = lib.mkDefault "v0.1.0";
          };
        };

        prek-pre-commit.package.runtimePkgs = [ pkgs.git-cliff ];

        filegen.settings.files = [
          {
            type = "copy";
            target = "cliff.toml";
            source = standardsLib.managedFile {
              inherit pkgs;
              name = "cliff.toml";
              file = (pkgs.formats.toml { }).generate "cliff.toml" cfg.settings;
              note = ''
                Change it through `famedly.standards.changelog.settings`. The
                release notes template is `standards/cliff-body.tera` in the
                engineering standards.
              '';
            };
          }
        ];
      })

      (lib.mkIf config.famedly.standards.commitMessages.enable {
        prek-pre-commit = {
          package.runtimePkgs = [ check-commits ];

          workspaces.".".repos = [
            {
              repo = "local";
              hooks = [
                {
                  id = "check-commits";
                  name = "check-commits";
                  description = "Ensure the pushed commits follow the commit rules";

                  entry = "check-commits";
                  # It reads commits, not files.
                  pass_filenames = false;
                  always_run = true;
                  stages = [ "pre-push" ];

                  language = "system";
                }
              ];
            }
          ];
        };

        devshells.standards.commands = [
          {
            name = "check-commits";
            help = "Check the commits no remote has yet against the commit rules, or those in a given range";
            category = "[[lints and checks]]";
            package = check-commits;
          }
        ];
      })

      (lib.mkIf config.famedly.standards.release.enable {
        devshells.standards.commands = [
          {
            name = "publish-release";
            help = "Tag the next version and push it, for the release workflow to publish";
            category = "[[releases]]";
            package = publish-release;
          }
        ];
      })
    ];
}
