{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (import ../../../lib/project-paths.nix { inherit lib; }) suffix;
  inherit (import ../workflow-ids.nix { inherit lib; }) artifact workflowId;

  script = import ../../../lib/compose-script.nix { inherit lib; };

  architectures = [
    "amd64"
    "arm64"
  ];
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.web.image = {
              enable = lib.mkEnableOption "building and pushing a container image that serves this web target";

              name = lib.mkOption {
                description = ''
                  Name of the image to push, without the registry.
                '';
                type = lib.types.str;
                example = "famedly-control-client";
              };

              nightlyRegistry = lib.mkOption {
                description = ''
                  Registry that images built from pull requests are pushed to.
                '';
                type = lib.types.str;
                default = "registry.famedly.net/docker-nightly";
              };

              releaseRegistry = lib.mkOption {
                description = ''
                  Registry that images built from `main` and version tags are
                  pushed to.
                '';
                type = lib.types.str;
                default = "registry.famedly.net/docker-releases";
              };

              contentTypes = lib.mkOption {
                description = ''
                  Content types the image is expected to serve, keyed by file
                  extension.

                  Checked against the site's own files, because these are the
                  headers a browser refuses to work with rather than merely
                  renders differently: it will not execute a module script that
                  is not typed as JavaScript, nor instantiate a WebAssembly
                  module that is not typed as such. Serving them wrong takes the
                  whole application down, and does so only in the browser, where
                  no build step is watching.

                  Extensions the site has no file for are skipped.
                '';
                type = lib.types.attrsOf lib.types.str;
                default = {
                  mjs = "application/javascript";
                  wasm = "application/wasm";
                };
              };

              runners = {
                amd64 = lib.mkOption {
                  description = "Runner that assembles the amd64 image.";
                  type = lib.types.str;
                  default = "ubuntu-latest";
                };

                arm64 = lib.mkOption {
                  description = "Runner that assembles the arm64 image.";
                  type = lib.types.str;
                  default = "arm-ubuntu-latest-8core";
                };
              };
            };
          }
        );
      };
    }
  );

  config.perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.web.enable && project.web.image.enable
      ) config.famedly.standards.dart.projects;

      mkJobs =
        project: projectConfig:
        let
          cfg = projectConfig.web.image;

          container = "smoke-web${suffix project}";

          registry = "\${{ github.event_name == 'pull_request' && '${cfg.nightlyRegistry}' || '${cfg.releaseRegistry}' }}";

          # What `docker/metadata-action` derived for us before: `pr-<number>`
          # for pull requests, the branch or tag name otherwise.
          tag = "\${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.number) || github.ref_name }}";
        in
        {
          # Only the server in the image is architecture-specific — the site
          # itself is bytes either way, and was built once in `build`. So these
          # jobs assemble rather than build, and run natively only because the
          # server they wrap has to match the platform it is pushed as.
          image = {
            needs = [ "build" ];

            strategy = {
              failFast = false;
              matrix.architecture = architectures;
            };

            runsOn = "\${{ matrix.architecture == 'arm64' && '${cfg.runners.arm64}' || '${cfg.runners.amd64}' }}";

            steps = steps.setup ++ [
              {
                uses = allowed-actions."actions/download-artifact".uses;

                with_ = {
                  name = artifact project;
                  path = "site";
                };
              }

              {
                name = "Assemble the image";
                # `getAttr` rather than a dynamic attribute, so the expression
                # carries nothing that looks like a shell variable.
                #
                # `--print-build-logs`, because without it a failure prints only
                # the path of a log that `nix log` would read — and the runner
                # that holds it is gone by the time anyone reads the step.
                run = ''
                  image="$(nix build --impure --no-link --print-build-logs --print-out-paths --expr '
                    let
                      flake = builtins.getFlake (toString ./.);
                      images = builtins.getAttr builtins.currentSystem flake.dartWebImages;
                    in images."${project}" {
                      site = ./site;

                      source = "''${{ github.server_url }}/''${{ github.repository }}";
                      revision = "''${{ github.sha }}";
                      version = "''${{ github.ref_name }}";
                    }
                  ')"

                  "$image" >image-''${{ matrix.architecture }}.tar
                '';
              }

              {
                # The image is what ships, so it is what gets tested — a server
                # that starts on the runner but not in the image is the failure
                # this catches. It fetches the site's real files rather than a
                # placeholder, so a missing entry document fails here too.
                name = "Smoke test the image";

                run = script (
                  [
                    ''
                      docker load <image-''${{ matrix.architecture }}.tar

                      # The runners are reused and a container outlives a
                      # cancelled job, so without this one cancellation would
                      # fail every later run on that runner.
                      docker rm --force ${container} 2>/dev/null || true

                      # An ephemeral host port, so that concurrent jobs on a
                      # shared runner cannot collide over one.
                      docker run --detach --name ${container} \
                      	--publish 127.0.0.1::${toString cfg.port} \
                      	${cfg.name}:latest

                      # The server's log and the container go away whichever way
                      # this step ends, so a failure below stays diagnosable.
                      trap 'docker logs ${container}; docker rm --force ${container} >/dev/null' EXIT

                      base="http://$(docker port ${container} ${toString cfg.port}/tcp | head -1)"

                      for _ in $(seq 30); do
                        curl -fsS -o /dev/null "$base/index.html" && break
                        sleep 1
                      done

                      # Again, so that a server which never came up fails the
                      # step rather than only the loop.
                      curl -fsS -o /dev/null "$base/index.html"

                      # What Kubernetes will ask before it sends anyone here.
                      curl -fsS -o /dev/null "$base/health"

                      # Read once and matched below against each header the
                      # server was configured with. Names are case-insensitive
                      # and it sends them lower-cased, so the pattern is folded
                      # rather than the file.
                      curl -fsSI "$base/index.html" | tr -d '\r' >headers
                    ''
                  ]
                  ++ lib.mapAttrsToList (header: expected: ''
                    sent="$(sed -n 's/^${lib.toLower header}: *//p' headers)"

                    if test "$sent" != ${lib.escapeShellArg expected}; then
                      echo "::error::${header} is sent as '$sent', expected '${expected}'"
                      exit 1
                    fi

                    echo "${header}: $sent"
                  '') cfg.sentHeaders
                  ++ lib.mapAttrsToList (extension: expected: ''
                    file="$(cd site && find . -type f -name '*.${extension}' -print -quit)"

                    if test -n "$file"; then
                      # Header names and media types are both case-insensitive,
                      # so each side is folded once instead of being matched a
                      # letter at a time.
                      served="$(curl -fsSI "$base/''${file#./}" \
                      	| tr -d '\r' \
                      	| tr '[:upper:]' '[:lower:]' \
                      	| sed -n 's/^content-type: *//p' \
                      	| sed 's/ *;.*//')"

                      if test "$served" != '${lib.toLower expected}'; then
                        echo "::error::$file is served as '$served', expected '${lib.toLower expected}'"
                        exit 1
                      fi

                      echo "$file is served as $served"
                    fi
                  '') cfg.contentTypes
                );
              }

              {
                uses = allowed-actions."actions/upload-artifact".uses;

                with_ = {
                  name = "image-\${{ matrix.architecture }}";
                  path = "image-\${{ matrix.architecture }}.tar";

                  # The publishing job reads the archive out of this artefact,
                  # and would push whatever it finds. Nothing is not an image.
                  if-no-files-found = "error";

                  retention-days = 1;
                };
              }
            ];
          };

          publish = {
            if_ = "github.event_name != 'merge_group'";
            needs = [ "image" ];
            runsOn = "ubuntu-latest";

            steps =
              steps.setup
              ++ steps.publishImages {
                inherit architectures tag;
                reference = "${registry}/${cfg.name}";
              };
          };
        };
    in
    {
      githubActions.workflows = lib.mapAttrs' (
        project: projectConfig:
        lib.nameValuePair (workflowId project) { jobs = mkJobs project projectConfig; }
      ) projects;
    };
}
