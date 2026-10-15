"""External tool discovery. Every resolver returns a path or a Missing — never raises.

Ports Resolve-XDK.ps1 / Resolve-PC-FXC.ps1 / Resolve-YAP.ps1 / Resolve-NuShaders.ps1,
preserving their lookup orders but moving the machine-specific fallbacks last and
making every one env-overridable.

The Missing sentinel is falsy, so callers write `if not fxc:` and decide for
themselves whether a miss is fatal *for the verb the user actually asked for*.
That is what lets `doctor` report per-role instead of dying on the first gap, and
what lets `build bpr` succeed on a machine with no Xbox 360 XDK installed.
"""

import os
import re
import shutil

from . import context, proc

# Resolvers are pure lookups over a filesystem that does not change mid-run, and
# the PC fxc search in particular walks the whole Windows Kits tree. Cache them.
_cache = {}


class Missing(object):
    """A tool that could not be found. Falsy, and carries its own fix line."""

    def __init__(self, what, fix):
        self.what = what
        self.fix = fix

    def __bool__(self):
        return False

    def __str__(self):
        return "<missing: %s>" % self.what


def require(tool, what=None):
    """Turn a Missing into a StepError with exit code 2 (environmental skip)."""
    if not tool:
        raise proc.StepError(
            "%s not found" % (what or tool.what),
            code=context.EXIT_SKIP,
            fix=tool.fix,
        )
    return tool


def _cached(name, fn):
    if name not in _cache:
        _cache[name] = fn()
    return _cache[name]


def _first_existing(paths):
    for p in paths:
        if p and os.path.isfile(p):
            return os.path.abspath(p)
    return None


# --- Xbox 360 XDK 6534: fxc.exe (Xenos SM3) + xsd.exe (constant disassembly) --


# XDK 6534 is preferred over a generic public Xbox 360 SDK on purpose: the
# Breaker build we pack against was compiled with 6534's fxc, and a different
# Xenos compiler version produces different microcode for the same source. A
# public-SDK fallback still builds, but stops being byte-comparable against the
# reference corpus — so doctor reports which one it picked.
_XDK_6534_HINTS = (
    r"C:\Program Files (x86)\XDK6534\bin\win32",
    r"C:\XDK6534\bin\win32",
    r"C:\Users\JeBobs\User Programs\XDK6534\bin\win32",
)
_XDK_GENERIC = r"C:\Program Files (x86)\Microsoft Xbox 360 SDK\bin\win32"


def _xdk_bin():
    """Returns (dir, is_6534) or (None, False)."""
    preferred = []
    if os.environ.get("XDK6534_BIN"):
        preferred.append(os.environ["XDK6534_BIN"])
    preferred += list(_XDK_6534_HINTS)

    for d in preferred:
        if d and os.path.isfile(os.path.join(d, "fxc.exe")):
            return os.path.abspath(d), True

    fallbacks = []
    if os.environ.get("XEDK"):
        fallbacks.append(os.path.join(os.environ["XEDK"], "bin", "win32"))
    fallbacks.append(_XDK_GENERIC)
    for d in fallbacks:
        if d and os.path.isfile(os.path.join(d, "fxc.exe")):
            return os.path.abspath(d), False

    return None, False


def xdk_is_6534():
    """False when we fell back to a non-6534 SDK — doctor and verify surface this."""
    return _xdk_bin()[1]


_XDK_FIX = "set XDK6534_BIN to the folder containing fxc.exe and xsd.exe (XDK 6534 bin/win32)"


def xdk_fxc():
    def find():
        d, _is6534 = _xdk_bin()
        if d:
            return os.path.join(d, "fxc.exe")
        return Missing("Xbox 360 XDK fxc.exe", _XDK_FIX)

    return _cached("xdk_fxc", find)


def xdk_xsd():
    def find():
        d, _is6534 = _xdk_bin()
        p = os.path.join(d, "xsd.exe") if d else None
        if p and os.path.isfile(p):
            return p
        return Missing("Xbox 360 XDK xsd.exe", _XDK_FIX)

    return _cached("xdk_xsd", find)


# --- Windows SDK fxc.exe (DX9 fx_2_0 for PC-TUB, SM5 for BPR) ---------------

_VER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$")


def pc_fxc():
    def find():
        override = os.environ.get("PC_FXC")
        if override and os.path.isfile(override):
            return os.path.abspath(override)

        # Windows 10/11 SDK layouts:
        #   ...\Windows Kits\10\bin\<version>\x64\fxc.exe   (newer)
        #   ...\Windows Kits\10\bin\x64\fxc.exe             (older)
        # Enumerate rather than recursing the whole tree — the PowerShell version
        # did a full -Recurse over Windows Kits on every single script run.
        found = []
        for root in (
            r"C:\Program Files (x86)\Windows Kits\10\bin",
            r"C:\Program Files\Windows Kits\10\bin",
        ):
            if not os.path.isdir(root):
                continue
            for arch in ("x64", "x86"):
                p = os.path.join(root, arch, "fxc.exe")
                if os.path.isfile(p):
                    found.append(((0, 0, 0, 0), arch, p))
            try:
                entries = os.listdir(root)
            except OSError:
                entries = []
            for name in entries:
                m = _VER_RE.match(name)
                if not m:
                    continue
                ver = tuple(int(g or 0) for g in m.groups())
                for arch in ("x64", "x86"):
                    p = os.path.join(root, name, arch, "fxc.exe")
                    if os.path.isfile(p):
                        found.append((ver, arch, p))

        if found:
            # Newest version wins; x64 beats x86 at the same version.
            found.sort(key=lambda t: (t[0], t[1] == "x64"), reverse=True)
            return found[0][2]

        on_path = shutil.which("fxc.exe") or shutil.which("fxc")
        if on_path:
            return on_path

        return Missing(
            "Windows SDK fxc.exe",
            "install the Windows 10/11 SDK, set PC_FXC to fxc.exe, or put it on PATH",
        )

    return _cached("pc_fxc", find)


# --- YAP (bundle extract/create) ---------------------------------------------

YAP_URL = "https://github.com/burninrubber0/YAP/releases/latest/download/YAP.7z"
_YAP_FIX = "put YAP on PATH, set YAP to YAP.exe, or run: nushaders.py tools fetch-yap"


def _find_cached_yap():
    root = os.path.join(context.TOOLS_CACHE_DIR, "yap")
    if not os.path.isdir(root):
        return None
    # The release extracts YAP.exe into a nested folder beside its Qt6 DLLs.
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.lower() == "yap.exe":
                return os.path.join(dirpath, f)
    return None


def yap():
    def find():
        on_path = shutil.which("yap")
        if on_path:
            return on_path
        override = os.environ.get("YAP")
        if override and os.path.isfile(override):
            return os.path.abspath(override)
        cached = _find_cached_yap()
        if cached:
            return cached
        return Missing("YAP.exe (bundle packer)", _YAP_FIX)

    return _cached("yap", find)


def fetch_yap():
    """Download + extract YAP into Build/tools/yap. Explicit, not a build side effect.

    The PowerShell resolver downloaded silently on first miss. Making it a verb
    keeps `build` from reaching out to the network without being asked.
    """
    import urllib.request

    target = os.path.join(context.TOOLS_CACHE_DIR, "yap")
    proc.ensure_dir(target)
    archive = os.path.join(target, "YAP.7z")

    proc.info("downloading %s" % YAP_URL)
    if not proc.DRY_RUN:
        urllib.request.urlretrieve(YAP_URL, archive)

    seven = _first_existing(
        [
            shutil.which("7z"),
            r"C:\Program Files\7-Zip\7z.exe",
            r"C:\Program Files (x86)\7-Zip\7z.exe",
        ]
    )
    if seven:
        proc.run([seven, "x", archive, "-o" + target, "-y"])
    elif shutil.which("tar"):
        # Windows' bundled bsdtar (libarchive) reads .7z; Expand-Archive does not.
        proc.run(["tar", "-xf", archive], cwd=target)
    else:
        raise proc.StepError(
            "downloaded YAP.7z but found no extractor",
            fix="install 7-Zip, or extract %s by hand" % context.rel(archive),
        )

    if not proc.DRY_RUN:
        try:
            os.remove(archive)
        except OSError:
            pass
    _cache.pop("yap", None)
    return yap()


# --- nushaders.exe (out of scope to build; we only resolve and invoke it) ----


def nushaders():
    def find():
        override = os.environ.get("NUSHADERS_EXE")
        if override and os.path.isfile(override):
            return os.path.abspath(override)
        found = _first_existing(
            os.path.join(context.NUSHADERS_CLI_DIR, *parts)
            for parts in (
                ("bin", "Release", "net10.0", "win-x64", "publish", "nushaders.exe"),
                ("bin", "Release", "net10.0", "nushaders.exe"),
                ("bin", "Debug", "net10.0", "nushaders.exe"),
            )
        )
        if found:
            return found
        return Missing(
            "nushaders.exe (NuShaders.CLI)",
            "run: nushaders.py tools build-cli   (or set NUSHADERS_EXE)",
        )

    return _cached("nushaders", find)


def forget_nushaders():
    """Drop the cached miss after `tools build-cli` produces the exe."""
    _cache.pop("nushaders", None)


# --- DXBC decompiler (optional, user-supplied) -------------------------------

_DECOMPILER_FIX = ('set NUSHADERS_DECOMPILER to the command that decompiles one DXBC file, with {in} and '
                   '{out} placeholders, e.g. "C:/tools/decompile.exe {in} {out}"')


def decompiler():
    """Returns the NUSHADERS_DECOMPILER command template, or Missing.

    There is no default and no guessed syntax on purpose: 3DMigoto's and other
    decompilers each take their own arguments, and wiring one up before its real
    invocation is confirmed would only produce plausible-looking failures.
    """
    template = os.environ.get("NUSHADERS_DECOMPILER", "").strip()
    return template or Missing("DXBC decompiler", _DECOMPILER_FIX)


# --- Xbox 360 devkit transfer ------------------------------------------------

_XEDK_FIX = "install the Xbox 360 XDK and set XEDK (the folder containing bin\\win32)"


def _xedk_tool(name):
    xedk = os.environ.get("XEDK")
    if xedk:
        p = os.path.join(xedk, "bin", "win32", name)
        if os.path.isfile(p):
            return p
    on_path = shutil.which(name)
    if on_path:
        return on_path
    return Missing(name, _XEDK_FIX)


def xbcp():
    return _cached("xbcp", lambda: _xedk_tool("xbcp.exe"))


def xbmkdir():
    return _cached("xbmkdir", lambda: _xedk_tool("xbmkdir.exe"))


def xbreboot():
    return _cached("xbreboot", lambda: _xedk_tool("xbreboot.exe"))


# --- host toolchains used only by the `tools` verb ---------------------------


def dotnet():
    def find():
        p = shutil.which("dotnet")
        return p or Missing("dotnet", "install the .NET 10 SDK (https://dot.net)")

    return _cached("dotnet", find)


def cmake():
    def find():
        p = shutil.which("cmake") or _first_existing(
            [r"C:\Program Files\CMake\bin\cmake.exe"]
        )
        return p or Missing("cmake", "install CMake and put it on PATH")

    return _cached("cmake", find)


def powershell():
    def find():
        p = shutil.which("pwsh") or shutil.which("powershell")
        return p or Missing(
            "powershell", "needed only by `config migrate` to read the legacy .psd1 files"
        )

    return _cached("powershell", find)


# --- doctor support ----------------------------------------------------------

# name -> (resolver, roles it belongs to)
REGISTRY = (
    ("xdk fxc", xdk_fxc, ("x360",)),
    ("xdk xsd", xdk_xsd, ("x360",)),
    ("pc fxc", pc_fxc, ("bpr", "pc")),
    ("nushaders.exe", nushaders, ("x360", "bpr")),
    ("YAP.exe", yap, ("deploy",)),
    ("xbcp", xbcp, ("deploy-x360",)),
    ("xbreboot", xbreboot, ("deploy-x360",)),
    ("dotnet", dotnet, ("tools",)),
    ("cmake", cmake, ("tools",)),
)

ROLES = ("x360", "bpr", "pc", "deploy", "deploy-x360", "tools")
