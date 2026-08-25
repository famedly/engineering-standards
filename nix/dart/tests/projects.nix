## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The project configuration the fixture is evaluated against. Every option the
# Dart standards offer is set to something other than its default here, so that
# a refactor which drops one shows up as a difference in the generated files
# rather than as a silent loss downstream.
{
  perSystem = { pkgs, ... }: {
    famedly.standards.dart.projects = {
      # A plain Dart server at the repository root: the compiled-binary image,
      # the checks that need no framework, and the vodozemac bindings.
      "." = {
        checks = {
          testCommand = "dart test test/unit/";
          privateDependencies = true;

          coverage = {
            enable = true;
            flags = "unit-tests";
          };

          licenses.enable = true;

          dependencies = {
            enable = true;
            ignore = [ "build_runner" ];
          };
        };

        linting = {
          exclude = [ "lib/shared/l10n/*.dart" ];

          dartCodeLinter = {
            enable = true;
            disabledRules = [ "member-ordering" ];

            extraRules = [
              {
                avoid-banned-imports.entries = [
                  {
                    paths = [ "features/.*\\.dart" ];
                    deny = [ "services/implementations.*\\.dart" ];
                    message = "Use the service API instead.";
                  }
                ];
              }
            ];
          };
        };

        runtime = {
          libraries = [ pkgs.sqlite ];
          env.FIXTURE_RUNTIME = "set";
        };

        vodozemac.enable = true;

        image = {
          enable = true;
          name = "famedly-fixture-server";
          entrypoint = "bin/fixture.dart";
          binary = "fixture";
          healthPath = "/api/v1/health";
          writableDirs = [ "/app/data" ];
          gate = "./.github/workflows/test.yaml";
          files."/app/config.yaml" = ./files/config.yaml;
        };
      };

      # A Flutter application in a subdirectory: the web target and all three
      # of its destinations, plus the checks only a framework project has.
      "./app" = {
        flutter = true;

        checks = {
          testCommand = "flutter test --coverage";
          browser = true;
          coverage.enable = true;
          translations.enable = true;
        };

        web = {
          enable = true;
          sentry.enable = true;
          livekitE2eeWorker.enable = true;
          buildArgs = [ "--dart-define=FLAVOR=production" ];

          image = {
            enable = true;
            name = "famedly-fixture-client";
            crossOriginIsolation = true;
          };

          githubPages = {
            enable = true;
            baseHref = "/famedly-fixture/";
          };

          reviewApp = {
            enable = true;
            projectName = "famedly-fixture";
          };
        };
      };
    };
  };
}
