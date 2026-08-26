using System.Text.Json.Serialization;

namespace RandomLeadServerPlugin;

public sealed class PlaybackStatus
{
    [JsonPropertyName("diagnosticsVersion")] public int DiagnosticsVersion { get; init; } = 1;
    [JsonPropertyName("state")] public string State { get; init; } = "unknown";
    [JsonPropertyName("mode")] public string Mode { get; init; } = "current";
    [JsonPropertyName("message")] public string Message { get; init; } = "";
    [JsonPropertyName("runCount")] public int RunCount { get; init; }
    [JsonPropertyName("selectedIndex")] public int? SelectedIndex { get; init; }
    [JsonPropertyName("runId")] public string? RunId { get; init; }
    [JsonPropertyName("lastCompletedRunId")] public string? LastCompletedRunId { get; init; }
    [JsonPropertyName("duration")] public double Duration { get; init; }
    [JsonPropertyName("elapsed")] public double Elapsed { get; init; }
    [JsonPropertyName("visible")] public bool Visible { get; init; }
    [JsonPropertyName("leaderSessionId")] public byte LeaderSessionId { get; init; }
    [JsonPropertyName("targetBodySpeed")] public float TargetBodySpeed { get; init; }
    [JsonPropertyName("targetWheelSpeed")] public float[] TargetWheelSpeed { get; init; } = [0, 0, 0, 0];
    [JsonPropertyName("sentWheelSpeed")] public float[] SentWheelSpeed { get; init; } = [0, 0, 0, 0];
}
