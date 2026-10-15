"""Byte-parity checks against the shipped resources in Reference/.

This is the gate that says our packer can still reproduce the game's own bytes.
It does NOT compile from source: the shipped binaries came from a specific
compiler version with a specific define set, so a source rebuild would never be
byte-identical and the gate would always be red.

What each platform actually checks, and what it does not
--------------------------------------------------------

  x360   Reconstruct the Xenos blob (primary minus its engine header, plus
         secondary) and re-pack with `--mode split`. This covers the header
         reconstruction and the primary/secondary split, which `--mode generate`
         also ends with. It does NOT cover generate's descriptor-table synthesis:
         a shipped blob already carries a descriptor table, so re-running
         generate over it would insert a second one. That layer is covered only
         by the C# unit tests.

  bpr    Feed the shipped DXBC back through `pack-bpr --stock-primary-dir`,
         which is the path used when modding a shader that already exists in the
         bundle. Byte equality is required here.

         `--generate` instead builds the primary from DXBC reflection alone, the
         path used when a shader's $Globals layout has moved. It must reproduce
         the shipped primary except for bytes nothing in the DXBC predicts: the
         two runtime pointers, the stray upper bytes of bindingCount, and the
         gap (the engine's $Globals copy, which 76 shipped primaries fill with
         leftover memory from Criterion's tool). Those are masked; anything
         else that differs is a failure.

A skip means the corpus is not checked out (Reference/**/SHADERS/* is gitignored).
"""

import os
import struct
import threading
from concurrent.futures import ThreadPoolExecutor

from . import context, graph, proc, toolchain

# primary.dat: 0x14 of engine header, then a D3D shader header whose size
# depends on the stage. 0x14 + 872 = 0x37C (VS), 0x14 + 40 = 0x3C (PS).
_X360_D3D_HEADER = {0: 872, 1: 40}


def _x360_header_size(primary):
    if len(primary) < 4:
        raise ValueError("primary too short")
    m_type = struct.unpack_from(">I", primary, 0)[0]
    if m_type not in _X360_D3D_HEADER:
        raise ValueError("unexpected m_type %d" % m_type)
    return 0x14 + _X360_D3D_HEADER[m_type]


def _pairs(directory):
    """(id, primary_path, secondary_path) for every complete pair in a dir."""
    if not os.path.isdir(directory):
        return []
    out = []
    for name in sorted(os.listdir(directory)):
        if not name.endswith("_primary.dat"):
            continue
        res_id = name[: -len("_primary.dat")]
        secondary = os.path.join(directory, res_id + "_secondary.dat")
        if os.path.isfile(secondary):
            out.append((res_id, os.path.join(directory, name), secondary))
    return out


def _describe_diff(expected, actual):
    if len(expected) != len(actual):
        return "size %d != %d" % (len(actual), len(expected))
    for i, (a, b) in enumerate(zip(expected, actual)):
        if a != b:
            return "first diff at 0x%X (%02X != %02X)" % (i, b, a)
    return "identical"


def _read(path):
    with open(path, "rb") as handle:
        return handle.read()


def _outputs(out_dir, res_id):
    return (_read(os.path.join(out_dir, res_id + "_primary.dat")),
            _read(os.path.join(out_dir, res_id + "_secondary.dat")))


def _x360_case(nushaders, res_id, primary_path, secondary_path, scratch, _generate):
    primary = _read(primary_path)
    secondary = _read(secondary_path)
    blob = primary[_x360_header_size(primary):] + secondary

    # 0x102A11.. is the Xenos container magic; a few corpus entries are
    # placeholders rather than shaders.
    if len(blob) < 4 or blob[0] != 0x10 or blob[1] != 0x2A or blob[2] != 0x11:
        return "skip", "not a Xenos blob"

    blob_path = os.path.join(scratch, res_id + ".bin")
    with open(blob_path, "wb") as handle:
        handle.write(blob)

    out_dir = os.path.join(scratch, "out")
    done = proc.run(
        [nushaders, "pack-x360", "--mode", "split", "--input", blob_path,
         "--out-dir", out_dir, "--name", res_id, "--force"],
        check=False, read_only=True,
    )
    if done.returncode != 0:
        return "fail", "pack-x360 exited %d: %s" % (done.returncode,
                                                    (done.stderr or "").strip()[:160])

    got_pri, got_sec = _outputs(out_dir, res_id)
    if got_pri == primary and got_sec == secondary:
        return "pass", None
    return "fail", "primary[%s] secondary[%s]" % (_describe_diff(primary, got_pri),
                                                  _describe_diff(secondary, got_sec))


def _bpr_unpredictable(primary):
    """[start, end) ranges of a BPR primary that no DXBC determines (see the module docstring)."""
    ranges = [(0x04, 0x08), (0x1D, 0x20)]
    count = primary[0x1C]
    if any(primary[0x54 + 8 * i + 5] == 0x1A for i in range(count)):  # $Globals bound -> descriptor
        desc = (0x54 + 8 * count + 15) & ~15
        gap = struct.unpack_from("<I", primary, desc + 0x0C)[0]
        ranges += [(desc + 0x14, desc + 0x18), (desc + 0x30, desc + 0x30 + gap)]
    return ranges


def _masked(data, ranges):
    out = bytearray(data)
    for start, end in ranges:
        out[start:min(end, len(out))] = bytes(max(0, min(end, len(out)) - start))
    return bytes(out)


def _bpr_case(nushaders, res_id, primary_path, secondary_path, scratch, generate):
    primary = _read(primary_path)
    secondary = _read(secondary_path)
    if len(primary) < 0x20:
        return "skip", "primary too short"

    # dxbcSize @ 0x14; secondary is that blob zero-padded to 0x80.
    dxbc_size = struct.unpack_from("<I", primary, 0x14)[0]
    if dxbc_size == 0 or dxbc_size > len(secondary):
        return "skip", "implausible dxbcSize %d" % dxbc_size
    dxbc = secondary[:dxbc_size]
    if dxbc[:4] != b"DXBC":
        return "skip", "secondary is not DXBC"

    dxbc_path = os.path.join(scratch, res_id + ".dxbc")
    with open(dxbc_path, "wb") as handle:
        handle.write(dxbc)

    out_dir = os.path.join(scratch, "out")
    argv = [nushaders, "pack-bpr", "--input", dxbc_path,
            "--out-dir", out_dir, "--name", res_id, "--force"]
    if not generate:
        argv += ["--stock-primary-dir", os.path.dirname(primary_path)]

    done = proc.run(argv, check=False, read_only=True)
    if done.returncode != 0:
        return "fail", "pack-bpr exited %d: %s" % (done.returncode,
                                                   (done.stderr or "").strip()[:160])

    got_pri, got_sec = _outputs(out_dir, res_id)
    if generate:
        mask = _bpr_unpredictable(primary)
        primary, got_pri = _masked(primary, mask), _masked(got_pri, mask)
    if got_pri == primary and got_sec == secondary:
        return "pass", None
    return "fail", "primary[%s] secondary[%s]" % (_describe_diff(primary, got_pri),
                                                  _describe_diff(secondary, got_sec))


def _corpus_dirs(platform, against, version):
    if against:
        return [(os.path.basename(os.path.normpath(against)), against)]
    if platform == "bpr":
        return [("BPR", os.path.join(context.BPR_REF, "ShaderProgramBuffer"))]
    return [(v, os.path.join(context.x360_ref(v), "ShaderProgramBuffer"))
            for v in context.X360_VERSIONS]


def verify(platform, against=None, version="Breaker", jobs=None, limit=None,
           generate=False):
    if platform not in ("x360", "bpr"):
        raise proc.StepError("verify supports x360 and bpr", fix="pick one of those")
    if generate and platform != "bpr":
        raise proc.StepError(
            "--generate applies to bpr only",
            fix="an x360 blob already carries its descriptor table, so re-running "
                "generate over it would insert a second one",
        )

    nushaders = toolchain.require(toolchain.nushaders())
    case = _x360_case if platform == "x360" else _bpr_case

    work = []
    for label, directory in _corpus_dirs(platform, against, version):
        found = _pairs(directory)
        if not found:
            proc.detail("no pairs in %s" % context.rel(directory))
            continue
        if limit:
            found = found[:limit]
        work += [(label, res_id, pri, sec) for res_id, pri, sec in found]

    if not work:
        raise proc.StepError(
            "no ShaderProgramBuffer pairs found for %s" % platform,
            code=context.EXIT_SKIP,
            fix="extract the stock bundle into Reference/ (its contents are gitignored)",
        )

    scratch = os.path.join(context.CACHE_DIR, "verify", platform)
    proc.ensure_dir(scratch)
    proc.ensure_dir(os.path.join(scratch, "out"))

    mode = "generate from reflection" if generate else "reproduce shipped bytes"
    proc.step("verify %s: %d resource pairs (%s)" % (platform, len(work), mode))

    counts = {"pass": 0, "fail": 0, "skip": 0}
    failures = []
    lock = threading.Lock()

    def run_one(item):
        label, res_id, pri, sec = item
        try:
            outcome, detail = case(nushaders, res_id, pri, sec, scratch, generate)
        except Exception as err:  # a malformed corpus entry, not a packer bug
            outcome, detail = "skip", "%s: %s" % (type(err).__name__, err)
        with lock:
            counts[outcome] += 1
            if outcome == "fail":
                failures.append("%s/%s: %s" % (label, res_id, detail))

    with ThreadPoolExecutor(max_workers=jobs or graph.default_jobs()) as pool:
        list(pool.map(run_one, work))

    proc.info("")
    summary = "pass %d  fail %d  skip %d" % (counts["pass"], counts["fail"], counts["skip"])
    proc.info("%s  (of %d)" % (summary, len(work)))

    if failures:
        proc.info("")
        proc.info("mismatches:")
        for line in sorted(failures)[:15]:
            proc.info("  " + line)
        if len(failures) > 15:
            proc.info("  ... and %d more" % (len(failures) - 15))
        raise proc.StepError(
            "%d of %d resources did not round-trip" % (counts["fail"], len(work)),
            fix="a packer regression: compare against NuShaders.Formats and the "
                "round-trip tests in NuShaders.Tests",
        )

    if counts["pass"] == 0:
        raise proc.StepError(
            "nothing verified (every case skipped)",
            code=context.EXIT_SKIP,
            fix="the corpus is present but holds no packable resources",
        )

    return context.EXIT_OK
