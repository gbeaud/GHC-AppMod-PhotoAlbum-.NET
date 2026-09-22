#!/usr/bin/env pwsh

# PhotoAlbum Azure Infrastructure Deployment Script (PowerShell)
# This script provisions all required Azure resources for PhotoAlbum cloud deployment

param(
    [string]$ResourceGroupName = "rg-photoalbum-dev",
    [string]$Location = "eastus2",
    [string]$EnvironmentName = "dev",
    [string]$TemplateFile = "main.bicep",
    [string]$ParametersFile = "main.parameters.json"
)

# Set strict mode
Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PhotoAlbum Azure Infrastructure Deployment                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verify Azure CLI is installed
Write-Host "✓ Checking Azure CLI..." -ForegroundColor Green
$azVersion = az --version 2>$null
if ($null -eq $azVersion) {
    Write-Host "✗ Azure CLI is not installed. Please install it from https://aka.ms/azure-cli" -ForegroundColor Red
    exit 1
}
Write-Host "  Azure CLI version: $(az --version --query 'azure-cli' -o tsv 2>/dev/null)" -ForegroundColor Gray

# Verify Bicep CLI is installed
Write-Host "✓ Checking Bicep CLI..." -ForegroundColor Green
$bicepVersion = az bicep version 2>$null
if ($null -eq $bicepVersion) {
    Write-Host "⚠ Bicep CLI is not installed. Installing..." -ForegroundColor Yellow
    az bicep install 2>$null
}

# Check Azure login status
Write-Host "✓ Checking Azure authentication..." -ForegroundColor Green
$currentAccount = az account show 2>$null
if ($null -eq $currentAccount) {
    Write-Host "⚠ Not logged in to Azure. Starting login..." -ForegroundColor Yellow
    az login
} else {
    $accountName = $currentAccount | ConvertFrom-Json | Select-Object -ExpandProperty name
    $subscriptionId = $currentAccount | ConvertFrom-Json | Select-Object -ExpandProperty id
    Write-Host "  Logged in as: $accountName" -ForegroundColor Gray
    Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
}

# Validate Bicep template
Write-Host ""
Write-Host "✓ Validating Bicep template..." -ForegroundColor Green
$bicepValidation = az bicep build --file $TemplateFile 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Bicep template validation failed:" -ForegroundColor Red
    Write-Host $bicepValidation -ForegroundColor Red
    exit 1
}
Write-Host "  Template is valid" -ForegroundColor Gray

# Create resource group if it doesn't exist
Write-Host ""
Write-Host "✓ Creating resource group..." -ForegroundColor Green
$rgExists = az group exists --name $ResourceGroupName 2>$null
if ($rgExists -eq "false") {
    Write-Host "  Creating new resource group: $ResourceGroupName" -ForegroundColor Gray
    az group create `
        --name $ResourceGroupName `
        --location $Location `
        --tags "environment=$EnvironmentName" "created=$(Get-Date -Format 'yyyy-MM-dd')" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to create resource group" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  Resource group already exists: $ResourceGroupName" -ForegroundColor Gray
}

# Prompt for SQL Admin Password if not provided
Write-Host ""
Write-Host "✓ Collecting deployment parameters..." -ForegroundColor Green

# Generate secure SQL password if needed
$sqlAdminPassword = Read-Host "  Enter SQL Server admin password (min 8 chars, must include uppercase, lowercase, number, special char)" -AsSecureString
$sqlAdminPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sqlAdminPassword)
)

# Validate password complexity
if ($sqlAdminPasswordPlain.Length -lt 8) {
    Write-Host "✗ Password must be at least 8 characters long" -ForegroundColor Red
    exit 1
}
if (-not ($sqlAdminPasswordPlain -match '[A-Z]') -or -not ($sqlAdminPasswordPlain -match '[a-z]') -or -not ($sqlAdminPasswordPlain -match '\d')) {
    Write-Host "✗ Password must contain uppercase, lowercase, and numeric characters" -ForegroundColor Red
    exit 1
}

# Deploy infrastructure
Write-Host ""
Write-Host "✓ Deploying Azure infrastructure..." -ForegroundColor Green
Write-Host "  This may take 5-10 minutes..." -ForegroundColor Gray

$deploymentName = "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$deployment = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file $TemplateFile `
    --parameters `
        environmentName=$EnvironmentName `
        location=$Location `
        sqlAdminPassword=$sqlAdminPasswordPlain `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Deployment failed:" -ForegroundColor Red
    Write-Host $deployment -ForegroundColor Red
    exit 1
}

# Parse deployment outputs
$deploymentObject = $deployment | ConvertFrom-Json
$outputs = $deploymentObject.properties.outputs

# Display deployment results
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Deployment Successful!                                        ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "📊 Deployment Information:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host "  Environment: $EnvironmentName" -ForegroundColor White
Write-Host "  Deployment ID: $deploymentName" -ForegroundColor White
Write-Host ""

Write-Host "🔗 Resource Endpoints:" -ForegroundColor Cyan
Write-Host "  Container Registry: $(if ($outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT) { $outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value } else { 'N/A' })" -ForegroundColor White
Write-Host "  Container App URL: $(if ($outputs.AZURE_CONTAINERAPP_URL) { $outputs.AZURE_CONTAINERAPP_URL.value } else { 'N/A' })" -ForegroundColor White
Write-Host "  SQL Server FQDN: $(if ($outputs.AZURE_SQL_SERVER_FQDN) { $outputs.AZURE_SQL_SERVER_FQDN.value } else { 'N/A' })" -ForegroundColor White
Write-Host "  Storage Account: $(if ($outputs.AZURE_STORAGE_ACCOUNT_NAME) { $outputs.AZURE_STORAGE_ACCOUNT_NAME.value } else { 'N/A' })" -ForegroundColor White
Write-Host ""

Write-Host "💾 Generated infra-config.md:" -ForegroundColor Cyan
Write-Host "  Run: ./generate-infra-config.ps1" -ForegroundColor White
Write-Host ""

Write-Host "⚠️  Important Notes:" -ForegroundColor Yellow
Write-Host "  1. Save SQL admin password securely - you cannot retrieve it later" -ForegroundColor Gray
Write-Host "  2. Run 'az login' to authenticate Azure CLI before using other scripts" -ForegroundColor Gray
Write-Host "  3. Container App may take a few minutes to become accessible" -ForegroundColor Gray
Write-Host "  4. Check Azure Portal for detailed resource information" -ForegroundColor Gray
Write-Host ""

Write-Host "✓ Deployment complete!" -ForegroundColor Green
