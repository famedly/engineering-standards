# Local platform dev environment module.
#
# Wraps famedly-platform for single-repo development: one `enable` flag
# and a concise `image` description is all a consumer needs.
#
#   perSystem = { ... }: {
#     famedly.standards.platform = {
#       enable = true;
#       image = {
#         name = "famedly-operator";
#         chart = ./helm/famedly-operator;
#       };
#     };
#   };
#
# Then run `famedly-platform-up` to start k3d + Tilt with the local
# image build.  All other platform services use pre-built registry images.

{
  inputs,
  flake-parts-lib,
  ...
}:
_caller-args:
{
  imports = [ inputs.famedly-platform.flakeModules.default ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.platform;
      img = cfg.image;
      hasImage = img.name != null;

      localImages =
        (lib.optional hasImage (
          {
            subchart = img.name;
            context = img.src;
          }
          // lib.optionalAttrs (img.build.docker != null) {
            dockerfile = img.build.docker;
          }
          // lib.optionalAttrs (img.build.nix != null) {
            nix_target = img.build.nix;
          }
          // lib.optionalAttrs (img.hotReload != [ ]) {
            live_update = map (r: {
              sync = {
                local = r.from;
                container = r.to;
              };
            }) img.hotReload;
          }
          // lib.optionalAttrs (img.patch.cargo != { }) {
            cargo_patch = img.patch.cargo;
          }
        ))
        ++ cfg.extraImages;

      localChartOverrides = lib.optional (hasImage && img.chart != null) img.chart;
    in
    {
      options.famedly.standards.platform = {
        enable = lib.mkEnableOption "Local platform dev environment (k3d + Tilt)";

        image = {
          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Service name (must match the Helm subchart name in the
              platform umbrella chart).  When set, Tilt builds this
              repo's container image locally on every source change.
            '';
            example = "famedly-operator";
          };

          src = lib.mkOption {
            type = lib.types.str;
            default = ".";
            description = "Docker build context directory, relative to the repo root.";
          };

          build = {
            docker = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Path to the Dockerfile (relative to the repo root).
                When null, defaults to <src>/Dockerfile.
                Mutually exclusive with build.nix.
              '';
            };

            nix = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Nix flake package that produces a container image
                (e.g. "famedly-control-service-container").
                When set, Tilt uses `nix build` instead of `docker build`.
                Mutually exclusive with build.docker.
              '';
              example = "famedly-control-service-container";
            };
          };

          chart = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Local Helm chart directory.  Overrides the published
              subchart in the umbrella chart — use this to test chart
              changes alongside code changes.
            '';
            example = "./helm/famedly-operator";
          };

          hotReload = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  from = lib.mkOption {
                    type = lib.types.str;
                    description = "Local path (relative to src) to watch and push.";
                  };
                  to = lib.mkOption {
                    type = lib.types.str;
                    description = "Container path to receive the files.";
                  };
                };
              }
            );
            default = [ ];
            description = ''
              Hot-reload rules: push changed files directly into the
              running container without rebuilding the image.  Useful
              for frontend builds (HTML/JS/CSS → nginx).
            '';
            example = [
              {
                from = "build/web";
                to = "/usr/share/nginx/html";
              }
            ];
          };

          patch = {
            cargo = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = ''
                Cargo [patch] overrides — maps git URLs to local paths
                for developing against a local checkout of a Rust dependency.
              '';
              example = {
                "https://github.com/famedly/zitadel-rust-client" = "../zitadel-rust-client";
              };
            };
          };
        };

        extraImages = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
          description = ''
            Additional local images for monorepo setups.
            Uses the same schema as famedly.platform.localImages.
          '';
        };

        testCommand = lib.mkOption {
          type = lib.types.str;
          default = "echo 'No test command configured'";
          description = "Command executed by `famedly-platform` (CI mode) after the environment is ready.";
        };

        chart = lib.mkOption {
          type = lib.types.either lib.types.str (lib.types.attrsOf lib.types.str);
          default = "${inputs.helm-charts}/e2e-platform";
          description = ''
            Platform umbrella chart source.  Defaults to the pinned
            helm-charts input from engineering-standards.
          '';
        };

        values = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Additional Helm values for the platform chart.";
        };

        ports = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "9310:9310@loadbalancer"
            "8080:8080@loadbalancer"
            "8008:8008@loadbalancer"
            "8282:8282@loadbalancer"
          ];
          description = "k3d cluster port mappings (format: host:container@loadbalancer).";
        };

        extraManifests = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = "Additional Kubernetes manifests to apply before the platform chart.";
        };
      };

      config = lib.mkIf cfg.enable {
        famedly.platform = {
          enable = true;
          chart = cfg.chart;
          values = cfg.values;
          ports = cfg.ports;
          testCommand = cfg.testCommand;
          extraManifests = cfg.extraManifests;
          localImages = localImages;
          localChartOverrides = localChartOverrides;
        };
      };
    }
  );
}
