# Environment Configuration Quick Reference

## Files Created

- `.env.example` - Template with all available configuration options
- `.env` - Your actual configuration (DO NOT COMMIT TO GIT)
- `deploy.ps1` - Main deployment script
- `validate-env.ps1` - Configuration validator
- `.gitignore` - Updated to exclude .env file

## Quick Setup

### 1. Initial Setup
```powershell
# Copy example to create your .env file
Copy-Item .env.example .env

# Edit with your values
notepad .env
```

### 2. Validate Configuration
```powershell
# Check if all required variables are set
.\validate-env.ps1
```

### 3. Deploy
```powershell
# Test deployment (validation only, no actual deployment)
.\deploy.ps1 -Test

# Deploy to Azure
.\deploy.ps1

# Clean deployment (removes existing resources first)
.\deploy.ps1 -Clean -Force
```

## Required Environment Variables

You MUST set these in your `.env` file:

```bash
RESOURCE_GROUP=your-resource-group-name
LOCATION=centralus
ADMIN_PASSWORD=YourSecurePassword123!
CERTIFICATE_THUMBPRINT=YOUR_CERT_THUMBPRINT
CERTIFICATE_URL_VALUE=https://your-vault.vault.azure.net/secrets/cert-name/version
SOURCE_VAULT_VALUE=/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.KeyVault/vaults/xxx
```

## Using PowerShell Scripts Directly

### Load Environment Variables
```powershell
# Load variables from .env into current session
C:\github\jagilber\powershellscripts\load-envFile.ps1 -Path .\.env

# Or dot-source it
. C:\github\jagilber\powershellscripts\load-envFile.ps1 -Path .\.env -Force
```

### Deploy with azure-az-deploy-template.ps1
```powershell
# After loading .env variables
C:\github\jagilber\powershellscripts\azure-az-deploy-template.ps1 `
    -resourceGroup $env:RESOURCE_GROUP `
    -location $env:LOCATION `
    -templateFile .\azuredeploy.json `
    -templateParameterFile .\azuredeploy.Parameters.json `
    -adminUsername $env:ADMIN_USERNAME `
    -adminPassword $env:ADMIN_PASSWORD `
    -additionalParameters @{
        certificateThumbprint = $env:CERTIFICATE_THUMBPRINT
        certificateUrlValue = $env:CERTIFICATE_URL_VALUE
        sourceVaultValue = $env:SOURCE_VAULT_VALUE
        dnsName = $env:DNS_NAME
    }
```

## Common Configuration Examples

### Minimal Configuration (5-node cluster)
```bash
RESOURCE_GROUP=sfsa-prod
LOCATION=centralus
ADMIN_PASSWORD=SecureP@ssw0rd123!
CERTIFICATE_THUMBPRINT=ABC123...
CERTIFICATE_URL_VALUE=https://vault.vault.azure.net/secrets/cert/version
SOURCE_VAULT_VALUE=/subscriptions/.../vaults/vault
VIRTUAL_MACHINE_COUNT=5
CLUSTER_NAME=sfsa-prod-cluster
DNS_NAME=sfsa-prod-cluster
```

### Development Configuration (3-node cluster)
```bash
RESOURCE_GROUP=sfsa-dev
LOCATION=centralus
ADMIN_PASSWORD=DevP@ssw0rd123!
CERTIFICATE_THUMBPRINT=ABC123...
CERTIFICATE_URL_VALUE=https://vault.vault.azure.net/secrets/cert/version
SOURCE_VAULT_VALUE=/subscriptions/.../vaults/vault
VIRTUAL_MACHINE_COUNT=3
CLUSTER_NAME=sfsa-dev-cluster
DNS_NAME=sfsa-dev-cluster
VM_NODE_TYPE_0_SIZE=Standard_DS2_v2
```

## Troubleshooting

### Environment variables not loading
```powershell
# Check if .env file exists
Test-Path .\.env

# Manually check file contents
Get-Content .\.env

# Load with verbose output
C:\github\jagilber\powershellscripts\load-envFile.ps1 -Path .\.env -Force -Verbose
```

### Missing required scripts
```powershell
# Verify script locations
Test-Path C:\github\jagilber\powershellscripts\load-envFile.ps1
Test-Path C:\github\jagilber\powershellscripts\azure-az-deploy-template.ps1

# Or set custom locations in .env
LOAD_ENV_SCRIPT=C:\custom\path\load-envFile.ps1
DEPLOY_SCRIPT=C:\custom\path\azure-az-deploy-template.ps1
```

### Template validation errors
```powershell
# Test deployment without actually deploying
.\deploy.ps1 -Test

# Check Azure resource group
Get-AzResourceGroup -Name $env:RESOURCE_GROUP
```

## Security Best Practices

1. **Never commit .env file to Git**
   - It's already in .gitignore
   - Contains sensitive passwords and certificates

2. **Use strong passwords**
   - Minimum 12 characters
   - Mix of uppercase, lowercase, numbers, and symbols

3. **Rotate certificates regularly**
   - Update CERTIFICATE_THUMBPRINT and CERTIFICATE_URL_VALUE
   - Redeploy cluster with new certificate

4. **Use separate environments**
   - Create different .env files for dev/test/prod
   - Example: .env.dev, .env.prod (don't forget to add to .gitignore)

## Reference Parameter Files

Example configurations available in:
`C:\github\jagilber-pr\serviceFabricInternal\configs\`

Useful examples:
- `sf-1nt-3n-1slb.parameters.json` - 1 node type, 3 nodes, Standard LB
- `sf-1nt-5n-1slb.parameters.json` - 1 node type, 5 nodes, Standard LB
- `sf-2nt-5n-1slb.parameters.json` - 2 node types, 5 nodes, Standard LB
