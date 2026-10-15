"""Repo paths and constants — the single place any path is written down.

This module exists because commit 97f46d7 ("move/cleanup") renamed directories
and left 8 PowerShell scripts pointing at paths that no longer existed, which
broke the shader build end-to-end. Every path the build system touches is
defined here exactly once, so a future move is a one-file edit.

Renames this module encodes (old -> new):
    Reference/TUB/Bundle/gamedb/burnout5/{Shaders,Include}
        -> Source/Bundle/gamedb/burnout5/{Shaders,Include}
    Reference/360Shaders/<ver>            -> Reference/360/Shaders/<ver>/SHADERS
    Source/NuShaders.CLI                  -> Tools/ShaderApp/Source/NuShaders.CLI
    "PBR Mats"                            -> Materials
"""

import os
import socket

# --- roots -------------------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

BUILD_DIR = os.path.join(REPO_ROOT, "Build")
SOURCE_DIR = os.path.join(REPO_ROOT, "Source")
REFERENCE_DIR = os.path.join(REPO_ROOT, "Reference")
TOOLS_DIR = os.path.join(REPO_ROOT, "Tools")
MATERIALS_DIR = os.path.join(REPO_ROOT, "Materials")

# --- shader source -----------------------------------------------------------

BUNDLE_DIR = os.path.join(SOURCE_DIR, "Bundle", "gamedb", "burnout5")
SHADERS_DIR = os.path.join(BUNDLE_DIR, "Shaders")
INCLUDE_DIR = os.path.join(BUNDLE_DIR, "Include")
PLAYGROUND_DIR = os.path.join(BUNDLE_DIR, "Playground")

# --- reference corpora -------------------------------------------------------

X360_SHADERS_ROOT = os.path.join(REFERENCE_DIR, "360", "Shaders")
X360_VERSIONS = ("Breaker", "1.6", "1.8")
X360_REF_DEFAULT = os.path.join(X360_SHADERS_ROOT, "Breaker", "SHADERS")
BPR_REF = os.path.join(REFERENCE_DIR, "BPR", "SHADERS")
BPR_SPB_REF = os.path.join(BPR_REF, "ShaderProgramBuffer")
# `reference extract` output: exact DXBC, disassembly, decompiles, manifest.json. Generated, gitignored.
BPR_EXTRACTED = os.path.join(REFERENCE_DIR, "BPR", "Extracted")
RESOURCE_DB = os.path.join(REFERENCE_DIR, "ResourceDB.json")


def x360_ref(version="Breaker"):
    """Extracted X360 SHADERS bundle for one game version."""
    return os.path.join(X360_SHADERS_ROOT, version, "SHADERS")


# --- build outputs (paths unchanged from the PowerShell era, so existing
#     deploy configs and extracted-bundle scratch dirs keep working) ----------

OUTPUT_DIR = os.path.join(BUILD_DIR, "Output")
CACHE_DIR = os.path.join(BUILD_DIR, ".cache")
MANIFEST_DIR = os.path.join(BUILD_DIR, "manifest")
CONFIG_DIR = os.path.join(BUILD_DIR, "config")
TOOLS_CACHE_DIR = os.path.join(BUILD_DIR, "tools")

AUTOTEST_DIR = os.path.join(BUILD_DIR, "autotest")

# --- out-of-scope projects we only ever invoke, never own --------------------

NUSHADERS_CLI_DIR = os.path.join(TOOLS_DIR, "ShaderApp", "Source", "NuShaders.CLI")
NUSHADERS_CSPROJ = os.path.join(NUSHADERS_CLI_DIR, "NuShaders.CLI.csproj")
NUSHADERS_SLN = os.path.join(TOOLS_DIR, "ShaderApp", "Source", "NuShaders.slnx")
SSRHOOK_DIR = os.path.join(TOOLS_DIR, "Mod", "SSRHook")

# --- exit contract -----------------------------------------------------------
#   0 pass, 1 real failure, 2 environmental skip (tool or corpus missing).
# 2 is distinct so a missing XDK never reads as a broken shader.

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_SKIP = 2

IS_WINDOWS = os.name == "nt"


def hostname():
    return socket.gethostname()


def default_config_path():
    """Per-machine deploy config. Gitignored; Build/config/example.toml is the template."""
    return os.path.join(CONFIG_DIR, hostname() + ".toml")


def rel(path):
    """Repo-relative path for display. Falls back to the absolute path off-tree."""
    try:
        r = os.path.relpath(path, REPO_ROOT)
    except ValueError:  # different drive on Windows
        return path
    return path if r.startswith("..") else r.replace(os.sep, "/")
