namespace Scaffolder.Domain.Errors;

/// <summary>
/// Base type for errors the domain raises deliberately. Anything deriving from
/// this is an expected outcome with a stable <see cref="Code"/>; anything else
/// escaping a use case is a bug or an infrastructure fault.
/// </summary>
public abstract class ScaffolderException : Exception
{
    protected ScaffolderException(string code, string message, Exception? innerException = null)
        : base(message, innerException) => Code = code;

    /// <summary>Machine-readable code. Step Functions matches <c>Catch</c> clauses on this.</summary>
    public string Code { get; }
}

/// <summary>The requested name cannot be used as a repository, service or DNS name.</summary>
public sealed class InvalidApplicationNameException(string? name, string reason)
    : ScaffolderException("INVALID_APPLICATION_NAME", $"'{name}' is not a valid application name: {reason}")
{
    public string? AttemptedName { get; } = name;
}

/// <summary>The name is already reserved by a different request.</summary>
public sealed class NameAlreadyReservedException(string name)
    : ScaffolderException("NAME_ALREADY_RESERVED", $"application name '{name}' is already reserved")
{
    public string ApplicationName { get; } = name;
}
