## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.web.githubPages = {
            enable = lib.mkEnableOption "publishing this site to GitHub Pages when `main` moves";

            baseHref = lib.mkOption {
              description = ''
                Path the site is served under on Pages, or `null` to leave the
                entry document alone.

                A project site lives under the repository's name, so one built
                for the domain root resolves its assets one directory too
                high. We rewrite it here instead of building a second time, so
                that Pages serves the same bytes as every other destination.
              '';
              type = lib.types.nullOr (lib.types.strMatching "/.*/");
              default = null;
              example = "/famedly-control/";
            };
          };
        }
      );
    };
  });

  config.perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.web.enable && project.web.githubPages.enable
      ) config.famedly.standards.dart.projects;

      mkJob =
        project: projectConfig:
        let
          cfg = projectConfig.web.githubPages;
        in
        {
          # Pages has one live deployment, so it follows `main` and nothing
          # else.
          if_ = "github.event_name == 'push' && github.ref == 'refs/heads/main'";
          needs = [ "build" ];
          runsOn = "ubuntu-latest";

          timeoutMinutes = 15;

          # We need `id-token` because the deployment is authorised by OIDC
          # rather than by a secret.
          permissions = {
            pages = "write";
            id-token = "write";
          };

          environment = {
            name = "github-pages";
            url = "\${{ steps.deployment.outputs.page_url }}";
          };

          steps = [
            {
              uses = allowed-actions."actions/download-artifact".uses;

              with_ = {
                name = projectConfig.web.artifact;
                path = "site";
              };
            }
          ]
          ++ lib.optional (cfg.baseHref != null) {
            name = "Point the base href at the Pages path";
            env.BASE_HREF = cfg.baseHref;

            # We anchor this to the tag `flutter build web` writes, so that a
            # document without one fails here rather than being published
            # with every asset path broken.
            run = ''
              if ! grep -q '<base href="[^"]*">' site/index.html; then
                echo '::error::site/index.html carries no base href to rewrite'
                exit 1
              fi

              sed -i "s|<base href=\"[^\"]*\">|<base href=\"$BASE_HREF\">|" site/index.html
            '';
          }
          ++ [
            { uses = allowed-actions."actions/configure-pages".uses; }

            {
              uses = allowed-actions."actions/upload-pages-artifact".uses;
              with_.path = "site";
            }

            {
              name = "Deploy to GitHub Pages";
              id = "deployment";
              uses = allowed-actions."actions/deploy-pages".uses;
            }
          ];
        };
    in
    {
      githubActions.workflows = lib.mapAttrs' (
        project: projectConfig:
        lib.nameValuePair projectConfig.web.workflowId { jobs.pages = mkJob project projectConfig; }
      ) projects;
    };
}
