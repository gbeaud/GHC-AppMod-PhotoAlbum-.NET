using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using PhotoAlbum.Services;

namespace PhotoAlbum.Pages;

/// <summary>
/// Page model for serving photo files from Azure Blob Storage with indirect access
/// </summary>
public class PhotoFileModel : PageModel
{
    private readonly IPhotoService _photoService;
    private readonly IBlobStorageService _blobStorage;
    private readonly ILogger<PhotoFileModel> _logger;

    /// <summary>
    /// Initializes a new instance of the PhotoFileModel class
    /// </summary>
    /// <param name="photoService">Service for photo operations</param>
    /// <param name="blobStorage">Service for blob storage operations</param>
    /// <param name="logger">Logger instance</param>
    public PhotoFileModel(
        IPhotoService photoService,
        IBlobStorageService blobStorage,
        ILogger<PhotoFileModel> logger)
    {
        _photoService = photoService;
        _blobStorage = blobStorage;
        _logger = logger;
    }

    /// <summary>
    /// Serves a photo file by ID from Azure Blob Storage
    /// </summary>
    /// <param name="id">The ID of the photo to serve</param>
    /// <returns>File result with the photo, or NotFound if photo doesn't exist</returns>
    public async Task<IActionResult> OnGetAsync(int? id)
    {
        if (id == null)
        {
            _logger.LogWarning("Photo file request with null ID");
            return NotFound();
        }

        try
        {
            var photo = await _photoService.GetPhotoByIdAsync(id.Value);

            if (photo == null)
            {
                _logger.LogWarning("Photo with ID {PhotoId} not found", id);
                return NotFound();
            }

            // Download blob from Azure Storage
            var blobStream = await _blobStorage.DownloadBlobAsync(photo.StoredFileName);
            if (blobStream == null)
            {
                _logger.LogError("Blob not found in Azure Storage for photo ID {PhotoId}: {BlobName}", id, photo.StoredFileName);
                return NotFound();
            }

            _logger.LogDebug("Serving photo ID {PhotoId} ({FileName}) from Azure Blob Storage",
                id, photo.OriginalFileName);

            // Return the file with appropriate content type and enable caching
            Response.Headers.CacheControl = "public,max-age=31536000"; // Cache for 1 year
            Response.Headers.ETag = $"\"{photo.Id}-{photo.UploadedAt.Ticks}\"";

            return File(blobStream, photo.MimeType);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error serving photo with ID {PhotoId}", id);
            return StatusCode(500);
        }
    }
}
