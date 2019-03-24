param(
    $resourceGroupName = $Global:resourceGroupName,
    $location = $global:location
)

$deploymentName = $resourceGroupName
set-location $PSScriptRoot

.\azure-rm-deploy-template.ps1 `
    -deploymentName $deploymentName `
    -location $location `
    -resourceGroup $resourceGroupName `
    -clean `
    -force `
    -templateFile ..\azuredeploy.json `
    -templateParameterFile ..\azuredeploy.Parameters.local.json

write-host "finished"