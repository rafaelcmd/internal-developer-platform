using System.Text.Json;
using Microsoft.Extensions.Logging;
using Scaffolder.Application.ReserveName;

namespace Scaffolder.Worker;

/// <summary>
/// Maps a task name to the use case that implements it, deserializes the
/// payload and serializes the result. No business logic lives here - exactly the
/// rule the Lambda handlers followed, which is why the use cases needed no
/// changes when the runtime did.
/// </summary>
internal sealed class TaskDispatcher
{
    /// <summary>
    /// Case-insensitive on the way in, property names as declared on the way
    /// out. That is the shape the state machine passes between states, and the
    /// shape the fixtures in <c>events/</c> are written in.
    /// </summary>
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false,
    };

    private readonly Dictionary<string, Func<JsonElement, CancellationToken, Task<object>>> handlers;
    private readonly ILogger<TaskDispatcher> logger;

    public TaskDispatcher(ReserveNameUseCase reserveName, ILogger<TaskDispatcher> logger)
    {
        this.logger = logger;

        // One entry per task state in the machine. Adding a task is adding a
        // line here plus its use case - never a new deployment.
        handlers = new Dictionary<string, Func<JsonElement, CancellationToken, Task<object>>>(
            StringComparer.OrdinalIgnoreCase)
        {
            ["ReserveName"] = async (input, cancellationToken) =>
                await reserveName.ExecuteAsync(Bind<ReserveNameCommand>(input), cancellationToken),
        };
    }

    public IReadOnlyCollection<string> KnownTasks => handlers.Keys;

    /// <summary>Runs one task and returns its result as the JSON the state machine receives.</summary>
    /// <exception cref="UnknownScaffolderTaskException">No handler is registered for the task name.</exception>
    public async Task<string> DispatchAsync(TaskEnvelope envelope, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(envelope);

        if (!handlers.TryGetValue(envelope.Task, out var handler))
        {
            logger.LogError(
                "No handler for scaffold task {Task}; known tasks are {KnownTasks}",
                envelope.Task,
                string.Join(", ", KnownTasks));

            throw new UnknownScaffolderTaskException(envelope.Task);
        }

        var result = await handler(envelope.Input, cancellationToken);

        return JsonSerializer.Serialize(result, result.GetType(), Json);
    }

    private static T Bind<T>(JsonElement input) =>
        input.Deserialize<T>(Json)
        ?? throw new JsonException($"task payload deserialized to null for {typeof(T).Name}");
}
