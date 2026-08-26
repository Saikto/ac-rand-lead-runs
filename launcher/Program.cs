using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;

const string launcherUrl = "http://127.0.0.1:32123";
var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls(launcherUrl);
builder.Services.AddSingleton<LauncherService>();

var app = builder.Build();
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/catalog", (LauncherService service) => service.GetCatalog());
app.MapGet("/api/settings", (LauncherService service) => service.GetSettings());
app.MapPut("/api/settings", (LauncherSettings settings, LauncherService service) =>
{
    try
    {
        service.SaveSettings(settings);
        return Results.Ok(settings);
    }
    catch (Exception exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
});
app.MapPost("/api/server/start", (LauncherSettings settings, LauncherService service) =>
{
    try
    {
        service.StartServer(settings);
        return Results.Accepted(value: service.GetServerStatus());
    }
    catch (Exception exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
});
app.MapPost("/api/server/stop", async (LauncherService service) =>
{
    await service.StopServerAsync();
    return Results.Ok(service.GetServerStatus());
});
app.MapGet("/api/server/status", (LauncherService service) => service.GetServerStatus());
app.MapFallbackToFile("index.html");

await app.StartAsync();
if (!args.Contains("--no-browser", StringComparer.OrdinalIgnoreCase))
{
    try
    {
        Process.Start(new ProcessStartInfo(launcherUrl) { UseShellExecute = true });
    }
    catch (Exception exception)
    {
        app.Logger.LogWarning(exception, "Could not open the launcher browser automatically");
    }
}
await app.WaitForShutdownAsync();

public sealed class LauncherService : IDisposable
{
    private readonly object _sync = new();
    private readonly ConcurrentQueue<string> _log = new();
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly string _repoRoot;
    private readonly string _assettoCorsaRoot;
    private readonly string _runsRoot;
    private readonly string _settingsPath;
    private Process? _serverProcess;
    private LauncherCatalog? _catalog;
    private bool _ready;
    private bool _stopping;
    private string _lastError = "";

    public LauncherService(IWebHostEnvironment environment)
    {
        _repoRoot = FindRepoRoot(environment.ContentRootPath);
        _assettoCorsaRoot = @"N:\SteamLibrary\steamapps\common\assettocorsa";
        _runsRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "Assetto Corsa", "ac-random-lead-runs", "runs");
        _settingsPath = Path.Combine(_repoRoot, ".runtime", "launcher", "settings.json");
    }

    public LauncherCatalog GetCatalog()
    {
        lock (_sync)
        {
            if (_catalog != null) return _catalog;
        }
        var runs = ScanRuns();
        var cars = ScanCars();
        var weather = Directory.Exists(Path.Combine(_assettoCorsaRoot, "content", "weather"))
            ? Directory.EnumerateDirectories(Path.Combine(_assettoCorsaRoot, "content", "weather"))
                .Select(Path.GetFileName).Where(value => !string.IsNullOrWhiteSpace(value))
                .Cast<string>().OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray()
            : [];
        var catalog = new LauncherCatalog(runs, cars, weather);
        lock (_sync) _catalog ??= catalog;
        return _catalog;
    }

    public LauncherSettings GetSettings()
    {
        LauncherSettings? settings = null;
        if (File.Exists(_settingsPath))
        {
            try { settings = JsonSerializer.Deserialize<LauncherSettings>(File.ReadAllText(_settingsPath), _jsonOptions); }
            catch { /* A damaged launcher profile falls back to discovered defaults. */ }
        }
        settings ??= new LauncherSettings();
        var catalog = GetCatalog();
        if (string.IsNullOrWhiteSpace(settings.RunFile) || !File.Exists(settings.RunFile))
            settings.RunFile = catalog.Runs.FirstOrDefault()?.Path ?? "";
        RunCatalogItem? run = catalog.Runs.FirstOrDefault(item => PathEquals(item.Path, settings.RunFile));
        if (string.IsNullOrWhiteSpace(settings.PlayerCar)) settings.PlayerCar = run?.Car ?? catalog.Cars.FirstOrDefault()?.Id ?? "";
        CarCatalogItem? car = catalog.Cars.FirstOrDefault(item =>
            string.Equals(item.Id, settings.PlayerCar, StringComparison.OrdinalIgnoreCase));
        if (car == null && catalog.Cars.Length > 0)
        {
            car = catalog.Cars[0];
            settings.PlayerCar = car.Id;
        }
        else if (car != null)
        {
            settings.PlayerCar = car.Id;
        }
        if (car != null && !car.Skins.Contains(settings.PlayerSkin, StringComparer.OrdinalIgnoreCase))
            settings.PlayerSkin = car.Skins.FirstOrDefault() ?? "";
        if (!catalog.Weather.Contains(settings.Weather, StringComparer.OrdinalIgnoreCase))
            settings.Weather = catalog.Weather.FirstOrDefault(value => value == "3_clear") ?? catalog.Weather.FirstOrDefault() ?? "3_clear";
        return settings;
    }

    public void SaveSettings(LauncherSettings settings)
    {
        ValidateSettings(settings);
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
        File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, _jsonOptions));
    }

    public void StartServer(LauncherSettings settings)
    {
        lock (_sync)
        {
            if (_serverProcess is { HasExited: false }) throw new InvalidOperationException("The launcher server is already running");
            SaveSettings(settings);
            _ready = false;
            _stopping = false;
            _lastError = "";
            while (_log.TryDequeue(out _)) { }
            AppendLog("Launcher: preparing localhost server…");

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                WorkingDirectory = _repoRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(Path.Combine(_repoRoot, "tools", "start-localhost-test.ps1"));
            startInfo.ArgumentList.Add("-LauncherSettingsPath");
            startInfo.ArgumentList.Add(_settingsPath);
            startInfo.ArgumentList.Add("-RuntimePath");
            startInfo.ArgumentList.Add(Path.Combine(_repoRoot, ".runtime", "launcher-server"));

            _serverProcess = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            _serverProcess.OutputDataReceived += (_, eventArgs) => HandleOutput(eventArgs.Data, false);
            _serverProcess.ErrorDataReceived += (_, eventArgs) => HandleOutput(eventArgs.Data, true);
            _serverProcess.Exited += (_, _) =>
            {
                if (!_stopping && string.IsNullOrWhiteSpace(_lastError))
                    _lastError = _ready ? "Server process exited unexpectedly" : "Server process exited before becoming ready";
                AppendLog($"Launcher: server process exited with code {_serverProcess?.ExitCode}");
            };
            if (!_serverProcess.Start()) throw new InvalidOperationException("Could not start PowerShell server process");
            _serverProcess.BeginOutputReadLine();
            _serverProcess.BeginErrorReadLine();
        }
    }

    public async Task StopServerAsync()
    {
        Process? process;
        lock (_sync) process = _serverProcess;
        if (process is { HasExited: false })
        {
            _stopping = true;
            AppendLog("Launcher: stopping server…");
            process.Kill(true);
            await process.WaitForExitAsync();
        }
        lock (_sync)
        {
            _ready = false;
            _stopping = false;
            _serverProcess = null;
        }
    }

    public ServerProcessStatus GetServerStatus()
    {
        lock (_sync)
        {
            bool running = _serverProcess is { HasExited: false };
            var settings = GetSettings();
            return new ServerProcessStatus(
                running ? (_ready ? "ready" : "starting") : (string.IsNullOrWhiteSpace(_lastError) ? "stopped" : "error"),
                running, _ready, _lastError, _log.ToArray(), settings.TcpPort, settings.HttpPort,
                $"https://acstuff.club/s/q:race/online/join?ip=127.0.0.1&httpPort={settings.HttpPort}");
        }
    }

    private RunCatalogItem[] ScanRuns()
    {
        if (!Directory.Exists(_runsRoot)) return [];
        var runs = new Dictionary<string, RunCatalogItem>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in Directory.EnumerateFiles(_runsRoot, "*.json", SearchOption.AllDirectories))
        {
            try
            {
                using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path), new JsonDocumentOptions { AllowTrailingCommas = true });
                JsonElement root = document.RootElement;
                int version = root.GetProperty("version").GetInt32();
                if (version is not (1 or 2 or 3) || root.GetProperty("frames").GetArrayLength() < 2) continue;
                string id = root.GetProperty("id").GetString() ?? Path.GetFileNameWithoutExtension(path);
                string track = root.GetProperty("track").GetString() ?? "";
                string layout = root.GetProperty("layout").GetString() ?? "-";
                string car = root.GetProperty("car").GetString() ?? "";
                double duration = root.GetProperty("duration").GetDouble();
                string? createdAt = root.TryGetProperty("createdAt", out JsonElement created) ? created.GetString() : null;
                var item = new RunCatalogItem(Path.GetFullPath(path), id, track, layout, car, duration, createdAt,
                    GetTrackName(track, layout), GetCarName(car));
                bool isLatest = Path.GetFileName(path).Equals("latest.json", StringComparison.OrdinalIgnoreCase);
                if (!runs.TryGetValue(id, out RunCatalogItem? existing) ||
                    Path.GetFileName(existing.Path).Equals("latest.json", StringComparison.OrdinalIgnoreCase) && !isLatest)
                    runs[id] = item;
            }
            catch { /* Invalid recordings are reported by the server and omitted from the launcher catalog. */ }
        }
        return runs.Values.OrderByDescending(item => item.CreatedAt ?? "").ThenByDescending(item => item.Id).ToArray();
    }

    private CarCatalogItem[] ScanCars()
    {
        string root = Path.Combine(_assettoCorsaRoot, "content", "cars");
        if (!Directory.Exists(root)) return [];
        var cars = new List<CarCatalogItem>();
        foreach (string path in Directory.EnumerateDirectories(root))
        {
            string id = Path.GetFileName(path);
            string[] skins = Directory.Exists(Path.Combine(path, "skins"))
                ? Directory.EnumerateDirectories(Path.Combine(path, "skins")).Select(Path.GetFileName)
                    .Where(value => !string.IsNullOrWhiteSpace(value)).Cast<string>()
                    .OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray()
                : [];
            if (skins.Length > 0) cars.Add(new CarCatalogItem(id, GetCarName(id), skins));
        }
        return cars.OrderBy(car => car.Name, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private string GetTrackName(string track, string layout)
    {
        string trackRoot = Path.Combine(_assettoCorsaRoot, "content", "tracks", track);
        string[] candidates =
        [
            Path.Combine(trackRoot, "ui", layout, "ui_track.json"),
            Path.Combine(trackRoot, "ui", "ui_track.json")
        ];
        return ReadJsonName(candidates) ?? $"{track} / {layout}";
    }

    private string GetCarName(string car)
    {
        string path = Path.Combine(_assettoCorsaRoot, "content", "cars", car, "ui", "ui_car.json");
        return ReadJsonName([path]) ?? car;
    }

    private static string? ReadJsonName(IEnumerable<string> candidates)
    {
        foreach (string path in candidates)
        {
            try
            {
                if (!File.Exists(path)) continue;
                using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path), new JsonDocumentOptions { AllowTrailingCommas = true });
                if (document.RootElement.TryGetProperty("name", out JsonElement name)) return name.GetString();
            }
            catch { }
        }
        return null;
    }

    private void ValidateSettings(LauncherSettings settings)
    {
        string fullRunPath = Path.GetFullPath(settings.RunFile ?? "");
        string relative = Path.GetRelativePath(_runsRoot, fullRunPath);
        if (relative.StartsWith(".." + Path.DirectorySeparatorChar) || Path.IsPathRooted(relative) || !File.Exists(fullRunPath))
            throw new InvalidOperationException("Select a valid recording from the run library");
        string playerCarRoot = Path.Combine(_assettoCorsaRoot, "content", "cars", settings.PlayerCar ?? "");
        if (!Directory.Exists(playerCarRoot)) throw new InvalidOperationException("Select an installed player car");
        if (!Directory.Exists(Path.Combine(playerCarRoot, "skins", settings.PlayerSkin ?? "")))
            throw new InvalidOperationException("Select an installed skin for the player car");
        if (!Directory.Exists(Path.Combine(_assettoCorsaRoot, "content", "weather", settings.Weather ?? "")))
            throw new InvalidOperationException("Select an installed weather preset");
        if (settings.AmbientTemperature is < -20 or > 50 || settings.RoadTemperature is < -20 or > 80)
            throw new InvalidOperationException("Temperature is outside the supported range");
        if (settings.SunAngle is < -80 or > 80 || settings.StartDelaySeconds is < 0 or > 60 || settings.LoopDelaySeconds is < 0 or > 60)
            throw new InvalidOperationException("Sun angle or playback delay is outside the supported range");
        if (settings.TcpPort is < 1024 or > 65535 || settings.HttpPort is < 1024 or > 65535 || settings.TcpPort == settings.HttpPort)
            throw new InvalidOperationException("TCP and HTTP ports must be distinct values between 1024 and 65535");
    }

    private void HandleOutput(string? line, bool error)
    {
        if (string.IsNullOrWhiteSpace(line)) return;
        AppendLog(line);
        if (line.Contains("Server startup completed", StringComparison.OrdinalIgnoreCase)) _ready = true;
        if (error && (line.Contains("Exception", StringComparison.OrdinalIgnoreCase) || line.Contains("error", StringComparison.OrdinalIgnoreCase)))
            _lastError = line;
    }

    private void AppendLog(string line)
    {
        _log.Enqueue(line);
        while (_log.Count > 500) _log.TryDequeue(out _);
    }

    private static bool PathEquals(string a, string b) => string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);

    private static string FindRepoRoot(string start)
    {
        DirectoryInfo? current = new(start);
        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, "tools", "start-localhost-test.ps1"))) return current.FullName;
            current = current.Parent;
        }
        throw new DirectoryNotFoundException("Could not locate AC Random Lead Runs repository root");
    }

    public void Dispose()
    {
        if (_serverProcess is { HasExited: false }) _serverProcess.Kill(true);
        _serverProcess?.Dispose();
    }
}

public sealed class LauncherSettings
{
    public string ServerName { get; set; } = "AC Random Lead Runs (localhost)";
    public string RunFile { get; set; } = "";
    public string PlayerCar { get; set; } = "";
    public string PlayerSkin { get; set; } = "";
    public string Weather { get; set; } = "3_clear";
    public int AmbientTemperature { get; set; } = 18;
    public int RoadTemperature { get; set; } = 24;
    public double SunAngle { get; set; } = 6;
    public double StartDelaySeconds { get; set; } = 5;
    public bool Loop { get; set; } = true;
    public double LoopDelaySeconds { get; set; } = 3;
    public int TcpPort { get; set; } = 9600;
    public int HttpPort { get; set; } = 8081;
}

public sealed record LauncherCatalog(RunCatalogItem[] Runs, CarCatalogItem[] Cars, string[] Weather);
public sealed record RunCatalogItem(string Path, string Id, string Track, string Layout, string Car, double Duration,
    string? CreatedAt, string TrackName, string CarName);
public sealed record CarCatalogItem(string Id, string Name, string[] Skins);
public sealed record ServerProcessStatus(string State, bool Running, bool Ready, string Error, string[] Log,
    int TcpPort, int HttpPort, string ConnectUrl);
