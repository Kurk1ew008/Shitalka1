using FastenerAccounting.Api.Models;
using FastenerAccounting.Api.Services;
using Xunit;

namespace FastenerAccounting.Tests;

public class StateMachineTests
{
    [Theory]
    [InlineData(DocumentStatus.Draft, DocumentStatus.Posted, true)]
    [InlineData(DocumentStatus.Draft, DocumentStatus.Cancelled, true)]
    [InlineData(DocumentStatus.Posted, DocumentStatus.Paid, true)]
    [InlineData(DocumentStatus.Draft, DocumentStatus.Paid, false)]
    [InlineData(DocumentStatus.Paid, DocumentStatus.Draft, false)]
    public void TestTransitions(DocumentStatus from, DocumentStatus to, bool expected)
    {
        var result = DocumentStateMachine.CanTransition(from, to);
        Assert.Equal(expected, result);
    }
}
