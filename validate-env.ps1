<#
.SYNOPSIS
    Helper script to validate .env configuration before deployment.

.DESCRIPTION
    Validates that all required environment variables are set in .env file
    and displays current configuration for review.

.PARAMETER EnvFile
    Path to the .env file. Defaults to .env in the script directory.

.EXAMPLE
    .\validate-env.ps1
    Validate the default .env file

.EXAMPLE
    .\validate-env.ps1 -EnvFile .env.production
    Validate a specific environment file
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment Configuration Validator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if .env file exists
if (-not (Test-Path $EnvFile)) {
    Write-Host "✗ Environment file not found: $EnvFile" -ForegroundColor Red
    Write-Host ""
    Write-Host "To create one:" -ForegroundColor Yellow
    Write-Host "  Copy-Item .env.example .env" -ForegroundColor Gray
    Write-Host "  Then edit .env with your values" -ForegroundColor Gray
    exit 1
}

Write-Host "✓ Environment file found: $EnvFile" -ForegroundColor Green
Write-Host ""

# Load environment variables
$loadEnvScript = "C:\github\jagilber\powershellscripts\load-envFile.ps1"
if (-not (Test-Path $loadEnvScript)) {
    Write-Warning "load-envFile.ps1 not found at expected location"
    Write-Host "Reading .env file directly..." -ForegroundColor Yellow
    
    # Simple .env parser
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.StartsWith('#')) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                if ($value -match '^["''](.*)["'']$') {
                    $value = $matches[1]
                }
                [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            }
        }
    }
} else {
    & $loadEnvScript -Path $EnvFile -Force | Out-Null
}

Write-Host ""
Write-Host "Validating Configuration..." -ForegroundColor Cyan
Write-Host ""

# Define required variables
$requiredVars = @{
    'RESOURCE_GROUP' = 'Azure resource group name'
    'LOCATION' = 'Azure region'
    'ADMIN_PASSWORD' = 'VM administrator password'
    'CERTIFICATE_THUMBPRINT' = 'Certificate thumbprint'
    'CERTIFICATE_COMMON_NAME' = 'Certificate common name'
    'CERTIFICATE_URL_VALUE' = 'KeyVault certificate URL'
    'SOURCE_VAULT_VALUE' = 'KeyVault resource ID'
}

# Define optional but recommended variables
$recommendedVars = @{
    'CLUSTER_NAME' = 'Service Fabric cluster name'
    'DNS_NAME' = 'DNS name for public IP'
    'VIRTUAL_MACHINE_COUNT' = 'Number of VMs in cluster'
}

$hasErrors = $false
$hasWarnings = $false

# Validate required variables
Write-Host "Required Variables:" -ForegroundColor White
foreach ($var in $requiredVars.GetEnumerator()) {
    $value = [System.Environment]::GetEnvironmentVariable($var.Key)
    
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Host "  ✗ $($var.Key): NOT SET - $($var.Value)" -ForegroundColor Red
        $hasErrors = $true
    } else {
        # Mask sensitive values
        $displayValue = $value
        if ($var.Key -match '(PASSWORD|SECRET|KEY|TOKEN|THUMBPRINT)') {
            $displayValue = "***SET***"
        } elseif ($value.Length -gt 50) {
            $displayValue = $value.Substring(0, 47) + "..."
        }
        Write-Host "  ✓ $($var.Key): $displayValue" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Recommended Variables:" -ForegroundColor White
foreach ($var in $recommendedVars.GetEnumerator()) {
    $value = [System.Environment]::GetEnvironmentVariable($var.Key)
    
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Host "  ⚠ $($var.Key): NOT SET - $($var.Value)" -ForegroundColor Yellow
        $hasWarnings = $true
    } else {
        Write-Host "  ✓ $($var.Key): $value" -ForegroundColor Green
    }
}

# Validate template files
Write-Host ""
Write-Host "Template Files:" -ForegroundColor White

$templateFile = Join-Path $PSScriptRoot ([System.Environment]::GetEnvironmentVariable('TEMPLATE_FILE') ?? 'azuredeploy.json')
if (Test-Path $templateFile) {
    Write-Host "  ✓ Template: $templateFile" -ForegroundColor Green
} else {
    Write-Host "  ✗ Template: $templateFile (NOT FOUND)" -ForegroundColor Red
    $hasErrors = $true
}

$paramFile = [System.Environment]::GetEnvironmentVariable('TEMPLATE_PARAMETER_FILE')
if ($paramFile) {
    $paramFilePath = Join-Path $PSScriptRoot $paramFile
    if (Test-Path $paramFilePath) {
        Write-Host "  ✓ Parameters: $paramFilePath" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Parameters: $paramFilePath (NOT FOUND)" -ForegroundColor Yellow
        $hasWarnings = $true
    }
} else {
    Write-Host "  ⚠ Parameters: Not specified (will use env vars)" -ForegroundColor Yellow
}

# Validate deployment scripts
Write-Host ""
Write-Host "Deployment Scripts:" -ForegroundColor White

$loadScript = [System.Environment]::GetEnvironmentVariable('LOAD_ENV_SCRIPT') ?? 'C:\github\jagilber\powershellscripts\load-envFile.ps1'
if (Test-Path $loadScript) {
    Write-Host "  ✓ Load Env: $loadScript" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Load Env: $loadScript (NOT FOUND)" -ForegroundColor Yellow
    $hasWarnings = $true
}

$deployScript = [System.Environment]::GetEnvironmentVariable('DEPLOY_SCRIPT') ?? 'C:\github\jagilber\powershellscripts\azure-az-deploy-template.ps1'
if (Test-Path $deployScript) {
    Write-Host "  ✓ Deploy Script: $deployScript" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Deploy Script: $deployScript (NOT FOUND)" -ForegroundColor Yellow
    $hasWarnings = $true
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

if ($hasErrors) {
    Write-Host "✗ Validation FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please update your .env file with the missing required values." -ForegroundColor Yellow
    exit 1
} elseif ($hasWarnings) {
    Write-Host "⚠ Validation passed with warnings" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You can proceed with deployment, but some optional features may not work correctly." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "✓ Validation PASSED" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your configuration is ready for deployment!" -ForegroundColor Green
    Write-Host "Run: .\deploy.ps1" -ForegroundColor Cyan
    exit 0
}
