using Amazon.Lambda.Core;
using Microsoft.Extensions.Logging;
using Scaffolder.Application.ReserveName;

// One serializer for every handler in this assembly. Case-insensitive on the way
// in, PascalCase on the way out - the shape the state machine passes between states.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Scaffolder.Functions;

/// <summary>
/// <c>ReserveName</c> task of the scaffold state machine.
/// <para>
/// Handler string: <c>Scaffolder.Functions::Scaffolder.Functions.ReserveNameFunction::HandleAsync</c>
/// </para>
/// </summary>
public sealed class ReserveNameFunction
{
    private readonly ReserveNameUseCase useCase;
    private readonly ILogger<ReserveNameFunction> logger;

    /// <summary>Entry point Lambda constructs, once per execution context.</summary>
    public ReserveNameFunction()
        : this(FunctionHost.Resolve<ReserveNameUseCase>(), FunctionHost.Resolve<ILogger<ReserveNameFunction>>())
    {
    }

    /// <summary>Test seam: hand the handler its collaborators directly.</summary>
    internal ReserveNameFunction(ReserveNameUseCase useCase, ILogger<ReserveNameFunction> logger)
    {
        this.useCase = useCase;
        this.logger = logger;
    }

    /// <summary>
    /// Deserialize, delegate, serialize - no business logic here. Domain errors
    /// are left to propagate: Lambda reports the exception type as the error
    /// name, which is what a Step Functions <c>Catch</c> clause matches on.
    /// </summary>
    public async Task<ReserveNameResult> HandleAsync(ReserveNameCommand command, ILambdaContext context)
    {
        var invocation = ExecutionContextTelemetry.Record();

        logger.LogInformation(
            "ReserveName invocation {InvocationNumber} on instance {InstanceId} "
            + "(coldStart={IsColdStart}, contextAge={ContextAgeSeconds}s, awsRequestId={AwsRequestId}, "
            + "memoryMB={MemoryLimit}, remainingMs={RemainingMs})",
            invocation.InvocationNumber,
            invocation.InstanceId,
            invocation.IsColdStart,
            (int)invocation.ContextAge.TotalSeconds,
            context.AwsRequestId,
            context.MemoryLimitInMB,
            (int)context.RemainingTime.TotalMilliseconds);

        return await useCase.ExecuteAsync(command, CancellationToken.None);
    }
}
