using System.Diagnostics;

namespace Scaffolder.Worker;

/// <summary>
/// The worker's own trace source. One span per task keeps a scaffold visible as
/// part of the request that started it: the state machine propagates W3C trace
/// context, so these spans join the trace the Go API opened rather than starting
/// a new one.
/// </summary>
internal static class ScaffolderTelemetry
{
    public const string ActivitySourceName = "Scaffolder.Worker";

    public static readonly ActivitySource ActivitySource = new(ActivitySourceName);
}
