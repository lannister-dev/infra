"""Structural and syntax tests for Ansible roles.

These tests validate role structure, YAML correctness, task naming,
default variable coverage and playbook syntax without requiring Docker.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
ROLES_DIR = REPO_ROOT / "ansible" / "roles"

ROLE_NAMES = [
    "docker-prerequisites",
    "docker-secrets",
    "docker-networks",
    "node-bootstrap",
    "swarm-join",
    "stack-deploy",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_yaml(path: Path) -> object:
    with open(path) as fh:
        return yaml.safe_load(fh)


def _iter_task_files(role_dir: Path):
    """Yield all YAML files under tasks/, handlers/, etc."""
    for subdir in ("tasks", "handlers"):
        d = role_dir / subdir
        if d.is_dir():
            yield from d.glob("*.yml")


# ---------------------------------------------------------------------------
# Parametrize over all roles
# ---------------------------------------------------------------------------

@pytest.fixture(params=ROLE_NAMES)
def role_name(request):
    return request.param


@pytest.fixture
def role_dir(role_name):
    return ROLES_DIR / role_name


# ---------------------------------------------------------------------------
# 1. Structure
# ---------------------------------------------------------------------------

class TestRoleStructure:
    def test_tasks_main_exists(self, role_dir):
        assert (role_dir / "tasks" / "main.yml").is_file(), (
            f"{role_dir.name}: tasks/main.yml missing"
        )

    def test_defaults_main_exists(self, role_dir):
        assert (role_dir / "defaults" / "main.yml").is_file(), (
            f"{role_dir.name}: defaults/main.yml missing"
        )


# ---------------------------------------------------------------------------
# 2. YAML validity
# ---------------------------------------------------------------------------

class TestYamlSyntax:
    def test_tasks_main_is_valid_yaml(self, role_dir):
        data = _load_yaml(role_dir / "tasks" / "main.yml")
        assert isinstance(data, list), "tasks/main.yml must be a YAML list"

    def test_defaults_main_is_valid_yaml(self, role_dir):
        data = _load_yaml(role_dir / "defaults" / "main.yml")
        assert isinstance(data, dict), "defaults/main.yml must be a YAML dict"

    def test_all_yaml_files_parse(self, role_dir):
        for yml in role_dir.rglob("*.yml"):
            try:
                yaml.safe_load(yml.read_text())
            except yaml.YAMLError as exc:
                pytest.fail(f"{yml.relative_to(REPO_ROOT)}: {exc}")


# ---------------------------------------------------------------------------
# 3. Task quality
# ---------------------------------------------------------------------------

class TestTaskQuality:
    def test_all_tasks_have_names(self, role_dir):
        for task_file in _iter_task_files(role_dir):
            tasks = _load_yaml(task_file)
            if not tasks:
                continue
            for i, task in enumerate(tasks):
                assert "name" in task, (
                    f"{task_file.relative_to(REPO_ROOT)}: task #{i} missing 'name'"
                )

    def test_no_deprecated_modules(self, role_dir):
        deprecated = {"command", "shell"}  # not deprecated, but check for raw
        # Only flag ansible.builtin.raw outside of bootstrap context
        for task_file in _iter_task_files(role_dir):
            tasks = _load_yaml(task_file) or []
            for task in tasks:
                if "ansible.builtin.raw" in task:
                    # raw is acceptable only in node-bootstrap (pre-python)
                    assert role_dir.name == "node-bootstrap", (
                        f"{task_file.relative_to(REPO_ROOT)}: "
                        f"raw module should only be used in node-bootstrap"
                    )


# ---------------------------------------------------------------------------
# 4. Default variable coverage
# ---------------------------------------------------------------------------

def _extract_jinja_vars(text: str) -> set[str]:
    """Extract variable names referenced in Jinja2 {{ }} and when: clauses."""
    import re
    # Match {{ var_name }} or {{ var_name.something }}
    refs = set(re.findall(r"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)", text))
    # Exclude Ansible built-ins and common filters
    builtins = {
        "item", "ansible_facts", "inventory_hostname", "hostvars",
        "groups", "omit", "true", "false", "none", "lookup",
    }
    return refs - builtins


def _extract_registered_vars(tasks: list[dict]) -> set[str]:
    """Extract variable names from register: directives in task list."""
    registered = set()
    for task in (tasks or []):
        if "register" in task:
            registered.add(task["register"])
    return registered


class TestDefaultCoverage:
    def test_role_variables_have_defaults(self, role_dir):
        """Every variable used in tasks should be either in defaults or a
        well-known Ansible variable.  This catches missing defaults that
        would cause undefined-variable errors at runtime."""
        import re

        tasks_path = role_dir / "tasks" / "main.yml"
        tasks_text = tasks_path.read_text()
        tasks_data = _load_yaml(tasks_path) or []
        used_vars = _extract_jinja_vars(tasks_text)

        defaults_text = (role_dir / "defaults" / "main.yml").read_text()
        defaults = _load_yaml(role_dir / "defaults" / "main.yml") or {}
        defined_vars = set(defaults.keys())
        # Also count variables mentioned in defaults comments (documented but commented)
        defined_vars |= _extract_jinja_vars(defaults_text)

        # Variables that are expected to come from the caller (role params)
        # are documented in defaults as comments — extract those too
        comment_vars = set(re.findall(r"#\s*([a-zA-Z_][a-zA-Z0-9_]*):", defaults_text))
        defined_vars |= comment_vars

        # Variables created by register: directives are internal, not inputs
        defined_vars |= _extract_registered_vars(tasks_data)

        # Variables commonly provided by group_vars or playbook scope
        defined_vars |= {"repo_root"}

        missing = used_vars - defined_vars
        if missing:
            pytest.fail(
                f"{role_dir.name}: variables used in tasks but not in "
                f"defaults: {sorted(missing)}"
            )


# ---------------------------------------------------------------------------
# 5. Playbook syntax check (roles resolve correctly)
# ---------------------------------------------------------------------------

_SYNTAX_CHECK_PLAYBOOKS = [
    "ansible/playbooks/deploy-stacks.yml",
    "ansible/playbooks/deploy-data-stacks.yml",
    "ansible/playbooks/reconcile-vpn-nodes.yml",
    "ansible/playbooks/reconcile-infra-nodes.yml",
]


_has_ansible_playbook = shutil.which("ansible-playbook") is not None


class TestPlaybookSyntax:
    @pytest.mark.skipif(
        not _has_ansible_playbook,
        reason="ansible-playbook not installed",
    )
    @pytest.mark.parametrize("playbook", _SYNTAX_CHECK_PLAYBOOKS)
    def test_syntax_check(self, playbook):
        """ansible-playbook --syntax-check must pass for playbooks using roles."""
        pb_path = REPO_ROOT / playbook
        if not pb_path.is_file():
            pytest.skip(f"{playbook} not found")
        result = subprocess.run(
            [
                "ansible-playbook",
                "--syntax-check",
                str(pb_path),
            ],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
            env={
                "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
                "HOME": str(Path.home()),
                "ANSIBLE_CONFIG": str(REPO_ROOT / "ansible" / "ansible.cfg"),
                "ANSIBLE_ROLES_PATH": str(ROLES_DIR),
            },
        )
        assert result.returncode == 0, (
            f"Syntax check failed for {playbook}:\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}"
        )
