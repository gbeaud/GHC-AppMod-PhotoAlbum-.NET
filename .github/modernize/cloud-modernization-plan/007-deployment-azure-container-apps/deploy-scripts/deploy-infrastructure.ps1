#!/usr/bin/env pwsh
# Infrastructure Deployment Script for PhotoAlbum on Azure Container Apps
# This script deploys all Azure resources required for the PhotoAlbum application

param(
    [string]$EnvironmentName = "dev",
    [string]$ResourceGroupName = "rg-photoalbum-dev",
    [string]$Location = "eastus2",
    [string]$SubscriptionId = "cdea6d05-fcb9-446b-b0d4-2f71071885c4",
    [string]$SqlAdminPassword = "",
    [string]$ContainerImageName = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== PhotoAlbum Infrastructure Deployment ===" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentName" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Yellow

# Set subscription
Write-Host "`n--- Setting Subscription ---" -ForegroundColor Cyan
az account set --subscription $SubscriptionId
$account = az account show --output json | ConvertFrom-Json
Write-Host "✓ Working with subscription: $($account.name)" -ForegroundColor Green

# Verify resource group
Write-Host "`n--- Verifying Resource Group ---" -ForegroundColor Cyan
$rg = az group show --name $ResourceGroupName --location $Location --output json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($null -eq $rg) {
    Write-Host "⚠ Resource group '$ResourceGroupName' not found. Creating..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output json | Out-Null
    $rg = az group show --name $ResourceGroupName --output json | ConvertFrom-Json
}
Write-Host "✓ Resource group ready: $ResourceGroupName" -ForegroundColor Green

# Generate SQL Admin Password if not provided
if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
    Write-Host "`n⚠ SQL Admin Password not provided. Generating secure password..." -ForegroundColor Yellow
    # Generate a secure password with at least one uppercase, lowercase, number, and special character
    $SqlAdminPassword = -join ((65..90) + (97..122) + (48..57) + (33, 35, 36, 37, 38, 42, 43, 45, 46, 47, 58, 59, 61, 63, 64, 94, 95, 96, 123, 125, 126) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
    Write-Host "✓ Generated secure password" -ForegroundColor Green
}

# Set default container image if not provided
if ([string]::IsNullOrEmpty($ContainerImageName)) {
    $ContainerImageName = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    Write-Host "`n⚠ Container image name not provided. Using default: $ContainerImageName" -ForegroundColor Yellow
}

# Deploy Bicep template
Write-Host "`n--- Deploying Bicep Template ---" -ForegroundColor Cyan
Write-Host "Template: ./infra/main.bicep" -ForegroundColor Yellow

try {
    $deployment = az deployment group create `
        --name "photoalbum-deployment-$(Get-Date -Format 'yyyyMMddHHmmss')" `
        --resource-group $ResourceGroupName `
        --template-file "./infra/main.bicep" `
        --parameters `
            environmentName=$EnvironmentName `
            location=$Location `
            sqlAdminPassword=$SqlAdminPassword `
            webImageName=$ContainerImageName `
        --output json | ConvertFrom-Json
    
    Write-Host "✓ Deployment initiated successfully" -ForegroundColor Green
    Write-Host "Deployment Name: $($deployment.name)" -ForegroundColor Cyan
    
    # Check deployment status
    Write-Host "`n--- Waiting for deployment to complete ---" -ForegroundColor Cyan
    $maxRetries = 120
    $retryCount = 0
    $sleepInterval = 5
    
    do {
        $depStatus = az deployment group show `
            --resource-group $ResourceGroupName `
            --name $deployment.name `
            --output json | ConvertFrom-Json
        
        $retryCount++
        $progress = [Math]::Round(($retryCount / $maxRetries) * 100)
        Write-Host -NoNewline "`r[$progress%] Deployment state: $($depStatus.properties.provisioningState)  "
        
        if ($depStatus.properties.provisioningState -in @("Succeeded", "Failed")) {
            Write-Host ""
            break
        }
        
        if ($retryCount -ge $maxRetries) {
            Write-Host "`n❌ Deployment timeout after $($maxRetries * $sleepInterval) seconds" -ForegroundColor Red
            exit 1
        }
        
        Start-Sleep -Seconds $sleepInterval
    } while ($true)
    
    if ($depStatus.properties.provisioningState -ne "Succeeded") {
        Write-Host "❌ Deployment failed: $($depStatus.properties.provisioningState)" -ForegroundColor Red
        if ($depStatus.properties.error) {
            Write-Host "Error Details: $($depStatus.properties.error.message)" -ForegroundColor Red
        }
        exit 1
    }
    
    Write-Host "✓ Deployment completed successfully" -ForegroundColor Green
    
    # Extract outputs
    Write-Host "`n--- Extracting Deployment Outputs ---" -ForegroundColor Cyan
    $outputs = $depStatus.properties.outputs
    
    $outputValues = @{
        AZURE_LOCATION = $outputs.AZURE_LOCATION.value
        AZURE_RESOURCE_GROUP = $outputs.AZURE_RESOURCE_GROUP.value
        AZURE_CONTAINER_REGISTRY_ENDPOINT = $outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
        AZURE_CONTAINER_REGISTRY_NAME = $outputs.AZURE_CONTAINER_REGISTRY_NAME.value
        AZURE_CONTAINERAPP_NAME = $outputs.AZURE_CONTAINERAPP_NAME.value
        AZURE_CONTAINERAPP_FQDN = $outputs.AZURE_CONTAINERAPP_FQDN.value
        AZURE_CONTAINERAPP_URL = $outputs.AZURE_CONTAINERAPP_URL.value
        AZURE_SQL_SERVER_NAME = $outputs.AZURE_SQL_SERVER_NAME.value
        AZURE_SQL_SERVER_FQDN = $outputs.AZURE_SQL_SERVER_FQDN.value
        AZURE_SQL_DATABASE_NAME = $outputs.AZURE_SQL_DATABASE_NAME.value
        AZURE_STORAGE_ACCOUNT_NAME = $outputs.AZURE_STORAGE_ACCOUNT_NAME.value
        AZURE_STORAGE_BLOB_ENDPOINT = $outputs.AZURE_STORAGE_BLOB_ENDPOINT.value
        USER_ASSIGNED_IDENTITY_ID = $outputs.USER_ASSIGNED_IDENTITY_ID.value
        USER_ASSIGNED_IDENTITY_PRINCIPAL_ID = $outputs.USER_ASSIGNED_IDENTITY_PRINCIPAL_ID.value
        SQL_ADMIN_PASSWORD = $SqlAdminPassword
    }
    
    # Display outputs
    Write-Host "`n=== Infrastructure Deployment Outputs ===" -ForegroundColor Cyan
    $outputValues.GetEnumerator() | ForEach-Object {
        if ($_.Key -eq "SQL_ADMIN_PASSWORD") {
            Write-Host "$($_.Key): [REDACTED]" -ForegroundColor Green
        } else {
            Write-Host "$($_.Key): $($_.Value)" -ForegroundColor Green
        }
    }
    
    # Save outputs to file for later use
    $outputsFile = ".github/modernize/cloud-modernization-plan/007-deployment-azure-container-apps/deployment-outputs.json"
    $outputValues | ConvertTo-Json | Set-Content $outputsFile
    Write-Host "`n✓ Outputs saved to: $outputsFile" -ForegroundColor Green
    
    return $outputValues
}
catch {
    Write-Host "`n❌ Deployment failed with error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
