#!/usr/bin/env python3
"""cover-letter-web의 태그 출처·노출 경로·nginx 실행 계약을 로컬에서 검증한다."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
CHART = REPOSITORY / "helm/applications/cover-letter-web"
TEST_TAG = "0123456789ab"
CORE_ROOT = None
DEPLOYMENT_STAGE = "active"


def run_command(*arguments, input_text=None):
    return subprocess.run(
        arguments, input=input_text, text=True, cwd=REPOSITORY,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def yaml_documents(yaml_text):
    completed = run_command("yq", "eval", "-o=json", "-I=0", ".", "-", input_text=yaml_text)
    if completed.returncode:
        raise AssertionError(completed.stderr)
    return [json.loads(document) for document in completed.stdout.splitlines() if document]


def yaml_file(relative_path):
    return yaml_documents((REPOSITORY / relative_path).read_text(encoding="utf-8"))[0]


class CoverLetterDeploymentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        completed = run_command(
            "helm", "template", "cover-letter-web-prod", str(CHART),
            "-f", str(CHART / "values-prod.yaml"),
            "--set-string", f"cover-letter-web.image.tag={TEST_TAG}",
        )
        if completed.returncode:
            raise AssertionError(completed.stderr)
        cls.resources = {manifest["kind"]: manifest for manifest in yaml_documents(completed.stdout)}

    def test_chart_requires_a_real_sha12_tag(self):
        missing_tag = run_command("helm", "template", "cover-letter-web-prod", str(CHART))
        self.assertNotEqual(missing_tag.returncode, 0)
        self.assertIn("cover-letter-web.image.tag", missing_tag.stderr)
        invalid_tag = run_command("helm", "template", "cover-letter-web-prod", str(CHART), "--set-string", "cover-letter-web.image.tag=latest")
        self.assertNotEqual(invalid_tag.returncode, 0)
        self.assertIn("SHA", invalid_tag.stderr)

    def test_chart_has_no_image_tag_fallback(self):
        chart_values = yaml_file("helm/applications/cover-letter-web/values.yaml")
        prod_values = yaml_file("helm/applications/cover-letter-web/values-prod.yaml")
        self.assertEqual(chart_values["cover-letter-web"]["image"]["tag"], "")
        self.assertNotIn("tag", prod_values["cover-letter-web"]["image"])
        container = self.resources["Deployment"]["spec"]["template"]["spec"]["containers"][0]
        self.assertEqual(container["image"], f"harbor.onjitda.com/prod/cover-letter-web:{TEST_TAG}")

    def test_service_and_health_probes_use_nginx_8080(self):
        deployment = self.resources["Deployment"]
        pod = deployment["spec"]["template"]["spec"]
        container = pod["containers"][0]
        self.assertEqual(container["ports"][0]["containerPort"], 8080)
        self.assertEqual(self.resources["Service"]["spec"]["ports"][0]["port"], 80)
        self.assertEqual(self.resources["Service"]["spec"]["ports"][0]["targetPort"], 8080)
        for probe_name in ("startupProbe", "readinessProbe", "livenessProbe"):
            self.assertEqual(container[probe_name]["httpGet"], {"path": "/healthz", "port": "http"})
        self.assertEqual(self.resources["Service"]["spec"]["selector"], deployment["spec"]["selector"]["matchLabels"])
        self.assertEqual(deployment["metadata"]["name"], "cover-letter-web-prod")

    def test_pod_runs_without_runtime_env_and_with_non_root_security(self):
        pod = self.resources["Deployment"]["spec"]["template"]["spec"]
        container = pod["containers"][0]
        self.assertFalse(pod["automountServiceAccountToken"])
        self.assertEqual(pod["imagePullSecrets"], [{"name": "harbor-docker-secret"}])
        self.assertTrue(pod["securityContext"]["runAsNonRoot"])
        self.assertEqual(pod["securityContext"]["runAsUser"], 101)
        self.assertEqual(pod["securityContext"]["runAsGroup"], 101)
        self.assertEqual(pod["securityContext"]["seccompProfile"], {"type": "RuntimeDefault"})
        self.assertFalse(container["securityContext"]["allowPrivilegeEscalation"])
        self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
        self.assertEqual(container["securityContext"]["capabilities"], {"drop": ["ALL"]})
        self.assertEqual(container["volumeMounts"], [{"name": "nginx-tmp", "mountPath": "/tmp"}])
        self.assertIn("emptyDir", pod["volumes"][0])
        self.assertEqual(container["resources"]["requests"], {"cpu": "25m", "memory": "16Mi"})
        for runtime_key in ("env", "envFrom"):
            self.assertNotIn(runtime_key, container)
        self.assertNotIn("initContainers", pod)

    def test_application_reads_chart_and_required_tag_from_main(self):
        if DEPLOYMENT_STAGE == "prepared":
            self.assertFalse((REPOSITORY / "environments/argocd/apps/cover-letter-web-prod.yaml").exists())
            return
        application = yaml_file("environments/argocd/apps/cover-letter-web-prod.yaml")
        chart_source, values_source = application["spec"]["sources"]
        self.assertEqual(chart_source["repoURL"], "https://github.com/kimjoongwon/prj-devops.git")
        self.assertEqual(chart_source["targetRevision"], "main")
        self.assertEqual(chart_source["path"], "helm/applications/cover-letter-web")
        self.assertEqual(chart_source["helm"]["valueFiles"], ["values-prod.yaml", "$values/prod/cover-letter-web.yaml"])
        self.assertFalse(chart_source["helm"].get("ignoreMissingValueFiles", False))
        self.assertEqual(values_source, {"repoURL": "https://github.com/kimjoongwon/prj-deploy.git", "targetRevision": "main", "ref": "values"})
        self.assertEqual(application["spec"]["destination"]["namespace"], "plate-prod")
        self.assertFalse((REPOSITORY / "environments/argocd/apps/cover-letter-web-stg.yaml").exists())

    def test_ingress_preserves_the_cover_letter_prefix(self):
        completed = run_command("helm", "template", "ingress-prod", "helm/ingress")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        ingress = next(manifest for manifest in yaml_documents(completed.stdout) if manifest["kind"] == "Ingress")
        host_rule = next(rule for rule in ingress["spec"]["rules"] if rule["host"] == "onjitda.com")
        prefix_routes = [route for route in host_rule["http"]["paths"] if route["path"] == "/cover-letter"]
        expected_routes = [] if DEPLOYMENT_STAGE == "prepared" else [{"path": "/cover-letter", "pathType": "Prefix", "backend": {"service": {"name": "cover-letter-web-prod", "port": {"number": 80}}}}]
        self.assertEqual(prefix_routes, expected_routes)
        self.assertFalse(any("rewrite" in name for name in ingress["metadata"].get("annotations", {})))

    def test_job_dsl_and_push_router_match_the_new_app_build_paths(self):
        configurations = yaml_file("helm/development-tools/jenkins/values.yaml")["controller"]["JCasC"]["configScripts"]
        app_jobs = configurations["app-build-jobs"]
        push_router = configurations["push-router-job"]
        for configuration in (app_jobs, push_router):
            app_entry = next(line for line in configuration.splitlines() if "[name: 'cover-letter-web-build'" in line)
            matched_region = re.search(r"regions:\s*['\"](.+?)['\"]", app_entry).group(1)
            app_region = matched_region.removesuffix("${rootCfg}").rstrip("|")
            for changed_path in (
                "apps/cover-letter/web/src/main.tsx", "devops/Dockerfile.cover-letter-web",
                "devops/nginx.cover-letter-web.conf",
            ):
                self.assertIsNotNone(re.fullmatch(app_region, changed_path), changed_path)
            self.assertIsNone(re.fullmatch(app_region, "apps/proposal/web/src/app/page.tsx"))
        self.assertIn("script: 'devops/Jenkinsfile.cover-letter-web'", app_jobs)
        self.assertRegex(app_jobs, r"if \(app\.name == 'cover-letter-web-build'\) \{\s*booleanParam\('INITIALIZE_APP', false,")


class CrossRepositoryPipelineTests(unittest.TestCase):
    def setUp(self):
        if CORE_ROOT is None:
            self.skipTest("--core-root를 지정하면 저장소 간 계약을 검증한다.")

    def test_shared_job_keeps_trust_sha12_and_explicit_initialize_gates(self):
        pipeline = (CORE_ROOT / "devops/Jenkinsfile.gitops-update").read_text(encoding="utf-8")
        self.assertRegex(pipeline, r"name: 'INITIALIZE_APP',\s*defaultValue: false")
        self.assertIn("'cover-letter-web'", pipeline)
        for gate in (
            "env.CHANGE_ID || env.TRUSTED_DEPLOYMENT != 'true'",
            "params.IMAGE_TAG ==~ /[0-9a-f]{12}/",
            "params.APP_NAME == 'cover-letter-web' && params.DEPLOY_ENV != 'prod'",
            "params.INITIALIZE_APP && (params.APP_NAME != 'cover-letter-web' || params.DEPLOY_ENV != 'prod')",
        ):
            self.assertIn(gate, pipeline)
            self.assertLess(pipeline.index(gate), pipeline.index("withCredentials([", pipeline.index("pipeline {")))
        self.assertIn('if [[ "${INITIALIZE_APP:-false}" == "true" ]]', pipeline)
        self.assertIn("initialize_args+=(--initialize)", pipeline)
        self.assertIn('"${initialize_args[@]}"', pipeline)

    def test_app_pipeline_passes_initialize_only_after_image_push(self):
        pipeline = (CORE_ROOT / "devops/Jenkinsfile.cover-letter-web").read_text(encoding="utf-8")
        self.assertRegex(pipeline, r"def INITIALIZE_APP = params\?\.INITIALIZE_APP == true")
        self.assertRegex(pipeline, r"booleanParam\(\s*name: 'INITIALIZE_APP',\s*value: INITIALIZE_APP\s*\)")
        self.assertLess(pipeline.index("stage('Build and Push Image')"), pipeline.index("stage('Trigger GitOps Update Job')"))
        self.assertNotIn("properties([", pipeline)

    def test_nginx_keeps_prefix_redirect_health_and_non_root_paths(self):
        nginx_configuration = (CORE_ROOT / "devops/nginx.cover-letter-web.conf").read_text(encoding="utf-8")
        dockerfile = (CORE_ROOT / "devops/Dockerfile.cover-letter-web").read_text(encoding="utf-8")
        self.assertIn("listen 8080;", nginx_configuration)
        self.assertRegex(nginx_configuration, r"location = /cover-letter \{\s*return 308 /cover-letter/;")
        self.assertRegex(nginx_configuration, r"location = /healthz \{[^}]*return 200")
        self.assertIn("location /cover-letter/", nginx_configuration)
        self.assertIn("pid /tmp/nginx.pid", dockerfile + nginx_configuration)
        self.assertRegex(dockerfile, r"(?m)^USER (?:nginx|101(?::101)?)$")


if __name__ == "__main__":
    argument_parser = argparse.ArgumentParser()
    argument_parser.add_argument("--core-root", type=Path)
    argument_parser.add_argument("--deployment-stage", choices=("prepared", "active"), default="active")
    options, unittest_options = argument_parser.parse_known_args()
    CORE_ROOT = options.core_root.resolve() if options.core_root else None
    DEPLOYMENT_STAGE = options.deployment_stage
    unittest.main(argv=[sys.argv[0], *unittest_options], verbosity=2)
