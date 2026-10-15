// nushaders — Burnout shader/bundle binary tool.
using NuShaders.CLI;
using NuShaders.CLI.Commands;

if (args.Length == 0)
    return Usage();

try
{
    return args[0] switch
    {
        "pack-bpr" => PackBPRCommand.Run(new ArgMap(args, 1)),
        "extract-bpr" => ExtractBPRCommand.Run(new ArgMap(args, 1)),
        "pack-bpr-shader" => PackBPRShaderCommand.Run(new ArgMap(args, 1)),
        "pack-x360" => PackX360Command.Run(new ArgMap(args, 1)),
        "pack-texture" => PackTextureCommand.Run(new ArgMap(args, 1)),
        "material" => MaterialCommand.Run(args),
        "analyze" => AnalyzeCommand.Run(new ArgMap(args, 1)),
        _ => Unknown(args[0]),
    };
}
catch (Exception ex)
{
    Console.Error.WriteLine($"error: {ex.Message}");
    return 1;
}

static int Usage()
{
    Console.Error.WriteLine("nushaders <command> [options]");
    Console.Error.WriteLine("commands: pack-bpr  extract-bpr  pack-bpr-shader  pack-x360  pack-texture  material  analyze");
    return 1;
}

static int Unknown(string command)
{
    Console.Error.WriteLine($"unknown command '{command}'");
    return Usage();
}
