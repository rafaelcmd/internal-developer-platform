using Microsoft.Extensions.Logging;
using Scaffolder.Domain.Model;
using Scaffolder.Domain.Ports;
using Scaffolder.Domain.ValueObjects;

namespace Scaffolder.Application.ReserveName;

/// <summary>
/// First task of the scaffold state machine: claim the application name before
/// anything is created, so a duplicate request fails here rather than after a
/// GitHub repository already exists.
/// </summary>
public sealed class ReserveNameUseCase(
    INameReservationStore store,
    TimeProvider timeProvider,
    ReserveNameOptions options,
    ILogger<ReserveNameUseCase> logger)
{
    public async Task<ReserveNameResult> ExecuteAsync(
        ReserveNameCommand command,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        var name = ApplicationName.Parse(command.ApplicationName);
        var reservation = NameReservation.Open(
            name,
            command.RequestId,
            timeProvider.GetUtcNow(),
            options.ReservationTtl);

        var outcome = await store.ReserveAsync(reservation, cancellationToken);

        logger.LogInformation(
            "Reserved name {ApplicationName} for request {RequestId} ({Outcome}), expires {ExpiresAt:O}",
            name.Value,
            reservation.RequestId,
            outcome,
            reservation.ExpiresAt);

        return new ReserveNameResult(
            name.Value,
            reservation.RequestId,
            reservation.ExpiresAt,
            outcome is ReservationOutcome.AlreadyHeldByThisRequest);
    }
}
