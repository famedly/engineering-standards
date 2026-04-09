#!/usr/bin/env bash
set -euo pipefail

echo "Preparing Rust build environment"

# Ensure repo path is safe
git config --global --add safe.directory "$(pwd)"

# Determine sudo availability (works inside and outside containers)
if [[ "$(id -u)" -eq 0 ]]; then
	SUDO=""
else
	SUDO="sudo"
fi

if [[ -n "${ADDITIONAL_PACKAGES:-}" ]]; then
  echo "Installing additional packages: ${ADDITIONAL_PACKAGES}"
	# We want to be explicit about word splitting here.
	# https://github.com/koalaman/shellcheck/wiki/Sc2046
	read -ra packages <<< "${ADDITIONAL_PACKAGES}"
	$SUDO apt-get install -yqq --no-install-recommends "${packages[@]}"
else
	echo "No additional packages specified. Skipping installation."
fi


# TODO: Don't set CARGO_HOME to a relative path. It is supposed to be an absolute path, this is potentially problematic.
# However, it works for now and any change to this needs to be thoroughly tested as github actions is really weird about runner home directories.
echo "Setting up build environment"
echo "CARGO_HOME = ${HOME}/${CARGO_HOME}"
mkdir -p "${HOME}/${CARGO_HOME}"

# Decide public/private mode based on presence of registry token
if [[ -z "${SHIPYARD_RS_TOKEN:-}" ]]; then
	echo "No private registry token provided. Configuring for public builds."
	export CRATE_REGISTRY_NAME="crates-io"
else
	echo "Private registry token detected. Configuring HTTPS credentials for Shipyard.rs."
	git config --global credential.helper store
	echo "https://famedly:${SHIPYARD_RS_TOKEN}@git.shipyard.rs" > ~/.git-credentials
	chmod 600 ~/.git-credentials
fi

cat << EOF >> "${HOME}/${CARGO_HOME}/config.toml"
[net]
git-fetch-with-cli = true

[registry]
global-credential-providers = ["cargo:token"]
EOF

if [ "$CRATE_REGISTRY_NAME" != "crates-io" ]; then
	cat << EOF >> "${HOME}/${CARGO_HOME}/config.toml"
[registries.${CRATE_REGISTRY_NAME}]
index = "${CRATE_REGISTRY_INDEX_URL}"
EOF

	cat << EOF >> "${HOME}/${CARGO_HOME}/credentials.toml"
[registries.${CRATE_REGISTRY_NAME}]
token = "${SHIPYARD_RS_TOKEN}"
EOF
fi

echo "CARGO_HOME=${HOME}/${CARGO_HOME}" >> "$GITHUB_ENV"

# Persist registry settings for subsequent GitHub Actions steps
echo "CRATE_REGISTRY_NAME=${CRATE_REGISTRY_NAME}" >> "$GITHUB_ENV"
if [[ -n "${CRATE_REGISTRY_INDEX_URL:-}" ]]; then
	echo "CRATE_REGISTRY_INDEX_URL=${CRATE_REGISTRY_INDEX_URL}" >> "$GITHUB_ENV"
fi

echo "Preparations finished"
