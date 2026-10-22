using FastenerAccounting.Api.Models;

namespace FastenerAccounting.Api.Services;

public static class DocumentStateMachine
{
    public static readonly Dictionary<DocumentStatus, HashSet<DocumentStatus>> Transitions = new()
    {
        { DocumentStatus.Draft, new() { DocumentStatus.Posted, DocumentStatus.Cancelled } },
        { DocumentStatus.Posted, new() { DocumentStatus.Paid, DocumentStatus.Cancelled } },
        { DocumentStatus.Paid, new() },
        { DocumentStatus.Cancelled, new() }
    };

    public static bool CanTransition(DocumentStatus from, DocumentStatus to)
        => Transitions.TryGetValue(from, out var allowed) && allowed.Contains(to);
}
