## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Composes shell blocks into one script without the blank lines that
# interpolating them into a surrounding string would leave behind — which is
# what otherwise turns a generated `run:` into a `|+` block with trailing
# emptiness for a reader to wonder about.
{ lib }: blocks: lib.concatStringsSep "\n\n" (map (lib.removeSuffix "\n") blocks)
