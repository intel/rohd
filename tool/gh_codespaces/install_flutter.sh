#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_flutter.sh
# Install the current stable Flutter SDK and its bundled Dart SDK.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

declare -r flutter_sdk_dir='/opt/flutter'
declare -r flutter_releases_url='https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'

if ! command -v curl >/dev/null 2>&1 ||
    ! command -v python3 >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl python3
fi

release_manifest="$(mktemp)"
archive="$(mktemp)"
trap 'rm -f "${release_manifest}" "${archive}"' EXIT

curl --fail --location --silent --show-error "${flutter_releases_url}" \
  --output "${release_manifest}"

flutter_release="$(
  python3 - "${release_manifest}" <<'PYTHON'
import json
import sys

with open(sys.argv[1]) as manifest:
    release_data = json.load(manifest)
stable_hash = release_data['current_release']['stable']
stable_release = next(
    release for release in release_data['releases']
    if release['hash'] == stable_hash
)
print(stable_release['version'], stable_release['archive'])
PYTHON
)"
read -r flutter_version flutter_archive_path <<< "${flutter_release}"
declare -r flutter_version
declare -r flutter_archive_path
declare -r flutter_archive_url="https://storage.googleapis.com/flutter_infra_release/releases/${flutter_archive_path}"

if [[ -x "${flutter_sdk_dir}/bin/flutter" ]] &&
    "${flutter_sdk_dir}/bin/flutter" --version | grep -q "Flutter ${flutter_version}"; then
  sudo ln --force --symbolic "${flutter_sdk_dir}/bin/dart" /usr/local/bin/dart
  echo "Flutter ${flutter_version} is already installed."
  exit 0
fi

sudo rm -rf "${flutter_sdk_dir}"
sudo apt-get update
sudo apt-get install -y xz-utils

curl --fail --location --silent --show-error "${flutter_archive_url}" \
  --output "${archive}"
sudo tar --extract --xz --file "${archive}" --directory /opt
sudo ln --force --symbolic "${flutter_sdk_dir}/bin/flutter" /usr/local/bin/flutter
sudo ln --force --symbolic "${flutter_sdk_dir}/bin/dart" /usr/local/bin/dart

flutter --version
