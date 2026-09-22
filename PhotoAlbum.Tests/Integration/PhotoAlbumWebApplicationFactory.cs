using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PhotoAlbum.Data;
using PhotoAlbum.Models;
using System.Net.Http.Headers;

namespace PhotoAlbum.Tests.Integration;

/// <summary>
/// Shared fixture for integration tests using Testcontainers (SQL Server + Azurite)
/// </summary>
public class PhotoAlbumWebApplicationFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly string _sqlConnectionString;
    private readonly string _blobStorageConnectionString;
    private readonly string _containerName = "photos";

    public HttpClient? TestClient { get; private set; }
    public BlobContainerClient? BlobContainerClient { get; private set; }
    public PhotoAlbumContext? DbContext { get; private set; }

    public PhotoAlbumWebApplicationFactory()
    {
        // For local testing: use hardcoded testcontainer endpoints
        // In CI: Testcontainers will override these via environment variables
        var sqlHost = Environment.GetEnvironmentVariable("SQL_HOST") ?? "localhost";
        var sqlPort = Environment.GetEnvironmentVariable("SQL_PORT") ?? "1433";
        var blobHost = Environment.GetEnvironmentVariable("BLOB_HOST") ?? "localhost";
        var blobPort = Environment.GetEnvironmentVariable("BLOB_PORT") ?? "10000";

        _sqlConnectionString = $"Server={sqlHost},{sqlPort};User Id=sa;Password=YourStrong@Password123;Database=PhotoAlbumDb;Encrypt=false;TrustServerCertificate=true;";
        _blobStorageConnectionString = $"DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://{blobHost}:{blobPort}/devstoreaccount1/";
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("IntegrationTest");

        builder.ConfigureServices(services =>
        {
            // Remove the production DbContext registration
            var descriptor = services.FirstOrDefault(d => d.ServiceType == typeof(DbContextOptions<PhotoAlbumContext>));
            if (descriptor != null)
            {
                services.Remove(descriptor);
            }

            // Add test DbContext with in-memory or testcontainer SQL
            services.AddDbContext<PhotoAlbumContext>(options =>
            {
                options.UseSqlServer(_sqlConnectionString);
            });
        });

        builder.ConfigureAppConfiguration((context, config) =>
        {
            // Add test appsettings override
            config.AddJsonFile("appsettings.IntegrationTest.json", optional: true);
            config.AddInMemoryCollection(new Dictionary<string, string>
            {
                { "ConnectionStrings:DefaultConnection", _sqlConnectionString },
                { "BlobStorage:Uri", $"http://{Environment.GetEnvironmentVariable("BLOB_HOST") ?? "localhost"}:{Environment.GetEnvironmentVariable("BLOB_PORT") ?? "10000"}/devstoreaccount1" },
                { "BlobStorage:ContainerName", _containerName },
                { "IsTestEnvironment", "true" }
            });
        });
    }

    public async Task InitializeAsync()
    {
        // Create HTTP test client
        TestClient = CreateClient();

        // Initialize blob storage client
        var blobServiceClient = new BlobServiceClient(new Uri($"http://{Environment.GetEnvironmentVariable("BLOB_HOST") ?? "localhost"}:{Environment.GetEnvironmentVariable("BLOB_PORT") ?? "10000"}/devstoreaccount1"), 
            new Azure.Storage.StorageSharedKeyCredential("devstoreaccount1", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="));
        
        BlobContainerClient = blobServiceClient.GetBlobContainerClient(_containerName);

        // Create blob container if not exists
        try
        {
            await BlobContainerClient.CreateIfNotExistsAsync();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Could not create blob container: {ex.Message}");
        }

        // Get DbContext and ensure database is created
        using var scope = Services.CreateScope();
        DbContext = scope.ServiceProvider.GetRequiredService<PhotoAlbumContext>();

        try
        {
            await DbContext.Database.EnsureDeletedAsync();
            await DbContext.Database.EnsureCreatedAsync();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Database initialization issue: {ex.Message}");
        }
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        // Clean up blob storage
        if (BlobContainerClient != null)
        {
            try
            {
                await BlobContainerClient.DeleteIfExistsAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Warning: Could not delete blob container: {ex.Message}");
            }
        }

        // Clean up database
        if (DbContext != null)
        {
            try
            {
                await DbContext.Database.EnsureDeletedAsync();
                await DbContext.DisposeAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Warning: Database cleanup issue: {ex.Message}");
            }
        }

        await base.DisposeAsync();
    }

    /// <summary>
    /// Helper: Create authenticated HTTP client with admin cookie
    /// </summary>
    public async Task<HttpClient> CreateAuthenticatedClientAsync()
    {
        var client = CreateClient();
        
        // Login to get auth cookie
        var loginContent = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            { "Input.Username", "admin" },
            { "Input.Password", "TestAdmin123!" }
        });

        var response = await client.PostAsync("/Login", loginContent);
        
        // Extract cookies from response if any
        if (response.Headers.TryGetValues("Set-Cookie", out var cookies))
        {
            foreach (var cookie in cookies)
            {
                client.DefaultRequestHeaders.Add("Cookie", cookie.Split(';')[0]);
            }
        }

        return client;
    }

    /// <summary>
    /// Helper: Seed photo records into database for test preconditions
    /// </summary>
    public async Task SeedPhotosAsync(params Photo[] photos)
    {
        foreach (var photo in photos)
        {
            DbContext.Photos.Add(photo);
        }
        await DbContext.SaveChangesAsync();
    }

    /// <summary>
    /// Helper: Get all photos from database
    /// </summary>
    public async Task<List<Photo>> GetAllPhotosAsync()
    {
        return await DbContext!.Photos.OrderByDescending(p => p.UploadedAt).ToListAsync();
    }

    /// <summary>
    /// Helper: Refresh DbContext (reload latest changes)
    /// </summary>
    public async Task RefreshDbContextAsync()
    {
        if (DbContext != null)
        {
            foreach (var entity in DbContext.ChangeTracker.Entries().ToList())
            {
                await entity.ReloadAsync();
            }
        }
    }

    /// <summary>
    /// Helper: Upload fixture file to blob storage
    /// </summary>
    public async Task<string> UploadFixtureFileAsync(string fixturePath, string? blobName = null)
    {
        blobName ??= Guid.NewGuid().ToString() + Path.GetExtension(fixturePath);
        var blobClient = BlobContainerClient.GetBlobClient(blobName);

        using var fileStream = File.OpenRead(fixturePath);
        await blobClient.UploadAsync(fileStream, overwrite: true);

        return blobName;
    }

    /// <summary>
    /// Helper: Download blob content as string
    /// </summary>
    public async Task<string> DownloadBlobAsStringAsync(string blobName)
    {
        var blobClient = BlobContainerClient.GetBlobClient(blobName);
        var download = await blobClient.DownloadAsync();
        using var sr = new StreamReader(download.Value.Content);
        return await sr.ReadToEndAsync();
    }

    /// <summary>
    /// Helper: Check if blob exists
    /// </summary>
    public async Task<bool> BlobExistsAsync(string blobName)
    {
        var blobClient = BlobContainerClient.GetBlobClient(blobName);
        return await blobClient.ExistsAsync();
    }

    /// <summary>
    /// Helper: Delete blob
    /// </summary>
    public async Task DeleteBlobAsync(string blobName)
    {
        var blobClient = BlobContainerClient.GetBlobClient(blobName);
        await blobClient.DeleteIfExistsAsync();
    }
}
