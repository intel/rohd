#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_flutter.sh
# GitHub Codespaces setup: Install the Flutter SDK used by CI.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

declare -r flutter_version='3.47.0'
declare -r flutter_sdk_dir='/opt/flutter'
declare -r flutter_archive_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"

if [[ -x "${flutter_sdk_dir}/bin/flutter" ]] &&
    "${flutter_sdk_dir}/bin/flutter" --version | grep -q "Flutter ${flutter_version}"; then
  sudo ln --force --symbolic "${flutter_sdk_dir}/bin/dart" /usr/local/bin/dart
  echo "Flutter ${flutter_version} is already installed."
  exit 0
fi

sudo rm -rf "${flutter_sdk_dir}"
sudo apt-get update
sudo apt-get install -y curl xz-utils

archive="$(mktemp)"
trap 'rm -f "${archive}"' EXIT

curl --fail --location --silent --show-error "${flutter_archive_url}" \
  --output "${archive}"
sudo tar --extract --xz --file "${archive}" --directory /opt
sudo ln --force --symbolic "${flutter_sdk_dir}/bin/flutter" /usr/local/bin/flutter
sudo ln --force --symbolic "${flutter_sdk_dir}/bin/dart" /usr/local/bin/dart

flutter --version
