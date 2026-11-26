#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Famedly GmbH
#
# SPDX-License-Identifier: Apache-2.0

# Docker credential helper, also understood by podman, that hands out the
# job's GitHub Actions OIDC token.
# https://github.com/docker/docker-credential-helpers#development
set -euo pipefail

if [[ ${1:-} != get ]]; then
	echo "unsupported operation: ${1:-<none>}" >&2
	exit 1
fi

IFS= read -r server || [[ -n $server ]]

curl --silent --show-error --fail --get \
	--data-urlencode "audience=https://$server" \
	--header "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
	"$ACTIONS_ID_TOKEN_REQUEST_URL" |
	jq --arg server "$server" \
		'{ServerURL: $server, Username: "__jwt", Secret: (.value // error("response has no .value"))}'
