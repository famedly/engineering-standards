# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Famedly GmbH
#
# SPDX-License-Identifier: Apache-2.0

# Second half of the step that installs docker-credential-gha-oidc. The first
# half, in `docker-gha-oidc.nix`, has written the helper to `$bin`.
# shellcheck disable=SC2154 # bin is assigned in the first half.
chmod +x "$bin"
dirname "$bin" >>"$GITHUB_PATH"

# Register the helper in a config file, keeping whatever else it holds.
configure-credhelper() {
	mkdir --parents "$(dirname "$1")"
	[ -s "$1" ] || echo '{}' >"$1"
	jq '.credHelpers["registry.famedly.net"] = "gha-oidc"' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}

# Docker reads its config file.
configure-credhelper "${DOCKER_CONFIG:-$HOME/.docker}/config.json"

# The containers tools (podman, skopeo, buildah) read their auth file
# (containers-auth.json(5)). If the job already points them at one, add the
# helper there; otherwise create one.
if [[ -n ${REGISTRY_AUTH_FILE:-} ]]; then
	configure-credhelper "$REGISTRY_AUTH_FILE"
else
	auth="$RUNNER_TEMP/containers-auth.json"
	configure-credhelper "$auth"
	echo "REGISTRY_AUTH_FILE=$auth" >>"$GITHUB_ENV"
fi
