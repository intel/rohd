#!/bin/bash

# Copyright (C) 2023-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dart.sh
# GitHub Codespaces setup: Install Dart SDK according to the instructions from https://dart.dev/get-dart#install-using-apt-get.
#
# 2023 February 5
# Author: Chykon
#
# 2026 June 21
# Updated to add fallback logic for fetching the latest Dart repository key from Google if the locally cached key fails verification (e.g. due to key rotation).
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

declare -r cached_pubkey_file="$(dirname "${BASH_SOURCE[0]}")/pubkeys/dart.pub"
declare -r keyring_file='/usr/share/keyrings/dart.gpg'
declare -r dart_repository_file='/etc/apt/sources.list.d/dart_stable.list'
declare -r dart_repository_url='https://storage.googleapis.com/download.dartlang.org/linux/debian'
declare -r google_signing_key_url='https://dl-ssl.google.com/linux/linux_signing_key.pub'

sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https

sudo mkdir -p /usr/share/keyrings

# Add Dart repository.

echo "deb [signed-by=${keyring_file}] ${dart_repository_url} stable main" \
  | sudo tee "${dart_repository_file}"

# Install the repository key from the locally cached, ASCII-armored public key.
install_key_from_file() {
  sudo gpg --yes --output "${keyring_file}" --dearmor "${1}"
}

# Install the repository key by fetching the latest key from Google.
install_key_from_google() {
  wget -qO- "${google_signing_key_url}" \
    | gpg --dearmor \
    | sudo tee "${keyring_file}" >/dev/null
}

# Emit a prominent warning that stands out in CI logs (and as a GitHub Actions
# annotation when available) without failing the build.
warn_loudly() {
  local message="${1}"
  {
    echo ''
    echo '################################################################################'
    echo '## install_dart WARNING'
    echo "## ${message}"
    echo '################################################################################'
    echo ''
  } >&2
  # Surface a GitHub Actions warning annotation (non-fatal) when running in CI.
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning title=install_dart cached key bypassed::${message}"
  fi
}

# Verify that the installed keyring can authenticate the Dart repository by
# refreshing only the Dart sources list and checking for signature/key errors.
dart_repository_verified() {
  local update_log
  if ! update_log=$(sudo apt-get update \
        -o Dir::Etc::sourcelist="${dart_repository_file}" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0" 2>&1); then
    return 1
  fi
  if echo "${update_log}" \
      | grep -Eiq 'NO_PUBKEY|EXPKEYSIG|REVKEYSIG|BADSIG|not signed|could.?n.?t be verified'; then
    return 1
  fi
  return 0
}

# Prefer the locally cached key. If it can no longer authenticate the repository
# (e.g. the key has been rotated), fall back to fetching the latest key from
# Google so the install can still proceed.
install_key_from_file "${cached_pubkey_file}"

if dart_repository_verified; then
  echo 'install_dart: using locally cached Dart repository key.'
else
  install_key_from_google
  if ! dart_repository_verified; then
    echo 'install_dart: Dart repository key verification failed even after fetching the latest key from Google.' >&2
    exit 1
  fi
  warn_loudly "Cached Dart repository key (${cached_pubkey_file}) failed verification and was bypassed; installed using the latest key fetched from Google. Please refresh the cached key."
fi

# Install Dart.

sudo apt-get update
sudo apt-get install -y dart
