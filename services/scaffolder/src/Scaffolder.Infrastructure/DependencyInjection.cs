using Amazon.DynamoDBv2;
using Microsoft.Extensions.DependencyInjection;
using Scaffolder.Domain.Ports;
using Scaffolder.Infrastructure.Configuration;
using Scaffolder.Infrastructure.Persistence;

namespace Scaffolder.Infrastructure;

public static class DependencyInjection
{
    /// <summary>
    /// Registers the adapters. Everything here is a singleton on purpose: the
    /// container is built once per execution context, so the AWS SDK clients -
    /// and the HTTPS connections and credentials they cache - survive across
    /// warm invocations instead of being rebuilt per request.
    /// </summary>
    public static IServiceCollection AddScaffolderInfrastructure(
        this IServiceCollection services,
        ScaffolderOptions options)
    {
        services.AddSingleton(options);
        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IAmazonDynamoDB>(_ => new AmazonDynamoDBClient());
        services.AddSingleton<INameReservationStore, DynamoDbNameReservationStore>();

        return services;
    }
}
