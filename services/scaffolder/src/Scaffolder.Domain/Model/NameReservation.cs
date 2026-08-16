using Scaffolder.Domain.ValueObjects;

namespace Scaffolder.Domain.Model;

/// <summary>Lifecycle of a name reservation.</summary>
public enum ReservationStatus
{
    /// <summary>Held for an in-flight scaffold. Expires on its own if the scaffold never finishes.</summary>
    Pending,

    /// <summary>The repository exists; the name is permanently taken.</summary>
    Confirmed,

    /// <summary>Compensation released it. The name is available again.</summary>
    Released,
}

/// <summary>
/// A claim on an application name, held for one request. Uniqueness is enforced
/// by the store as a conditional write, not by reading first - see
/// <see cref="Ports.INameReservationStore"/>.
/// </summary>
public sealed record NameReservation
{
    private NameReservation(
        ApplicationName name,
        string requestId,
        ReservationStatus status,
        DateTimeOffset createdAt,
        DateTimeOffset expiresAt)
    {
        Name = name;
        RequestId = requestId;
        Status = status;
        CreatedAt = createdAt;
        ExpiresAt = expiresAt;
    }

    public ApplicationName Name { get; }

    /// <summary>The request that owns this reservation. A replay of the same request re-reserves; a different one is rejected.</summary>
    public string RequestId { get; }

    public ReservationStatus Status { get; }

    public DateTimeOffset CreatedAt { get; }

    /// <summary>DynamoDB TTL. An abandoned scaffold releases its name without anyone intervening.</summary>
    public DateTimeOffset ExpiresAt { get; }

    public static NameReservation Open(
        ApplicationName name,
        string requestId,
        DateTimeOffset now,
        TimeSpan timeToLive)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestId);

        if (timeToLive <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeToLive), timeToLive, "reservation TTL must be positive");
        }

        return new NameReservation(name, requestId, ReservationStatus.Pending, now, now.Add(timeToLive));
    }

    public static NameReservation Rehydrate(
        ApplicationName name,
        string requestId,
        ReservationStatus status,
        DateTimeOffset createdAt,
        DateTimeOffset expiresAt) => new(name, requestId, status, createdAt, expiresAt);
}
