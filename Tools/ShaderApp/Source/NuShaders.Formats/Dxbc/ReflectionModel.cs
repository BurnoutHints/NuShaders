namespace NuShaders.Formats.DXBC;

/// <summary>Shader stage, from the RDEF program-type token.</summary>
public enum ShaderKind { Unknown = 0, Vertex, Pixel }

/// <summary>Resource binding category, mapped from the D3D shader-input type.</summary>
public enum ResourceKind { Other = 0, Sampler, Texture, CBuffer }

/// <summary>A bound resource (sampler / texture / cbuffer) from the RDEF resource-binding table.</summary>
public sealed record ResourceBinding(string Name, int Register, ResourceKind Kind, uint D3DInputType, uint BindFlags,
    uint Dimension = 0, int BindCount = 1);

/// <summary>A cbuffer member from the RDEF variable table.</summary>
public sealed record CbufferVariable(
    string Name,
    int ByteOffset,
    int SizeBytes,
    int Rows,
    int Columns,
    int ElementCount,
    int DeclarationIndex,
    uint Flags,
    int VariableClass = 0,
    int VariableType = 0)
{
    /// <summary>D3D_SVF_USED.</summary>
    public const uint UsedFlag = 0x2;

    /// <summary>D3D_SVT_FLOAT.</summary>
    public const int FloatType = 3;

    public bool IsUsed => (Flags & UsedFlag) != 0;

    /// <summary>Rows as stored in the BPR primary var table: matrix rows × array length (1 for vectors/scalars).</summary>
    public int PackedRows => Rows * (ElementCount == 0 ? 1 : ElementCount);
}

/// <summary>A constant buffer and its members.</summary>
public sealed record CbufferReflection(string Name, int SizeBytes, IReadOnlyList<CbufferVariable> Variables);

/// <summary>One ISGN/OSGN element: what a stage reads from or writes to its neighbour.</summary>
public sealed record SignatureElement(string SemanticName, int SemanticIndex, uint SystemValue, uint ComponentType,
    int Register, byte Mask, byte ReadWriteMask);

/// <summary>Everything the packers need out of a compiled DXBC shader.</summary>
public sealed record DXBCReflection(
    ShaderKind Kind,
    IReadOnlyList<ResourceBinding> Bindings,
    IReadOnlyList<CbufferReflection> Cbuffers)
{
    public int MajorVersion { get; init; }
    public int MinorVersion { get; init; }
    public IReadOnlyList<SignatureElement> Inputs { get; init; } = [];
    public IReadOnlyList<SignatureElement> Outputs { get; init; } = [];

    /// <summary>fxc-style target, e.g. <c>ps_5_0</c>.</summary>
    public string Profile => $"{(Kind == ShaderKind.Pixel ? "ps" : Kind == ShaderKind.Vertex ? "vs" : "unknown")}_{MajorVersion}_{MinorVersion}";
}
