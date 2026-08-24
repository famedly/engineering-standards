## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# What a build calls itself. The same two values reach the application, as
# dart-defines, and Sentry, as the release and the distribution it files reports
# under — a report can only be read against the sources it came from if both
# agree on which build that was.
#
# Command substitutions rather than a step that exports them, so that the build
# command the flake prints reproduces a CI build by hand.
{
  # `--long` even on a tag, so that every build reads the same way and a version
  # in a bug report can be compared to another without knowing which of the two
  # happened to be a release.
  version = "$(git describe --tags --long --always)";

  commit = "$(git rev-parse HEAD)";
}
