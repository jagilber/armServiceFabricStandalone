<#
.SYNOPSIS
    Deploy Azure Service Fabric Standalone cluster using environment variables.

.DESCRIPTION
    This script loads environment variables from .env file and deploys the ARM template
    using the azure-az-deploy-template.ps1 script from powershellScripts repository.

.PARAMETER Test
    If specified, will test the deployment without actually deploying.

.PARAMETER Clean
    If specified, will delete existing resource group and deployment.

.PARAMETER Force
    If specified, will force operations without prompting.

.PARAMETER EnvFile
    Path to the .env file. Defaults to .env in the script directory.

.EXAMPLE
    .\deploy.ps1
    Deploy using variables from .env file

.EXAMPLE
    .\deploy.ps1 -Test
    Test deployment without actually deploying

.EXAMPLE
    .\deploy.ps1 -Clean -Force
    Clean existing resources and deploy

.NOTES
    Requires:
    - Azure PowerShell modules (Az.Accounts, Az.Resources)
    - .env file with configuration (copy from .env.example)
    - load-envFile.ps1 from powershellScripts repository
    - azure-az-deploy-template.ps1 from powershellScripts repository
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Test,
    
    [Parameter()]
    [switch]$Clean,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure Service Fabric Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if .env file exists
if (-not (Test-Path $EnvFile)) {
    Write-Error "Environment file not found: $EnvFile"
    Write-Host "Please copy .env.example to .env and fill in your values." -ForegroundColor Yellow
    exit 1
}

# Load environment variables
Write-Host "Loading environment variables..." -ForegroundColor Cyan
$loadEnvScript = Join-Path $PSScriptRoot ".." "powershellscripts" "load-envFile.ps1"

# Try multiple possible locations for the script
$possiblePaths = @(
    "C:\github\jagilber\powershellscripts\load-envFile.ps1",
    (Join-Path $PSScriptRoot ".." ".." "powershellscripts" "load-envFile.ps1"),
    $env:LOAD_ENV_SCRIPT
)

$loadEnvScript = $null
foreach ($path in $possiblePaths) {
    if ($path -and (Test-Path $path)) {
        $loadEnvScript = $path
        break
    }
}

if (-not $loadEnvScript) {
    Write-Error "Could not find load-envFile.ps1 script. Please set LOAD_ENV_SCRIPT environment variable or ensure script exists in expected location."
    exit 1
}

# Load environment variables
& $loadEnvScript -Path $EnvFile -Force

Write-Host ""

# Validate required environment variables
$requiredVars = @(
    'RESOURCE_GROUP',
    'LOCATION',
    'TEMPLATE_FILE',
    'ADMIN_PASSWORD',
    'CERTIFICATE_THUMBPRINT',
    'CERTIFICATE_URL_VALUE',
    'SOURCE_VAULT_VALUE'
)

$missingVars = @()
foreach ($var in $requiredVars) {
    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($var))) {
        $missingVars += $var
    }
}

if ($missingVars.Count -gt 0) {
    Write-Error "Missing required environment variables: $($missingVars -join ', ')"
    Write-Host "Please update your .env file with these values." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ All required environment variables are set" -ForegroundColor Green
Write-Host ""

# Build template file paths
$templateFile = Join-Path $PSScriptRoot $env:TEMPLATE_FILE
$templateParameterFile = if ($env:TEMPLATE_PARAMETER_FILE) { 
    Join-Path $PSScriptRoot $env:TEMPLATE_PARAMETER_FILE 
} else { 
    $null 
}

# Validate template files exist
if (-not (Test-Path $templateFile)) {
    Write-Error "Template file not found: $templateFile"
    exit 1
}

Write-Host "✓ Template file found: $templateFile" -ForegroundColor Green

if ($templateParameterFile -and (Test-Path $templateParameterFile)) {
    Write-Host "✓ Parameter file found: $templateParameterFile" -ForegroundColor Green
} elseif ($templateParameterFile) {
    Write-Warning "Parameter file not found: $templateParameterFile"
    Write-Host "  Will use environment variables for parameters" -ForegroundColor Yellow
    $templateParameterFile = $null
}

Write-Host ""

# Find deployment script
$deployScript = $null
$possibleDeployPaths = @(
    "C:\github\jagilber\powershellscripts\azure-az-deploy-template.ps1",
    (Join-Path $PSScriptRoot ".." ".." "powershellscripts" "azure-az-deploy-template.ps1"),
    $env:DEPLOY_SCRIPT
)

foreach ($path in $possibleDeployPaths) {
    if ($path -and (Test-Path $path)) {
        $deployScript = $path
        break
    }
}

if (-not $deployScript) {
    Write-Error "Could not find azure-az-deploy-template.ps1 script. Please set DEPLOY_SCRIPT environment variable or ensure script exists in expected location."
    exit 1
}

Write-Host "✓ Deployment script found: $deployScript" -ForegroundColor Green
Write-Host ""

# Build deployment parameters
$deployParams = @{
    resourceGroup = $env:RESOURCE_GROUP
    location = $env:LOCATION
    templateFile = $templateFile
    adminUsername = if ($env:ADMIN_USERNAME) { $env:ADMIN_USERNAME } else { "cloudadmin" }
    adminPassword = $env:ADMIN_PASSWORD
}

# Add optional parameters
if ($templateParameterFile) {
    $deployParams.templateParameterFile = $templateParameterFile
}

if ($env:DEPLOYMENT_NAME) {
    $deployParams.deploymentName = $env:DEPLOYMENT_NAME
}

if ($env:DEPLOYMENT_MODE) {
    $deployParams.mode = $env:DEPLOYMENT_MODE
}

if ($Test -or ($env:TEST_DEPLOYMENT -eq 'true')) {
    $deployParams.test = $true
}

if ($Clean -or ($env:CLEAN_DEPLOYMENT -eq 'true')) {
    $deployParams.clean = $true
}

if ($Force) {
    $deployParams.force = $true
}

# Build additional parameters from environment variables
$additionalParams = @{}

if ($env:CERTIFICATE_THUMBPRINT) {
    $additionalParams.certificateThumbprint = $env:CERTIFICATE_THUMBPRINT
}
if ($env:CERTIFICATE_COMMON_NAME) {
    $additionalParams.certificateCommonName = $env:CERTIFICATE_COMMON_NAME
}
if ($env:CERTIFICATE_URL_VALUE) {
    $additionalParams.certificateUrlValue = $env:CERTIFICATE_URL_VALUE
}
if ($env:SOURCE_VAULT_VALUE) {
    $additionalParams.sourceVaultValue = $env:SOURCE_VAULT_VALUE
}
if ($env:DNS_NAME) {
    $additionalParams.dnsName = $env:DNS_NAME
}
if ($env:VIRTUAL_MACHINE_COUNT) {
    $additionalParams.virtualMachineCount = [int]$env:VIRTUAL_MACHINE_COUNT
}
if ($env:VM_IMAGE_SKU) {
    $additionalParams.vmImageSku = $env:VM_IMAGE_SKU
}

if ($additionalParams.Count -gt 0) {
    $deployParams.additionalParameters = $additionalParams
}

# Display deployment information
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resource Group    : $($env:RESOURCE_GROUP)" -ForegroundColor White
Write-Host "Location          : $($env:LOCATION)" -ForegroundColor White
Write-Host "Template          : $($templateFile)" -ForegroundColor White
Write-Host "Parameter File    : $(if ($templateParameterFile) { $templateParameterFile } else { 'None (using env vars)' })" -ForegroundColor White
Write-Host "Deployment Mode   : $(if ($deployParams.mode) { $deployParams.mode } else { 'incremental' })" -ForegroundColor White
Write-Host "Test Mode         : $(if ($deployParams.test) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "Clean Deployment  : $(if ($deployParams.clean) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $Force -and -not $Test) {
    $response = Read-Host "Continue with deployment? (Y/N)"
    if ($response -notmatch '^[Yy]') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Execute deployment
Write-Host "Starting deployment..." -ForegroundColor Green
Write-Host ""

try {
    & $deployScript @deployParams
    
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✓ Deployment completed successfully!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    } else {
        Write-Error "Deployment failed with exit code: $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}
catch {
    Write-Error "Deployment failed: $_"
    exit 1
}
