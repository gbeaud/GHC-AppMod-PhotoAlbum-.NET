using System.Net;
using FluentAssertions;
using PhotoAlbum.Data;
using PhotoAlbum.Models;

namespace PhotoAlbum.Tests.Integration;

/// <summary>
/// Post-Migration Integration Tests for PhotoAlbum
/// 
/// Verifies that the migrated application (with Azure Blob Storage and SQL Database + Managed Identity)
/// maintains the same behavioral contract as defined in the frozen baseline specification.
/// 
/// Test framework: xUnit with WebApplicationFactory
/// Infrastructure: Testcontainers (SQL Server + Azurite)
/// 
/// Note: Tests require Docker and running testcontainers (SQL Server and Azurite).
/// Run with: dotnet test PhotoAlbum.Tests -c Release
/// </summary>
public class PhotoAlbumPostMigrationIT : IAsyncLifetime
{
    private readonly PhotoAlbumWebApplicationFactory _factory;
    private HttpClient? _client;

    public PhotoAlbumPostMigrationIT()
    {
        _factory = new PhotoAlbumWebApplicationFactory();
    }

    public async Task InitializeAsync()
    {
        await _factory.InitializeAsync();
        _client = _factory.TestClient;
    }

    public async Task DisposeAsync()
    {
        _client?.Dispose();
        await _factory.DisposeAsync();
    }

    /// <summary>
    /// TC-WEB-001: List all photos (happy path)
    /// 
    /// When a user visits the index page with multiple photos, all are returned
    /// in reverse chronological order (newest first).
    /// </summary>
    [Fact(DisplayName = "TC-WEB-001 — List all photos (happy path)")]
    public async Task tcWeb001_ListAllPhotosHappyPath()
    {
        // Arrange: Preconditions
        var now = DateTime.UtcNow;
        var photos = new[]
        {
            new Photo { OriginalFileName = "photo1.jpg", UploadedAt = now.AddHours(-2), MimeType = "image/jpeg", Width = 100, Height = 100, StoredFileName = Guid.NewGuid().ToString() + ".jpg" },
            new Photo { OriginalFileName = "photo2.jpg", UploadedAt = now.AddHours(-1), MimeType = "image/jpeg", Width = 100, Height = 100, StoredFileName = Guid.NewGuid().ToString() + ".jpg" },
            new Photo { OriginalFileName = "photo3.jpg", UploadedAt = now, MimeType = "image/jpeg", Width = 100, Height = 100, StoredFileName = Guid.NewGuid().ToString() + ".jpg" }
        };

        await _factory.SeedPhotosAsync(photos);

        // Act: HTTP GET request to /Index
        var response = await _client!.GetAsync("/");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var content = await response.Content.ReadAsStringAsync();
        content.Should().Contain("photo3.jpg");
        content.Should().Contain("photo2.jpg");
        content.Should().Contain("photo1.jpg");

        var photosResult = await _factory.GetAllPhotosAsync();
        photosResult.Should().HaveCount(3);
        photosResult[0].OriginalFileName.Should().Be("photo3.jpg");
        photosResult[1].OriginalFileName.Should().Be("photo2.jpg");
        photosResult[2].OriginalFileName.Should().Be("photo1.jpg");
    }

    /// <summary>
    /// TC-WEB-002: Upload valid photo (happy path)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-002 — Upload valid photo (happy path)")]
    public async Task tcWeb002_UploadValidPhotoHappyPath()
    {
        // Arrange: Load testdata fixture
        var fixturePath = FindTestdataFile("sample-16x16.png");
        if (!File.Exists(fixturePath))
        {
            throw new FileNotFoundException($"Test fixture not found: {fixturePath}");
        }

        using var fileStream = File.OpenRead(fixturePath);
        using var content = new MultipartFormDataContent();
        var fileContent = new StreamContent(fileStream);
        fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("image/png");
        content.Add(fileContent, "files", "photo.png");

        // Act
        var response = await _client!.PostAsync("/?handler=Upload", content);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var responseContent = await response.Content.ReadAsStringAsync();
        responseContent.Should().Contain("success");

        var photos = await _factory.GetAllPhotosAsync();
        photos.Should().HaveCount(1);
        photos[0].OriginalFileName.Should().Be("photo.png");
        photos[0].MimeType.Should().Be("image/png");
        photos[0].Width.Should().Be(16);
        photos[0].Height.Should().Be(16);
    }

    /// <summary>
    /// TC-WEB-003: Upload with invalid file type (failure)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-003 — Upload with invalid file type (failure)")]
    public async Task tcWeb003_UploadInvalidFileTypeFailure()
    {
        // Arrange
        var fixturePath = FindTestdataFile("invalid-file.txt");
        using var fileStream = File.OpenRead(fixturePath);
        using var content = new MultipartFormDataContent();
        var fileContent = new StreamContent(fileStream);
        fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("text/plain");
        content.Add(fileContent, "files", "document.txt");

        // Act
        var response = await _client!.PostAsync("/?handler=Upload", content);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var responseContent = await response.Content.ReadAsStringAsync();
        responseContent.Should().Contain("false");

        var photos = await _factory.GetAllPhotosAsync();
        photos.Should().BeEmpty();
    }

    /// <summary>
    /// TC-WEB-004: Upload file exceeding size limit (boundary)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-004 — Upload file exceeding size limit (boundary)")]
    public async Task tcWeb004_UploadFileSizeExceedsBoundary()
    {
        // Arrange
        var fixturePath = FindTestdataFile("oversized-image.bin");
        using var fileStream = File.OpenRead(fixturePath);
        using var content = new MultipartFormDataContent();
        var fileContent = new StreamContent(fileStream);
        fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("image/jpeg");
        content.Add(fileContent, "files", "huge.jpg");

        // Act
        var response = await _client!.PostAsync("/?handler=Upload", content);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var photos = await _factory.GetAllPhotosAsync();
        photos.Should().BeEmpty();
    }

    /// <summary>
    /// TC-WEB-005: Upload empty file (special input)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-005 — Upload empty file (special input)")]
    public async Task tcWeb005_UploadEmptyFileSpecialInput()
    {
        // Arrange
        using var content = new MultipartFormDataContent();
        var fileContent = new StreamContent(new MemoryStream());
        fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("image/jpeg");
        content.Add(fileContent, "files", "empty.jpg");

        // Act
        var response = await _client!.PostAsync("/?handler=Upload", content);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var photos = await _factory.GetAllPhotosAsync();
        photos.Should().BeEmpty();
    }

    /// <summary>
    /// TC-WEB-006: View photo detail (happy path)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-006 — View photo detail (happy path)")]
    public async Task tcWeb006_ViewPhotoDetailHappyPath()
    {
        // Arrange
        var now = DateTime.UtcNow;
        var photos = new[]
        {
            new Photo { OriginalFileName = "photo1.jpg", UploadedAt = now.AddHours(-2), MimeType = "image/jpeg", Width = 100, Height = 100, StoredFileName = Guid.NewGuid().ToString() + ".jpg" },
            new Photo { OriginalFileName = "photo2.jpg", UploadedAt = now.AddHours(-1), MimeType = "image/jpeg", Width = 100, Height = 100, StoredFileName = Guid.NewGuid().ToString() + ".jpg" },
            new Photo { OriginalFileName = "photo3.jpg", UploadedAt = now, MimeType = "image/jpeg", Width = 100, Height = 100, StoredFileName = Guid.NewGuid().ToString() + ".jpg" }
        };

        await _factory.SeedPhotosAsync(photos);
        await _factory.RefreshDbContextAsync();

        var photoIds = (await _factory.GetAllPhotosAsync()).OrderByDescending(p => p.UploadedAt).ToList();

        // Act
        var response = await _client!.GetAsync($"/Detail/{photoIds[1].Id}");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var content = await response.Content.ReadAsStringAsync();
        content.Should().Contain("photo2.jpg");
    }

    /// <summary>
    /// TC-WEB-007: View non-existent photo (failure)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-007 — View non-existent photo (failure)")]
    public async Task tcWeb007_ViewNonExistentPhotoFailure()
    {
        // Act
        var response = await _client!.GetAsync("/Detail/999");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    /// <summary>
    /// TC-WEB-008: Delete photo authenticated (happy path)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-008 — Delete photo authenticated (happy path)")]
    public async Task tcWeb008_DeletePhotoAuthenticatedHappyPath()
    {
        // Arrange
        var photo = new Photo
        {
            OriginalFileName = "photo.jpg",
            UploadedAt = DateTime.UtcNow,
            MimeType = "image/jpeg",
            Width = 100,
            Height = 100,
            StoredFileName = Guid.NewGuid().ToString() + ".jpg"
        };

        await _factory.SeedPhotosAsync(photo);
        await _factory.RefreshDbContextAsync();

        var authClient = await _factory.CreateAuthenticatedClientAsync();
        var photoId = (await _factory.GetAllPhotosAsync()).First().Id;

        // Act
        var response = await authClient.PostAsync($"/Detail/{photoId}?handler=Delete", new StringContent(""));

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Found);
        var photosAfter = await _factory.GetAllPhotosAsync();
        photosAfter.Should().BeEmpty();
    }

    /// <summary>
    /// TC-WEB-009: Delete photo unauthenticated (failure)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-009 — Delete photo unauthenticated (failure)")]
    public async Task tcWeb009_DeletePhotoUnauthenticatedFailure()
    {
        // Arrange
        var photo = new Photo
        {
            OriginalFileName = "photo.jpg",
            UploadedAt = DateTime.UtcNow,
            MimeType = "image/jpeg",
            Width = 100,
            Height = 100,
            StoredFileName = Guid.NewGuid().ToString() + ".jpg"
        };

        await _factory.SeedPhotosAsync(photo);
        await _factory.RefreshDbContextAsync();

        var photoId = (await _factory.GetAllPhotosAsync()).First().Id;

        // Act
        var response = await _client!.PostAsync($"/Detail/{photoId}?handler=Delete", new StringContent(""));

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Found);
        var photosAfter = await _factory.GetAllPhotosAsync();
        photosAfter.Should().HaveCount(1);
    }

    /// <summary>
    /// TC-WEB-010: Delete non-existent photo (failure)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-010 — Delete non-existent photo (failure)")]
    public async Task tcWeb010_DeleteNonExistentPhotoFailure()
    {
        // Arrange
        var authClient = await _factory.CreateAuthenticatedClientAsync();

        // Act
        var response = await authClient.PostAsync("/Detail/999?handler=Delete", new StringContent(""));

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Found);
    }

    /// <summary>
    /// TC-WEB-011: Login with valid credentials (happy path)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-011 — Login with valid credentials (happy path)")]
    public async Task tcWeb011_LoginWithValidCredentialsHappyPath()
    {
        // Arrange
        var loginContent = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            { "Input.Username", "admin" },
            { "Input.Password", "TestAdmin123!" }
        });

        // Act
        var response = await _client!.PostAsync("/Login", loginContent);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Found);
        response.Headers.Location.Should().NotBeNull();
    }

    /// <summary>
    /// TC-WEB-012: Login with invalid credentials (failure)
    /// </summary>
    [Fact(DisplayName = "TC-WEB-012 — Login with invalid credentials (failure)")]
    public async Task tcWeb012_LoginWithInvalidCredentialsFailure()
    {
        // Arrange
        var loginContent = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            { "Input.Username", "admin" },
            { "Input.Password", "WrongPassword" }
        });

        // Act
        var response = await _client!.PostAsync("/Login", loginContent);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var content = await response.Content.ReadAsStringAsync();
        content.Should().Contain("Invalid");
    }

    /// <summary>
    /// Helper: Find testdata file
    /// </summary>
    private static string FindTestdataFile(string filename)
    {
        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var searchPaths = new[]
        {
            Path.Combine(baseDir, "..", "..", "..", "PhotoAlbum.Tests", "test-cases", "testdata", "inputs", filename),
            Path.Combine(baseDir, "test-cases", "testdata", "inputs", filename),
            Path.Combine(baseDir, "../../../../PhotoAlbum.Tests/test-cases/testdata/inputs", filename)
        };

        foreach (var path in searchPaths)
        {
            var fullPath = Path.GetFullPath(path);
            if (File.Exists(fullPath))
            {
                return fullPath;
            }
        }

        throw new FileNotFoundException($"Testdata file not found: {filename}");
    }
}
