# armServiceFabricStandalone

test arm template to deploy Service Fabric Standalone cluster into Azure.  
NOTE: not for production use

## required:

### self signed or trusted certificate stored in azure keyvault.

* **'certificateThumbprint'** certificate thumbprint
* **'sourceVaultValue'** "Resource Id of the key vault. Example:  
/subscriptions/\<Sub ID\>/resourceGroups/\<Resource group name\>/providers/Microsoft.KeyVault/vaults/\<vault name\>
* **'certificateUrlValue'** - location URL of certificate in key vault. Example:  
        https://\<name of the vault\>.vault.azure.net:443/secrets/\<location\>

## click button below to deploy

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjagilber%2FarmServiceFabricStandalone%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fjagilber%2FarmServiceFabricStandalone%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>
</p>
