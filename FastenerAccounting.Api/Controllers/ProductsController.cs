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
