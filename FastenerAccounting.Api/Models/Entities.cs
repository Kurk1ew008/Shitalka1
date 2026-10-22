using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace FastenerAccounting.Api.Models;

public enum UserRole { Admin, Accountant, Storekeeper }
public enum DocumentStatus { Draft, Posted, Paid, Cancelled }
public enum DocumentType { Income, Outcome }

public class User
{
    public int Id { get; set; }
    [Required] public string Email { get; set; } = string.Empty;
    [Required] public string PasswordHash { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Accountant;
}

public class Counterparty
{
    public int Id { get; set; }
    [Required] public string Name { get; set; } = string.Empty;
    [Required] public string Inn { get; set; } = string.Empty;
    public bool IsSupplier { get; set; }
    public bool IsCustomer { get; set; }
}

public class Product
{
    public int Id { get; set; }
    [Required] public string Sku { get; set; } = string.Empty;
    [Required] public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Unit { get; set; } = "С€С‚";
    public decimal Price { get; set; }
}

public class Batch
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int Quantity { get; set; }
    public decimal CostPrice { get; set; }
    public DateTime ArrivedAt { get; set; } = DateTime.UtcNow;
}

public class Document
{
    public int Id { get; set; }
    public DocumentType DocType { get; set; }
    [Required] public string Number { get; set; } = string.Empty;
    public int CounterpartyId { get; set; }
    public Counterparty? Counterparty { get; set; }
    public DocumentStatus Status { get; set; } = DocumentStatus.Draft;
    public decimal Total { get; set; }
    public List<DocumentLine> Lines { get; set; } = new();
}

public class DocumentLine
{
    public int Id { get; set; }
    public int DocumentId { get; set; }
    [JsonIgnore] public Document? Document { get; set; }
    public int ProductId { get; set; }
    public int Quantity { get; set; }
    public decimal Price { get; set; }
}
