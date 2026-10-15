using System.Buffers.Binary;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using NuShaders.Formats.BPR;
using NuShaders.Formats.Bundle;
using NuShaders.Formats.DXBC;
using NuShaders.Formats.IO;

namespace NuShaders.CLI.Commands;

/// <summary>
/// extract-bpr: inventory and validate every ShaderProgramBuffer pair in an extracted BPR bundle, and report the
/// exact DXBC each one carries, as JSON on stdout. Read-only; nushaders.py `reference extract` writes the files.
///
/// The DXBC is secondary[0..dxbcSize). That length is cross-checked against the DXBC header and the 0x80-padded
/// secondary; a pair whose lengths disagree is reported, never trimmed into agreement.
/// </summary>
internal static class ExtractBPRCommand
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter() },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static int Run(ArgMap args)
    {
        string dir = args.Require("spb-dir");
        string xmlPath = args.Get("debug-xml") ?? Path.Combine(Path.GetDirectoryName(Path.GetFullPath(dir))!, ".debug.xml");
        var debug = DebugXML.TryReadFile(xmlPath);

        // Group the directory by id, so a lone half or a stray file is reported rather than skipped.
        var halves = new SortedDictionary<string, (string? Primary, string? Secondary)>(StringComparer.Ordinal);
        var records = new List<Record>();
        foreach (var path in Directory.GetFiles(dir))
        {
            string file = Path.GetFileName(path);
            bool isPrimary = file.EndsWith("_primary.dat", StringComparison.OrdinalIgnoreCase);
            bool isSecondary = file.EndsWith("_secondary.dat", StringComparison.OrdinalIgnoreCase);
            string id = isPrimary || isSecondary ? file[..file.LastIndexOf('_')].ToUpperInvariant() : "";
            if (id.Length != 8 || !uint.TryParse(id, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _))
            {
                records.Add(new Record(file) { Errors = [$"not a <ID>_primary.dat / <ID>_secondary.dat file"] });
                continue;
            }
            halves.TryGetValue(id, out var pair);
            halves[id] = isPrimary ? (path, pair.Secondary) : (pair.Primary, path);
        }

        foreach (var (id, (pri, sec)) in halves)
            records.Add(Inspect(id, pri, sec, debug));

        Console.Out.Write(JsonSerializer.Serialize(new
        {
            SpbDir = Path.GetFullPath(dir),
            DebugXml = debug is null ? null : Path.GetFullPath(xmlPath),
            Resources = records,
        }, Json));
        return 0;
    }

    private static Record Inspect(string id, string? priPath, string? secPath, DebugXML? debug)
    {
        uint idValue = uint.Parse(id, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        var rec = new Record(id);
        if (debug?.Resources.TryGetValue(idValue, out var res) == true)
        {
            rec.DebugName = res.Name;
            rec.DebugType = res.Type;
            // Bundle ids are CRC-32 of the lowercased name (true for all 337 BPR SHADERS entries).
            rec.NameMatchesId = BurnoutResourceName.ResourceIDFor(res.Name).Value == idValue;
        }

        if (priPath is null) rec.Errors.Add("missing primary half");
        if (secPath is null) rec.Errors.Add("missing secondary half");
        if (priPath is null || secPath is null) return rec;

        byte[] primary = File.ReadAllBytes(priPath);
        byte[] secondary = File.ReadAllBytes(secPath);
        rec.Primary = Describe(priPath, primary);
        rec.Secondary = Describe(secPath, secondary);

        if (primary.Length < BPRShaderProgramBuffer.BindingTableOffset)
        {
            rec.Errors.Add($"primary is {primary.Length} bytes, shorter than its 0x54-byte header");
            return rec;
        }
        rec.MType = BinaryPrimitives.ReadUInt32LittleEndian(primary.AsSpan(0x00));
        rec.DxbcSize = BinaryPrimitives.ReadUInt32LittleEndian(primary.AsSpan(0x14));

        // Stock round-trip: the serializer reproduces this primary (runtime pointers aside).
        try
        {
            var parsed = BPRShaderProgramBuffer.ReadPrimary(primary);
            byte[] again = parsed.ToBytes();
            int desc = BPRShaderProgramBuffer.DescriptorOffset(parsed.BindingCount) + BPRShaderProgramBuffer.DescriptorRuntimePtrOffset;
            bool same = again.Length == primary.Length && Enumerable.Range(0, primary.Length)
                .All(i => again[i] == primary[i] || (i is >= 4 and < 8) || (parsed.HasDescriptor && i >= desc && i < desc + 4));
            rec.StockRoundTrip = same ? "pass" : "fail";
        }
        catch (Exception ex) when (ex is ArgumentException or IndexOutOfRangeException or InvalidDataException)
        {
            rec.Errors.Add($"primary does not parse: {ex.Message}");
            return rec;
        }

        // ---- exact DXBC: three lengths, which must agree
        uint size = rec.DxbcSize.Value;
        if (size < 0x20 || size > secondary.Length)
        {
            rec.Errors.Add($"dxbcSize {size} does not fit the {secondary.Length}-byte secondary");
            return rec;
        }
        if (!secondary.AsSpan(0, 4).SequenceEqual("DXBC"u8))
        {
            rec.Errors.Add("secondary does not start with DXBC");
            return rec;
        }
        uint headerSize = BinaryPrimitives.ReadUInt32LittleEndian(secondary.AsSpan(0x18));
        if (headerSize != size)
            rec.Errors.Add($"contradictory sizes: primary dxbcSize {size}, DXBC header {headerSize}");
        int padded = Alignment.Align((int)size, BPRShaderProgramBuffer.SecondaryAlignment);
        if (secondary.Length != padded)
            rec.Errors.Add($"secondary is {secondary.Length} bytes, expected alignUp({size}, 0x80) = {padded}");
        if (secondary.AsSpan((int)size).ContainsAnyExcept((byte)0))
            rec.Errors.Add("non-zero bytes in the secondary's padding");

        var dxbc = secondary.AsSpan(0, (int)size);
        rec.DxbcLength = size;
        rec.DxbcSha256 = Convert.ToHexStringLower(SHA256.HashData(dxbc));

        try
        {
            var refl = RdefReflection.Instance.Reflect(dxbc);
            rec.Reflection = refl;
            string? stage = refl.Kind switch { ShaderKind.Vertex => "VertexShader", ShaderKind.Pixel => "PixelShader", _ => null };
            if (rec.DebugType is { } t && t != stage)
                rec.Errors.Add($".debug.xml says {t}, the DXBC is {refl.Kind}");
        }
        catch (Exception ex) when (ex is ArgumentException or IndexOutOfRangeException or InvalidDataException)
        {
            rec.Errors.Add($"malformed DXBC/RDEF: {ex.Message}");
            return rec;
        }

        if (rec.Errors.Count == 0)
        {
            var diffs = BPRShaderABI.CheckPrimary(primary, dxbc);
            rec.PrimaryDescribesDxbc = diffs.Count == 0 ? "pass" : "fail";
            rec.Notes.AddRange(diffs);
        }
        return rec;
    }

    private static FileFact Describe(string path, byte[] data) =>
        new(Path.GetFullPath(path), data.Length, Convert.ToHexStringLower(SHA256.HashData(data)));

    private sealed record FileFact(string Path, long Length, string Sha256);

    private sealed record Record(string Id)
    {
        public string? DebugName { get; set; }
        public string? DebugType { get; set; }
        public bool? NameMatchesId { get; set; }
        public FileFact? Primary { get; set; }
        public FileFact? Secondary { get; set; }
        public uint? MType { get; set; }
        public uint? DxbcSize { get; set; }
        public uint? DxbcLength { get; set; }
        public string? DxbcSha256 { get; set; }
        public DXBCReflection? Reflection { get; set; }
        public string StockRoundTrip { get; set; } = "not-run";
        public string PrimaryDescribesDxbc { get; set; } = "not-run";
        public List<string> Errors { get; set; } = [];
        public List<string> Notes { get; set; } = [];
    }
}
