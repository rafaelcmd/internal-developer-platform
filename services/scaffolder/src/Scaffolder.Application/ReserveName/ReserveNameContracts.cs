namespace Scaffolder.Application.ReserveName;

/// <summary>Input to the <c>ReserveName</c> state machine task.</summary>
/// <param name="ApplicationName">Raw, unvalidated name as the developer typed it.</param>
/// <param name="RequestId">Correlation id of the provisioning request. Replays reuse it.</param>
public sealed record ReserveNameCommand(string ApplicationName, string RequestId);

/// <summary>Output of the <c>ReserveName</c> task, passed to the next state.</summary>
/// <param name="AlreadyReserved">
/// True when this same request had already reserved the name - a Step Functions
/// retry, handled as a no-op rather than an error.
/// </param>
public sealed record ReserveNameResult(
    string ApplicationName,
    string RequestId,
    DateTimeOffset ExpiresAt,
    bool AlreadyReserved);

/// <summary>Tunables for the use case, bound from environment variables by the composition root.</summary>
/// <param name="ReservationTtl">
/// How long an unfinished scaffold keeps its name. Long enough to outlive a slow
/// Terraform run, short enough that an abandoned request frees the name the same day.
/// </param>
public sealed record ReserveNameOptions(TimeSpan ReservationTtl)
{
    public static readonly ReserveNameOptions Default = new(TimeSpan.FromHours(6));
}
