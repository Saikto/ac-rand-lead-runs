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
    private const int Time = 0;
    private const int Px = 1;
    private const int Py = 2;
    private const int Pz = 3;
    private const int Lx = 4;
    private const int Ly = 5;
    private const int Lz = 6;
    private const int Ux = 7;
    private const int Uy = 8;
    private const int Uz = 9;
    private const int Vx = 10;
    private const int Vy = 11;
    private const int Vz = 12;
    private const int Steer = 13;
    private const int Gas = 14;
    private const int Brake = 15;
    private const int Gear = 18;
    private const int Rpm = 19;
    private const int WheelFl = 20;
    private const int WheelFr = 21;
    private const int WheelRl = 22;
    private const int WheelRr = 23;

    private readonly RandomLeadServerConfiguration _configuration;
    private readonly ACServer _server;
    private readonly EntryCarManager _entryCarManager;
    private readonly SessionManager _sessionManager;
    private RecordedRun? _run;
    private EntryCar? _leader;
    private long _playbackStartMs = -1;
    private int _cursor;
    private byte _sequence;
    private bool _visible;
    private readonly HashSet<byte> _announcedClients = [];

    public RandomLeadServer(
        RandomLeadServerConfiguration configuration,
        ACServer server,
        EntryCarManager entryCarManager,
        SessionManager sessionManager)
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
            Log.Information("Random lead server plugin is disabled");
            return Task.CompletedTask;
        }

        string path = ResolveRunPath();
        _run = JsonSerializer.Deserialize<RecordedRun>(File.ReadAllText(path), new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidDataException($"Could not deserialize run: {path}");
        _run.Validate();

        if (_configuration.LeaderSessionId >= _entryCarManager.EntryCars.Length)
            throw new InvalidOperationException($"LeaderSessionId {_configuration.LeaderSessionId} is outside the entry list");

        _leader = _entryCarManager.EntryCars[_configuration.LeaderSessionId];
        if (_leader.Client != null)
            throw new InvalidOperationException($"Leader slot {_configuration.LeaderSessionId} is occupied by a client");
        if (!string.Equals(_leader.Model, _run.Car, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Leader slot car '{_leader.Model}' does not match recorded car '{_run.Car}'");

        _server.Update += OnServerUpdate;
        _entryCarManager.ClientConnected += OnClientConnected;
        _entryCarManager.ClientDisconnected += OnClientDisconnected;
        Log.Information("Random lead loaded {RunId}: {Duration:F2}s, {Frames} frames, {Path}",
            _run.Id, _run.Duration, _run.Frames.Length, path);
        float maxBodySpeed = _run.Frames.Max(frame => MathF.Sqrt(
            (float)(frame[Vx] * frame[Vx] + frame[Vy] * frame[Vy] + frame[Vz] * frame[Vz])));
        float maxWheelSpeed = _run.Frames
            .Where(frame => frame.Length > WheelRr)
            .SelectMany(frame => frame.Skip(WheelFl).Take(4))
            .Select(value => MathF.Abs((float)value))
            .DefaultIfEmpty(0)
            .Max();
        Log.Information("Run dynamics: max body speed {BodySpeed:F2} m/s, max wheel angular speed {WheelSpeed:F2} rad/s",
            maxBodySpeed, maxWheelSpeed);
        if (_run.Version <= 2)
        {
            Log.Information("Applying legacy GRAPHICS_OFFSET correction: ({X:F3}, {Y:F3}, {Z:F3})",
                _configuration.LegacyGraphicsOffsetX,
                _configuration.LegacyGraphicsOffsetY,
                _configuration.LegacyGraphicsOffsetZ);
        }
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _server.Update -= OnServerUpdate;
        _entryCarManager.ClientConnected -= OnClientConnected;
        _entryCarManager.ClientDisconnected -= OnClientDisconnected;
        if (_visible && _leader != null)
            _entryCarManager.BroadcastPacket(new CarDisconnected { SessionId = _leader.SessionId });
        return Task.CompletedTask;
    }

    private void OnClientConnected(ACTcpClient client, EventArgs args)
    {
        _playbackStartMs = -1;
        _announcedClients.Remove(client.SessionId);
        Log.Information("Random lead waiting for client {SessionId} to become ready", client.SessionId);
    }

    private void OnClientDisconnected(ACTcpClient client, EventArgs args)
    {
        _announcedClients.Remove(client.SessionId);
    }

    private void OnServerUpdate(ACServer sender, EventArgs args)
    {
        if (_run == null || _leader == null) return;
        bool hasReadyPlayer = _entryCarManager.EntryCars.Any(car =>
            car.SessionId != _leader.SessionId && car.Client is { HasSentFirstUpdate: true });
        if (!hasReadyPlayer) return;

        long now = _sessionManager.ServerTimeMilliseconds;
        foreach (EntryCar car in _entryCarManager.EntryCars)
        {
            if (car.SessionId == _leader.SessionId
                || car.Client is not { HasSentFirstUpdate: true } client
                || !_announcedClients.Add(car.SessionId)) continue;

            client.SendPacket(new CarConnected
            {
                SessionId = _leader.SessionId,
                Name = "Recorded Leader",
                Nation = ""
            });
            _visible = true;
        }

        if (_playbackStartMs < 0)
        {
            _playbackStartMs = now + (long)(_configuration.StartDelaySeconds * 1000);
            _cursor = 0;
        }
        if (now < _playbackStartMs) return;

        double elapsed = (now - _playbackStartMs) / 1000.0;
        if (elapsed >= _run.Duration)
        {
            if (!_configuration.Loop)
            {
                if (_visible)
                {
                    _entryCarManager.BroadcastPacket(new CarDisconnected { SessionId = _leader.SessionId });
                    _visible = false;
                }
                return;
            }

            _playbackStartMs = now + (long)(_configuration.LoopDelaySeconds * 1000);
            _cursor = 0;
            return;
        }

        while (_cursor < _run.Frames.Length - 2 && _run.Frames[_cursor + 1][Time] <= elapsed)
            _cursor++;

        double[] a = _run.Frames[_cursor];
        double[] b = _run.Frames[Math.Min(_cursor + 1, _run.Frames.Length - 1)];
        double interval = Math.Max(b[Time] - a[Time], 0.0001);
        float alpha = (float)Math.Clamp((elapsed - a[Time]) / interval, 0, 1);
        SendFrame(a, b, alpha, now);
    }

    private void SendFrame(double[] a, double[] b, float alpha, long now)
    {
        Vector3 position = LerpVector(a, b, Px, Py, Pz, alpha);
        Vector3 look = SafeNormalize(LerpVector(a, b, Lx, Ly, Lz, alpha), Vector3.UnitZ);
        Vector3 up = SafeNormalize(LerpVector(a, b, Ux, Uy, Uz, alpha), Vector3.UnitY);
        if (_run!.Version <= 2)
            position = CorrectLegacyVisualOrigin(position, look, up);
        Vector3 velocity = LerpVector(a, b, Vx, Vy, Vz, alpha);
        Vector3 rotation = ToNetworkRotation(look, up);
        float steer = Lerp(a[Steer], b[Steer], alpha);
        float gas = Lerp(a[Gas], b[Gas], alpha);
        float brake = Lerp(a[Brake], b[Brake], alpha);
        int gear = alpha < 0.5f ? (int)a[Gear] : (int)b[Gear];
        float rpm = Lerp(a[Rpm], b[Rpm], alpha);

        var status = _leader!.Status;
        status.PakSequenceId = _sequence++;
        status.Timestamp = now;
        status.Position = position;
        status.Rotation = rotation;
        status.Velocity = velocity;
        status.TyreAngularSpeed[0] = EncodeWheelSpeed(ReadWheel(a, b, WheelFl, alpha));
        status.TyreAngularSpeed[1] = EncodeWheelSpeed(ReadWheel(a, b, WheelFr, alpha));
        status.TyreAngularSpeed[2] = EncodeWheelSpeed(ReadWheel(a, b, WheelRl, alpha));
        status.TyreAngularSpeed[3] = EncodeWheelSpeed(ReadWheel(a, b, WheelRr, alpha));
        status.SteerAngle = EncodeSignedUnit(steer);
        status.WheelAngle = EncodeSignedUnit(steer);
        status.EngineRpm = (ushort)Math.Clamp(MathF.Round(rpm), 0, ushort.MaxValue);
        status.Gear = (byte)Math.Clamp(gear + 1, 0, byte.MaxValue);
        status.StatusFlag = brake > 0.05f ? CarStatusFlags.BrakeLightsOn : 0;
        status.Gas = (byte)Math.Clamp(MathF.Round(gas * byte.MaxValue), 0, byte.MaxValue);

        foreach (EntryCar target in _entryCarManager.EntryCars)
        {
            if (target.SessionId == _leader.SessionId
                || target.Client is not { HasSentFirstUpdate: true } client
                || !_leader.GetPositionUpdateForCar(target, out var packet)) continue;
            client.SendPacketUdp(in packet);
        }
    }

    private string ResolveRunPath()
    {
        if (!string.IsNullOrWhiteSpace(_configuration.RunFile))
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(_configuration.RunFile));

        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "Assetto Corsa", "ac-random-lead-runs", "runs");
        var newest = new DirectoryInfo(root).EnumerateFiles("latest.json", SearchOption.AllDirectories)
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .FirstOrDefault();
        return newest?.FullName ?? throw new FileNotFoundException($"No latest.json found below {root}");
    }

    private static Vector3 LerpVector(double[] a, double[] b, int x, int y, int z, float alpha) => new(
        Lerp(a[x], b[x], alpha),
        Lerp(a[y], b[y], alpha),
        Lerp(a[z], b[z], alpha));

    private static float Lerp(double a, double b, float alpha) => (float)(a + (b - a) * alpha);

    private static float ReadWheel(double[] a, double[] b, int index, float alpha)
    {
        if (a.Length <= index || b.Length <= index) return 0;
        return Lerp(a[index], b[index], alpha);
    }

    private static Vector3 SafeNormalize(Vector3 value, Vector3 fallback) =>
        value.LengthSquared() > 0.000001f ? Vector3.Normalize(value) : fallback;

    private Vector3 CorrectLegacyVisualOrigin(Vector3 position, Vector3 look, Vector3 up)
    {
        Vector3 side = SafeNormalize(Vector3.Cross(up, look), Vector3.UnitX);
        return position
               - side * _configuration.LegacyGraphicsOffsetX
               - up * _configuration.LegacyGraphicsOffsetY
               - look * _configuration.LegacyGraphicsOffsetZ;
    }

    private static byte EncodeSignedUnit(float value) =>
        (byte)Math.Clamp(MathF.Round(127 + Math.Clamp(value, -1, 1) * 127), 0, 254);

    private static byte EncodeWheelSpeed(float angularSpeed)
    {
        float encoded = MathF.Round(MathF.Log10(MathF.Abs(angularSpeed) + 1) * 20) * MathF.Sign(angularSpeed);
        return (byte)Math.Clamp(encoded + 100, 0, 254);
    }

    private static Vector3 ToNetworkRotation(Vector3 look, Vector3 up)
    {
        float yaw = MathF.Atan2(look.Z, look.X) - MathF.PI / 2;
        float pitch = -(MathF.Atan2(MathF.Sqrt(look.Z * look.Z + look.X * look.X), look.Y) - MathF.PI / 2);
        Vector3 side = SafeNormalize(Vector3.Cross(up, look), Vector3.UnitX);
        float roll = MathF.Atan2(Vector3.Dot(side, Vector3.UnitY), Vector3.Dot(up, Vector3.UnitY));
        return new Vector3(yaw, pitch, roll);
    }
}
