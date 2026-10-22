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
