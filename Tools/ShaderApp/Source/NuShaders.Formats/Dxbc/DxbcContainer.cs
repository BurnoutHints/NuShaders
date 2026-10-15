using System.Text;
using NuShaders.Formats.IO;

namespace NuShaders.Formats.DXBC;

/// <summary>
/// Parses the DXBC chunk table: magic "DXBC", a 16-byte hash, version, total size @0x18,
/// chunk count @0x1C, then a uint32 offset table @0x20. Each chunk is FourCC(4) + size(4) + data.
/// </summary>
public sealed class DXBCContainer
{
    private readonly byte[] _data;
    private readonly (string FourCc, int Offset, int Size)[] _chunks;

    /// <summary>Total container size as recorded in the header (@0x18).</summary>
    public int TotalSize { get; }

    public DXBCContainer(ReadOnlySpan<byte> data)
    {
        if (data.Length < 0x20 ||
            data[0] != (byte)'D' || data[1] != (byte)'X' || data[2] != (byte)'B' || data[3] != (byte)'C')
            throw new InvalidDataException("Not a DXBC container (bad magic).");

        var r = new SpanReader(data);
        uint total = r.U32LE(0x18);
        uint count = r.U32LE(0x1C);

        // Everything below is bounded by the header's own size, which must fit the buffer. A padded secondary
        // (zeros past TotalSize) is fine; a chunk reaching into that padding is not.
        if (total < 0x20 || total > data.Length)
            throw new InvalidDataException($"DXBC size {total} does not fit the {data.Length}-byte buffer.");
        if (0x20 + 4L * count > total)
            throw new InvalidDataException($"DXBC chunk table ({count} entries) overruns the {total}-byte container.");
        TotalSize = (int)total;

        _chunks = new (string, int, int)[count];
        for (int i = 0; i < count; i++)
        {
            uint chunkOff = r.U32LE(0x20 + i * 4);
            if (chunkOff < 0x20 + 4L * count || chunkOff + 8L > total)
                throw new InvalidDataException($"DXBC chunk {i} at 0x{chunkOff:X} is outside the container.");
            string fourCc = Encoding.ASCII.GetString(data.Slice((int)chunkOff, 4));
            uint size = r.U32LE((int)chunkOff + 4);
            if (chunkOff + 8L + size > total)
                throw new InvalidDataException($"DXBC chunk '{fourCc}' ({size} bytes at 0x{chunkOff:X}) overruns the container.");
            _chunks[i] = (fourCc, (int)chunkOff + 8, (int)size);
        }

        _data = data.ToArray();
    }

    public bool TryGetChunk(string fourCc, out ReadOnlySpan<byte> chunk)
    {
        foreach (var c in _chunks)
        {
            if (c.FourCc == fourCc)
            {
                chunk = _data.AsSpan(c.Offset, c.Size);
                return true;
            }
        }
        chunk = default;
        return false;
    }

    public ReadOnlySpan<byte> GetChunk(string fourCc) =>
        TryGetChunk(fourCc, out var chunk) ? chunk : throw new InvalidDataException($"DXBC has no '{fourCc}' chunk.");
}
