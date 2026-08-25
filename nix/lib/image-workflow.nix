## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# What every workflow of ours that ships a container image does the same way:
# which architectures it publishes for, where an image goes depending on what
# triggered the run, how one is built out of the flake, how it is run and asked
# whether it came up, and the job that pushes what was built.
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

  script = import ./compose-script.nix { inherit lib; };

  architectures = [
    "amd64"
    "arm64"
  ];

  # What `docker/metadata-action` derived for us before: `pr-<number>` for pull
  # requests, the branch or tag name otherwise.
  tag = "\${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.number) || github.ref_name }}";

  # The expression the build step evaluates. It is generated into the
  # repository rather than assembled into the step, so that it is a Nix file
  # nixfmt formats and a reader can open, instead of Nix source built up line
  # by line inside a shell string inside a YAML document.
  #
  # `nix/dart/workflows/build-image.nix` is what puts it there.
  buildImage = {
    target = ".github/build-image.nix";
    source = ./files/build-image.nix;
  };
in
{
  inherit buildImage;

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

  # `artefact` is what the run just produced: `name` is the argument the image
  # takes it as, `path` where in the checkout it was left.
  buildStep =
    {
      name,
      output,
      project,
      artefact,
    }:
    {
      inherit name;

      # The expression reads these rather than being written around them,
      # which is why it can be a file instead of a string.
      env = {
        IMAGE_OUTPUT = output;
        IMAGE_PROJECT = project;

        IMAGE_ARTEFACT = artefact.name;
        IMAGE_PATH = artefact.path;

        IMAGE_SOURCE = "\${{ github.server_url }}/\${{ github.repository }}";
        IMAGE_REVISION = "\${{ github.sha }}";
        IMAGE_VERSION = "\${{ github.ref_name }}";
      };

      # `--print-build-logs`, because without it a failure prints only the path
      # of a log that `nix log` would read — and the runner that holds it is
      # gone by the time anyone reads the step.
      run = ''
        image="$(nix build --impure --no-link --print-build-logs --print-out-paths \
        	--file ${buildImage.target})"

        "$image" >image-''${{ matrix.architecture }}.tar
      '';
    };

  # The image is what ships, so it is what we test: something that runs on the
  # runner but not in the image used to ship unnoticed.
  #
  # What the two image workflows ask of a running container differs — one polls
  # the healthcheck, the other fetches pages — but the lifecycle around the
  # question does not, and it is the part that is easy to get subtly wrong.
  #
  # `container` has to name the project. A repository with two of them
  # generates two of these workflows, which can be on the same runner at the
  # same time, and a shared name would have each tear down the other's run.
  smokeTest =
    {
      name,
      container,
      image,
      options ? [ ],
      checks,
    }:
    {
      inherit name;

      run = script (
        [
          ''
            docker load <image-''${{ matrix.architecture }}.tar

            # Runners are reused and a container outlives a cancelled job, so
            # one cancellation would fail every later run.
            docker rm --force ${container} 2>/dev/null || true

            docker run --detach --name ${container} \
            	${lib.concatStringsSep " \\\n\t" (options ++ [ "${image}:latest" ])}

            # Set before the first check, so that a failure is diagnosable and
            # the container is gone however the step ends.
            trap 'docker logs ${container}; docker rm --force ${container} >/dev/null' EXIT
          ''
        ]
        ++ checks
      );
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
