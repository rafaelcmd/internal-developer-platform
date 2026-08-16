using System.Xml.Linq;

namespace Scaffolder.UnitTests.Architecture;

/// <summary>
/// The hexagonal dependency rule, enforced by the build rather than by good
/// intentions. It reads the project files instead of the compiled assemblies on
/// purpose: the compiler drops references a project never actually uses, so a
/// wrong-but-unused reference would pass an assembly-level check and still be
/// there for the next person to lean on.
/// </summary>
public sealed class DependencyRuleTests
{
    private static readonly string SolutionRoot = FindSolutionRoot();

    [Fact]
    public void Domain_references_nothing()
    {
        var (projects, packages) = ReferencesOf("src/Scaffolder.Domain/Scaffolder.Domain.csproj");

        Assert.Empty(projects);
        Assert.Empty(packages);
    }

    [Fact]
    public void Application_depends_on_domain_only()
    {
        var (projects, _) = ReferencesOf("src/Scaffolder.Application/Scaffolder.Application.csproj");

        Assert.Equal(new[] { "Scaffolder.Domain" }, projects);
    }

    [Fact]
    public void Infrastructure_depends_on_domain_only()
    {
        var (projects, _) = ReferencesOf("src/Scaffolder.Infrastructure/Scaffolder.Infrastructure.csproj");

        Assert.Equal(new[] { "Scaffolder.Domain" }, projects);
    }

    [Theory]
    [InlineData("src/Scaffolder.Domain/Scaffolder.Domain.csproj")]
    [InlineData("src/Scaffolder.Application/Scaffolder.Application.csproj")]
    public void Aws_sdk_is_confined_to_infrastructure(string project)
    {
        var (_, packages) = ReferencesOf(project);

        Assert.DoesNotContain(packages, p => p.StartsWith("AWSSDK.", StringComparison.Ordinal));
        Assert.DoesNotContain(packages, p => p.StartsWith("Amazon.", StringComparison.Ordinal));
    }

    [Fact]
    public void Functions_is_the_only_project_referencing_the_lambda_runtime()
    {
        var lambdaAware = ProjectFiles()
            .Where(path => ReferencesOf(path).Packages.Any(p => p.StartsWith("Amazon.Lambda.", StringComparison.Ordinal)))
            .Select(path => Path.GetFileNameWithoutExtension(path)!)
            .Order()
            .ToArray();

        Assert.Equal(new[] { "Scaffolder.Functions", "Scaffolder.UnitTests" }, lambdaAware);
    }

    [Fact]
    public void Every_package_version_is_pinned_centrally()
    {
        var unpinned = ProjectFiles()
            .SelectMany(path => XDocument.Load(path)
                .Descendants("PackageReference")
                .Where(reference => reference.Attribute("Version") is not null)
                .Select(reference => $"{Path.GetFileName(path)}: {reference.Attribute("Include")?.Value}"))
            .ToArray();

        Assert.Empty(unpinned);
    }

    // src/ and tests/ only: templates/ holds golden-path sample projects, which
    // are scaffolding output and not part of this solution's layering.
    private static IEnumerable<string> ProjectFiles() =>
        new[] { "src", "tests" }
            .SelectMany(folder => Directory.EnumerateFiles(
                Path.Combine(SolutionRoot, folder), "*.csproj", SearchOption.AllDirectories))
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            .Order();

    private static (string[] Projects, string[] Packages) ReferencesOf(string relativeOrAbsolutePath)
    {
        var path = Path.IsPathRooted(relativeOrAbsolutePath)
            ? relativeOrAbsolutePath
            : Path.Combine(SolutionRoot, relativeOrAbsolutePath);

        var document = XDocument.Load(path);

        var projects = document.Descendants("ProjectReference")
            .Select(reference => Path.GetFileNameWithoutExtension(
                reference.Attribute("Include")!.Value.Replace('\\', Path.DirectorySeparatorChar))!)
            .Order()
            .ToArray();

        var packages = document.Descendants("PackageReference")
            .Select(reference => reference.Attribute("Include")!.Value)
            .Order()
            .ToArray();

        return (projects, packages);
    }

    private static string FindSolutionRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null && directory.GetFiles("Directory.Packages.props").Length == 0)
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new InvalidOperationException("could not locate the scaffolder solution root from " + AppContext.BaseDirectory);
    }
}
