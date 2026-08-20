using System.Text.Json;

namespace Scaffolder.Worker;

/// <summary>
/// The message the scaffold state machine puts on the task queue for a
/// <c>.waitForTaskToken</c> task.
/// <para>
/// The state supplies <c>TaskToken.$: $$.Task.Token</c> and its own payload, so
/// one queue and one worker serve every task in the machine - the task name is
/// data, not a separate endpoint. <see cref="Input"/> stays as raw JSON because
/// only the dispatcher knows which command type a given task binds to.
/// </para>
/// </summary>
internal sealed record TaskEnvelope
{
    /// <summary>Which state machine task this is, e.g. <c>ReserveName</c>.</summary>
    public required string Task { get; init; }

    /// <summary>Callback token. Without it there is nothing to report back to.</summary>
    public required string TaskToken { get; init; }

    /// <summary>The task's own payload, deserialized by the dispatcher.</summary>
    public JsonElement Input { get; init; }
}

/// <summary>
/// The queue carried a task name this build does not implement. Reported to
/// Step Functions as a task failure rather than retried: redelivering it cannot
/// make an unknown name known, and the execution should fail visibly instead of
/// waiting out its timeout.
/// </summary>
internal sealed class UnknownScaffolderTaskException(string task)
    : Exception($"no handler is registered for scaffold task '{task}'")
{
    public string Task { get; } = task;
}
