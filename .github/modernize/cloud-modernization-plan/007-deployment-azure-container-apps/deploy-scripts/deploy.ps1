#!/usr/bin/env pwsh
# Deploy PhotoAlbum Infrastructure using Bicep
# This script deploys all Azure resources for PhotoAlbum on Container Apps

param(
    [string]$EnvironmentName = "dev",
    [string]$Location = "eastus2",
    [string]$ResourceGroupName = "rg-photoalbum-dev",
    [string]$SubscriptionId = "cdea6d05-fcb9-446b-b0d4-2f71071885c4"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PhotoAlbum Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Set subscription
Write-Host "`n[1/5] Setting subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId
$account = az account show --output json | ConvertFrom-Json
Write-Host "✓ Working with subscription: $($account.name)" -ForegroundColor Green

# Verify/create resource group
Write-Host "`n[2/5] Verifying resource group..." -ForegroundColor Yellow
$rg = az group show --name $ResourceGroupName --output json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($null -eq $rg) {
    Write-Host "Creating resource group '$ResourceGroupName'..." -ForegroundColor Cyan
    az group create --name $ResourceGroupName --location $Location --output none
}
Write-Host "✓ Resource group: $ResourceGroupName" -ForegroundColor Green

# Generate SQL Admin Password
Write-Host "`n[3/5] Generating SQL admin password..." -ForegroundColor Yellow
$SqlAdminPassword = -join ((65..90) + (97..122) + (48..57) + (33, 35, 36, 37, 38, 42, 43, 45, 46, 47, 58, 59, 61, 63, 64, 94, 95, 96, 123, 125, 126) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
Write-Host "✓ SQL admin password generated" -ForegroundColor Green

# Build Bicep template
Write-Host "`n[4/5] Building Bicep template..." -ForegroundColor Yellow
az bicep build --file "./infra/main.bicep" --outfile "./infra/main.json" --output none 2>&1
Write-Host "✓ Bicep template built" -ForegroundColor Green

# Deploy
Write-Host "`n[5/5] Deploying infrastructure..." -ForegroundColor Yellow
Write-Host "This may take 10-15 minutes..." -ForegroundColor Cyan

$deploymentName = "photoalbum-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Create the deployment
$deployment = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file "./infra/main.bicep" `
    --parameters `
        environmentName=$EnvironmentName `
        location=$Location `
        sqlAdminPassword=$SqlAdminPassword `
        webImageName="mcr.microsoft.com/azuredocs/containerapps-helloworld:latest" `
    --output json 2>&1

# Parse deployment result
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Deployment failed!" -ForegroundColor Red
    Write-Host $deployment
    exit 1
}

$depObj = $deployment | ConvertFrom-Json

Write-Host "✓ Deployment completed!" -ForegroundColor Green
Write-Host "Provisioning State: $($depObj.properties.provisioningState)" -ForegroundColor Cyan

if ($depObj.properties.provisioningState -ne "Succeeded") {
    Write-Host "`n❌ Deployment did not succeed!" -ForegroundColor Red
    if ($depObj.properties.error) {
        Write-Host "Error: $($depObj.properties.error.message)" -ForegroundColor Red
    }
    exit 1
}

# Extract and save outputs
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Deployment Outputs" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$outputsFile = ".github/modernize/cloud-modernization-plan/007-deployment-azure-container-apps/deployment-outputs.json"

$outputs = @{}
$depObj.properties.outputs | ForEach-Object {
    $_.PSObject.Properties | ForEach-Object {
        $name = $_.Name
        $value = $_.Value.value
        $outputs[$name] = $value
        
        # Display output
        if ($name -match "PASSWORD|SECRET|KEY") {
            Write-Host "$($name): [REDACTED]" -ForegroundColor Green
        } else {
            Write-Host "$($name): $value" -ForegroundColor Green
        }
    }
}

# Save outputs to file
if (-not (Test-Path (Split-Path $outputsFile))) {
    New-Item -ItemType Directory -Path (Split-Path $outputsFile) -Force | Out-Null
}

$outputs | ConvertTo-Json | Set-Content $outputsFile
Write-Host "`n✓ Outputs saved to: $outputsFile" -ForegroundColor Green

# Return outputs for further use
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✓ Infrastructure deployment completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

# Save SQL password to file (this will be needed for later steps)
$passwordFile = ".github/modernize/cloud-modernization-plan/007-deployment-azure-container-apps/sql-admin-password.txt"
$SqlAdminPassword | Set-Content $passwordFile -Force
Write-Host "✓ SQL admin password saved (password file created)" -ForegroundColor Green

exit 0
