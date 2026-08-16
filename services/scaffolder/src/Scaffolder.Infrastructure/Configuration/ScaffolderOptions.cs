namespace Scaffolder.Infrastructure.Configuration;

/// <summary>
/// Everything this service reads from its environment. SAM sets these per
/// function; there is deliberately no config file.
/// </summary>
public sealed record ScaffolderOptions
{
    public required string TableName { get; init; }

    public required TimeSpan ReservationTtl { get; init; }

    public required string ServiceName { get; init; }

    public required string Environment { get; init; }

    /// <summary>
    /// Reads the environment once, at cold start. Missing required values throw
    /// here rather than on the first invocation, so the failure shows up as an
    /// init error in CloudWatch instead of an obscure NullReference later.
    /// </summary>
    public static ScaffolderOptions FromEnvironment() => new()
    {
        TableName = Required("SCAFFOLDER_TABLE_NAME"),
        ReservationTtl = TimeSpan.FromMinutes(OptionalInt("SCAFFOLDER_RESERVATION_TTL_MINUTES", 360)),
        ServiceName = Optional("SERVICE_NAME", "scaffolder"),
        Environment = Optional("ENVIRONMENT", "dev"),
    };

    private static string Required(string key)
    {
        var value = System.Environment.GetEnvironmentVariable(key);
        return string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"required environment variable {key} is not set")
            : value;
    }

    private static string Optional(string key, string fallback)
    {
        var value = System.Environment.GetEnvironmentVariable(key);
        return string.IsNullOrWhiteSpace(value) ? fallback : value;
    }

    private static int OptionalInt(string key, int fallback)
    {
        var value = System.Environment.GetEnvironmentVariable(key);

        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return int.TryParse(value, out var parsed) && parsed > 0
            ? parsed
            : throw new InvalidOperationException($"environment variable {key} must be a positive integer, got '{value}'");
    }
}
