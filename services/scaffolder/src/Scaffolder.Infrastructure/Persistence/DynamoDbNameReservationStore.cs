using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Microsoft.Extensions.Logging;
using Scaffolder.Domain.Errors;
using Scaffolder.Domain.Model;
using Scaffolder.Domain.Ports;
using Scaffolder.Infrastructure.Configuration;

namespace Scaffolder.Infrastructure.Persistence;

/// <summary>
/// Name reservations in the single <c>scaffolder</c> table, keyed
/// <c>NAME#&lt;app&gt;</c> / <c>RESERVATION</c>.
/// </summary>
public sealed class DynamoDbNameReservationStore(
    IAmazonDynamoDB dynamoDb,
    ScaffolderOptions options,
    ILogger<DynamoDbNameReservationStore> logger) : INameReservationStore
{
    internal const string SortKeyValue = "RESERVATION";

    public async Task<ReservationOutcome> ReserveAsync(
        NameReservation reservation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(reservation);

        var request = new PutItemRequest
        {
            TableName = options.TableName,
            Item = ToItem(reservation),

            // The whole point of this class. Uniqueness is one atomic write:
            // free name, or already held by this very request (a Step Functions
            // retry). Anything else fails the condition and is a real conflict.
            ConditionExpression = "attribute_not_exists(PK) OR RequestId = :requestId",
            ExpressionAttributeValues = new Dictionary<string, AttributeValue>
            {
                [":requestId"] = new() { S = reservation.RequestId },
            },

            // ALL_OLD tells replay (an item came back) from first write (none did)
            // without a second read.
            ReturnValues = ReturnValue.ALL_OLD,
            ReturnValuesOnConditionCheckFailure = ReturnValuesOnConditionCheckFailure.ALL_OLD,
        };

        try
        {
            var response = await dynamoDb.PutItemAsync(request, cancellationToken);
            var replayed = response.Attributes is { Count: > 0 };

            return replayed ? ReservationOutcome.AlreadyHeldByThisRequest : ReservationOutcome.Created;
        }
        catch (ConditionalCheckFailedException ex)
        {
            // Surface a domain error. A leaked SDK exception would put an AWS
            // type in the state machine's Catch clauses and in the API response.
            logger.LogWarning(
                "Name {ApplicationName} is held by another request; {RequestId} was rejected",
                reservation.Name.Value,
                reservation.RequestId);

            throw new NameAlreadyReservedException(reservation.Name.Value) { Data = { ["dynamodb"] = ex.Message } };
        }
    }

    private static Dictionary<string, AttributeValue> ToItem(NameReservation reservation) => new()
    {
        ["PK"] = new AttributeValue { S = $"NAME#{reservation.Name.Value}" },
        ["SK"] = new AttributeValue { S = SortKeyValue },
        ["ApplicationName"] = new AttributeValue { S = reservation.Name.Value },
        ["RequestId"] = new AttributeValue { S = reservation.RequestId },
        ["Status"] = new AttributeValue { S = reservation.Status.ToString() },
        ["CreatedAt"] = new AttributeValue { S = reservation.CreatedAt.ToString("O") },

        // DynamoDB TTL only understands epoch seconds as a Number.
        ["ExpiresAt"] = new AttributeValue { N = reservation.ExpiresAt.ToUnixTimeSeconds().ToString() },
    };
}
