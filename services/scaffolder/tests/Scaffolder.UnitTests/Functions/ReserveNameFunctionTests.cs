using Amazon.Lambda.TestUtilities;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using Scaffolder.Application.ReserveName;
using Scaffolder.Domain.Model;
using Scaffolder.Domain.Ports;
using Scaffolder.Functions;

namespace Scaffolder.UnitTests.Functions;

/// <summary>
/// Handler-level checks that need no Lambda runtime. They exist mainly to keep
/// the handler thin - if these ever need elaborate setup, logic has leaked out
/// of the use case and into the entry point.
/// </summary>
public sealed class ReserveNameFunctionTests
{
    private readonly INameReservationStore store = Substitute.For<INameReservationStore>();

    [Fact]
    public async Task Passes_the_payload_through_to_the_use_case_and_returns_its_result()
    {
        store.ReserveAsync(Arg.Any<NameReservation>(), Arg.Any<CancellationToken>())
            .Returns(ReservationOutcome.Created);

        var result = await Function().HandleAsync(
            new ReserveNameCommand("payments-api", "req-1"),
            new TestLambdaContext { AwsRequestId = "aws-req-1", MemoryLimitInMB = 512 });

        Assert.Equal("payments-api", result.ApplicationName);
        Assert.Equal("req-1", result.RequestId);
    }

    [Fact]
    public void Execution_context_telemetry_counts_invocations_on_one_context()
    {
        var first = ExecutionContextTelemetry.Record();
        var second = ExecutionContextTelemetry.Record();

        // Same static state, so the same instance id and a rising counter. On
        // Lambda this is what distinguishes a warm invocation from a cold one.
        Assert.Equal(first.InstanceId, second.InstanceId);
        Assert.Equal(first.InvocationNumber + 1, second.InvocationNumber);
    }

    private ReserveNameFunction Function()
    {
        var useCase = new ReserveNameUseCase(
            store,
            TimeProvider.System,
            ReserveNameOptions.Default,
            NullLogger<ReserveNameUseCase>.Instance);

        return new ReserveNameFunction(useCase, NullLogger<ReserveNameFunction>.Instance);
    }
}
