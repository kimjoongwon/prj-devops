#!/usr/bin/env python3
"""실제 임시 Git 저장소로 범프·최초 생성·실패 시 무변경을 검증한다."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("update-gitops-image-tag.sh")
INITIAL_TAG = "a1b2c3d4e5f6"
NEXT_TAG = "012345678901"


class GitOpsImageTagTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.repository = Path(self.temporary_directory.name)
        self.command("git", "init", "--quiet", "--initial-branch=main")
        self.command("git", "config", "user.name", "GitOps Test")
        self.command("git", "config", "user.email", "gitops-test@localhost")
        self.command("git", "config", "commit.gpgsign", "false")
        for deploy_environment in ("prod", "stg"):
            self.write_values(f"{deploy_environment}/idp-api.yaml", "idp-api")
        self.command("git", "add", ".")
        self.command("git", "commit", "--quiet", "-m", "test: seed deploy fixtures")
        self.initial_commit = self.command("git", "rev-parse", "HEAD").strip()

    def command(self, *arguments):
        completed = subprocess.run(
            arguments, cwd=self.repository, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        return completed.stdout

    def write_values(self, relative_path, app_name="cover-letter-web"):
        values_file = self.repository / relative_path
        values_file.parent.mkdir(parents=True, exist_ok=True)
        values_file.write_text(
            f'{app_name}:\n  image:\n    tag: "{INITIAL_TAG}"\n'
            '    pullPolicy: IfNotPresent\n', encoding="utf-8",
        )
        return values_file

    def seed_cover_letter(self):
        values_file = self.write_values("prod/cover-letter-web.yaml")
        self.command("git", "add", ".")
        self.command("git", "commit", "--quiet", "-m", "test: seed cover letter")
        return values_file

    def update_tag(self, *arguments, succeeds=True, additional_environment=None):
        environment = os.environ.copy()
        for environment_key in (
            "APP_NAME", "IMAGE_TAG", "DEPLOY_ENV", "ENV", "REPO_URL", "TARGET_BRANCH",
            "GIT_USER_NAME", "GIT_USER_EMAIL", "PUSH_RETRIES", "WORKDIR", "DRY_RUN",
            "SKIP_PUSH", "INITIALIZE_APP",
        ):
            environment.pop(environment_key, None)
        environment.update(additional_environment or {})
        completed = subprocess.run(
            ["bash", str(SCRIPT), "--workdir", str(self.repository), "--app",
             "cover-letter-web", "--tag", NEXT_TAG, "--skip-push", *arguments],
            cwd=self.repository, env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )
        if succeeds:
            self.assertEqual(completed.returncode, 0, completed.stdout)
        else:
            self.assertNotEqual(completed.returncode, 0, completed.stdout)
        return completed.stdout

    def assert_repository_unchanged(self, expected_commit=None):
        self.assertEqual(self.command("git", "status", "--porcelain"), "")
        self.assertEqual(
            self.command("git", "rev-parse", "HEAD").strip(),
            expected_commit or self.initial_commit,
        )

    def test_missing_file_requires_explicit_initialize_option(self):
        self.assertIn("Values file not found", self.update_tag(succeeds=False))
        self.assertFalse((self.repository / "prod/cover-letter-web.yaml").exists())
        self.assert_repository_unchanged()

    def test_initialize_cannot_be_enabled_with_an_environment_variable(self):
        self.update_tag(succeeds=False, additional_environment={"INITIALIZE_APP": "true"})
        self.assert_repository_unchanged()

    def test_initialize_commits_only_the_app_image_tag_as_a_string(self):
        self.update_tag("--initialize")
        values_file = self.repository / "prod/cover-letter-web.yaml"
        actual_values = json.loads(self.command("yq", "eval", "-o=json", ".", str(values_file)))
        self.assertEqual(actual_values, {"cover-letter-web": {"image": {"tag": NEXT_TAG}}})
        self.assertIn(f'tag: "{NEXT_TAG}"', values_file.read_text(encoding="utf-8"))
        self.assertEqual(
            self.command("git", "show", "--format=", "--name-only", "HEAD").strip(),
            "prod/cover-letter-web.yaml",
        )
        self.assertIn("ci(gitops): bump cover-letter-web image to", self.command("git", "log", "-1", "--format=%s"))
        self.assertEqual(self.command("git", "status", "--porcelain"), "")

    def test_existing_file_bumps_without_initialize_and_preserves_other_values(self):
        self.seed_cover_letter()
        self.update_tag()
        self.assertEqual(self.command("yq", ".[\"cover-letter-web\"].image.tag", "prod/cover-letter-web.yaml").strip(), NEXT_TAG)
        self.assertEqual(self.command("yq", ".[\"cover-letter-web\"].image.pullPolicy", "prod/cover-letter-web.yaml").strip(), "IfNotPresent")

    def test_initialize_on_existing_file_keeps_normal_bump_behavior(self):
        self.seed_cover_letter()
        self.update_tag("--initialize")
        self.assertEqual(self.command("yq", ".[\"cover-letter-web\"].image.pullPolicy", "prod/cover-letter-web.yaml").strip(), "IfNotPresent")

    def test_identical_existing_tag_is_a_no_op(self):
        self.seed_cover_letter()
        existing_commit = self.command("git", "rev-parse", "HEAD").strip()
        self.assertIn("No change needed", self.update_tag("--tag", INITIAL_TAG, "--initialize"))
        self.assert_repository_unchanged(existing_commit)

    def test_other_apps_cannot_initialize_even_when_their_file_exists(self):
        for app_name in ("idp-api", "dolmen-web"):
            with self.subTest(app_name=app_name):
                self.assertIn("--initialize is only allowed", self.update_tag("--app", app_name, "--initialize", succeeds=False))
                self.assert_repository_unchanged()

    def test_cover_letter_stg_is_rejected_with_or_without_initialize(self):
        for extra_options in ((), ("--initialize",)):
            with self.subTest(extra_options=extra_options):
                self.assertIn("prod-only", self.update_tag("--env", "stg", *extra_options, succeeds=False))
                self.assert_repository_unchanged()

    def test_unsupported_app_and_environment_are_rejected(self):
        for invalid_options in (("--app", "../idp-api"), ("--env", "qa")):
            with self.subTest(invalid_options=invalid_options):
                self.assertIn("Unsupported", self.update_tag(*invalid_options, "--initialize", succeeds=False))
                self.assert_repository_unchanged()

    def test_tags_must_be_twelve_lowercase_hexadecimal_characters(self):
        for invalid_tag in ("latest", "123456789ab", "ABCDEF012345", "a" * 40, "12345678901g"):
            with self.subTest(invalid_tag=invalid_tag):
                self.assertIn("--tag must be", self.update_tag("--tag", invalid_tag, "--initialize", succeeds=False))
                self.assert_repository_unchanged()

    def test_initialize_dry_run_shows_the_new_file_without_leaving_changes(self):
        output = self.update_tag("--initialize", "--dry-run")
        self.assertIn("+cover-letter-web:", output)
        self.assertFalse((self.repository / "prod/cover-letter-web.yaml").exists())
        self.assert_repository_unchanged()

    def test_existing_file_dry_run_restores_the_original_bytes(self):
        values_file = self.seed_cover_letter()
        original_content = values_file.read_bytes()
        existing_commit = self.command("git", "rev-parse", "HEAD").strip()
        self.update_tag("--dry-run")
        self.assertEqual(values_file.read_bytes(), original_content)
        self.assert_repository_unchanged(existing_commit)

    def test_existing_file_without_an_image_tag_is_not_reinitialized(self):
        values_file = self.repository / "prod/cover-letter-web.yaml"
        values_file.write_text("cover-letter-web: {}\n", encoding="utf-8")
        self.command("git", "add", ".")
        self.command("git", "commit", "--quiet", "-m", "test: missing image tag")
        existing_commit = self.command("git", "rev-parse", "HEAD").strip()
        self.assertIn("Could not find current image tag", self.update_tag("--initialize", succeeds=False))
        self.assert_repository_unchanged(existing_commit)

    def test_existing_service_stg_bump_is_preserved(self):
        self.update_tag("--app", "idp-api", "--env", "stg")
        self.assertEqual(self.command("yq", ".[\"idp-api\"].image.tag", "stg/idp-api.yaml").strip(), NEXT_TAG)
        self.assertIn("bump stg/idp-api image", self.command("git", "log", "-1", "--format=%s"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
