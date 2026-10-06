# Demo SaaS Service

A minimal ASP.NET Core service targeting .NET 8. It exposes a health endpoint and writes a sample application log to the console when the root endpoint is requested.

## Prerequisites

- .NET 8 SDK

Run the following commands from this directory (`demo-saas-service-app`).

Confirm that the .NET 8 SDK is available with `dotnet --list-sdks`. If multiple .NET installations are present on macOS and `dotnet` selects the wrong one, use the .NET 8 executable directly. For the Microsoft PKG installer, its path is typically `/usr/local/share/dotnet/dotnet`.

## Build

```bash
dotnet build src/SaasService.csproj
```

## Run unit tests

```bash
dotnet test tests/SaasService.Tests.csproj
```

## Run the service

```bash
dotnet run --project src/SaasService.csproj
```

The app prints its listening address in the terminal. In another terminal, use that address for the requests below. By default, it is typically `http://localhost:5000`.

## Check service health

Open `http://localhost:5000/health` in a browser, or run:

```bash
curl -i http://localhost:5000/health
```

The endpoint responds with HTTP 200 and:

```json
{"status":"healthy"}
```

## View sample logs

The service writes logs to standard output; it does not create log files by itself. The `/health` route does not emit an application log. Request `/` to generate the sample log:

```bash
curl http://localhost:5000/
```

To save console output to a local sample log file, start the service with:

```bash
dotnet run --project src/SaasService.csproj 2>&1 | tee sample.log
```

Then, from another terminal, request `/` and inspect the captured output:

```bash
curl http://localhost:5000/
tail -f sample.log
```

The sample application log resembles:

```text
info: Program[0] handled request to /
```

On the deployed Linux VM, systemd stores the service's console output in the journal. Follow new entries with:

```bash
sudo journalctl -u app.service -f
```

View recent entries with:

```bash
sudo journalctl -u app.service -n 50 --no-pager
```