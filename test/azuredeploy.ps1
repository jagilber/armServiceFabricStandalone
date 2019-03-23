param(
    $resourceGroupName = $Global:resourceGroupName,
    $location = $global:location,
    $adminUserName = $global:adminUserName,
    $adminPassword = $global:adminPassword
)

$deploymentName = $resourceGroupName
set-location $PSScriptRoot

.\azure-rm-deploy-template.ps1 -adminUsername $adminUserName `
    -adminPassword $adminPassword `
    -deploymentName $deploymentName `
    -location $location `
    -resourceGroup $resourceGroupName `
    -clean `
    -force `
    -templateFile ..\azuredeploy.json `
    -templateParameterFile ..\azuredeploy.Parameters.local.json

write-host "finished"