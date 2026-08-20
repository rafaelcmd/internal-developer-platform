using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using Scaffolder.Application.ReserveName;
using Scaffolder.Domain.Errors;
using Scaffolder.Domain.Model;
using Scaffolder.Domain.Ports;
using Scaffolder.Worker;

namespace Scaffolder.UnitTests.Worker;

/// <summary>
/// Dispatcher-level checks that need no queue, no AWS and no Step Functions.
/// They exist mainly to keep the entry point thin - if these ever need elaborate
/// setup, logic has leaked out of a use case and into the worker.
/// </summary>
public sealed class TaskDispatcherTests
{
    private readonly INameReservationStore store = Substitute.For<INameReservationStore>();

    [Fact]
    public async Task Binds_the_payload_to_the_command_and_returns_the_use_case_result_as_json()
    {
        store.ReserveAsync(Arg.Any<NameReservation>(), Arg.Any<CancellationToken>())
            .Returns(ReservationOutcome.Created);

        var output = await Dispatcher().DispatchAsync(Envelope("ReserveName", """
            { "ApplicationName": "payments-api", "RequestId": "req-1" }
            """), CancellationToken.None);

        var result = JsonSerializer.Deserialize<ReserveNameResult>(output, TaskDispatcher.Json)!;

        Assert.Equal("payments-api", result.ApplicationName);
        Assert.Equal("req-1", result.RequestId);
        Assert.False(result.AlreadyReserved);
    }

    [Fact]
    public async Task Task_names_are_matched_case_insensitively()
    {
        store.ReserveAsync(Arg.Any<NameReservation>(), Arg.Any<CancellationToken>())
            .Returns(ReservationOutcome.Created);

        var output = await Dispatcher().DispatchAsync(Envelope("reservename", """
            { "applicationName": "payments-api", "requestId": "req-1" }
            """), CancellationToken.None);

        Assert.Contains("payments-api", output, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Unknown_task_names_are_rejected_rather_than_silently_dropped()
    {
        var exception = await Assert.ThrowsAsync<UnknownScaffolderTaskException>(
            () => Dispatcher().DispatchAsync(Envelope("CreateRepository", "{}"), CancellationToken.None));

        Assert.Equal("CreateRepository", exception.Task);
    }

    [Fact]
    public async Task Domain_errors_propagate_so_the_worker_can_report_them_as_task_failures()
    {
        // The worker turns a ScaffolderException into SendTaskFailure with the
        // domain's own Code. The dispatcher must not swallow or rewrap it.
        var exception = await Assert.ThrowsAsync<InvalidApplicationNameException>(
            () => Dispatcher().DispatchAsync(Envelope("ReserveName", """
                { "ApplicationName": "Payments_API", "RequestId": "req-1" }
                """), CancellationToken.None));

        Assert.Equal("INVALID_APPLICATION_NAME", exception.Code);
    }

    [Fact]
    public void Every_registered_task_is_a_state_in_the_scaffold_machine()
    {
        // Guards against a handler being registered under a name no state ever
        // sends, which would look wired up and never run.
        Assert.Equal(new[] { "ReserveName" }, Dispatcher().KnownTasks.Order().ToArray());
    }

    private static TaskEnvelope Envelope(string task, string input) => new()
    {
        Task = task,
        TaskToken = "token-1",
        Input = JsonDocument.Parse(input).RootElement.Clone(),
    };

    private TaskDispatcher Dispatcher()
    {
        var useCase = new ReserveNameUseCase(
            store,
            TimeProvider.System,
            ReserveNameOptions.Default,
            NullLogger<ReserveNameUseCase>.Instance);

        return new TaskDispatcher(useCase, NullLogger<TaskDispatcher>.Instance);
    }
}
