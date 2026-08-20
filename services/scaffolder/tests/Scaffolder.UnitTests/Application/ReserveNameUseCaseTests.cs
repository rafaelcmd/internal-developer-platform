using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using Scaffolder.Application.ReserveName;
using Scaffolder.Domain.Errors;
using Scaffolder.Domain.Model;
using Scaffolder.Domain.Ports;

namespace Scaffolder.UnitTests.Application;

public sealed class ReserveNameUseCaseTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 16, 12, 0, 0, TimeSpan.Zero);

    private readonly INameReservationStore store = Substitute.For<INameReservationStore>();

    [Fact]
    public async Task Reserves_the_name_with_a_ttl_derived_from_options()
    {
        store.ReserveAsync(Arg.Any<NameReservation>(), Arg.Any<CancellationToken>())
            .Returns(ReservationOutcome.Created);

        var result = await UseCase(TimeSpan.FromHours(6))
            .ExecuteAsync(new ReserveNameCommand("payments-api", "req-1"));

        Assert.Equal("payments-api", result.ApplicationName);
        Assert.Equal("req-1", result.RequestId);
        Assert.Equal(Now.AddHours(6), result.ExpiresAt);
        Assert.False(result.AlreadyReserved);

        await store.Received(1).ReserveAsync(
            Arg.Is<NameReservation>(r =>
                r.Name.Value == "payments-api"
                && r.RequestId == "req-1"
                && r.Status == ReservationStatus.Pending),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Reports_a_replay_of_the_same_request_as_already_reserved()
    {
        store.ReserveAsync(Arg.Any<NameReservation>(), Arg.Any<CancellationToken>())
            .Returns(ReservationOutcome.AlreadyHeldByThisRequest);

        var result = await UseCase().ExecuteAsync(new ReserveNameCommand("payments-api", "req-1"));

        Assert.True(result.AlreadyReserved);
    }

    [Fact]
    public async Task Rejects_an_invalid_name_before_touching_the_store()
    {
        await Assert.ThrowsAsync<InvalidApplicationNameException>(
            () => UseCase().ExecuteAsync(new ReserveNameCommand("Payments_API", "req-1")));

        await store.DidNotReceiveWithAnyArgs().ReserveAsync(default!, default);
    }

    [Fact]
    public async Task Lets_a_conflict_from_the_store_surface_as_a_domain_error()
    {
        store.ReserveAsync(Arg.Any<NameReservation>(), Arg.Any<CancellationToken>())
            .Returns<ReservationOutcome>(_ => throw new NameAlreadyReservedException("payments-api"));

        var exception = await Assert.ThrowsAsync<NameAlreadyReservedException>(
            () => UseCase().ExecuteAsync(new ReserveNameCommand("payments-api", "req-2")));

        Assert.Equal("NAME_ALREADY_RESERVED", exception.Code);
    }

    private ReserveNameUseCase UseCase(TimeSpan? ttl = null) => new(
        store,
        new FixedTimeProvider(Now),
        new ReserveNameOptions(ttl ?? TimeSpan.FromHours(1)),
        NullLogger<ReserveNameUseCase>.Instance);

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
