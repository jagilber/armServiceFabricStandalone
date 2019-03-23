<#
Copyright 2017 Microsoft Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

.SYNOPSIS
    powershell script to test azure deployments

.DESCRIPTION
    powershell script to test azure deployments

    to enable script execution, you may need to Set-ExecutionPolicy Bypass -Force
     
.NOTES
   file name  : azure-rm-deploy-template.ps1
   version    : 171013 original

.EXAMPLE
    .\azure-rm-deploy-template.ps1 -adminPassword changeme3240e2938r92 -resourceGroup rdsdeptest
    Example command to deploy rds-deployment with 2 instances using A1 machines. the resource group is rdsdeptest and domain fqdn is rdsdeptest.lab

.PARAMETER adminUsername
    if specified, the name of the administrator account. 

.PARAMETER adminPassword
    if specified, the administrator account password in clear text. password needs to meet azure password requirements.
    use -credentials to pass credentials securely

.PARAMETER credentials
    can be used for administrator account password. password needs to meet azure password requirements.

.PARAMETER resourceGroup
    resourceGroup is a mandatory paramenter and is the azure arm resourcegroup to use / create for this deployment

.PARAMETER test
    If specified, will test script and parameters but will not start deployment

.PARAMETER templateFile
    required. path to template file on disk

.PARAMETER templateParameterFile
    required. path to template parameter file on disk

#>
[cmdletbinding()]
param(
    [string]$adminUsername = "cloudadmin",
    [string]$adminPassword = "", 
    [pscredential]$credentials,
    [string]$deploymentName = $resourceGroup + (get-date).ToString("yyMMddHHmmss"),
    [string]$location,
    [switch]$monitor,
    [switch]$postConnect,
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [switch]$test,
    [Parameter(Mandatory = $true)]
    [string]$templateFile,
    [Parameter(Mandatory = $true)]
    [string]$templateParameterFile,
    [hashtable]$additionalParameters = @{},
    [switch]$clean,
    [switch]$force
)

# shouldnt need modification
$error.Clear()
$ErrorActionPreference = "Continue"

if (!$deploymentName)
{
    $deploymentName = $resourceGroup
}

if (!(test-path $templateFile))
{
    write-host "unable to find json file $($templateFile)"
    return
}

if (!(test-path $templateParameterFile))
{
    write-host "unable to find json file $($templateParameterFile)"
    return
}

write-host "running quickstart:$($quickStartTemplate) for group $($resourceGroup)"

write-host "authenticating to azure"
try
{
    get-command connect-azurermaccount | Out-Null
}
catch [management.automation.commandNotFoundException]
{
    if ((read-host "azurerm not installed but is required for this script. is it ok to install?[y|n]") -imatch "y")
    {
        write-host "installing minimum required azurerm modules..."
        install-module azurerm.profile
        install-module azurerm.resources
        import-module azurerm.profile
        import-module azurerm.resources
    }
    else
    {
        return 1
    }
}

if (!(Get-AzureRmResourceGroup))
{
    connect-azurermaccount

    if (!(Get-AzureRmResourceGroup))
    {
        Write-Warning "unable to authenticate to azurerm. returning..."
        return 1
    }
}

write-host "checking resource group"

if (!$resourceGroup)
{
    write-warning "resourcegroup is a mandatory argument. supply -resourceGroup argument and restart script."
    exit 1
}

write-host "checking location"

if (!(Get-AzureRmLocation | Where-Object Location -Like $location) -or [string]::IsNullOrEmpty($location))
{
    (Get-AzureRmLocation).Location
    write-warning "location: $($location) not found. supply -location using one of the above locations and restart script."
    exit 1
}

write-host "reading parameter file $($templateparameterFile)"
$ujson = ConvertFrom-Json (get-content -Raw -Path $templateparameterFile)

$ujson | ConvertTo-Json

if ($ujson.parameters.adminUserName -and $ujson.parameters.adminPassword -and !$test)
{
    write-host "checking password"

    if (!$credentials)
    {
        if(!$adminPassword)
        {
            $adminPassword = $ujson.parameters.adminPassword.value
        }

        if(!$adminUsername)
        {
            $adminUsername = $ujson.parameters.adminUserName.value
        }

        if (!$adminPassword)
        {
            $global:credential = Get-Credential
        }
        else
        {
            $SecurePassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force  
            $global:credential = new-object Management.Automation.PSCredential -ArgumentList $adminUsername, $SecurePassword
        }
    }
    else
    {
        $global:credential = $credentials
    }

    $adminUsername = $global:credential.UserName
    $adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($global:credential.Password)) 

    $count = 0
    # uppercase check
    if ($adminPassword -match "[A-Z]")
    {
        $count++ 
    }
    # lowercase check
    if ($adminPassword -match "[a-z]")
    {
        $count++ 
    }
    # numeric check
    if ($adminPassword -match "\d")
    {
        $count++ 
    }
    # specialKey check
    if ($adminPassword -match "\W")
    {
        $count++ 
    } 

    if ($adminPassword.Length -lt 8 -or $adminPassword.Length -gt 123 -or $count -lt 3)
    {
        Write-warning @"
        azure password requirements at time of writing (3/2017):
        The supplied password must be between 8-123 characters long and must satisfy at least 3 of password complexity requirements from the following: 
            1) Contains an uppercase character
            2) Contains a lowercase character
            3) Contains a numeric digit
            4) Contains a special character.
    
        correct password and restart script. 
"@
        exit 1
    }
}

write-host "checking for existing deployment"

if ((Get-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroup -Name $deploymentName -ErrorAction SilentlyContinue))
{
    if($clean -and $force)
    {
        write-warning "resource group deployment exists! deleting as -clean and -force are specified!"
        Remove-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroup -Name $deploymentName
    }
    elseif($clean)
    {
        if ((read-host "resource group deployment exists! Do you want to delete?[y|n]") -ilike 'y')
        {
            Remove-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroup -Name $deploymentName
        }
    }
    else
    {
        write-warning "resource group deployment exists!"
    }
}

write-host "checking for existing resource group"

if ((Get-AzureRmResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue))
{
    if($clean -and $force)
    {
        write-warning "resource group exists! deleting as -clean and -force are specified!"
        Remove-AzureRmResourceGroup -ResourceGroupName $resourceGroup -Force
    }
    elseif($clean)
    {
        if ((read-host "resource group exists! Do you want to delete?[y|n]") -ilike 'y')
        {
            Remove-AzureRmResourceGroup -ResourceGroupName $resourceGroup -Force
        }
    }
    else
    {
        write-warning "resource group exists!"
    }
}

# create resource group if it does not exist
if (!(Get-AzureRmResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue))
{
    Write-Host "creating resource group $($resourceGroup) in location $($location)"   
    New-AzureRmResourceGroup -Name $resourceGroup -Location $location
}

write-host "validating template"
$error.Clear() 
$ret = $null
$VerbosePreference = "continue"
$DebugPreference = "continue"

if ($global:credential.Password.Length)
{
    $ret = Test-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroup `
        -TemplateFile $templateFile `
        -Mode Complete `
        -adminUserName $global:credential.UserName `
        -adminPassword $global:credential.Password `
        -TemplateParameterFile $templateParameterFile `
        @additionalParameters
}
else
{
    $ret = Test-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroup `
        -TemplateFile $templateFile `
        -Mode Complete `
        -TemplateParameterFile $templateParameterFile `
        @additionalParameters
}

if ($ret)
{
    Write-Error "template validation failed. error: `n`n$($ret.Code)`n`n$($ret.Message)`n`n$($ret.Details)"
    $VerbosePreference = "silentlycontinue"
    $DebugPreference = "silentlycontinue"
    exit 1
}

if ($monitor)
{
    write-host "$([DateTime]::Now) starting monitor"
    $monitorScript = "$(get-location)\azure-rm-log-reader.ps1"
    
    if (![IO.File]::Exists($monitorScript))
    {
        [IO.File]::WriteAllText($monitorScript, 
            (Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/azure-rm-log-reader.ps1").ToString().Replace("???", ""))
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Minimized -ExecutionPolicy Bypass $($monitorScript)"
}

if (!$test)
{
    write-host "$([DateTime]::Now) creating deployment"
    $error.Clear() 
   
    if ($global:credential.Password.Length)
    {
        New-AzureRmResourceGroupDeployment -Name $deploymentName `
            -ResourceGroupName $resourceGroup `
            -DeploymentDebugLogLevel All `
            -TemplateFile $templateFile `
            -adminUserName $global:credential.UserName `
            -adminPassword $global:credential.Password `
            -TemplateParameterFile $templateParameterFile `
            -Verbose `
            @additionalParameters
    }
    else
    {
        New-AzureRmResourceGroupDeployment -Name $deploymentName `
            -ResourceGroupName $resourceGroup `
            -DeploymentDebugLogLevel All `
            -TemplateFile $templateFile `
            -TemplateParameterFile $templateParameterFile `
            -Verbose `
            @additionalParameters
         
    }
}

$VerbosePreference = "silentlycontinue"
$DebugPreference = "silentlycontinue"
$error | out-string
write-host "$([DateTime]::Now) finished"
