$ErrorActionPreference = "Stop"
$ProjectName = "FastenerAccounting"

dotnet new sln -n $ProjectName
dotnet new webapi -n "$ProjectName.Api"
dotnet new xunit -n "$ProjectName.Tests"
dotnet sln add "$ProjectName.Api/$ProjectName.Api.csproj"
dotnet sln add "$ProjectName.Tests/$ProjectName.Tests.csproj"
dotnet add "$ProjectName.Tests/$ProjectName.Tests.csproj" reference "$ProjectName.Api/$ProjectName.Api.csproj"

Set-Location "$ProjectName.Api"
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer
dotnet add package Swashbuckle.AspNetCore
dotnet add package BCrypt.Net-Next
Set-Location ..

Set-Location "$ProjectName.Tests"
dotnet add package Microsoft.EntityFrameworkCore.InMemory
dotnet add package Microsoft.AspNetCore.Mvc.Testing
Set-Location ..

New-Item -ItemType Directory -Force -Path "$ProjectName.Api\Models" | Out-Null
@'
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
    public string Unit { get; set; } = "шт";
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
'@ | Set-Content -Path "$ProjectName.Api\Models\Entities.cs" -Encoding UTF8

New-Item -ItemType Directory -Force -Path "$ProjectName.Api\Data" | Out-Null
@'
using Microsoft.EntityFrameworkCore;
using FastenerAccounting.Api.Models;

namespace FastenerAccounting.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Counterparty> Counterparties => Set<Counterparty>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<Batch> Batches => Set<Batch>();
    public DbSet<Document> Documents => Set<Document>();
    public DbSet<DocumentLine> DocumentLines => Set<DocumentLine>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Product>().HasIndex(p => p.Sku).IsUnique();
        modelBuilder.Entity<Document>().HasIndex(d => d.Number).IsUnique();
    }
}
'@ | Set-Content -Path "$ProjectName.Api\Data\AppDbContext.cs" -Encoding UTF8

New-Item -ItemType Directory -Force -Path "$ProjectName.Api\Services" | Out-Null
@'
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
'@ | Set-Content -Path "$ProjectName.Api\Services\DocumentStateMachine.cs" -Encoding UTF8

New-Item -ItemType Directory -Force -Path "$ProjectName.Api\Controllers" | Out-Null
@'
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using FastenerAccounting.Api.Data;
using FastenerAccounting.Api.Models;

namespace FastenerAccounting.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;

    public AuthController(AppDbContext db, IConfiguration config)
    { _db = db; _config = config; }

    public record RegisterDto(string Email, string Password, string FullName);
    public record LoginDto(string Email, string Password);

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterDto dto)
    {
        if (await _db.Users.AnyAsync(u => u.Email == dto.Email))
            return BadRequest("Email exists");

        var user = new User
        {
            Email = dto.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password),
            FullName = dto.FullName,
            Role = UserRole.Accountant
        };
        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        return Ok(new { user.Id, user.Email });
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginDto dto)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == dto.Email);
        if (user == null || !BCrypt.Net.BCrypt.Verify(dto.Password, user.PasswordHash))
            return Unauthorized();

        var tokenHandler = new JwtSecurityTokenHandler();
        var key = Encoding.ASCII.GetBytes(_config["Jwt:Key"]!);
        var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(new[] 
            { 
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new Claim(ClaimTypes.Role, user.Role.ToString()) 
            }),
            Expires = DateTime.UtcNow.AddHours(1),
            SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
        };
        var token = tokenHandler.CreateToken(tokenDescriptor);
        return Ok(new { Token = tokenHandler.WriteToken(token) });
    }
}
'@ | Set-Content -Path "$ProjectName.Api\Controllers\AuthController.cs" -Encoding UTF8

@'
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using FastenerAccounting.Api.Data;
using FastenerAccounting.Api.Models;

namespace FastenerAccounting.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly AppDbContext _db;
    public ProductsController(AppDbContext db) => _db = db;

    [HttpPost]
    public async Task<IActionResult> Create(Product product)
    {
        if (await _db.Products.AnyAsync(p => p.Sku == product.Sku))
            return BadRequest("SKU exists");
        _db.Products.Add(product);
        await _db.SaveChangesAsync();
        return Ok(product);
    }

    [HttpGet]
    public async Task<IActionResult> GetAll() => Ok(await _db.Products.ToListAsync());
}
'@ | Set-Content -Path "$ProjectName.Api\Controllers\ProductsController.cs" -Encoding UTF8

@'
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using FastenerAccounting.Api.Data;
using FastenerAccounting.Api.Models;
using FastenerAccounting.Api.Services;

namespace FastenerAccounting.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class DocumentsController : ControllerBase
{
    private readonly AppDbContext _db;
    public DocumentsController(AppDbContext db) => _db = db;

    [HttpPost]
    public async Task<IActionResult> Create(Document doc)
    {
        doc.Total = doc.Lines.Sum(l => l.Quantity * l.Price);
        doc.Status = DocumentStatus.Draft;
        _db.Documents.Add(doc);
        await _db.SaveChangesAsync();
        return Ok(doc);
    }

    [HttpPost("{id}/status")]
    public async Task<IActionResult> ChangeStatus(int id, [FromBody] DocumentStatus newStatus)
    {
        var doc = await _db.Documents.Include(d => d.Lines).FirstOrDefaultAsync(d => d.Id == id);
        if (doc == null) return NotFound();

        if (!DocumentStateMachine.CanTransition(doc.Status, newStatus))
            return BadRequest($"Transition {doc.Status} -> {newStatus} is forbidden");

        if (newStatus == DocumentStatus.Posted)
        {
            if (doc.DocType == DocumentType.Income)
            {
                foreach (var line in doc.Lines)
                    _db.Batches.Add(new Batch { ProductId = line.ProductId, Quantity = line.Quantity, CostPrice = line.Price });
            }
            else
            {
                foreach (var line in doc.Lines)
                {
                    var batches = await _db.Batches.Where(b => b.ProductId == line.ProductId && b.Quantity > 0).OrderBy(b => b.ArrivedAt).ToListAsync();
                    int need = line.Quantity;
                    foreach (var b in batches)
                    {
                        if (need <= 0) break;
                        int take = Math.Min(b.Quantity, need);
                        b.Quantity -= take;
                        need -= take;
                    }
                    if (need > 0) return BadRequest("Not enough stock");
                }
            }
        }

        doc.Status = newStatus;
        await _db.SaveChangesAsync();
        return Ok(doc);
    }
}
'@ | Set-Content -Path "$ProjectName.Api\Controllers\DocumentsController.cs" -Encoding UTF8

@'
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using FastenerAccounting.Api.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddDbContext<AppDbContext>(opt => opt.UseSqlite("Data Source=fastener.db"));

var jwtKey = "super_secret_key_12345678901234567890";
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = false,
            ValidateAudience = false,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.ASCII.GetBytes(jwtKey))
        };
    });

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.Run();
'@ | Set-Content -Path "$ProjectName.Api\Program.cs" -Encoding UTF8

@'
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
'@ | Set-Content -Path "$ProjectName.Tests\StateMachineTests.cs" -Encoding UTF8

dotnet build
dotnet test
Write-Host "DONE"