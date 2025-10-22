# armServiceFabricStandalone

test arm template to deploy Service Fabric Standalone cluster into Azure.  
NOTE: not for production use

## Features

- **Standard Load Balancer** with explicit outbound rules
- **Network Security Group** with Service Fabric security rules
- Environment variable-based configuration via `.env` file
- PowerShell deployment automation

## Quick Start

### 1. Prerequisites

- Azure PowerShell modules (`Az.Accounts`, `Az.Resources`)
- PowerShell scripts from [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts):
  - `load-envFile.ps1`
  - `azure-az-deploy-template.ps1`

### 2. Setup Environment Configuration

```powershell
# Copy the example environment file
Copy-Item .env.example .env

# Edit .env with your values (required fields marked with REQUIRED)
notepad .env
```

### 3. Deploy

```powershell
# Test deployment (validation only)
.\deploy.ps1 -Test

# Deploy to Azure
.\deploy.ps1

# Clean deployment (removes existing resources)
.\deploy.ps1 -Clean -Force
```

## Environment Variables

The `.env` file contains all deployment configuration. Key variables include:

| Variable | Description | Required |
|----------|-------------|----------|
| `RESOURCE_GROUP` | Azure resource group name | ✓ |
| `LOCATION` | Azure region (e.g., centralus) | ✓ |
| `ADMIN_PASSWORD` | VM admin password | ✓ |
| `CERTIFICATE_THUMBPRINT` | Certificate thumbprint | ✓ |
| `CERTIFICATE_COMMON_NAME` | Certificate common name | ✓ |
| `CERTIFICATE_URL_VALUE` | KeyVault certificate URL | ✓ |
| `SOURCE_VAULT_VALUE` | KeyVault resource ID | ✓ |
| `VIRTUAL_MACHINE_COUNT` | Number of VMs (3-5 recommended) | ✓ |

See `.env.example` for all available configuration options.

## Manual Deployment

You can also use the PowerShell scripts directly:

```powershell
# Load environment variables
. C:\github\jagilber\powershellscripts\load-envFile.ps1

# Deploy using azure-az-deploy-template.ps1
C:\github\jagilber\powershellscripts\azure-az-deploy-template.ps1 `
    -resourceGroup $env:RESOURCE_GROUP `
    -location $env:LOCATION `
    -templateFile .\azuredeploy.json `
    -adminPassword $env:ADMIN_PASSWORD
```

## Required Certificate Setup

### self signed or trusted certificate stored in azure keyvault.

* **'certificateThumbprint'** certificate thumbprint
* **'commonname'** certificate common name / subject
* **'sourceVaultValue'** "Resource Id of the key vault. Example:  
/subscriptions/\<Sub ID\>/resourceGroups/\<Resource group name\>/providers/Microsoft.KeyVault/vaults/\<vault name\>
* **'certificateUrlValue'** - location URL of certificate in key vault. Example:  
        https://\<name of the vault\>.vault.azure.net:443/secrets/\<location\>

## click button below to deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjagilber%2FarmServiceFabricStandalone%2Fmaster%2Fazuredeploy.json)
[![Visualize](http://armviz.io/visualizebutton.png)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fjagilber%2FarmServiceFabricStandalone%2Fmaster%2Fazuredeploy.json)
