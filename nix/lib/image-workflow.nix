## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# What every workflow of ours that ships a container image does the same way:
# which architectures it publishes for, where an image goes depending on what
# triggered the run, how one is built out of the flake, and the job that pushes
# what was built.
#
# The two Dart image workflows each carried their own copy of all of it, down
# to the comments — and the copies had begun to differ in wording where they did
# not yet differ in behaviour, which is how two answers to the same question get
# into a repository.
{ lib }:
{
  # The flake's own config, for the shared steps and the pinned action
  # versions.
  config,
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
in
rec {
  architectures = [
    "amd64"
    "arm64"
  ];

  # What `docker/metadata-action` derived for us before: `pr-<number>` for pull
  # requests, the branch or tag name otherwise.
  tag = "\${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.number) || github.ref_name }}";

  # Where an image goes, given its options: a build off a pull request is a
  # nightly, one off `main` or a version tag a release.
  reference =
    {
      name,
      nightlyRegistry,
      releaseRegistry,
      ...
    }:
    "\${{ github.event_name == 'pull_request' && '${nightlyRegistry}' || '${releaseRegistry}' }}/${name}";

  # An image is built on the architecture it is for, rather than
  # cross-compiled: it is assembled from the same nixpkgs as the artefacts in
  # it, and they carry that nixpkgs' loader.
  buildJob =
    {
      runners,
      steps,
      needs ? [ ],
    }:
    lib.optionalAttrs (needs != [ ]) { inherit needs; }
    // {
      inherit steps;

      strategy = {
        failFast = false;
        matrix.architecture = architectures;
      };

      runsOn =
        let
          arm64 =
            if (runners.arm64Release or runners.arm64) == runners.arm64 then
              "'${runners.arm64}'"
            else
              "(github.event_name == 'push' && '${runners.arm64Release}' || '${runners.arm64}')";
        in
        "\${{ matrix.architecture == 'arm64' && ${arm64} || '${runners.amd64}' }}";

      timeoutMinutes = 30;
    };

  # `arguments` is what the image function takes, as Nix source: the artefact
  # CI just produced, and whatever else the image is stamped with.
  buildStep =
    {
      name,
      output,
      project,
      arguments,
    }:
    {
      inherit name;

      # `getAttr` rather than a dynamic attribute, so the expression carries
      # nothing that looks like a shell variable to shellcheck.
      #
      # `--print-build-logs`, because without it a failure prints only the path
      # of a log that `nix log` would read — and the runner that holds it is
      # gone by the time anyone reads the step.
      run = ''
        image="$(nix build --impure --no-link --print-build-logs --print-out-paths --expr '
      ''
      + lib.concatLines (
        [
          "  let"
          "    flake = builtins.getFlake (toString ./.);"
          "    images = builtins.getAttr builtins.currentSystem flake.${output};"
          "  in images.\"${project}\" {"
        ]
        ++ map (line: lib.optionalString (line != "") "    ${line}") (
          lib.splitString "\n" (lib.removeSuffix "\n" arguments)
        )
        ++ [ "  }" ]
      )
      + ''
        ')"

        "$image" >image-''${{ matrix.architecture }}.tar
      '';
    };

  uploadStep = {
    uses = allowed-actions."actions/upload-artifact".uses;

    with_ = {
      name = "image-\${{ matrix.architecture }}";
      path = "image-\${{ matrix.architecture }}.tar";

      # The publishing job reads the archive out of this artefact, and would
      # push whatever it finds. Nothing is not an image.
      if-no-files-found = "error";

      retention-days = 1;
    };
  };

  publishJob =
    {
      needs,
      reference,
      lockfile,
      release,
    }:
    {
      # Skipped on merge queues: the queue's ref is a temporary branch and
      # would make a nonsense tag.
      if_ = "github.event_name != 'merge_group'";

      inherit needs;

      runsOn = "ubuntu-latest";
      timeoutMinutes = 20;

      # `id-token`, because cosign signs with this workflow's identity rather
      # than with a key. `contents`, only where there is a release to attach
      # the documents to.
      permissions = {
        contents = if release then "write" else "read";
        id-token = "write";
      };

      steps =
        steps.setup
        ++ steps.publishImages {
          inherit
            architectures
            lockfile
            reference
            release
            tag
            ;
        };
    };
}
