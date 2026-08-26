using System.Net;
using Microsoft.AspNetCore.Mvc;

namespace RandomLeadServerPlugin;

[ApiController]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class RandomLeadController : ControllerBase
{
    private readonly RandomLeadServer _randomLeadServer;

    public RandomLeadController(RandomLeadServer randomLeadServer) => _randomLeadServer = randomLeadServer;

    [HttpGet("/api/random-lead/status")]
    public ActionResult<PlaybackStatus> Status()
    {
        if (!IsLoopback()) return Forbid();
        return _randomLeadServer.GetStatus();
    }

    [HttpPost("/api/random-lead/command/{command}")]
    public ActionResult<PlaybackStatus> Command(string command)
    {
        if (!IsLoopback()) return Forbid();
        if (!_randomLeadServer.QueueCommand(command, out string error)) return BadRequest(error);
        return Accepted(_randomLeadServer.GetStatus());
    }

    private bool IsLoopback()
    {
        IPAddress? address = HttpContext.Connection.RemoteIpAddress;
        return address != null && IPAddress.IsLoopback(address);
    }
}
