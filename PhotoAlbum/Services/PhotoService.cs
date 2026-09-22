using Microsoft.EntityFrameworkCore;
using PhotoAlbum.Data;
using PhotoAlbum.Models;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats;

namespace PhotoAlbum.Services;

/// <summary>
/// Service for photo operations including upload, retrieval, and deletion
/// Uses Azure Blob Storage for file persistence with Managed Identity authentication
/// </summary>
public class PhotoService : IPhotoService
{
    private readonly PhotoAlbumContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<PhotoService> _logger;
    private readonly IBlobStorageService _blobStorage;
    private readonly long _maxFileSizeBytes;
    private readonly string[] _allowedMimeTypes;

    // Only these real (content-detected) raster image formats may be stored.
    private static readonly HashSet<string> _allowedImageExtensions =
        new(StringComparer.OrdinalIgnoreCase) { "jpg", "jpeg", "png", "gif", "webp" };

    public PhotoService(
        PhotoAlbumContext context,
        IConfiguration configuration,
        ILogger<PhotoService> logger,
        IBlobStorageService blobStorage)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
        _blobStorage = blobStorage;

        _maxFileSizeBytes = _configuration.GetValue<long>("FileUpload:MaxFileSizeBytes", 10485760);
        _allowedMimeTypes = _configuration.GetSection("FileUpload:AllowedMimeTypes").Get<string[]>()
            ?? new[] { "image/jpeg", "image/png", "image/gif", "image/webp" };
    }

    /// <summary>
    /// Get all photos ordered by upload date (newest first)
    /// </summary>
    public async Task<List<Photo>> GetAllPhotosAsync()
    {
        try
        {
            return await _context.Photos
                .OrderByDescending(p => p.UploadedAt)
                .ToListAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving photos from database");
            throw;
        }
    }

    /// <summary>
    /// Get a specific photo by ID
    /// </summary>
    public async Task<Photo?> GetPhotoByIdAsync(int id)
    {
        try
        {
            return await _context.Photos.FindAsync(id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving photo with ID {PhotoId}", id);
            throw;
        }
    }

    /// <summary>
    /// Upload a photo file to Azure Blob Storage
    /// </summary>
    public async Task<UploadResult> UploadPhotoAsync(IFormFile file)
    {
        var result = new UploadResult
        {
            FileName = file.FileName
        };

        try
        {
            // NOTE: the client-supplied Content-Type is NOT trusted for validation.
            // The real image format is detected from the file content below (CWE-434).

            // Validate file size
            if (file.Length > _maxFileSizeBytes)
            {
                result.Success = false;
                result.ErrorMessage = $"File size exceeds {_maxFileSizeBytes / 1024 / 1024}MB limit.";
                _logger.LogWarning("Upload rejected: File size {FileSize} exceeds limit for {FileName}",
                    file.Length, file.FileName);
                return result;
            }

            // Validate file length
            if (file.Length <= 0)
            {
                result.Success = false;
                result.ErrorMessage = "File is empty.";
                return result;
            }

            // Verify the upload is a real raster image and determine its true
            // format from the content (never from the client Content-Type or the
            // user-supplied file name). Fail closed if it cannot be decoded
            // (CWE-434 unrestricted upload / CWE-79 stored XSS via .html/.svg).
            int? width = null;
            int? height = null;
            IImageFormat imageFormat;
            try
            {
                await using var probeStream = file.OpenReadStream();
                var imageInfo = await Image.IdentifyAsync(probeStream);
                imageFormat = imageInfo.Metadata.DecodedImageFormat
                    ?? throw new InvalidOperationException("Unknown image format.");
                width = imageInfo.Width;
                height = imageInfo.Height;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Upload rejected: not a valid image {FileName}", file.FileName);
                result.Success = false;
                result.ErrorMessage = "File type not supported. Please upload JPEG, PNG, GIF, or WebP images.";
                return result;
            }

            // Allow only known-safe raster formats, keyed off the detected format's
            // canonical extension (not the attacker-controlled file name).
            var safeExtension = imageFormat.FileExtensions.FirstOrDefault();
            if (safeExtension == null || !_allowedImageExtensions.Contains(safeExtension))
            {
                result.Success = false;
                result.ErrorMessage = "File type not supported. Please upload JPEG, PNG, GIF, or WebP images.";
                _logger.LogWarning("Upload rejected: unsupported image format {Format} for {FileName}",
                    imageFormat.Name, file.FileName);
                return result;
            }

            // Build a safe stored file name using the detected format's extension.
            var storedFileName = $"{Guid.NewGuid()}.{safeExtension}";
            var relativePath = $"/uploads/{storedFileName}";

            // Upload file to Azure Blob Storage
            try
            {
                // Reset stream position to start
                file.OpenReadStream().Position = 0;
                
                await using var uploadStream = file.OpenReadStream();
                var uploadSuccess = await _blobStorage.UploadBlobAsync(
                    storedFileName, 
                    uploadStream, 
                    imageFormat.DefaultMimeType);

                if (!uploadSuccess)
                {
                    result.Success = false;
                    result.ErrorMessage = "Error saving file. Please try again.";
                    return result;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error uploading blob {FileName} to Azure Storage", file.FileName);
                result.Success = false;
                result.ErrorMessage = "Error saving file. Please try again.";
                return result;
            }

            // Create photo entity
            var photo = new Photo
            {
                OriginalFileName = Path.GetFileName(file.FileName),
                StoredFileName = storedFileName,
                FilePath = relativePath,
                FileSize = file.Length,
                MimeType = imageFormat.DefaultMimeType,
                UploadedAt = DateTime.UtcNow,
                Width = width,
                Height = height
            };

            // Save to database
            try
            {
                await _context.Photos.AddAsync(photo);
                await _context.SaveChangesAsync();

                result.Success = true;
                result.PhotoId = photo.Id;

                _logger.LogInformation("Successfully uploaded photo {FileName} with ID {PhotoId}",
                    file.FileName, photo.Id);
            }
            catch (Exception ex)
            {
                // Rollback: Delete blob if database save fails
                try
                {
                    await _blobStorage.DeleteBlobAsync(storedFileName);
                    _logger.LogInformation("Rolled back blob deletion for {BlobName} due to database save failure", storedFileName);
                }
                catch (Exception deleteEx)
                {
                    _logger.LogError(deleteEx, "Error deleting blob {BlobName} during rollback", storedFileName);
                }

                _logger.LogError(ex, "Error saving photo metadata to database for {FileName}", file.FileName);
                result.Success = false;
                result.ErrorMessage = "Error saving photo information. Please try again.";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error during photo upload for {FileName}", file.FileName);
            result.Success = false;
            result.ErrorMessage = "An unexpected error occurred. Please try again.";
        }

        return result;
    }

    /// <summary>
    /// Delete a photo by ID from Azure Blob Storage and database
    /// </summary>
    public async Task<bool> DeletePhotoAsync(int id)
    {
        try
        {
            var photo = await _context.Photos.FindAsync(id);
            if (photo == null)
            {
                _logger.LogWarning("Photo with ID {PhotoId} not found for deletion", id);
                return false;
            }

            // Delete blob from Azure Storage
            try
            {
                await _blobStorage.DeleteBlobAsync(photo.StoredFileName);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting blob {BlobName} for photo ID {PhotoId}", photo.StoredFileName, id);
                // Continue with database deletion even if blob deletion fails
            }

            // Delete from database
            _context.Photos.Remove(photo);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Successfully deleted photo ID {PhotoId}", id);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting photo with ID {PhotoId}", id);
            throw;
        }
    }
}
