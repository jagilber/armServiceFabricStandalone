<#
 script to install service fabric standalone in azure arm
 # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-for-windows-server

    The CleanCluster.ps1 will clean these certificates or you can clean them up using script 'CertSetup.ps1 -Clean -CertSubjectName CN=ServiceFabricClientCert'.
    Server certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\server.pfx with the password 1230909376
    Client certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\client.pfx with the password 940188492
    Modify thumbprint in C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\ClusterConfig.X509.OneNode.json
#>
param(
    [string]$thumbprint,
    [string]$virtualMachineNamePrefix,
    [int]$virtualMachineCount,
    [Parameter(Mandatory=$false)]
    [string]$commonName = "",
    [Parameter(Mandatory=$false)]
    [string]$azureClientId = "optional",
    [Parameter(Mandatory=$false)]
    [string]$azureSecret = "optional",
    [Parameter(Mandatory=$false)]
    [string]$azureTenant = "optional",
    [string]$sourceVaultValue,
    [string]$certificateUrlValue,
    [string]$diagnosticShare,
    [switch]$remove,
    [switch]$force,
    [string]$configurationFile = ".\ClusterConfig.X509.OneNode.json", # ".\ClusterConfig.X509.MultiMachine.json", #".\ClusterConfig.Unsecure.DevCluster.json",
    [string]$serviceFabricPackageUrl = "https://go.microsoft.com/fwlink/?LinkId=730690",
    [string]$packageName = "Microsoft.Azure.ServiceFabric.WindowsServer.latest.zip",
    [string]$subnetPrefix = "10",
    [int]$timeout = 1200
)

$erroractionpreference = "continue"
$logFile = $null

function main()
{
    $VerbosePreference = $DebugPreference = "continue"
    $Error.Clear()
    $packagePath = "$psscriptroot\$([io.path]::GetFileNameWithoutExtension($packageName))"
    $packageZip = "$psscriptroot\$packageName"
    $logFile = "$psscriptroot\install.log"
    $currentLocation = (get-location).Path
    $configurationFileMod = "$([io.path]::GetFileNameWithoutExtension($configurationFile)).mod.json"
    log-info "-------------------------------"
    log-info "starting"
    log-info "script path: $psscriptroot"
    log-info "log file: $logFile"
    log-info "current location: $currentLocation"
    log-info "configuration file: $configurationFileMod"

    # verify and acl cert
    $cert = get-item Cert:\LocalMachine\My\$thumbprint

    if ($cert)
    {
        log-info "found cert: $cert"
        $machineKeyFileName = [regex]::Match((certutil -store my $thumbprint), "Unique container name: (.+?)\s").groups[1].value

        if (!$machineKeyFileName)
        {
            log-info "error: unable to find file for cert: $machineKeyFileName"
            finish-script
            return 1
        }

        #$certFile = "c:\programdata\microsoft\crypto\rsa\machinekeys\$machineKeyFileName"
        $certFile = "c:\programdata\microsoft\crypto\keys\$machineKeyFileName"
        log-info "cert file: $certFile"
        log-info "cert file: $(cacls $certFile)"

        log-info "setting acl on cert"
        $acl = get-acl $certFile
        $rule = new-object security.accesscontrol.filesystemaccessrule "NT AUTHORITY\NETWORK SERVICE", "Read", allow
        log-info "setting acl: $rule"
        $acl.AddAccessRule($rule)
        set-acl $certFile $acl
        log-info "acl set"
        log-info "cert file: $(cacls $certFile)"

    }
    else
    {
        log-info "error: unable to find cert: $thumbprint. exiting"
        finish-script
        return 1
    }


    # enable remoting
    log-info "disable firewall"
    # todo disable only sf ports?
    set-netFirewallProfile -Profile Domain, Public, Private -Enabled False
    log-info "enable remoting"
    enable-psremoting
    winrm quickconfig -force -q
    # todo remove?
    winrm set winrm/config/client/Auth '@{CredSSP="true"}'
    #winrm id -r:%machinename%
    #winrm set winrm/config/client '@{TrustedHosts="*"}'
    winrm set winrm/config/client '@{TrustedHosts="<local>"}'


    # if creds supplied, download cert and put into currentuser my store for cluster admin
    if (($azureClientId -and $azureClientId -ine "optional") -and $azureSecret -and $azureTenant)
    {
        log-info "downloading cert from store"
        download-kvCert
    }

    # read and modify config with thumb and nodes if first node
    $nodes = [collections.arraylist]@()

    for ($i = 0; $i -lt $virtualMachineCount; $i++)
    {
        $node = "$virtualMachineNamePrefix$i"
        write-host "adding node to list: $node"
        [void]$nodes.Add($node)
    }

    log-info "nodes count: $($nodes.count)"
    log-info "nodes: $($nodes)"

    if ($nodes[0] -inotmatch $env:COMPUTERNAME)
    {
        log-info "$env:COMPUTERNAME is not first node. exiting..."
        finish-script
        return
    }

    <#
    # todo needed?
    log-info "start sleeping $($timeout / 4) seconds"
    start-sleep -seconds ($timeout / 4)
    log-info "resuming"
    #>

    if ($force -and (test-path $packagePath))
    {
        log-info "deleting package"
        [io.directory]::Delete($packagePath, $true)
    }

    if (!(test-path $packagePath))
    {
        log-info "downloading package $serviceFabricPackageUrl"
        log-info "(new-object net.webclient).DownloadFile($serviceFabricPackageUrl, $packageZip)"
        $result = (new-object net.webclient).DownloadFile($serviceFabricPackageUrl, $packageZip)
        log-info $result
        log-info ($error | out-string)
        log-info "Expand-Archive $packageZip -DestinationPath $packagePath -Force"
        Expand-Archive -path $packageZip -DestinationPath $packagePath -Force
    }

    Set-Location $packagePath
    log-info "current location: $packagePath"

    if (!(test-path $configurationFile))
    {
        log-info "error: $configurationFile does not exist"
        return
    }

    log-info "modifying json"
    $json = Get-Content -Raw $configurationFile
    $json = $json.Replace("[Thumbprint]", $thumbprint)
    $json = $json.Replace("[IssuerCommonName]", $commonName)
    $json = $json.Replace("[CertificateCommonName]", $commonName)
    
    log-info "saving json: $configurationFileMod"
    Out-File -InputObject $json -FilePath $configurationFileMod -Force
    # add nodes to json
    $json = Get-Content -Raw $configurationFileMod | convertfrom-json
    $nodeList = [collections.arraylist]@()
    $count = 0

    log-info "adding nodes"

    foreach ($node in $nodes)
    {
        #[int]$toggle = !$toggle
        $nodeList.Add(@{
                nodeName      = $node
                iPAddress     = (@((Resolve-DnsName $node).ipaddress) -imatch "$subnetPrefix\..+\..+\.")[0]
                nodeTypeRef   = "NodeType0"
                faultDomain   = "fd:/dc1/r$count"
                upgradeDomain = "UD$count"
            })
        
        $count++
    }

    $json.nodes = $nodeList.toarray()
    log-info "saving json with nodes"
    Out-File -InputObject ($json | convertto-json -Depth 99) -FilePath $configurationFileMod -Force

    if ($remove)
    {
        log-info "removing cluster"
        $result = .\RemoveServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod -Force
        log-info "remove result: $result"
        $result = .\CleanFabric.ps1
        log-info "clean result: $result"
        $error.Clear()
    }
    else
    {
        log-info "testing cluster"
        $error.Clear()
        $result = .\TestConfiguration.ps1 -ClusterConfigFilePath $configurationFileMod
        log-info $result

        if ($result -imatch "false|fail|exception")
        {
            log-info "error: failed test: $($error | out-string)"
            return 1
        }

        $error.Clear()
        log-info "creating cluster"
        $result = .\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod `
            -AcceptEULA `
            -NoCleanupOnFailure `
            -TimeoutInSeconds $timeout `
            -MaxPercentFailedNodes 0 `
            -Verbose
        
        log-info "create result: $result"
        #log-info "connecting to cluster (not currently working)"
        #$result = Connect-ServiceFabricCluster -ConnectionEndpoint localhost:19000
        #log-info $result 
        #$result = Get-ServiceFabricNode |Format-Table
        #log-info $result 
    }

    finish-script

    if (!$error)
    {
        return $true
    }

    return $false
}

function download-kvCert()
{
    #  requires WMF 5.0
    #  verify NuGet package
    #
    $nuget = get-packageprovider nuget -Force
    if (-not $nuget -or ($nuget.Version -lt 2.8.5.22))
    {
        log-info "installing nuget package..."
        install-packageprovider -name NuGet -minimumversion 2.8.5.201 -force
    }

    #  install AzureRM module
    #  min need AzureRM.profile, AzureRM.KeyVault
    #
    if (-not (get-module AzureRM -ListAvailable))
    { 
        log-info "installing AzureRm powershell module..." 
        install-module AzureRM -force 
    } 

    #  log onto azure account
    #
    log-info "logging onto azure account with app id = $azureClientId ..."

    $creds = new-object Management.Automation.PSCredential ($azureClientId, (convertto-securestring $azureSecret -asplaintext -force))
    login-azurermaccount -credential $creds -serviceprincipal -tenantid $azureTenant -confirm:$false

    #  get the secret from key vault
    #
    log-info "getting secret: $certificateUrlValue from keyvault: $sourceVaultValue"
    $vaultPattern = "Microsoft.KeyVault/vaults/(.+?)(/|$)"
    $certificatePattern = "/secrets/(.+?)/"

    $vaultName = [regex]::Match($sourceVaultValue, $vaultPattern, [text.RegularExpressions.RegexOptions]::IgnoreCase).Groups[1].Value
    $secretName = [regex]::Match($certificateUrlValue, $certificatePattern, [text.RegularExpressions.RegexOptions]::IgnoreCase).Groups[1].Value
    log-info "getting secret: $secretName from keyvault: $vaultName"

    $secret = get-azurekeyVaultSecret -vaultname $vaultName -name $secretName
    $certObject = new-object Security.Cryptography.X509Certificates.X509Certificate2
    $bytes = [convert]::FromBase64String($secret.SecretValueText)
    $certObject.Import($bytes, $null, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)
        
    add-type -AssemblyName System.Web
    $password = [Web.Security.Membership]::GeneratePassword(38, 5)
    log-info "setting cert password: $password"
    $protectedCertificateBytes = $certObject.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12, $password)
    $pfxFilePath = "$PSScriptRoot\$secretName.pfx"

    log-info "saving cert to: $pfxFilePath"
    [io.file]::WriteAllBytes($pfxFilePath, $protectedCertificateBytes)

    log-info "import certificate to current user Certificate store"
    $certificateStore = new-object System.Security.Cryptography.X509Certificates.X509Store -argumentlist "My", "Currentuser"
    $certificateStore.Open("readWrite")
    $certificateStore.Add($certObject)
    $certificateStore.Close()
}

function log-info($data)
{
    $data = "$(get-date)::$data"
    write-host $data
    out-file -InputObject $data -FilePath $logFile -append
}

function finish-script()
{
    Set-Location $currentLocation
    $VerbosePreference = $DebugPreference = "silentlycontinue"
    log-info "all errors: $($error | out-string)"
}

return main