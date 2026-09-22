namespace PhotoAlbum.Services;

/// <summary>
/// Service interface for blob storage operations in Azure
/// </summary>
public interface IBlobStorageService
{
    /// <summary>
    /// Upload a blob to Azure Storage
    /// </summary>
    /// <param name="blobName">Name of the blob to store</param>
    /// <param name="stream">Stream containing the blob data</param>
    /// <param name="contentType">Content type of the blob</param>
    /// <returns>True if upload successful, false otherwise</returns>
    Task<bool> UploadBlobAsync(string blobName, Stream stream, string contentType);

    /// <summary>
    /// Download a blob from Azure Storage
    /// </summary>
    /// <param name="blobName">Name of the blob to retrieve</param>
    /// <returns>Stream containing the blob data, or null if not found</returns>
    Task<Stream?> DownloadBlobAsync(string blobName);

    /// <summary>
    /// Delete a blob from Azure Storage
    /// </summary>
    /// <param name="blobName">Name of the blob to delete</param>
    /// <returns>True if deletion successful, false if blob not found</returns>
    Task<bool> DeleteBlobAsync(string blobName);

    /// <summary>
    /// Check if a blob exists in Azure Storage
    /// </summary>
    /// <param name="blobName">Name of the blob to check</param>
    /// <returns>True if blob exists, false otherwise</returns>
    Task<bool> BlobExistsAsync(string blobName);
}
