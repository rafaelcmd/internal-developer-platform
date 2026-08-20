using System.Text.RegularExpressions;
using Scaffolder.Domain.Errors;

namespace Scaffolder.Domain.ValueObjects;

/// <summary>
/// The name a developer asks for. It ends up as a GitHub repository name, a
/// Kubernetes object name and a DNS label, so it is validated against the
/// strictest of the three rather than against GitHub alone.
/// </summary>
public sealed partial record ApplicationName
{
    public const int MinLength = 3;
    public const int MaxLength = 40;

    private ApplicationName(string value) => Value = value;

    public string Value { get; }

    /// <summary>Parses a raw name, throwing <see cref="InvalidApplicationNameException"/> if it is not usable.</summary>
    public static ApplicationName Parse(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            throw new InvalidApplicationNameException(raw, "name is required");
        }

        var trimmed = raw.Trim();

        if (trimmed.Length is < MinLength or > MaxLength)
        {
            throw new InvalidApplicationNameException(
                trimmed,
                $"name must be between {MinLength} and {MaxLength} characters");
        }

        if (!Pattern().IsMatch(trimmed))
        {
            throw new InvalidApplicationNameException(
                trimmed,
                "name must be lowercase, start with a letter, end with a letter or digit, "
                + "and contain only letters, digits and single hyphens");
        }

        return new ApplicationName(trimmed);
    }

    public static bool TryParse(string? raw, out ApplicationName? name)
    {
        try
        {
            name = Parse(raw);
            return true;
        }
        catch (InvalidApplicationNameException)
        {
            name = null;
            return false;
        }
    }

    public override string ToString() => Value;

    // Lowercase, letter-initial, alphanumeric-terminal, no doubled hyphens.
    [GeneratedRegex("^[a-z](?:[a-z0-9]|-(?=[a-z0-9]))*[a-z0-9]$")]
    private static partial Regex Pattern();
}
