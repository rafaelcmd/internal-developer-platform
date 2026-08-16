namespace Scaffolder.Functions;

/// <summary>
/// Per-invocation snapshot of the execution context this handler is running in.
/// </summary>
/// <param name="InstanceId">Identifies one execution context (one "warm container").</param>
/// <param name="InvocationNumber">1 on the invocation that paid for the cold start, then 2, 3, ...</param>
/// <param name="ContextAge">How long this execution context has been alive.</param>
public readonly record struct InvocationInfo(Guid InstanceId, int InvocationNumber, TimeSpan ContextAge)
{
    public bool IsColdStart => InvocationNumber == 1;
}

/// <summary>
/// Static counters proving execution-context reuse. Static state survives across
/// invocations that land on the same context and resets when Lambda creates a
/// new one - which is exactly why handler code must never keep request state in
/// a static field, and exactly what makes a static counter a reliable probe.
/// </summary>
internal static class ExecutionContextTelemetry
{
    private static readonly Guid Instance = Guid.NewGuid();
    private static readonly DateTimeOffset InitializedAt = DateTimeOffset.UtcNow;
    private static int invocations;

    public static InvocationInfo Record() => new(
        Instance,
        Interlocked.Increment(ref invocations),
        DateTimeOffset.UtcNow - InitializedAt);
}
