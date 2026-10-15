using NuShaders.Formats.DXBC;
using NuShaders.Formats.IO;

namespace NuShaders.Formats.BPR;

/// <summary>
/// Compatibility checks between a rebuilt BPR shader, the shipped one it replaces, and a primary. Each returns one
/// human-readable line per difference; an empty list means compatible.
///
/// <see cref="CompareInterface"/> — compiled interface: does the rebuilt DXBC expose exactly what the shipped one
/// did (profile, stage I/O, resource slots, $Globals layout)? Only then may the stock primary be reused.
///
/// <see cref="ContractViolations"/> — the subset generation cannot fix. Moved $Globals offsets are not on it (a
/// generated primary carries the new offsets); a changed slot, changed stage I/O, or a variable the shipped shader
/// never read is, because nothing proves the engine supplies it.
///
/// <see cref="CheckPrimary"/> — engine metadata: does a primary describe a DXBC, in the encoding the engine reads?
/// The rules below are the ones every one of the 242 shipped pairs satisfies (BPRShaderABITests), not the prose
/// notes: the var table lists only USED variables keyed by RDEF declaration index, and the "gap" after the
/// descriptor is the engine's CPU copy of $Globals, so its length is the cbuffer size, not a fixed 0x320.
/// </summary>
public static class BPRShaderABI
{
    public static List<string> CompareInterface(ReadOnlySpan<byte> rebuilt, ReadOnlySpan<byte> reference)
    {
        var got = RdefReflection.Instance.Reflect(rebuilt);
        var want = RdefReflection.Instance.Reflect(reference);
        var diffs = new List<string>();

        if (got.Profile != want.Profile) diffs.Add($"profile {got.Profile} (reference {want.Profile})");
        CompareKeyed("input", got.Inputs, want.Inputs, SignatureKey, DescribeSignature, diffs);
        CompareKeyed("output", got.Outputs, want.Outputs, SignatureKey, DescribeSignature, diffs);
        CompareKeyed("binding", got.Bindings, want.Bindings, b => $"{b.Kind} {EngineName(b.Name)}", DescribeBinding, diffs);
        CompareKeyed("cbuffer", got.Cbuffers, want.Cbuffers, c => EngineName(c.Name), c => $"{c.SizeBytes} bytes", diffs);
        foreach (var cb in want.Cbuffers)
        {
            var mine = got.Cbuffers.FirstOrDefault(c => EngineName(c.Name) == EngineName(cb.Name));
            if (mine is not null)
                CompareKeyed($"{EngineName(cb.Name)}.", mine.Variables, cb.Variables, v => v.Name, DescribeVariable, diffs);
        }
        return diffs;
    }

    public static List<string> ContractViolations(ReadOnlySpan<byte> rebuilt, ReadOnlySpan<byte> reference)
    {
        var got = RdefReflection.Instance.Reflect(rebuilt);
        var want = RdefReflection.Instance.Reflect(reference);
        var diffs = new List<string>();

        if (got.Profile != want.Profile) diffs.Add($"profile {got.Profile} (shipped {want.Profile})");
        CompareKeyed("input", got.Inputs, want.Inputs, SignatureKey, DescribeSignature, diffs);
        CompareKeyed("output", got.Outputs, want.Outputs, SignatureKey, DescribeSignature, diffs);

        // Dropping a binding is fine; adding one or moving one is not.
        var shippedBindings = want.Bindings.ToDictionary(b => $"{b.Kind} {EngineName(b.Name)}");
        foreach (var b in got.Bindings)
        {
            string key = $"{b.Kind} {EngineName(b.Name)}";
            if (!shippedBindings.TryGetValue(key, out var r))
                diffs.Add($"binding {key}: {DescribeBinding(b)}, which the shipped shader never bound");
            else if (DescribeBinding(r) != DescribeBinding(b))
                diffs.Add($"binding {key}: {DescribeBinding(b)} (shipped {DescribeBinding(r)})");
        }

        // Reading fewer variables is fine; reading one the shipped shader never read is new engine-fed data.
        var shippedUsed = want.Cbuffers.SelectMany(c => c.Variables).Where(v => v.IsUsed).ToDictionary(v => v.Name);
        foreach (var v in got.Cbuffers.SelectMany(c => c.Variables).Where(v => v.IsUsed))
        {
            if (!shippedUsed.TryGetValue(v.Name, out var r))
                diffs.Add($"variable {v.Name}: read here but never by the shipped shader; nothing proves the engine supplies it");
            else if (Shape(v) != Shape(r))
                diffs.Add($"variable {v.Name}: {Shape(v)} (shipped {Shape(r)})");
        }
        return diffs;
    }

    public static List<string> CheckPrimary(ReadOnlySpan<byte> primaryBytes, ReadOnlySpan<byte> dxbc)
    {
        var diffs = new List<string>();
        var refl = RdefReflection.Instance.Reflect(dxbc);
        var p = BPRShaderProgramBuffer.ReadPrimary(primaryBytes);
        byte[] pb = primaryBytes.ToArray();
        string Name(uint off) => off < pb.Length ? new SpanReader(pb).CString((int)off) : $"<name offset 0x{off:X} out of range>";

        // ---- header
        uint stage = refl.Kind switch { ShaderKind.Vertex => 0u, ShaderKind.Pixel => 1u, _ => uint.MaxValue };
        if (stage == uint.MaxValue) diffs.Add($"stage {refl.Kind} has no known BPR m_type");
        else if (p.MType != stage) diffs.Add($"m_type {p.MType}, shader is {refl.Kind} ({stage})");
        uint total = new SpanReader(dxbc).U32LE(0x18);
        if (p.DXBCSize != total) diffs.Add($"dxbcSize {p.DXBCSize}, DXBC is {total} bytes");
        if (p.Reserved08 != 0 || p.Reserved10 != 0) diffs.Add($"header words 0x08/0x10 are {p.Reserved08}/{p.Reserved10}, expected 0/0");
        uint hasGlobals = refl.Cbuffers.Count > 0 ? 1u : 0u;
        if (p.Version0C != hasGlobals) diffs.Add($"header word 0x0C is {p.Version0C}, expected {hasGlobals} (1 iff $Globals is bound)");

        // ---- binding table + sampler map
        var expected = BPRShaderProgramBuffer.BindingTableFor(refl, out var unsupported);
        foreach (var b in unsupported) diffs.Add($"binding {b.Name}: D3D input type {b.D3DInputType} has no known BPR encoding");
        var actual = new List<(string Name, int Reg, byte Type)>();
        for (int i = 0; i < p.BindingCount; i++)
        {
            int e = BPRShaderProgramBuffer.BindingTableOffset + i * 8;
            uint packed = U32(pb, e + 4);
            if (packed >> 16 != 1) diffs.Add($"binding {i}: flags 0x{packed >> 16:X}, expected 1");
            actual.Add((Name(U32(pb, e)), (int)(packed & 0xFF), (byte)(packed >> 8)));
        }
        CompareLists("binding", actual, expected, b => $"{b.Name} reg {b.Reg} type 0x{b.Type:X2}", diffs);

        foreach (var b in expected.Where(b => b.Type == 0x0A && b.Reg is < 0 or > 15))
            diffs.Add($"sampler {b.Name} at s{b.Reg}: only s0..s15 are representable");
        foreach (var b in expected.Where(b => b.Type == 0x1A && b.Reg != 0))
            diffs.Add($"cbuffer {b.Name} at b{b.Reg}: only $Globals at b0 is proven");
        byte[] mask = BPRShaderProgramBuffer.BitmaskFor(expected);
        if (!p.Bitmask.AsSpan().SequenceEqual(mask))
            diffs.Add($"bitmask {Convert.ToHexString(p.Bitmask)}, expected {Convert.ToHexString(mask)}");

        // ---- descriptor, gap, var table (present only when a cbuffer is bound)
        int strBase = BPRShaderProgramBuffer.BindingTableOffset + p.BindingCount * 8;
        if (!p.HasDescriptor)
        {
            if (refl.Cbuffers.Count != 0) diffs.Add("primary has no descriptor but the shader binds a cbuffer");
            CheckStrings(pb, strBase, p.StringTableSize, expected.Select(b => b.Name), diffs);
            return diffs;
        }
        if (refl.Cbuffers.Count != 1)
        {
            diffs.Add($"{refl.Cbuffers.Count} cbuffers: a single $Globals is the only layout the stock corpus proves");
            return diffs;
        }
        var cb = refl.Cbuffers[0];
        uint[] words = Enumerable.Range(0, 12).Select(i => U32(p.Descriptor, i * 4)).ToArray();
        int descEnd = BPRShaderProgramBuffer.DescriptorOffset(p.BindingCount) + BPRShaderProgramBuffer.DescriptorSize;
        // word 5 is the engine's runtime pointer; every other word is pinned by the corpus.
        uint[] want = [2, 4, 0, (uint)cb.SizeBytes, 1, words[5],
                       (uint)(descEnd + BPRShaderProgramBuffer.BindingTableOffset + p.BindingCount * 8), 0,
                       words[8], (uint)cb.Variables.Count(v => v.IsUsed), 1, (uint)(descEnd + cb.SizeBytes)];
        for (int i = 0; i < 12; i++)
            if (words[i] != want[i]) diffs.Add($"descriptor word {i}: {words[i]}, expected {want[i]}");
        if (Name(words[8]) != "$Globals") diffs.Add($"descriptor names cbuffer '{Name(words[8])}', expected $Globals");

        foreach (var v in cb.Variables.Where(v => v.IsUsed && v.VariableType != CbufferVariable.FloatType))
            diffs.Add($"variable {v.Name}: RDEF type {v.VariableType} — every stock variable is float (type 3); other types are unproven");
        var expectedVars = cb.Variables.Where(v => v.IsUsed)
            .Select(v => (v.Name, v.ByteOffset, v.SizeBytes, Packed: v.DeclarationIndex | 0x03 << 8 | v.PackedRows << 16 | v.Columns << 24))
            .ToList();
        var actualVars = Enumerable.Range(0, p.VarTable.Length / 16)
            .Select(i => (Name: Name(U32(p.VarTable, i * 16)), (int)U32(p.VarTable, i * 16 + 4), (int)U32(p.VarTable, i * 16 + 8),
                          Packed: (int)U32(p.VarTable, i * 16 + 12)))
            .ToList();
        CompareLists("variable", actualVars, expectedVars,
            v => $"{v.Item1} offset {v.Item2} size {v.Item3} idx {v.Packed & 0xFF} rows {(v.Packed >> 16) & 0xFF} cols {v.Packed >> 24}", diffs);

        strBase = (int)words[11] + p.VarTable.Length;
        CheckStrings(pb, strBase, p.StringTableSize,
            expected.Select(b => b.Name).Append("$Globals").Concat(expectedVars.Select(v => v.Name)), diffs);
        return diffs;
    }

    // Names are NUL-terminated and deduped in first-use order; stringTableSize counts them exactly and the
    // primary is zero-padded to 16 after them.
    private static void CheckStrings(byte[] pb, int strBase, uint size, IEnumerable<string> names, List<string> diffs)
    {
        int expectSize = names.Distinct(StringComparer.Ordinal).Sum(n => n.Length + 1);
        if (size != expectSize) diffs.Add($"stringTableSize {size}, names need {expectSize}");
        long end = strBase + (long)size;
        if (pb.Length != Alignment.Align((int)Math.Min(end, int.MaxValue), 16))
            diffs.Add($"primary is {pb.Length} bytes, expected align16(0x{strBase:X} + {size})");
        else if (pb.AsSpan((int)end).ContainsAnyExcept((byte)0))
            diffs.Add("non-zero bytes after the string table");
    }

    // ---------------------------------------------------------------- helpers

    private static uint U32(byte[] b, int offset) => new SpanReader(b).U32LE(offset);

    // fxc names the default cbuffer "$Globals"; our source declares it as _Globals (Platform.fxh). Same thing to the engine.
    private static string EngineName(string name) => name == "_Globals" ? "$Globals" : name;

    // D3D matches semantics case-insensitively (SV_Position == SV_POSITION).
    private static string SignatureKey(SignatureElement e) => $"{e.SemanticName.ToUpperInvariant()}{e.SemanticIndex}";

    // The read/write mask is left out on purpose: reading fewer components of an input does not change linkage.
    private static string DescribeSignature(SignatureElement e) =>
        $"v{e.Register}.{Mask(e.Mask)} sysvalue {e.SystemValue} component {e.ComponentType}";

    private static string Mask(byte m) => new(new[] { 'x', 'y', 'z', 'w' }.Where((_, i) => (m & (1 << i)) != 0).ToArray());

    private static string DescribeBinding(ResourceBinding b)
    {
        string prefix = b.Kind switch { ResourceKind.Sampler => "s", ResourceKind.Texture => "t", ResourceKind.CBuffer => "b", _ => "?" };
        string dim = b.Kind == ResourceKind.Texture ? $" dimension {b.Dimension}" : "";
        string count = b.BindCount == 1 ? "" : $" x{b.BindCount}";
        return $"{prefix}{b.Register}{dim}{count}";
    }

    private static string Shape(CbufferVariable v) =>
        $"class {v.VariableClass} type {v.VariableType} {v.Rows}x{v.Columns}" + (v.ElementCount > 0 ? $"[{v.ElementCount}]" : "");

    private static string DescribeVariable(CbufferVariable v) =>
        $"offset {v.ByteOffset} size {v.SizeBytes} class {v.VariableClass} type {v.VariableType} {v.Rows}x{v.Columns}" +
        (v.ElementCount > 0 ? $"[{v.ElementCount}]" : "") + (v.IsUsed ? "" : " (unused)");

    private static void CompareKeyed<T>(string what, IEnumerable<T> got, IEnumerable<T> want,
        Func<T, string> key, Func<T, string> describe, List<string> diffs)
    {
        var g = got.ToDictionary(key);
        var w = want.ToDictionary(key);
        string sep = what.EndsWith('.') ? "" : " ";
        foreach (var (k, wv) in w.OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            if (!g.TryGetValue(k, out var gv)) diffs.Add($"{what}{sep}{k}: missing (reference {describe(wv)})");
            else if (describe(gv) != describe(wv)) diffs.Add($"{what}{sep}{k}: {describe(gv)} (reference {describe(wv)})");
        }
        foreach (var (k, gv) in g.OrderBy(x => x.Key, StringComparer.Ordinal))
            if (!w.ContainsKey(k)) diffs.Add($"{what}{sep}{k}: {describe(gv)}, not in reference");
    }

    // Order matters in the primary's tables, so these compare position by position.
    private static void CompareLists<T>(string what, List<T> actual, List<T> expected, Func<T, string> describe, List<string> diffs)
    {
        for (int i = 0; i < Math.Max(actual.Count, expected.Count); i++)
        {
            string a = i < actual.Count ? describe(actual[i]) : "(none)";
            string e = i < expected.Count ? describe(expected[i]) : "(none)";
            if (a != e) diffs.Add($"{what} {i}: primary has {a}, shader needs {e}");
        }
    }
}
