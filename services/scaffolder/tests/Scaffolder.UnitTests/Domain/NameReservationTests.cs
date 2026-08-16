using Scaffolder.Domain.Model;
using Scaffolder.Domain.ValueObjects;

namespace Scaffolder.UnitTests.Domain;

public sealed class NameReservationTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 16, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Opens_pending_and_expiring_after_the_ttl()
    {
        var reservation = NameReservation.Open(
            ApplicationName.Parse("payments-api"),
            "req-1",
            Now,
            TimeSpan.FromHours(6));

        Assert.Equal(ReservationStatus.Pending, reservation.Status);
        Assert.Equal(Now, reservation.CreatedAt);
        Assert.Equal(Now.AddHours(6), reservation.ExpiresAt);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Requires_a_request_id(string requestId) =>
        Assert.Throws<ArgumentException>(() => NameReservation.Open(
            ApplicationName.Parse("payments-api"), requestId, Now, TimeSpan.FromHours(1)));

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Requires_a_positive_ttl(int hours) =>
        Assert.Throws<ArgumentOutOfRangeException>(() => NameReservation.Open(
            ApplicationName.Parse("payments-api"), "req-1", Now, TimeSpan.FromHours(hours)));
}
