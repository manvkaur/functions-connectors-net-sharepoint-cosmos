// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Text.Json;
using Azure.Connectors.Sdk.SharePointOnline.Models;
using Microsoft.Azure.Functions.Worker.Extensions.Connector;
using Microsoft.Extensions.Logging.Abstractions;
using SharePointCosmosDemo;
using Xunit;

public sealed class OnSharePointFileTests
{
    private readonly OnSharePointFile _function = new(NullLogger<OnSharePointFile>.Instance);

    [Fact]
    public void UsesSingleEventPollDeliveryWithDefaultTuning()
    {
        var method = Assert.Single(typeof(OnSharePointFile).GetMethods(), method => method.Name == nameof(OnSharePointFile.Run));
        var parameter = Assert.Single(method.GetParameters());
        var trigger = Assert.IsType<ConnectorTriggerAttribute>(
            Attribute.GetCustomAttribute(parameter, typeof(ConnectorTriggerAttribute)));

        Assert.Equal(ConnectorTriggerDeliveryMode.Poll, trigger.DeliveryMode);
        Assert.False(trigger.IsBatched);
        Assert.Equal(0, trigger.MaxBatchSize);
        Assert.Equal(0, trigger.MaxConcurrentCalls);
        Assert.Equal(0, trigger.TargetPendingEventThreshold);
    }

    [Fact]
    public void CreatesOneRecordPerFileAndPreservesStableIdentifiers()
    {
        ConnectorEvent<SharePointOnlineOnNewFileItemsTriggerPayload> message = CreateEvent(
            """{"headers":{},"body":{"value":[{"ID":1,"{FilenameWithExtension}":"order.pdf"},{"ID":"2"}]}}""");
        var first = _function.Run(message);
        var redelivery = _function.Run(message);

        Assert.Equal(2, first.Length);
        Assert.Equal(JsonSerializer.Serialize(first), JsonSerializer.Serialize(redelivery));
        Assert.NotEqual(first[0]["id"], first[1]["id"]);
        Assert.Equal("order.pdf", first[0]["fileName"]);
        Assert.Null(first[1]["fileName"]);
        Assert.Equal("sharepoint", first[0]["source"]);
        Assert.Equal("Received", first[0]["status"]);
    }

    [Fact]
    public void SerializesCosmosIdAndPartitionKeyWithRequiredNames()
    {
        var record = Assert.Single(_function.Run(CreateEvent("""{"body":{"value":[{"ID":1}]}}""")));
        string json = JsonSerializer.Serialize(record);
        using JsonDocument document = JsonDocument.Parse(json);
        Assert.Equal(record["id"], document.RootElement.GetProperty("id").GetString());
        Assert.Equal("sharepoint", document.RootElement.GetProperty("source").GetString());
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("""{"value":[{"ID":1}]}""")]
    [InlineData("""{"body":{}}""")]
    [InlineData("""{"body":{"value":[{}]}}""")]
    [InlineData("""{"body":{"value":[null]}}""")]
    [InlineData("""{"body":{"value":[{"ID":""}]}}""")]
    public void RejectsMalformedFilePayloads(string json) =>
        Assert.Throws<InvalidOperationException>(() => _function.Run(CreateEvent(json)));

    [Fact]
    public void RejectsMissingDeliveryIdentifier() =>
        Assert.Throws<InvalidOperationException>(() => _function.Run(
            CreateEvent("""{"body":{"value":[{"ID":1}]}}""", messageId: null)));

    [Fact]
    public void RejectsMalformedCollectionShape() =>
        Assert.Throws<InvalidOperationException>(() =>
            _function.Run(CreateEvent("""{"body":{"value":{}}}""")));

    [Fact]
    public void CreatesRecordFromSingleFileBody()
    {
        var record = Assert.Single(_function.Run(
            CreateEvent("""{"body":{"ID":1,"{FilenameWithExtension}":"order.pdf"}}""")));

        Assert.Equal("1", record["fileId"]);
        Assert.Equal("order.pdf", record["fileName"]);
    }

    [Fact]
    public void AcceptsEmptyFileCollection() =>
        Assert.Empty(_function.Run(CreateEvent("""{"body":{"value":[]}}""")));

    private static ConnectorEvent<SharePointOnlineOnNewFileItemsTriggerPayload> CreateEvent(
        string json,
        string? messageId = "event-1") =>
        new()
        {
            Data = JsonSerializer.Deserialize<SharePointOnlineOnNewFileItemsTriggerPayload>(json)!,
            MessageId = messageId
        };
}
