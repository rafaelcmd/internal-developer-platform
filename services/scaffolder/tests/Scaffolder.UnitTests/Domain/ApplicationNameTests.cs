using Scaffolder.Domain.Errors;
using Scaffolder.Domain.ValueObjects;

namespace Scaffolder.UnitTests.Domain;

public sealed class ApplicationNameTests
{
    [Theory]
    [InlineData("payments-api")]
    [InlineData("abc")]
    [InlineData("checkout-service-v2")]
    [InlineData("a1b2c3")]
    public void Accepts_names_valid_as_repo_service_and_dns_label(string raw) =>
        Assert.Equal(raw, ApplicationName.Parse(raw).Value);

    [Fact]
    public void Trims_surrounding_whitespace() =>
        Assert.Equal("payments-api", ApplicationName.Parse("  payments-api  ").Value);

    [Theory]
    [InlineData(null, "null")]
    [InlineData("", "empty")]
    [InlineData("   ", "whitespace only")]
    [InlineData("ab", "shorter than the minimum")]
    [InlineData("Payments-API", "uppercase")]
    [InlineData("payments_api", "underscore")]
    [InlineData("1payments", "leading digit")]
    [InlineData("-payments", "leading hyphen")]
    [InlineData("payments-", "trailing hyphen")]
    [InlineData("payments--api", "doubled hyphen")]
    [InlineData("payments.api", "dot")]
    public void Rejects_unusable_names(string? raw, string why)
    {
        var exception = Assert.Throws<InvalidApplicationNameException>(() => ApplicationName.Parse(raw));

        Assert.Equal("INVALID_APPLICATION_NAME", exception.Code);
        Assert.False(string.IsNullOrEmpty(why));
    }

    [Fact]
    public void Rejects_names_longer_than_the_maximum() =>
        Assert.Throws<InvalidApplicationNameException>(
            () => ApplicationName.Parse(new string('a', ApplicationName.MaxLength + 1)));

    [Fact]
    public void TryParse_reports_failure_without_throwing()
    {
        Assert.False(ApplicationName.TryParse("Not Valid", out var name));
        Assert.Null(name);
    }

    [Fact]
    public void Equality_is_by_value() =>
        Assert.Equal(ApplicationName.Parse("payments-api"), ApplicationName.Parse("payments-api"));
}
