#!/usr/bin/env python3
#
# Hookd deployment script — triggers a deploy via the Famedly Hookd webhook
# API and polls until the job completes.
#
# Required environment variables:
#   HOOKD_URL         — Base URL of the Hookd server
#   BASIC_AUTH_PASS   — Password for HTTP Basic Auth (user is always "github")
#
# Optional:
#   HOOKD_ENDPOINT    — Deploy endpoint path (default: /hookd/hook/deploy)

import os
import sys
import time
from urllib.parse import urlsplit

import requests
from requests.auth import HTTPBasicAuth


def stream_to_file(stream, file):
    for chunk in stream:
        file.write(chunk)


sys.stdout.reconfigure(line_buffering=True)

hookd_url = os.environ["HOOKD_URL"].rstrip("/")
hookd_endpoint = os.environ.get("HOOKD_ENDPOINT", "/hookd/hook/deploy")
basic = HTTPBasicAuth("github", os.environ["BASIC_AUTH_PASS"])

resp = requests.post(
    f"{hookd_url}{hookd_endpoint}",
    auth=basic,
    json={"vars": {}},
)
resp.raise_for_status()

cookies = resp.cookies
uuid = resp.content.decode()
server = next(
    filter(lambda x: x, [urlsplit(v).hostname for v in cookies.values()]),
    None,
)

print(f"The UUID of the hookd job is {uuid}")
print(f"It was run on the server: {server}")

while True:
    resp = requests.get(
        f"{hookd_url}/hookd/status/{uuid}",
        auth=basic,
        cookies=cookies,
    )
    status = resp.json()
    if status["running"]:
        print(f"Job {uuid} on {server} is still running, sleeping for 30s")
        time.sleep(30)
    else:
        break

print(f"\033[32mPrinting stdout of job {uuid}:\033[0m")
resp = requests.get(
    f"{hookd_url}/hookd/status/{uuid}/stdout",
    auth=basic,
    stream=True,
    cookies=cookies,
)
stream_to_file(resp.iter_content(chunk_size=None), sys.stdout.buffer)

if not status["success"]:
    print("\033[31mFAILURE, printing stderr of job:\033[0m")
    resp = requests.get(
        f"{hookd_url}/hookd/status/{uuid}/stderr",
        auth=basic,
        stream=True,
        cookies=cookies,
    )
    stream_to_file(resp.iter_content(chunk_size=None), sys.stdout.buffer)
    sys.exit(1)
