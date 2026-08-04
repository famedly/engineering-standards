{ config, lib, ... }:
let
  inherit (config.famedly.standards.ci) steps;

  cfg = config.famedly.standards.ci.binaryCache;

  # An output only builds on its own system, so each one needs a runner of that
  # kind. The arm64 Linux image is named by version because GitHub publishes no
  # `-latest` for it; it has only been available to private repositories since
  # January.
  runners = {
    x86_64-linux = "ubuntu-latest";
    aarch64-linux = "ubuntu-24.04-arm";
    aarch64-darwin = "macos-latest";
  };
in
{
  options.famedly.standards.ci.binaryCache.populate = lib.mkOption {
    description = ''
      Flake outputs this repository builds on `main` and hands to the shared
      binary cache, keyed by the system to build them for.

      Empty to begin with. Most repositories have nothing to add that another
      one would ever ask for: what they build is their own, and what they share
      with the rest of us comes from the standards. Their workflows read from
      the cache and leave the filling to whoever owns the derivation.

      Naming an output here is worth it when the thing is expensive to *build*
      and the same for everyone — a library pinned by version rather than by
      branch. An output that only fetches and unpacks what someone else built is
      a poor trade: the bytes get moved from one host to another and nobody's
      wait gets shorter. Anything a workflow on `main` builds anyway is already
      pushed by the step in `setup` and does not belong here either.

      Weigh `aarch64-darwin` before naming it. GitHub bills its macOS runners at
      ten times the rate, and it buys a shorter wait on laptops only.

      E.g.:

      ```nix
      famedly.standards.ci.binaryCache.populate = {
        x86_64-linux = [ ".#famedly-dart-sdk" ];
      };
      ```
    '';

    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
  };

  config.perSystem = lib.mkIf (cfg.populate != { }) {
    githubActions.workflows.populate-binary-cache = {
      name = "Fill the shared binary cache";

      # On `main` rather than on a pull request, because this is the one
      # workflow of ours whose whole purpose is to write to the cache, and only
      # `main` is trusted to. `workflow_dispatch` is there for the day the cache
      # has been emptied and nobody wants to wait for the next merge; start it
      # on `main`, since a run started on a branch reads and does not write.
      on.push.branches = [ "main" ];
      on.workflowDispatch = { };

      # Deliberately not cancelling what is in progress: a run cut short leaves
      # the cache as empty as it found it, and the next merge would start over.
      concurrency.group = "\${{ github.workflow }}";

      jobs = lib.mapAttrs' (
        system: outputs:
        lib.nameValuePair "populate-${system}" {
          runsOn =
            runners.${system}
              or (throw "famedly.standards.ci.binaryCache.populate: no GitHub runner for ${system}; supported: ${lib.concatStringsSep ", " (lib.attrNames runners)}");

          # Composed rather than taken from `setup`, because the cache is not
          # optional here the way it is everywhere else. A run that builds the
          # toolchain and then fails to hand it over has done nothing at all,
          # and it should say so instead of reporting a green tick.
          steps =
            steps.checkout
            ++ steps.installNix
            ++ steps.binaryCache { required = true; }
            ++ [
              {
                name = "Build what the other repositories resolve against";
                run = "nix build --no-link --print-build-logs ${lib.concatStringsSep " " outputs}";
              }
            ];
        }
      ) cfg.populate;
    };
  };
}
