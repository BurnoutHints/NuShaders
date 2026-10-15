using System.Buffers.Binary;
using NuShaders.Formats.BPR;

namespace NuShaders.CLI.Commands;

/// <summary>pack-bpr: compile a DXBC blob into a BPR ShaderProgramBuffer (primary + secondary).</summary>
internal static class PackBPRCommand
{
    public static int Run(ArgMap args)
    {
        string input = args.Require("input");
        var dxbc = File.ReadAllBytes(input);
        if (dxbc.Length < 32 || dxbc[0] != (byte)'D' || dxbc[1] != (byte)'X' || dxbc[2] != (byte)'B' || dxbc[3] != (byte)'C')
        {
            Console.Error.WriteLine($"not a DXBC blob: {input}");
            return 1;
        }

        var primary = BPRShaderProgramBuffer.FromDXBC(dxbc);
        byte[] primaryBytes = primary.ToBytes();
        byte[] secondary = BPRShaderProgramBuffer.PadSecondary(dxbc);

        // Diff-only mode: compare our generated primary against a stock one.
        if (args.Get("reference") is { } refPath)
        {
            var refBytes = File.ReadAllBytes(refPath);
            int n = Math.Min(primaryBytes.Length, refBytes.Length);
            int diffs = 0, first = -1;
            for (int i = 0; i < n; i++)
                if (primaryBytes[i] != refBytes[i]) { diffs++; if (first < 0) first = i; }
            string firstStr = first < 0 ? "-" : "0x" + first.ToString("x");
            Console.WriteLine($"diff vs {Path.GetFileName(refPath)}: ours={primaryBytes.Length}b ref={refBytes.Length}b diffs={diffs} first={firstStr} sizeDelta={primaryBytes.Length - refBytes.Length}");
            return 0;
        }

        string outDir = args.Get("out-dir") ?? Path.GetDirectoryName(Path.GetFullPath(input))!;
        string name = args.Get("name") ?? Path.GetFileNameWithoutExtension(input);

        // With a stock pair to compare against (the spec's BPR packaging policies):
        //   identical interface            -> reuse the stock primary, patching only dxbcSize
        //   moved layout, contract intact  -> generate (the stock primary's offsets would be stale)
        //   new/moved binding, new data    -> refuse: no primary can make the engine supply it
        // A matching file name proves nothing; an edit can move a register.
        string policy = "generated";
        if (args.Get("stock-primary-dir") is { } stockDir)
        {
            string stockPri = Path.Combine(stockDir, $"{name}_primary.dat");
            string stockSec = Path.Combine(stockDir, $"{name}_secondary.dat");
            if (!File.Exists(stockPri) || !File.Exists(stockSec))
            {
                Console.Error.WriteLine($"no stock pair for {name} in {stockDir}: nothing to prove reuse against");
                return 1;
            }
            byte[] candidate = File.ReadAllBytes(stockPri);
            byte[] stockSecondary = File.ReadAllBytes(stockSec);
            uint refSize = candidate.Length >= 0x20 ? BinaryPrimitives.ReadUInt32LittleEndian(candidate.AsSpan(0x14)) : 0;
            if (refSize == 0 || refSize > stockSecondary.Length)
            {
                Console.Error.WriteLine($"stock pair {name} is inconsistent (dxbcSize {refSize}, secondary {stockSecondary.Length} bytes)");
                return 1;
            }
            BinaryPrimitives.WriteUInt32LittleEndian(candidate.AsSpan(0x14), primary.DXBCSize);
            var shipped = stockSecondary.AsSpan(0, (int)refSize);

            var layout = BPRShaderABI.CompareInterface(dxbc, shipped);
            if (layout.Count == 0)
            {
                var stale = BPRShaderABI.CheckPrimary(candidate, dxbc);
                if (stale.Count > 0) return Refuse($"stock primary {name} does not describe this shader", stale);
                primaryBytes = candidate;
                policy = "reused stock (interface identical, dxbcSize patched)";
            }
            else
            {
                var broken = BPRShaderABI.ContractViolations(dxbc, shipped);
                if (broken.Count > 0)
                    return Refuse($"rebuilt {name} breaks the renderer contract of the shipped shader", broken);
                policy = $"generated ({layout.Count} layout difference(s) from stock {name}; contract intact)";
                foreach (var d in layout) Console.WriteLine("    " + d);
            }
        }

        // Whatever we emit must describe the shader in the encoding every shipped primary uses.
        if (policy.StartsWith("generated", StringComparison.Ordinal))
        {
            var unproven = BPRShaderABI.CheckPrimary(primaryBytes, dxbc);
            if (unproven.Count > 0) return Refuse("generated primary uses a layout no shipped primary proves", unproven);
        }
        Console.WriteLine($"  primary: {policy}");

        Directory.CreateDirectory(outDir);
        string pri = Path.Combine(outDir, $"{name}_primary.dat");
        string sec = Path.Combine(outDir, $"{name}_secondary.dat");
        if (!args.Has("force") && (File.Exists(pri) || File.Exists(sec)))
        {
            Console.Error.WriteLine("output exists (use --force)");
            return 1;
        }

        File.WriteAllBytes(pri, primaryBytes);
        File.WriteAllBytes(sec, secondary);
        Console.WriteLine($"packed BPR {(primary.MType == 1 ? "PS" : "VS")}: primary={primaryBytes.Length}b secondary={secondary.Length}b -> {outDir}");
        return 0;
    }

    private static int Refuse(string why, List<string> diffs)
    {
        Console.Error.WriteLine($"{why} ({diffs.Count}):");
        foreach (var d in diffs) Console.Error.WriteLine("  " + d);
        return 1;
    }
}
