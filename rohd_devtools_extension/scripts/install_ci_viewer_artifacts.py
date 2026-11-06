#!/usr/bin/env python3
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
"""Install a public commit-addressed dart_wellen branch artifact."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.error
import urllib.request


ARTIFACT_BRANCH = "artifacts"
BUILD_MANIFEST = "tool/bridge_artifacts.build.json"
CONTRACT_MANIFEST = "tool/bridge_artifacts.json"
FILES = (
    "lib/src/rust/api.dart",
    "lib/src/rust/frb_generated.dart",
    "lib/src/rust/frb_generated.io.dart",
    "lib/src/rust/frb_generated.web.dart",
    "web/pkg/wellen_bridge.js",
    "web/pkg/wellen_bridge_bg.wasm",
    "web/pkg/LICENSE",
    "web/pkg/wellen_bridge_LICENSES.txt",
)


def fail(message):
    raise ValueError(message)


def download(url):
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            fail(
                f"No public CI artifact exists at {url}. Push the selected "
                "commit and wait for General CI to publish it."
            )
        raise


def git_commit(package_root):
    commit = subprocess.run(
        ["git", "-C", str(package_root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        fail(f"Could not determine Git commit for {package_root}.")
    return commit


def git_origin(repository):
    repository = Path(repository)
    command = (
        ["git", "--git-dir", str(repository), "remote", "get-url", "origin"]
        if (repository / "HEAD").is_file() and (repository / "objects").is_dir()
        else ["git", "-C", str(repository), "remote", "get-url", "origin"]
    )
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def git_repository(package_root):
    repository = Path(package_root)
    remote = git_origin(repository)
    for _ in range(3):
        match = re.fullmatch(
            r"(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?",
            remote,
        )
        if match is not None:
            return match.group(1)

        cache = Path(remote.removeprefix("file://"))
        if not cache.is_dir():
            break
        repository = cache
        remote = git_origin(repository)
    fail(f"Resolved dart_wellen origin is not a GitHub repository: {remote}.")


def artifact_urls(repository, commit, version):
    base = (
        f"https://raw.githubusercontent.com/{repository}/{ARTIFACT_BRANCH}/"
        f"dart-wellen/{commit}/dart_wellen-{version}-web.tar.gz"
    )
    return base, f"{base}.json"


def install(package_root, archive, build):
    contract = json.loads((package_root / CONTRACT_MANIFEST).read_text())
    for key in ("version", "bridge_version", "profile", "archive_url"):
        if build.get(key) != contract.get(key):
            fail(
                "CI artifact metadata differs from the selected package "
                f"contract: {key}."
            )
    if build.get("source_commit") != git_commit(package_root):
        fail("CI artifact source commit does not match the resolved dart_wellen checkout.")
    files = build.get("files")
    if not isinstance(files, dict) or set(files) != set(FILES):
        fail("CI artifact has an unexpected dart_wellen file inventory.")
    if hashlib.sha256(archive).hexdigest() != build.get("archive_sha256"):
        fail("CI artifact archive SHA-256 does not match the build metadata.")

    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as bundle:
        members = bundle.getmembers()
        if (
            len(members) != len(FILES)
            or {member.name for member in members} != set(FILES)
            or any(not member.isfile() for member in members)
        ):
            fail("CI artifact archive has an unexpected dart_wellen file inventory.")
        for name in FILES:
            source = bundle.extractfile(name)
            if source is None:
                fail(f"CI artifact is missing {name}.")
            data = source.read()
            if hashlib.sha256(data).hexdigest() != files[name]:
                fail(f"CI artifact checksum does not match for {name}.")
            target = package_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    (package_root / BUILD_MANIFEST).write_text(json.dumps(build, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        commit = git_commit(args.package_root)
        repository = git_repository(args.package_root)
        contract = json.loads((args.package_root / CONTRACT_MANIFEST).read_text())
        archive_url, metadata_url = artifact_urls(
            repository,
            commit,
            contract["version"],
        )
        print(
            f"Downloading public CI artifact for {repository} at {commit}."
        )
        install(
            args.package_root,
            download(archive_url),
            json.loads(download(metadata_url)),
        )
    except (
        OSError,
        ValueError,
        KeyError,
        subprocess.CalledProcessError,
        urllib.error.URLError,
        tarfile.TarError,
    ) as error:
        parser.exit(1, f"dart_wellen CI artifact error: {error}\n")


if __name__ == "__main__":
    main()
