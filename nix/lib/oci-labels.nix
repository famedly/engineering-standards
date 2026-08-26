## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# What an image says about where it came from, in the annotations a registry
# and a scanner already know how to read.
#
# Whatever CI does not know is left out rather than sent empty: a label that is
# there but blank reads as an answer.
#
# No `org.opencontainers.image.created`: a timestamp would make two builds of
# the same commit differ, and the commit is what the question is really about.
{ lib }:
{
  title,
  source ? null,
  revision ? null,
  version ? null,
}:
lib.filterAttrs (_: value: value != null) {
  "org.opencontainers.image.title" = title;
  "org.opencontainers.image.source" = source;
  "org.opencontainers.image.revision" = revision;
  "org.opencontainers.image.version" = version;
}
