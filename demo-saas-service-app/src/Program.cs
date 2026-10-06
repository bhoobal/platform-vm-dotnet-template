// Minimal .NET service. Logs go to stdout; systemd -> syslog (local0) -> AMA -> Log Analytics.
// Keep GET /health returning 200: the deploy script and the pipeline both gate on it.
var builder = WebApplication.CreateBuilder(args);

// One line per event, easy to query in the Syslog table's SyslogMessage column.
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o =>
{
    o.SingleLine = true;
    o.TimestampFormat = null; // journald/syslog already timestamps
});

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.MapGet("/", (ILogger<Program> log) =>
{
    log.LogInformation("handled request to /");
    return Results.Ok(new
    {
        service = "demo-saas-service",
        version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev"
    });
});

app.Run();

public partial class Program { } // for WebApplicationFactory in tests
