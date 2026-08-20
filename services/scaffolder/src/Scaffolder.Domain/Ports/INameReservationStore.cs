using Scaffolder.Domain.Errors;
using Scaffolder.Domain.Model;

namespace Scaffolder.Domain.Ports;

/// <summary>What happened when a reservation was attempted.</summary>
public enum ReservationOutcome
{
    /// <summary>No reservation existed; this request now holds the name.</summary>
    Created,

    /// <summary>This same request already held it. A retry, not a conflict - the call is a no-op.</summary>
    AlreadyHeldByThisRequest,
}

/// <summary>
/// Persists name reservations. Implementations must make the reservation a
/// single atomic conditional write - never read-then-write, which races with a
/// concurrent request for the same name.
/// </summary>
public interface INameReservationStore
{
    /// <summary>
    /// Claims <paramref name="reservation"/>'s name for its request.
    /// </summary>
    /// <exception cref="NameAlreadyReservedException">A different request already holds the name.</exception>
    Task<ReservationOutcome> ReserveAsync(NameReservation reservation, CancellationToken cancellationToken = default);
}
