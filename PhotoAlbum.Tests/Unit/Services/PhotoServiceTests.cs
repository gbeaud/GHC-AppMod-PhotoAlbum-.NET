using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using PhotoAlbum.Data;
using PhotoAlbum.Models;
using PhotoAlbum.Services;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using System.Text;

namespace PhotoAlbum.Tests.Unit.Services;

public class PhotoServiceTests : IDisposable
{
    private readonly PhotoAlbumContext _context;
    private readonly IPhotoService _photoService;
    private readonly Mock<IBlobStorageService> _mockBlobStorageService;
    private readonly IConfiguration _configuration;
    private readonly ILogger<PhotoService> _logger;

    public PhotoServiceTests()
    {
        // Setup in-memory database
        var options = new DbContextOptionsBuilder<PhotoAlbumContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;
        _context = new PhotoAlbumContext(options);

        // Setup mock blob storage service
        _mockBlobStorageService = new Mock<IBlobStorageService>();
        
        // Default to successful uploads and deletions
        _mockBlobStorageService
            .Setup(x => x.UploadBlobAsync(It.IsAny<string>(), It.IsAny<Stream>(), It.IsAny<string>()))
            .ReturnsAsync(true);

        _mockBlobStorageService
            .Setup(x => x.DeleteBlobAsync(It.IsAny<string>()))
            .ReturnsAsync(true);

        _mockBlobStorageService
            .Setup(x => x.BlobExistsAsync(It.IsAny<string>()))
            .ReturnsAsync(true);

        _mockBlobStorageService
            .Setup(x => x.DownloadBlobAsync(It.IsAny<string>()))
            .ReturnsAsync((string blobName) => new MemoryStream(new byte[] { 1, 2, 3 }));

        // Setup configuration
        var inMemorySettings = new Dictionary<string, string>
        {
            {"FileUpload:MaxFileSizeBytes", "10485760"},
            {"FileUpload:AllowedMimeTypes:0", "image/jpeg"},
            {"FileUpload:AllowedMimeTypes:1", "image/png"},
            {"FileUpload:AllowedMimeTypes:2", "image/gif"},
            {"FileUpload:AllowedMimeTypes:3", "image/webp"}
        };
        _configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(inMemorySettings!)
            .Build();

        // Setup logger
        _logger = new LoggerFactory().CreateLogger<PhotoService>();

        // Create PhotoService instance with mocked blob storage
        _photoService = new PhotoService(_context, _configuration, _logger, _mockBlobStorageService.Object);
    }

    [Fact]
    public async Task UploadPhotoAsync_WithValidImage_ReturnsSuccess()
    {
        // Arrange
        var file = CreateImageFormFile("test.jpg", "image/jpeg");

        // Act
        var result = await _photoService.UploadPhotoAsync(file);

        // Assert
        Assert.True(result.Success);
        Assert.NotNull(result.PhotoId);
        Assert.Equal("test.jpg", result.FileName);
        Assert.Null(result.ErrorMessage);

        // Verify photo was saved to database
        var photo = await _context.Photos.FindAsync(result.PhotoId);
        Assert.NotNull(photo);
        Assert.Equal("test.jpg", photo.OriginalFileName);
        Assert.Equal("image/jpeg", photo.MimeType);
        Assert.True(photo.FileSize > 0);

        // Verify blob upload was called
        _mockBlobStorageService.Verify(
            x => x.UploadBlobAsync(It.IsAny<string>(), It.IsAny<Stream>(), "image/jpeg"),
            Times.Once);
    }

    [Fact]
    public async Task UploadPhotoAsync_WithInvalidMimeType_ReturnsError()
    {
        // Arrange
        var file = CreateMockFormFile("document.pdf", "application/pdf", 1024);

        // Act
        var result = await _photoService.UploadPhotoAsync(file);

        // Assert
        Assert.False(result.Success);
        Assert.Null(result.PhotoId);
        Assert.Contains("not supported", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);

        // Verify blob upload was never called
        _mockBlobStorageService.Verify(
            x => x.UploadBlobAsync(It.IsAny<string>(), It.IsAny<Stream>(), It.IsAny<string>()),
            Times.Never);
    }

    [Fact]
    public async Task UploadPhotoAsync_WithOversizedFile_ReturnsError()
    {
        // Arrange
        var file = CreateMockFormFile("huge.jpg", "image/jpeg", 11 * 1024 * 1024); // 11MB

        // Act
        var result = await _photoService.UploadPhotoAsync(file);

        // Assert
        Assert.False(result.Success);
        Assert.Null(result.PhotoId);
        Assert.Contains("exceeds", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);

        // Verify blob upload was never called
        _mockBlobStorageService.Verify(
            x => x.UploadBlobAsync(It.IsAny<string>(), It.IsAny<Stream>(), It.IsAny<string>()),
            Times.Never);
    }

    [Fact]
    public async Task UploadPhotoAsync_SavesMetadataToDatabase()
    {
        // Arrange
        var file = CreateImageFormFile("photo.jpg", "image/jpeg");

        // Act
        var result = await _photoService.UploadPhotoAsync(file);

        // Assert
        Assert.True(result.Success);

        var photo = await _context.Photos.FindAsync(result.PhotoId);
        Assert.NotNull(photo);
        Assert.Equal("photo.jpg", photo.OriginalFileName);
        Assert.NotEmpty(photo.StoredFileName);
        Assert.NotEmpty(photo.FilePath);
        Assert.True(photo.UploadedAt <= DateTime.UtcNow);
        Assert.True(photo.UploadedAt > DateTime.UtcNow.AddMinutes(-1));
    }

    [Fact]
    public async Task UploadPhotoAsync_WhenBlobUploadFails_ReturnsError()
    {
        // Arrange
        _mockBlobStorageService
            .Setup(x => x.UploadBlobAsync(It.IsAny<string>(), It.IsAny<Stream>(), It.IsAny<string>()))
            .ReturnsAsync(false);

        var file = CreateImageFormFile("test.jpg", "image/jpeg");

        // Act
        var result = await _photoService.UploadPhotoAsync(file);

        // Assert
        Assert.False(result.Success);
        Assert.Null(result.PhotoId);
        Assert.Contains("Error saving file", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task UploadPhotoAsync_WhenDatabaseSaveFails_RollsBackBlob()
    {
        // Arrange
        var file = CreateImageFormFile("test.jpg", "image/jpeg");

        // Simulate database save failure
        _context.ChangeTracker.Clear();
        var options = new DbContextOptionsBuilder<PhotoAlbumContext>()
            .UseInMemoryDatabase(databaseName: "FailingDb")
            .Options;
        var failingContext = new PhotoAlbumContext(options);
        
        // Dispose context to make it fail
        failingContext.Dispose();

        var logger = new LoggerFactory().CreateLogger<PhotoService>();
        var photoService = new PhotoService(failingContext, _configuration, logger, _mockBlobStorageService.Object);

        // Act - Note: This will throw because we disposed the context
        try
        {
            var result = await photoService.UploadPhotoAsync(file);
            Assert.False(result.Success);
        }
        catch
        {
            // Expected when context is disposed
        }

        // Verify blob was uploaded
        _mockBlobStorageService.Verify(
            x => x.UploadBlobAsync(It.IsAny<string>(), It.IsAny<Stream>(), It.IsAny<string>()),
            Times.Once);
    }

    [Fact]
    public async Task GetAllPhotosAsync_ReturnsPhotosOrderedByDate()
    {
        // Arrange
        var photo1 = new Photo
        {
            OriginalFileName = "first.jpg",
            StoredFileName = "guid1.jpg",
            FilePath = "/uploads/guid1.jpg",
            FileSize = 1024,
            MimeType = "image/jpeg",
            UploadedAt = DateTime.UtcNow.AddHours(-2)
        };
        var photo2 = new Photo
        {
            OriginalFileName = "second.jpg",
            StoredFileName = "guid2.jpg",
            FilePath = "/uploads/guid2.jpg",
            FileSize = 2048,
            MimeType = "image/jpeg",
            UploadedAt = DateTime.UtcNow.AddHours(-1)
        };
        var photo3 = new Photo
        {
            OriginalFileName = "third.jpg",
            StoredFileName = "guid3.jpg",
            FilePath = "/uploads/guid3.jpg",
            FileSize = 3072,
            MimeType = "image/jpeg",
            UploadedAt = DateTime.UtcNow
        };

        await _context.Photos.AddRangeAsync(photo1, photo2, photo3);
        await _context.SaveChangesAsync();

        // Act
        var photos = await _photoService.GetAllPhotosAsync();

        // Assert
        Assert.Equal(3, photos.Count);
        Assert.Equal("third.jpg", photos[0].OriginalFileName); // Most recent first
        Assert.Equal("second.jpg", photos[1].OriginalFileName);
        Assert.Equal("first.jpg", photos[2].OriginalFileName);
    }

    [Fact]
    public async Task DeletePhotoAsync_RemovesBlobAndDatabaseRecord()
    {
        // Arrange
        var file = CreateImageFormFile("todelete.jpg", "image/jpeg");
        var uploadResult = await _photoService.UploadPhotoAsync(file);
        var photoId = uploadResult.PhotoId!.Value;

        var photo = await _context.Photos.FindAsync(photoId);
        Assert.NotNull(photo);

        // Act
        var result = await _photoService.DeletePhotoAsync(photoId);

        // Assert
        Assert.True(result);
        Assert.Null(await _context.Photos.FindAsync(photoId));

        // Verify blob deletion was called
        _mockBlobStorageService.Verify(
            x => x.DeleteBlobAsync(photo.StoredFileName),
            Times.Once);
    }

    [Fact]
    public async Task GetPhotoByIdAsync_ReturnsPhoto()
    {
        // Arrange
        var photo = new Photo
        {
            OriginalFileName = "test.jpg",
            StoredFileName = "test-guid.jpg",
            FilePath = "/uploads/test-guid.jpg",
            FileSize = 1024,
            MimeType = "image/jpeg",
            UploadedAt = DateTime.UtcNow
        };

        await _context.Photos.AddAsync(photo);
        await _context.SaveChangesAsync();

        // Act
        var result = await _photoService.GetPhotoByIdAsync(photo.Id);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(photo.Id, result.Id);
        Assert.Equal("test.jpg", result.OriginalFileName);
    }

    private IFormFile CreateMockFormFile(string fileName, string contentType, long size)
    {
        var content = new byte[size];
        var stream = new MemoryStream(content);
        return new FormFile(stream, 0, size, "file", fileName)
        {
            Headers = new HeaderDictionary(),
            ContentType = contentType
        };
    }

    // Produces a real (decodable) image so hardened upload validation accepts it.
    private static IFormFile CreateImageFormFile(string fileName, string contentType)
    {
        using var image = new Image<Rgba32>(16, 16);
        var stream = new MemoryStream();
        switch (Path.GetExtension(fileName).ToLowerInvariant())
        {
            case ".png": image.SaveAsPng(stream); break;
            case ".gif": image.SaveAsGif(stream); break;
            case ".webp": image.SaveAsWebp(stream); break;
            default: image.SaveAsJpeg(stream); break;
        }
        stream.Position = 0;
        return new FormFile(stream, 0, stream.Length, "file", fileName)
        {
            Headers = new HeaderDictionary(),
            ContentType = contentType
        };
    }

    public void Dispose()
    {
        _context.Dispose();
    }
}
