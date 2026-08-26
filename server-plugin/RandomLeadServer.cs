using System.Collections.Concurrent;
using System.Numerics;
using System.Text.Json;
using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Shared.Network.Packets.Outgoing;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace RandomLeadServerPlugin;

public sealed class RandomLeadServer : IHostedService
{
    private const int Time = 0, Px = 1, Py = 2, Pz = 3, Lx = 4, Ly = 5, Lz = 6;
    private const int Ux = 7, Uy = 8, Uz = 9, Vx = 10, Vy = 11, Vz = 12;
    private const int Steer = 13, Gas = 14, Brake = 15, Gear = 18, Rpm = 19;
    private const int WheelFl = 20, WheelFr = 21, WheelRl = 22, WheelRr = 23;

    private readonly RandomLeadServerConfiguration _configuration;
    private readonly ACServer _server;
    private readonly EntryCarManager _entryCarManager;
    private readonly SessionManager _sessionManager;
    private readonly ConcurrentQueue<PlaybackCommand> _commands = new();
    private readonly HashSet<byte> _announcedClients = [];
    private readonly object _sync = new();
    private IReadOnlyList<RecordedRun> _runs = [];
    private RecordedRun? _run;
    private EntryCar? _leader;
    private int _selectedIndex;
    private long _playbackStartMs = -1;
    private int _cursor;
    private byte _sequence;
    private bool _visible;
    private bool _desiredPlaying;
    private bool _waitingBetweenRuns;
    private string _state = "initializing";
    private string _mode = "current";
    private string? _lastCompletedRunId;
    private string _message = "Loading run library";
    private float _targetBodySpeed;
    private readonly float[] _targetWheelSpeed = new float[4];
    private readonly float[] _sentWheelSpeed = new float[4];

    public RandomLeadServer(RandomLeadServerConfiguration configuration, ACServer server,
        EntryCarManager entryCarManager, SessionManager sessionManager)
    {
        _configuration = configuration;
        _server = server;
        _entryCarManager = entryCarManager;
        _sessionManager = sessionManager;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (!_configuration.Enabled)
        {
            _state = "disabled";
            _message = "Random lead server plugin is disabled";
            Log.Information(_message);
            return Task.CompletedTask;
        }

        string initialPath = ResolveInitialRunPath();
        RecordedRun initialRun = LoadRun(initialPath);
        _runs = LoadLibrary(initialPath, initialRun);
        _selectedIndex = Math.Max(0, _runs.ToList().FindIndex(run => run.Id == initialRun.Id));
        _run = _runs[_selectedIndex];

        if (_configuration.LeaderSessionId >= _entryCarManager.EntryCars.Length)
            throw new InvalidOperationException($"LeaderSessionId {_configuration.LeaderSessionId} is outside the entry list");
        _leader = _entryCarManager.EntryCars[_configuration.LeaderSessionId];
        if (_leader.Client != null)
            throw new InvalidOperationException($"Leader slot {_configuration.LeaderSessionId} is occupied by a client");
        if (!string.Equals(_leader.Model, _run.Car, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Leader slot car '{_leader.Model}' does not match recorded car '{_run.Car}'");

        _desiredPlaying = _configuration.AutoStart;
        _state = _desiredPlaying ? "waiting_for_player" : "stopped";
        _message = _desiredPlaying ? "Waiting for a ready chase client" : "Ready";
        _server.Update += OnServerUpdate;
        _entryCarManager.ClientConnected += OnClientConnected;
        _entryCarManager.ClientDisconnected += OnClientDisconnected;
        Log.Information("Random lead library loaded: {Count} compatible run(s), initial {RunId}, directory {Directory}",
            _runs.Count, _run.Id, ResolveLibraryDirectory(initialPath));
        LogRunDynamics(_run);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _server.Update -= OnServerUpdate;
        _entryCarManager.ClientConnected -= OnClientConnected;
        _entryCarManager.ClientDisconnected -= OnClientDisconnected;
        lock (_sync) HideLeader();
        return Task.CompletedTask;
    }

    public bool QueueCommand(string value, out string error)
    {
        if (!Enum.TryParse(value, true, out PlaybackCommand command))
        {
            error = "Unknown command. Use current, next, random, restart, or stop.";
            return false;
        }
        _commands.Enqueue(command);
        error = "";
        return true;
    }

    public PlaybackStatus GetStatus()
    {
        lock (_sync)
        {
            double elapsed = _state == "playing" && _playbackStartMs >= 0
                ? Math.Max(0, (_sessionManager.ServerTimeMilliseconds - _playbackStartMs) / 1000.0) : 0;
            bool conceal = _mode == "random" && _state is not ("stopped" or "completed");
            return new PlaybackStatus
            {
                State = _state,
                Mode = _mode,
                Message = _message,
                RunCount = _runs.Count,
                SelectedIndex = conceal ? null : _selectedIndex + 1,
                RunId = conceal ? null : _run?.Id,
                LastCompletedRunId = _lastCompletedRunId,
                Duration = _run?.Duration ?? 0,
                Elapsed = Math.Min(elapsed, _run?.Duration ?? 0),
                Visible = _visible,
                LeaderSessionId = _leader?.SessionId ?? _configuration.LeaderSessionId,
                TargetBodySpeed = _targetBodySpeed,
                TargetWheelSpeed = (float[])_targetWheelSpeed.Clone(),
                SentWheelSpeed = (float[])_sentWheelSpeed.Clone()
            };
        }
    }

    private void OnClientConnected(ACTcpClient client, EventArgs args)
    {
        lock (_sync)
        {
            _playbackStartMs = -1;
            _waitingBetweenRuns = false;
            _announcedClients.Remove(client.SessionId);
            if (_desiredPlaying)
            {
                _state = "waiting_for_player";
                _message = "Waiting for a ready chase client";
            }
        }
        Log.Information("Random lead waiting for client {SessionId} to become ready", client.SessionId);
    }

    private void OnClientDisconnected(ACTcpClient client, EventArgs args)
    {
        lock (_sync) _announcedClients.Remove(client.SessionId);
    }

    private void OnServerUpdate(ACServer sender, EventArgs args)
    {
        lock (_sync)
        {
            DrainCommands();
            if (_run == null || _leader == null || !_desiredPlaying) return;
            bool hasReadyPlayer = _entryCarManager.EntryCars.Any(car =>
                car.SessionId != _leader.SessionId && car.Client is { HasSentFirstUpdate: true });
            if (!hasReadyPlayer)
            {
                _state = "waiting_for_player";
                _message = "Waiting for a ready chase client";
                return;
            }

            EnsureLeaderAnnounced();
            long now = _sessionManager.ServerTimeMilliseconds;
            if (_playbackStartMs < 0) BeginCountdown(now, _configuration.StartDelaySeconds, false);
            if (now < _playbackStartMs)
            {
                SendFrame(_run.Frames[0], _run.Frames[0], 0, now);
                double remaining = (_playbackStartMs - now) / 1000.0;
                _state = _waitingBetweenRuns ? "loop_wait" : "countdown";
                _message = _waitingBetweenRuns ? $"Next attempt in {remaining:F1} s" : $"Leader starts in {remaining:F1} s";
                return;
            }

            _waitingBetweenRuns = false;
            _state = "playing";
            _message = "Leader is running";
            double elapsed = (now - _playbackStartMs) / 1000.0;
            if (elapsed >= _run.Duration)
            {
                _lastCompletedRunId = _run.Id;
                if (!_configuration.Loop)
                {
                    _desiredPlaying = false;
                    _state = "completed";
                    _message = "Run completed";
                    HideLeader();
                    return;
                }
                if (_mode == "random") SelectRandomRun();
                BeginCountdown(now, _configuration.LoopDelaySeconds, true);
                return;
            }

            while (_cursor < _run.Frames.Length - 2 && _run.Frames[_cursor + 1][Time] <= elapsed) _cursor++;
            double[] a = _run.Frames[_cursor];
            double[] b = _run.Frames[Math.Min(_cursor + 1, _run.Frames.Length - 1)];
            double interval = Math.Max(b[Time] - a[Time], 0.0001);
            float alpha = (float)Math.Clamp((elapsed - a[Time]) / interval, 0, 1);
            SendFrame(a, b, alpha, now);
        }
    }

    private void DrainCommands()
    {
        while (_commands.TryDequeue(out PlaybackCommand command))
        {
            switch (command)
            {
                case PlaybackCommand.Stop:
                    _desiredPlaying = false;
                    _state = "stopped";
                    _message = "Leader stopped and hidden";
                    HideLeader();
                    break;
                case PlaybackCommand.Next:
                    _mode = "current";
                    SelectRun((_selectedIndex + 1) % _runs.Count);
                    ArmSelectedRun();
                    break;
                case PlaybackCommand.Random:
                    _mode = "random";
                    SelectRandomRun();
                    ArmSelectedRun();
                    break;
                case PlaybackCommand.Restart:
                case PlaybackCommand.Current:
                    if (command == PlaybackCommand.Current) _mode = "current";
                    ArmSelectedRun();
                    break;
            }
        }
    }

    private void ArmSelectedRun()
    {
        HideLeader();
        _desiredPlaying = true;
        _playbackStartMs = -1;
        _waitingBetweenRuns = false;
        _cursor = 0;
        _lastCompletedRunId = null;
        _state = "waiting_for_player";
        _message = "Playback armed";
    }

    private void BeginCountdown(long now, double delaySeconds, bool betweenRuns)
    {
        _playbackStartMs = now + (long)(delaySeconds * 1000);
        _cursor = 0;
        _waitingBetweenRuns = betweenRuns;
        _state = betweenRuns ? "loop_wait" : "countdown";
    }

    private void SelectRandomRun() => SelectRun(Random.Shared.Next(_runs.Count));

    private void SelectRun(int index)
    {
        _selectedIndex = index;
        _run = _runs[index];
        _cursor = 0;
        Log.Information("Random lead selected run {RunId} ({Index}/{Count}) in {Mode} mode",
            _run.Id, _selectedIndex + 1, _runs.Count, _mode);
    }

    private void EnsureLeaderAnnounced()
    {
        foreach (EntryCar car in _entryCarManager.EntryCars)
        {
            if (car.SessionId == _leader!.SessionId || car.Client is not { HasSentFirstUpdate: true } client
                || !_announcedClients.Add(car.SessionId)) continue;
            client.SendPacket(new CarConnected { SessionId = _leader.SessionId, Name = "Recorded Leader", Nation = "" });
            _visible = true;
        }
    }

    private void HideLeader()
    {
        if (_visible && _leader != null)
            _entryCarManager.BroadcastPacket(new CarDisconnected { SessionId = _leader.SessionId });
        _visible = false;
        _announcedClients.Clear();
        _playbackStartMs = -1;
        _waitingBetweenRuns = false;
        _cursor = 0;
    }

    private void SendFrame(double[] a, double[] b, float alpha, long now)
    {
        Vector3 position = LerpVector(a, b, Px, Py, Pz, alpha);
        Vector3 look = SafeNormalize(LerpVector(a, b, Lx, Ly, Lz, alpha), Vector3.UnitZ);
        Vector3 up = SafeNormalize(LerpVector(a, b, Ux, Uy, Uz, alpha), Vector3.UnitY);
        if (_run!.Version <= 2) position = CorrectLegacyVisualOrigin(position, look, up);
        Vector3 velocity = LerpVector(a, b, Vx, Vy, Vz, alpha);
        Vector3 rotation = ToNetworkRotation(look, up);
        float steer = Lerp(a[Steer], b[Steer], alpha);
        float gas = Lerp(a[Gas], b[Gas], alpha);
        float brake = Lerp(a[Brake], b[Brake], alpha);
        int gear = alpha < 0.5f ? (int)a[Gear] : (int)b[Gear];
        float rpm = Lerp(a[Rpm], b[Rpm], alpha);
        _targetBodySpeed = velocity.Length();
        _targetWheelSpeed[0] = ReadWheel(a, b, WheelFl, alpha);
        _targetWheelSpeed[1] = ReadWheel(a, b, WheelFr, alpha);
        _targetWheelSpeed[2] = ReadWheel(a, b, WheelRl, alpha);
        _targetWheelSpeed[3] = ReadWheel(a, b, WheelRr, alpha);

        var status = _leader!.Status;
        status.PakSequenceId = _sequence++;
        status.Timestamp = now;
        status.Position = position;
        status.Rotation = rotation;
        status.Velocity = velocity;
        for (int i = 0; i < 4; i++)
        {
            status.TyreAngularSpeed[i] = EncodeWheelSpeed(_targetWheelSpeed[i]);
            _sentWheelSpeed[i] = DecodeWheelSpeed(status.TyreAngularSpeed[i]);
        }
        status.SteerAngle = EncodeSignedUnit(steer);
        status.WheelAngle = EncodeSignedUnit(steer);
        status.EngineRpm = (ushort)Math.Clamp(MathF.Round(rpm), 0, ushort.MaxValue);
        status.Gear = (byte)Math.Clamp(gear + 1, 0, byte.MaxValue);
        status.StatusFlag = brake > 0.05f ? CarStatusFlags.BrakeLightsOn : 0;
        status.Gas = (byte)Math.Clamp(MathF.Round(gas * byte.MaxValue), 0, byte.MaxValue);

        foreach (EntryCar target in _entryCarManager.EntryCars)
        {
            if (target.SessionId == _leader.SessionId || target.Client is not { HasSentFirstUpdate: true } client
                || !_leader.GetPositionUpdateForCar(target, out var packet)) continue;
            client.SendPacketUdp(in packet);
        }
    }

    private IReadOnlyList<RecordedRun> LoadLibrary(string initialPath, RecordedRun initialRun)
    {
        string directory = ResolveLibraryDirectory(initialPath);
        var byId = new Dictionary<string, RecordedRun>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in Directory.EnumerateFiles(directory, "*.json", SearchOption.TopDirectoryOnly)
                     .OrderBy(path => Path.GetFileName(path).Equals("latest.json", StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                RecordedRun run = LoadRun(path);
                if (!SameIdentity(run, initialRun))
                {
                    Log.Warning("Skipping incompatible random lead run {Path}", path);
                    continue;
                }
                byId.TryAdd(run.Id, run);
            }
            catch (Exception exception)
            {
                Log.Warning(exception, "Skipping invalid random lead run {Path}", path);
            }
        }
        byId.TryAdd(initialRun.Id, initialRun);
        return byId.Values.OrderBy(run => run.Id, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private string ResolveInitialRunPath()
    {
        if (!string.IsNullOrWhiteSpace(_configuration.RunFile))
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(_configuration.RunFile));
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "Assetto Corsa", "ac-random-lead-runs", "runs");
        var newest = new DirectoryInfo(root).EnumerateFiles("latest.json", SearchOption.AllDirectories)
            .OrderByDescending(file => file.LastWriteTimeUtc).FirstOrDefault();
        return newest?.FullName ?? throw new FileNotFoundException($"No latest.json found below {root}");
    }

    private string ResolveLibraryDirectory(string initialPath) => Path.GetFullPath(
        Environment.ExpandEnvironmentVariables(string.IsNullOrWhiteSpace(_configuration.RunDirectory)
            ? Path.GetDirectoryName(initialPath)! : _configuration.RunDirectory));

    private static RecordedRun LoadRun(string path)
    {
        var run = JsonSerializer.Deserialize<RecordedRun>(File.ReadAllText(path), new JsonSerializerOptions
        { PropertyNameCaseInsensitive = true }) ?? throw new InvalidDataException($"Could not deserialize run: {path}");
        run.Validate();
        return run;
    }

    private static bool SameIdentity(RecordedRun a, RecordedRun b) =>
        string.Equals(a.Track, b.Track, StringComparison.OrdinalIgnoreCase)
        && string.Equals(a.Layout, b.Layout, StringComparison.OrdinalIgnoreCase)
        && string.Equals(a.Car, b.Car, StringComparison.OrdinalIgnoreCase);

    private static void LogRunDynamics(RecordedRun run)
    {
        float maxBodySpeed = run.Frames.Max(frame => MathF.Sqrt(
            (float)(frame[Vx] * frame[Vx] + frame[Vy] * frame[Vy] + frame[Vz] * frame[Vz])));
        float maxWheelSpeed = run.Frames.Where(frame => frame.Length > WheelRr)
            .SelectMany(frame => frame.Skip(WheelFl).Take(4)).Select(value => MathF.Abs((float)value))
            .DefaultIfEmpty(0).Max();
        Log.Information("Run dynamics: max body speed {BodySpeed:F2} m/s, max wheel angular speed {WheelSpeed:F2} rad/s",
            maxBodySpeed, maxWheelSpeed);
    }

    private static Vector3 LerpVector(double[] a, double[] b, int x, int y, int z, float alpha) => new(
        Lerp(a[x], b[x], alpha), Lerp(a[y], b[y], alpha), Lerp(a[z], b[z], alpha));
    private static float Lerp(double a, double b, float alpha) => (float)(a + (b - a) * alpha);
    private static float ReadWheel(double[] a, double[] b, int index, float alpha) =>
        a.Length <= index || b.Length <= index ? 0 : Lerp(a[index], b[index], alpha);
    private static Vector3 SafeNormalize(Vector3 value, Vector3 fallback) =>
        value.LengthSquared() > 0.000001f ? Vector3.Normalize(value) : fallback;

    private Vector3 CorrectLegacyVisualOrigin(Vector3 position, Vector3 look, Vector3 up)
    {
        Vector3 side = SafeNormalize(Vector3.Cross(up, look), Vector3.UnitX);
        return position - side * _configuration.LegacyGraphicsOffsetX
            - up * _configuration.LegacyGraphicsOffsetY - look * _configuration.LegacyGraphicsOffsetZ;
    }

    private static byte EncodeSignedUnit(float value) =>
        (byte)Math.Clamp(MathF.Round(127 + Math.Clamp(value, -1, 1) * 127), 0, 254);

    private static byte EncodeWheelSpeed(float angularSpeed)
    {
        float encoded = MathF.Round(MathF.Log10(MathF.Abs(angularSpeed) + 1) * 20) * MathF.Sign(angularSpeed);
        return (byte)Math.Clamp(encoded + 100, 0, 254);
    }

    private static float DecodeWheelSpeed(byte encoded)
    {
        float value = encoded - 100;
        float sign = MathF.Sign(value);
        return sign == 0 ? 0 : (MathF.Pow(10, MathF.Abs(value) / 20) - 1) * sign;
    }

    private static Vector3 ToNetworkRotation(Vector3 look, Vector3 up)
    {
        float yaw = MathF.Atan2(look.Z, look.X) - MathF.PI / 2;
        float pitch = -(MathF.Atan2(MathF.Sqrt(look.Z * look.Z + look.X * look.X), look.Y) - MathF.PI / 2);
        Vector3 side = SafeNormalize(Vector3.Cross(up, look), Vector3.UnitX);
        float roll = MathF.Atan2(Vector3.Dot(side, Vector3.UnitY), Vector3.Dot(up, Vector3.UnitY));
        return new Vector3(yaw, pitch, roll);
    }

    private enum PlaybackCommand { Current, Next, Random, Restart, Stop }
}
