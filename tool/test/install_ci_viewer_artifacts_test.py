#!/usr/bin/env python3
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
"""Test branch-CI dart_wellen artifact installation without network access."""

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch


REPOSITORY = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "install_ci_viewer_artifacts",
    REPOSITORY / "rohd_devtools_extension/scripts/install_ci_viewer_artifacts.py",
)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallCiViewerArtifactsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ci viewer artifacts ")
        self.addCleanup(self.temporary.cleanup)
        self.package = Path(self.temporary.name) / "dart_wellen"
        self.package.mkdir()
        self.commit = "a" * 40
        self.contract = {
            "version": "0.1.2",
            "bridge_version": "2.8.0",
            "profile": "release",
            "archive_url": "https://github.com/example/viewer/releases/download/"
            "dart-wellen-0.1.2/dart_wellen-0.1.2-web.tar.gz",
            "files": list(installer.FILES),
        }
        (self.package / installer.CONTRACT_MANIFEST).parent.mkdir(parents=True)
        (self.package / installer.CONTRACT_MANIFEST).write_text(
            json.dumps(self.contract)
        )
        self.files = {
            name: f"artifact {name}".encode() for name in installer.FILES
        }
        self.files["web/pkg/wellen_bridge_bg.wasm"] = b"\0asmartifact"
        self.build = {
            **self.contract,
            "source_commit": self.commit,
            "files": {
                name: hashlib.sha256(data).hexdigest()
                for name, data in self.files.items()
            },
            "archive_sha256": "b" * 64,
        }

    def archive(self):
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:gz") as bundle:
            for name, data in self.files.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                bundle.addfile(info, io.BytesIO(data))
        return output.getvalue()

    def test_installs_matching_ci_artifact(self):
        archive = self.archive()
        self.build["archive_sha256"] = hashlib.sha256(archive).hexdigest()
        with patch.object(installer, "git_commit", return_value=self.commit):
            installer.install(self.package, archive, self.build)

        for name, data in self.files.items():
            self.assertEqual((self.package / name).read_bytes(), data)
        self.assertEqual(
            json.loads((self.package / installer.BUILD_MANIFEST).read_text()),
            self.build,
        )

    def test_rejects_artifact_from_another_commit(self):
        self.build["source_commit"] = "c" * 40

        with patch.object(installer, "git_commit", return_value=self.commit):
            with self.assertRaisesRegex(ValueError, "source commit"):
                installer.install(self.package, self.archive(), self.build)

    def test_builds_public_commit_addressed_urls(self):
        archive, metadata = installer.artifact_urls(
            "desmonddak/rohd-wave-viewer",
            self.commit,
            "0.1.2",
        )
        self.assertEqual(
            archive,
            "https://raw.githubusercontent.com/desmonddak/rohd-wave-viewer/"
            "artifacts/dart-wellen/"
            f"{self.commit}/dart_wellen-0.1.2-web.tar.gz",
        )
        self.assertEqual(metadata, f"{archive}.json")

    def test_derives_repository_from_resolved_git_origin(self):
        with patch.object(
            installer,
            "git_origin",
            side_effect=[
                "/cache/rohd-wave-viewer",
                "git@github.com:intel/rohd-wave-viewer.git",
            ],
        ), patch.object(
            installer.Path,
            "is_dir",
            side_effect=[True],
        ):
            self.assertEqual(
                installer.git_repository(self.package),
                "intel/rohd-wave-viewer",
            )


if __name__ == "__main__":
    unittest.main()
