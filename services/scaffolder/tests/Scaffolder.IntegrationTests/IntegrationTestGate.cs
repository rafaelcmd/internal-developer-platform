namespace Scaffolder.IntegrationTests;

/// <summary>
/// Adapter tests run against LocalStack and the sandbox GitHub org, so they need
/// Docker and credentials that CI does not always have. They are opt-in: set
/// <c>SCAFFOLDER_INTEGRATION=1</c> (or run <c>make test-integration</c>) to
/// enable them, otherwise xUnit reports them as skipped rather than failed.
/// </summary>
public static class IntegrationTestGate
{
    public const string EnvironmentVariable = "SCAFFOLDER_INTEGRATION";

    public static bool Enabled =>
        Environment.GetEnvironmentVariable(EnvironmentVariable) is "1" or "true";

    /// <summary>Skip reason for a fact, or <c>null</c> when the suite is enabled.</summary>
    public static string? SkipUnlessEnabled =>
        Enabled ? null : $"set {EnvironmentVariable}=1 to run adapter tests against LocalStack";
}

public sealed class IntegrationTestGateTests
{
    [Fact]
    public void Suite_is_opt_in_by_default() =>
        Assert.Equal(IntegrationTestGate.Enabled, IntegrationTestGate.SkipUnlessEnabled is null);
}
