using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Scaffolder.Application.ReserveName;
using Scaffolder.Infrastructure;
using Scaffolder.Infrastructure.Configuration;

namespace Scaffolder.Functions;

/// <summary>
/// Composition root shared by every handler in this assembly.
/// <para>
/// The container is built in a static initializer, so it runs during the INIT
/// phase of a cold start - once per execution context - and every warm
/// invocation reuses it. Building it inside a handler method would rebuild the
/// SDK clients, re-resolve credentials and re-open TLS connections on every
/// single request.
/// </para>
/// </summary>
internal static class FunctionHost
{
    private static readonly ServiceProvider Provider = Build();

    public static IServiceProvider Services => Provider;

    public static T Resolve<T>() where T : notnull => Provider.GetRequiredService<T>();

    private static ServiceProvider Build()
    {
        // Reads (and validates) the environment during INIT. A missing table
        // name fails the whole execution context here, which CloudWatch reports
        // as an init error - far easier to diagnose than a null deref later.
        var options = ScaffolderOptions.FromEnvironment();

        var services = new ServiceCollection();

        services.AddLogging(logging =>
        {
            // stdout is what Lambda ships to CloudWatch Logs. JSON keeps it
            // queryable in Logs Insights, matching the Go services' log shape.
            logging.AddJsonConsole(console =>
            {
                console.IncludeScopes = true;
                console.JsonWriterOptions = new System.Text.Json.JsonWriterOptions { Indented = false };
            });
            logging.SetMinimumLevel(LogLevel.Information);
        });

        services.AddScaffolderInfrastructure(options);

        // Use cases. Singleton for the same reason as the adapters: they are
        // stateless and there is only ever one invocation in flight per context.
        services.AddSingleton(new ReserveNameOptions(options.ReservationTtl));
        services.AddSingleton<ReserveNameUseCase>();

        return services.BuildServiceProvider();
    }
}
