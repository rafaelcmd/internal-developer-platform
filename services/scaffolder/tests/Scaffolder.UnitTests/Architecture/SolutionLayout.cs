namespace Scaffolder.UnitTests.Architecture;

/// <summary>Locates the solution on disk so build-configuration tests can read the real files.</summary>
internal static class SolutionLayout
{
    public static readonly string Root = FindRoot();

    public static string Path(string relative) =>
        System.IO.Path.Combine(Root, relative.Replace('/', System.IO.Path.DirectorySeparatorChar));

    private static string FindRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null && directory.GetFiles("Directory.Packages.props").Length == 0)
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new InvalidOperationException(
                "could not locate the scaffolder solution root from " + AppContext.BaseDirectory);
    }
}
