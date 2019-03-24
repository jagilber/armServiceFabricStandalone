# armServiceFabricStandalone
(beta) arm template to deploy Service Fabric Standalone cluster into Azure

## required:
- a self signed or trusted certificate stored in azure keyvault.

## optional:
- an existing or new azure application client id and secret for function authentication  
  * application client id and secret are an azure AD application and service principal name which is required for any application authenticating to azure in a non-interactive environment. there are multiple ways to create azure id and secret. one way is to copy the command below into admin powershell prompt and execute to create client id and secret. this will generate a self signed certificate on the local machine from where it is run. the certificate thumbprint will be used when creating the azure spn.
  * if needed, use one of the following options to generate a new client id and secret, save output, and use values when deploying template:
    * [create in portal.](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
    * [create in apps.dev.microsoft.com](https://apps.dev.microsoft.com)
    * use powershell script:
```powershell
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-rm-create-aad-application-spn.ps1"| iex
```  
## click button below to deploy

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjagilber%2FarmServiceFabricStandalone%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fjagilber%2FarmServiceFabricStandalone%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>
</p>
