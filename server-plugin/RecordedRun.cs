using System.Text.Json.Serialization;

namespace RandomLeadServerPlugin;

public sealed class RecordedRun
{
    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("id")]
    public string Id { get; init; } = "unknown";

    [JsonPropertyName("track")]
    public string Track { get; init; } = "";

    [JsonPropertyName("layout")]
    public string Layout { get; init; } = "";

    [JsonPropertyName("car")]
    public string Car { get; init; } = "";

    [JsonPropertyName("duration")]
    public double Duration { get; init; }

    [JsonPropertyName("frames")]
    public double[][] Frames { get; init; } = [];

    public void Validate()
    {
        if (Version is not (1 or 2)) throw new InvalidDataException($"Unsupported run version: {Version}");
        if (Frames.Length < 2) throw new InvalidDataException("Run must contain at least two frames");
        if (Duration <= 0) throw new InvalidDataException("Run duration must be positive");
        if (Frames.Any(frame => frame.Length < 20)) throw new InvalidDataException("Run contains a truncated frame");
    }
}
