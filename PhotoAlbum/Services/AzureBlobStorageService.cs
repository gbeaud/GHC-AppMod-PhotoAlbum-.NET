using Azure.Identity;
using Azure.Storage.Blobs;

namespace PhotoAlbum.Services;

/// <summary>
/// Service for Azure Blob Storage operations using Managed Identity authentication
/// </summary>
public class AzureBlobStorageService : IBlobStorageService
{
    private readonly BlobContainerClient _containerClient;
    private readonly ILogger<AzureBlobStorageService> _logger;

    public AzureBlobStorageService(
        IConfiguration configuration,
        ILogger<AzureBlobStorageService> logger)
    {
        _logger = logger;

        // Get the blob storage account URI and container name from configuration
        var blobStorageUri = configuration["BlobStorage:Uri"] 
            ?? throw new InvalidOperationException("BlobStorage:Uri not configured");
        var containerName = configuration["BlobStorage:ContainerName"] 
            ?? throw new InvalidOperationException("BlobStorage:ContainerName not configured");

        // Initialize BlobServiceClient using DefaultAzureCredential (Managed Identity)
        var blobServiceClient = new BlobServiceClient(
            new Uri(blobStorageUri),
            new DefaultAzureCredential());

        _containerClient = blobServiceClient.GetBlobContainerClient(containerName);
    }

    /// <summary>
    /// Upload a blob to Azure Storage
    /// </summary>
    public async Task<bool> UploadBlobAsync(string blobName, Stream stream, string contentType)
    {
        try
        {
            var blobClient = _containerClient.GetBlobClient(blobName);
            await blobClient.UploadAsync(stream, overwrite: true);
            _logger.LogInformation("Successfully uploaded blob {BlobName} to Azure Blob Storage", blobName);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error uploading blob {BlobName} to Azure Blob Storage", blobName);
            return false;
        }
    }

    /// <summary>
    /// Download a blob from Azure Storage
    /// </summary>
    public async Task<Stream?> DownloadBlobAsync(string blobName)
    {
        try
        {
            var blobClient = _containerClient.GetBlobClient(blobName);
            var download = await blobClient.DownloadAsync();
            _logger.LogDebug("Successfully downloaded blob {BlobName} from Azure Blob Storage", blobName);
            return download.Value.Content;
        }
        catch (Azure.RequestFailedException ex) when (ex.Status == 404)
        {
            _logger.LogWarning("Blob {BlobName} not found in Azure Blob Storage", blobName);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error downloading blob {BlobName} from Azure Blob Storage", blobName);
            return null;
        }
    }

    /// <summary>
    /// Delete a blob from Azure Storage
    /// </summary>
    public async Task<bool> DeleteBlobAsync(string blobName)
    {
        try
        {
            var blobClient = _containerClient.GetBlobClient(blobName);
            await blobClient.DeleteAsync();
            _logger.LogInformation("Successfully deleted blob {BlobName} from Azure Blob Storage", blobName);
            return true;
        }
        catch (Azure.RequestFailedException ex) when (ex.Status == 404)
        {
            _logger.LogWarning("Blob {BlobName} not found in Azure Blob Storage for deletion", blobName);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting blob {BlobName} from Azure Blob Storage", blobName);
            return false;
        }
    }

    /// <summary>
    /// Check if a blob exists in Azure Storage
    /// </summary>
    public async Task<bool> BlobExistsAsync(string blobName)
    {
        try
        {
            var blobClient = _containerClient.GetBlobClient(blobName);
            var exists = await blobClient.ExistsAsync();
            return exists.Value;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking if blob {BlobName} exists in Azure Blob Storage", blobName);
            return false;
        }
    }
}
