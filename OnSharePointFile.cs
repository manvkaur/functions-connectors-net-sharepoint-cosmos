// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Azure.Connectors.Sdk.SharePointOnline.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Connector;
using Microsoft.Extensions.Logging;

namespace SharePointCosmosDemo;

public sealed class OnSharePointFile(ILogger<OnSharePointFile> logger)
{
    [Function("OnSharePointFile")]
    [CosmosDBOutput(
        "%CosmosDatabaseName%",
        "%CosmosContainerName%",
        Connection = "CosmosConnection")]
    public Dictionary<string, object?>[] Run(
        [ConnectorTrigger(
            DeliveryMode = ConnectorTriggerDeliveryMode.Poll,
            Connection = "ConnectorNamespace",
            TriggerConfigName = "%SharePointTriggerConfigName%")]
        ConnectorEvent<SharePointOnlineOnNewFileItemsTriggerPayload> message)
    {
        ArgumentNullException.ThrowIfNull(message);
        if (string.IsNullOrWhiteSpace(message.MessageId))
        {
            throw new InvalidOperationException("Poll delivery must include a stable messageId.");
        }

        var files = message.Data?.Body?.Value
            ?? throw new InvalidOperationException("Expected SharePoint file metadata in the trigger body.");

        var documents = files.Select(file =>
        {
            if (file?.AdditionalProperties is not { } properties ||
                !properties.TryGetValue("ID", out JsonElement identifier) ||
                identifier.ValueKind is not (JsonValueKind.String or JsonValueKind.Number) ||
                string.IsNullOrWhiteSpace(identifier.ToString()))
            {
                throw new InvalidOperationException("SharePoint file metadata must contain a nonempty ID.");
            }

            string fileId = identifier.ToString();
            return new Dictionary<string, object?>
            {
                ["id"] = Convert.ToHexStringLower(
                    SHA256.HashData(Encoding.UTF8.GetBytes($"{message.MessageId}\n{fileId}"))),
                ["source"] = "sharepoint",
                ["messageId"] = message.MessageId,
                ["fileId"] = fileId,
                ["fileName"] = properties.TryGetValue("{FilenameWithExtension}", out JsonElement name) &&
                    name.ValueKind == JsonValueKind.String ? name.GetString() : null,
                ["status"] = "Received"
            };
        }).ToArray();

        logger.LogInformation(
            "Prepared {DocumentCount} document records for Cosmos output from Poll event {MessageId}.",
            documents.Length,
            message.MessageId);
        return documents;
    }
}
