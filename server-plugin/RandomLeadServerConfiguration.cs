using JetBrains.Annotations;
using YamlDotNet.Serialization;

namespace RandomLeadServerPlugin;

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public sealed class RandomLeadServerConfiguration
{
    [YamlMember(Description = "Enable recorded lead playback.")]
    public bool Enabled { get; init; } = true;

    [YamlMember(Description = "Entry-list session ID reserved for the synthetic leader.")]
    public byte LeaderSessionId { get; init; } = 1;

    [YamlMember(Description = "Absolute latest.json path. Empty selects the newest run in the standard Documents folder.")]
    public string RunFile { get; init; } = "";

    [YamlMember(Description = "Directory containing compatible run JSON files. Empty uses the RunFile directory.")]
    public string RunDirectory { get; init; } = "";

    [YamlMember(Description = "Start the current run automatically when the first chase client becomes ready.")]
    public bool AutoStart { get; init; } = true;

    [YamlMember(Description = "Seconds to wait after a player is ready before playback starts.")]
    public double StartDelaySeconds { get; init; } = 5;

    [YamlMember(Description = "Loop the selected run for this first visual/collision spike.")]
    public bool Loop { get; init; } = true;

    [YamlMember(Description = "Delay between loops in seconds.")]
    public double LoopDelaySeconds { get; init; } = 3;

    [YamlMember(Description = "Legacy v1/v2 visual-origin correction from car.ini GRAPHICS_OFFSET, X component.")]
    public float LegacyGraphicsOffsetX { get; init; }

    [YamlMember(Description = "Legacy v1/v2 visual-origin correction from car.ini GRAPHICS_OFFSET, Y component.")]
    public float LegacyGraphicsOffsetY { get; init; }

    [YamlMember(Description = "Legacy v1/v2 visual-origin correction from car.ini GRAPHICS_OFFSET, Z component.")]
    public float LegacyGraphicsOffsetZ { get; init; }
}
