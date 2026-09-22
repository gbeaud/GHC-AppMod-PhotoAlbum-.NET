#!/bin/bash

# PhotoAlbum Azure Infrastructure Deployment Script (Bash)
# This script provisions all required Azure resources for PhotoAlbum cloud deployment

set -e  # Exit on error

# Default values
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-rg-photoalbum-dev}"
LOCATION="${LOCATION:-eastus2}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
TEMPLATE_FILE="${TEMPLATE_FILE:-main.bicep}"
PARAMETERS_FILE="${PARAMETERS_FILE:-main.parameters.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}$1${NC}"
    echo ""
}

# Header
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  PhotoAlbum Azure Infrastructure Deployment                    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verify Azure CLI is installed
log_info "Checking Azure CLI..."
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install it from https://aka.ms/azure-cli"
    exit 1
fi
echo "  Azure CLI version: $(az --version --query 'azure-cli' -o tsv)"

# Verify Bicep CLI is installed
log_info "Checking Bicep CLI..."
if ! az bicep version &> /dev/null 2>&1; then
    log_warn "Bicep CLI is not installed. Installing..."
    az bicep install
fi

# Check Azure login status
log_info "Checking Azure authentication..."
if ! az account show &> /dev/null 2>&1; then
    log_warn "Not logged in to Azure. Starting login..."
    az login
else
    ACCOUNT_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    echo "  Logged in as: $ACCOUNT_NAME"
    echo "  Subscription: $SUBSCRIPTION_ID"
fi

# Validate Bicep template
log_section "Validating Bicep template..."
if ! az bicep build --file "$TEMPLATE_FILE" > /dev/null 2>&1; then
    log_error "Bicep template validation failed"
    az bicep build --file "$TEMPLATE_FILE"
    exit 1
fi
log_info "Template is valid"

# Create resource group if it doesn't exist
log_section "Creating resource group..."
if ! az group show --name "$RESOURCE_GROUP_NAME" > /dev/null 2>&1; then
    echo "  Creating new resource group: $RESOURCE_GROUP_NAME"
    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --tags "environment=$ENVIRONMENT_NAME" "created=$(date +'%Y-%m-%d')" > /dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create resource group"
        exit 1
    fi
else
    echo "  Resource group already exists: $RESOURCE_GROUP_NAME"
fi

# Prompt for SQL Admin Password
log_section "Collecting deployment parameters..."
read -sp "  Enter SQL Server admin password (min 8 chars, must include uppercase, lowercase, number, special char): " SQL_ADMIN_PASSWORD
echo ""

# Validate password complexity
if [ ${#SQL_ADMIN_PASSWORD} -lt 8 ]; then
    log_error "Password must be at least 8 characters long"
    exit 1
fi

if ! [[ "$SQL_ADMIN_PASSWORD" =~ [A-Z] ]] || ! [[ "$SQL_ADMIN_PASSWORD" =~ [a-z] ]] || ! [[ "$SQL_ADMIN_PASSWORD" =~ [0-9] ]]; then
    log_error "Password must contain uppercase, lowercase, and numeric characters"
    exit 1
fi

# Deploy infrastructure
log_section "Deploying Azure infrastructure..."
echo "  This may take 5-10 minutes..."

DEPLOYMENT_NAME="deploy-$(date +'%Y%m%d-%H%M%S')"

if ! DEPLOYMENT=$(az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters \
        environmentName="$ENVIRONMENT_NAME" \
        location="$LOCATION" \
        sqlAdminPassword="$SQL_ADMIN_PASSWORD" \
    --output json 2>&1); then
    log_error "Deployment failed:"
    echo "$DEPLOYMENT"
    exit 1
fi

# Parse deployment outputs
OUTPUTS=$(echo "$DEPLOYMENT" | jq '.properties.outputs')

# Display deployment results
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deployment Successful!                                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_section "📊 Deployment Information:"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Location: $LOCATION"
echo "  Environment: $ENVIRONMENT_NAME"
echo "  Deployment ID: $DEPLOYMENT_NAME"
echo ""

log_section "🔗 Resource Endpoints:"
echo "  Container Registry: $(echo "$OUTPUTS" | jq -r '.AZURE_CONTAINER_REGISTRY_ENDPOINT.value // "N/A"')"
echo "  Container App URL: $(echo "$OUTPUTS" | jq -r '.AZURE_CONTAINERAPP_URL.value // "N/A"')"
echo "  SQL Server FQDN: $(echo "$OUTPUTS" | jq -r '.AZURE_SQL_SERVER_FQDN.value // "N/A"')"
echo "  Storage Account: $(echo "$OUTPUTS" | jq -r '.AZURE_STORAGE_ACCOUNT_NAME.value // "N/A"')"
echo ""

log_section "💾 Generated infra-config.md:"
echo "  Run: ./generate-infra-config.sh"
echo ""

log_section "⚠️  Important Notes:"
echo "  1. Save SQL admin password securely - you cannot retrieve it later"
echo "  2. Run 'az login' to authenticate Azure CLI before using other scripts"
echo "  3. Container App may take a few minutes to become accessible"
echo "  4. Check Azure Portal for detailed resource information"
echo ""

log_info "Deployment complete!"
