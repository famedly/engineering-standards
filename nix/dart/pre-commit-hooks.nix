{
  flakeModules,
  inputs,
  flake-parts-lib,
  lib,
  ...
}:
importingFlake: {
  config.perSystem =
    {
      pkgs,
      config,
      ...
    }:
    let
      dart = lib.getExe pkgs.dart;
      grep = lib.getExe pkgs.gnugrep;

      check-conventional-commits = pkgs.writeShellScript "check-conventional-commits" ''
        set -eu

        commit_message_file="$1"
        accepted_prefixes='ci|fix|feat|chore|test|perf|refactor|style|builds|docs|revert'

        if ! ${grep} -Eq "^($accepted_prefixes)(\([[:alnum:]_.-]+\))?!?: .+" "$commit_message_file"; then
          echo "Commit message must start with one of: $accepted_prefixes"
          exit 1
        fi
      '';

      dart-analyze = pkgs.writeShellScript "dart-analyze" ''
        set -eu

        if [ -f pubspec.yaml ] && ${grep} -Eq '^flutter:' pubspec.yaml; then
          command=flutter
        else
          command=${dart}
        fi

        ${dart} format lib/ --set-exit-if-changed
        "$command" pub get
        "$command" analyze

        if command -v dart_code_metrics >/dev/null 2>&1; then
          dart_code_metrics analyze lib || true
        fi
      '';
    in
    {
      prek-pre-commit.workspaces = lib.mapAttrs (name: _: {
        default_language_version.dart = "system";

        repos = [
          {
            repo = "local";
            hooks = [
              {
                id = "check-conventional-commits";
                name = "check-conventional-commits";
                description = "Check commit messages follow conventional commits";

                entry = "${check-conventional-commits}";

                language = "system";
                stages = [ "commit-msg" ];
              }

              {
                id = "dart-analyze";
                name = "dart-analyze";
                description = "Run dart analyze on all targets";

                entry = "${dart-analyze}";

                language = "system";
                types = [ "dart" ];
                pass_filenames = false;
              }
            ];
          }
        ];
      }) config.famedly.standards.dart.projects;
    };
}
