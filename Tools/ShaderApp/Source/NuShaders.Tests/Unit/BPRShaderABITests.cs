using System.Buffers.Binary;
using NuShaders.Formats.BPR;
using NuShaders.Formats.DXBC;
using NuShaders.Tests.TestSupport;

namespace NuShaders.Tests.Unit;

public class BPRShaderABITests
{
    private static (byte[] Primary, byte[] Dxbc) StockPair(string id)
    {
        string dir = ReferencePaths.BPRShaderProgramBufferDir;
        byte[] primary = File.ReadAllBytes(Path.Combine(dir, $"{id}_primary.dat"));
        byte[] secondary = File.ReadAllBytes(Path.Combine(dir, $"{id}_secondary.dat"));
        return (primary, secondary[..(int)BinaryPrimitives.ReadUInt32LittleEndian(primary.AsSpan(0x14))]);
    }

    private static string[] StockIds() =>
        Directory.GetFiles(ReferencePaths.BPRShaderProgramBufferDir, "*_primary.dat")
            .Select(f => Path.GetFileName(f)[..8]).ToArray();

    private static bool HaveCorpus => ReferencePaths.Available && Directory.Exists(ReferencePaths.BPRShaderProgramBufferDir);

    // The fixture-backed answer to "what does a BPR primary encode": every shipped primary describes its own
    // DXBC under exactly the rules CheckPrimary enforces.
    [Fact]
    public void Every_stock_primary_describes_its_own_dxbc()
    {
        if (!HaveCorpus) return;
        var failures = new List<string>();
        foreach (var id in StockIds())
        {
            var (primary, dxbc) = StockPair(id);
            foreach (var diff in BPRShaderABI.CheckPrimary(primary, dxbc).Take(3))
                failures.Add($"{id}: {diff}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures.Take(30)));
    }

    // Fresh generation from reflection alone reproduces every shipped primary. Masked, because nothing in the
    // DXBC predicts them: the two runtime pointers the engine writes at load; the upper bytes of bindingCount
    // (stray bits on every VS and some PS); and the gap, the engine's $Globals copy, where 76 shipped primaries
    // carry leftover memory from Criterion's tool (fragments of d:\ge_b5dev\Shaders\*.fxh) instead of zeros.
    [Fact]
    public void Generated_primary_matches_every_stock_primary()
    {
        if (!HaveCorpus) return;
        var failures = new List<string>();
        foreach (var id in StockIds())
        {
            var (primary, dxbc) = StockPair(id);
            byte[] generated = BPRShaderProgramBuffer.FromDXBC(dxbc).ToBytes();
            int descOff = BPRShaderProgramBuffer.DescriptorOffset(primary[0x1C]);
            int gap = BPRShaderProgramBuffer.ReadPrimary(primary).Gap.Length;
            (int, int)[] masks =
            [
                (BPRShaderProgramBuffer.HeaderRuntimePtrOffset, 4),
                (0x1D, 3),
                (descOff + BPRShaderProgramBuffer.DescriptorRuntimePtrOffset, 4),
                (descOff + BPRShaderProgramBuffer.DescriptorSize, gap),
            ];
            var want = ByteDiff.WithRangesZeroed(primary, masks);
            var got = ByteDiff.WithRangesZeroed(generated, masks);
            if (!want.AsSpan().SequenceEqual(got))
                failures.Add($"{id}: {ByteDiff.Describe(want, got)}");
        }
        Assert.True(failures.Count == 0, $"{failures.Count} differ:\n" + string.Join("\n", failures.Take(20)));
    }

    [Fact]
    public void Every_stock_dxbc_matches_its_own_interface()
    {
        if (!HaveCorpus) return;
        foreach (var id in StockIds())
        {
            var (_, dxbc) = StockPair(id);
            Assert.Empty(BPRShaderABI.CompareInterface(dxbc, dxbc));
        }
    }

    // Specular_1Bit_Doublesided Default PS against Specular_Greyscale_Singlesided Default PS: same stage, different
    // material constants and samplers. Both checks must refuse to call them compatible.
    [Fact]
    public void A_different_shader_is_rejected_by_both_checks()
    {
        if (!HaveCorpus || !File.Exists(Path.Combine(ReferencePaths.BPRShaderProgramBufferDir, "A3A50BAB_primary.dat"))) return;
        var (specPrimary, specDxbc) = StockPair("A3A50BAB");
        var (_, greyDxbc) = StockPair("00433B5E");

        var iface = BPRShaderABI.CompareInterface(greyDxbc, specDxbc);
        Assert.Contains(iface, d => d.StartsWith("cbuffer $Globals: 784 bytes (reference 800 bytes)"));
        Assert.Contains(iface, d => d.StartsWith("input SV_ISFRONTFACE0: missing"));

        var meta = BPRShaderABI.CheckPrimary(specPrimary, greyDxbc);
        Assert.NotEmpty(meta);
    }

    // Specular_1Bit's PS reads sampleCoverage and SV_IsFrontFace; the greyscale PS it would replace reads neither.
    // A generated primary can describe new offsets, but not make the engine supply data it never supplied.
    [Fact]
    public void Reading_data_the_shipped_shader_never_read_breaks_the_contract()
    {
        if (!HaveCorpus || !File.Exists(Path.Combine(ReferencePaths.BPRShaderProgramBufferDir, "A3A50BAB_primary.dat"))) return;
        var (_, specDxbc) = StockPair("A3A50BAB");
        var (_, greyDxbc) = StockPair("00433B5E");

        var broken = BPRShaderABI.ContractViolations(specDxbc, greyDxbc);
        Assert.Contains(broken, d => d.StartsWith("variable sampleCoverage: read here but never by the shipped shader"));
        Assert.Contains(broken, d => d.StartsWith("input SV_ISFRONTFACE0"));
        Assert.DoesNotContain(broken, d => d.Contains("materialDiffuse")); // moved offset only: not a violation
    }

    [Fact]
    public void Every_stock_dxbc_keeps_its_own_contract()
    {
        if (!HaveCorpus) return;
        foreach (var id in StockIds())
        {
            var (_, dxbc) = StockPair(id);
            Assert.Empty(BPRShaderABI.ContractViolations(dxbc, dxbc));
        }
    }

    [Fact]
    public void A_vertex_shader_is_rejected_against_a_pixel_primary()
    {
        if (!HaveCorpus || !File.Exists(Path.Combine(ReferencePaths.BPRShaderProgramBufferDir, "2EC61041_primary.dat"))) return;
        var (psPrimary, psDxbc) = StockPair("A3A50BAB");
        var (_, vsDxbc) = StockPair("2EC61041");
        Assert.Contains(BPRShaderABI.CheckPrimary(psPrimary, vsDxbc), d => d.StartsWith("m_type"));
        Assert.Contains(BPRShaderABI.CompareInterface(vsDxbc, psDxbc), d => d.StartsWith("profile"));
    }

    [Fact]
    public void Malformed_dxbc_is_rejected()
    {
        if (!HaveCorpus || !File.Exists(Path.Combine(ReferencePaths.BPRShaderProgramBufferDir, "A3A50BAB_primary.dat"))) return;
        var (_, dxbc) = StockPair("A3A50BAB");

        // Header claims more bytes than the buffer holds.
        Assert.Throws<InvalidDataException>(() => new DXBCContainer(dxbc.AsSpan(0, dxbc.Length - 1)));

        // First chunk offset pointed past the end.
        var bad = (byte[])dxbc.Clone();
        BinaryPrimitives.WriteUInt32LittleEndian(bad.AsSpan(0x20), (uint)dxbc.Length);
        Assert.Throws<InvalidDataException>(() => new DXBCContainer(bad));

        // Chunk count that overruns the header.
        bad = (byte[])dxbc.Clone();
        BinaryPrimitives.WriteUInt32LittleEndian(bad.AsSpan(0x1C), 0x40000000);
        Assert.Throws<InvalidDataException>(() => new DXBCContainer(bad));
    }
}
