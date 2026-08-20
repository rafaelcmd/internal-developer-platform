using Amazon.SQS;
using Amazon.StepFunctions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Scaffolder.Application.ReserveName;
using Scaffolder.Infrastructure;
using Scaffolder.Infrastructure.Configuration;
using Scaffolder.Worker;

// Amazon.StepFunctions also defines a LogLevel (the state machine's own logging
// configuration). Alias so the logging builder below reads unambiguously.
using LogLevel = Microsoft.Extensions.Logging.LogLevel;

// Composition root. Configuration is read first and validated on the spot, so a
// missing table name or queue URL fails the process at startup - visible as a
// CrashLoopBackOff - instead of surfacing as a null reference on the first task.
var options = ScaffolderOptions.FromEnvironment();

var builder = Host.CreateApplicationBuilder(args);

// stdout as single-line JSON: the Collector ships it, and it matches the shape
// the Go services log in, so one Datadog query spans all three.
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(console =>
{
    console.IncludeScopes = true;
    console.JsonWriterOptions = new System.Text.Json.JsonWriterOptions { Indented = false };
});
builder.Logging.SetMinimumLevel(LogLevel.Information);

builder.Services.AddScaffolderInfrastructure(options);

// AWS clients are singletons so credentials and TLS connections are established
// once and reused for the life of the pod, not per message. Region and
// credentials come from the environment: IRSA in-cluster, LocalStack locally.
builder.Services.AddSingleton<IAmazonSQS>(_ => new AmazonSQSClient());
builder.Services.AddSingleton<IAmazonStepFunctions>(_ => new AmazonStepFunctionsClient());

builder.Services.AddSingleton(new ReserveNameOptions(options.ReservationTtl));
builder.Services.AddSingleton<ReserveNameUseCase>();
builder.Services.AddSingleton<TaskDispatcher>();
builder.Services.AddHostedService<TaskQueueWorker>();

// Telemetry is opt-in on the endpoint being set, so a local run stays quiet
// instead of retrying an exporter that has nowhere to go. In-cluster the
// Deployment always sets it.
if (options.OtlpEndpoint is not null)
{
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(resource => resource
            .AddService(options.ServiceName, serviceVersion: options.ServiceVersion)
            .AddAttributes([new KeyValuePair<string, object>("deployment.environment", options.Environment)]))
        .WithTracing(tracing => tracing
            .AddSource(ScaffolderTelemetry.ActivitySourceName)
            // Instruments the SDK calls themselves, so a slow DynamoDB write
            // shows as its own span rather than unexplained time in the task.
            .AddAWSInstrumentation()
            .AddOtlpExporter())
        .WithMetrics(metrics => metrics
            .AddRuntimeInstrumentation()
            .AddOtlpExporter());
}

await builder.Build().RunAsync();
