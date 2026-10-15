"""Content-hash build cache — what makes a rebuild cost nothing.

Keyed on everything that can change the output: the .fx bytes, every .fxh it
transitively includes, the defines, the compile target and entry point, the
compiler binary's own identity, the exact packer argv, and ACTION_VERSION.

Two rules, both learned the hard way in build systems that skipped them:

  Never trust the stamp alone. An entry is fresh only if the key matches AND
  every output it claims still exists. Otherwise deleting Build/Output by hand
  leaves a cache insisting everything is built.

  Hash the tool, not just the source. The Xenos and SM5 compilers produce
  different bytes across versions, so swapping XDK6534_BIN or a Windows SDK must
  invalidate everything — which mtime-on-source tracking would never notice.
"""

import hashlib
import json
import os

from . import context, proc

# Bump when the meaning of an action changes (new packer flags, different
# intermediate handling) so old entries cannot be mistaken for current ones.
ACTION_VERSION = 2  # 2: BPR reuse is verified, generated primaries follow the stock layout


def _file_digest(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(chunk)
            if not block:
                break
            h.update(block)
    return h.hexdigest()


_digest_cache = {}


def file_digest(path):
    """sha256 of a file, memoized on (path, mtime, size).

    An .fxh included by 55 shaders is hashed once, not 55 times.
    """
    try:
        stat = os.stat(path)
    except OSError:
        return "missing"
    key = (os.path.abspath(path), stat.st_mtime_ns, stat.st_size)
    if key not in _digest_cache:
        _digest_cache[key] = _file_digest(path)
    return _digest_cache[key]


def tool_signature(path):
    """Identify a compiler cheaply. Size+mtime, not a full hash of a 5 MB exe.

    A tool that changes without its size or mtime changing would fool this, but
    that does not happen with real SDK installs, and hashing every tool on every
    build costs more than it protects.
    """
    if not path or not os.path.isfile(path):
        return "missing"
    stat = os.stat(path)
    return "%s|%d|%d" % (os.path.abspath(path), stat.st_size, int(stat.st_mtime))


def compute_key(source, includes, defines, target, entry, tools, extra=()):
    """The cache key for one compile(+pack) chain."""
    h = hashlib.sha256()
    h.update(b"nubuild-v%d\n" % ACTION_VERSION)
    h.update(("source:" + file_digest(source) + "\n").encode())
    for path in sorted(includes):
        h.update(("inc:" + os.path.basename(path) + ":" + file_digest(path) + "\n").encode())
    h.update(("defines:" + ",".join(sorted(defines)) + "\n").encode())
    h.update(("target:%s entry:%s\n" % (target, entry)).encode())
    for name in sorted(tools):
        h.update(("tool:%s=%s\n" % (name, tool_signature(tools[name]))).encode())
    for item in extra:
        h.update(("extra:%s\n" % (item,)).encode())
    return h.hexdigest()


class Cache(object):
    """Per-platform cache, loaded once and written once at the end of a build."""

    def __init__(self, platform):
        self.platform = platform
        self.path = os.path.join(context.CACHE_DIR, platform + ".json")
        self.entries = {}
        self.dirty = False
        self._load()

    def _load(self):
        if not os.path.isfile(self.path):
            return
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            proc.detail("cache unreadable, starting fresh: %s" % context.rel(self.path))
            return
        if data.get("action_version") != ACTION_VERSION:
            proc.detail("cache is from action_version %s, discarding"
                        % data.get("action_version"))
            return
        self.entries = data.get("entries", {})

    def is_fresh(self, action_id, key):
        entry = self.entries.get(action_id)
        if not entry or entry.get("key") != key:
            return False
        for out in entry.get("outputs", []):
            if not os.path.exists(out):
                return False
        return True

    def record(self, action_id, key, outputs):
        self.entries[action_id] = {"key": key, "outputs": sorted(outputs)}
        self.dirty = True

    def forget(self, action_id):
        if self.entries.pop(action_id, None) is not None:
            self.dirty = True

    def outputs(self):
        """Every file this cache claims to have produced (for `clean`)."""
        seen = []
        for entry in self.entries.values():
            seen += entry.get("outputs", [])
        return sorted(set(seen))

    def save(self):
        if not self.dirty or proc.DRY_RUN:
            return
        proc.ensure_dir(os.path.dirname(self.path))
        tmp = self.path + ".partial"
        payload = {
            "action_version": ACTION_VERSION,
            "platform": self.platform,
            "entries": self.entries,
        }
        with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(payload, handle, indent=1, sort_keys=True)
        os.replace(tmp, self.path)  # atomic: a killed build cannot truncate it

    def clear(self):
        self.entries = {}
        self.dirty = True
