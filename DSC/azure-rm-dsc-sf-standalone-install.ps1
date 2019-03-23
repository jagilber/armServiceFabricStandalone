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
    [string[]]$nodes,
    [string]$commonname,
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$diagnosticShare,
    [switch]$remove,
    [switch]$force,
    [string]$configurationFile = ".\ClusterConfig.X509.OneNode.json", # ".\ClusterConfig.X509.MultiMachine.json", #".\ClusterConfig.Unsecure.DevCluster.json",
    [string]$sfPackageUrl = "https://go.microsoft.com/fwlink/?LinkId=730690",
    [string]$packageName = "Microsoft.Azure.ServiceFabric.WindowsServer.latest.zip",
    [int]$timeout = 1200,
    [int]$subnetPrefix = "10"
)

$erroractionpreference = "continue"
$logFile = $null
$jobName = "sa"

function main()
{
    $VerbosePreference = $DebugPreference = "continue"
    $Error.Clear()
    $packagePath = "$psscriptroot\$([io.path]::GetFileNameWithoutExtension($packageName))"
    $packageZip = "$psscriptroot\$packageName"
    $logFile = "$psscriptroot\install.log"
    $certPath = "$packagePath\Certificates"
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

    if($cert)
    {
        log-info "found cert: $cert"
        $machineKeyFileName = [regex]::Match((certutil -store my $thumbprint),"Unique container name: (.+?)\s").groups[1].value

        if(!$machineKeyFileName)
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
    # todo disaable only sf ports?
    set-netFirewallProfile -Profile Domain,Public,Private -Enabled False
    log-info "enable remoting"
    enable-psremoting
    winrm quickconfig -force -q
    # todo remove?
    winrm set winrm/config/client/Auth '@{CredSSP="true"}'
    #winrm id -r:%machinename%
    #winrm set winrm/config/client '@{TrustedHosts="*"}'
    winrm set winrm/config/client '@{TrustedHosts="<local>"}'

    # read and modify config with thumb and nodes if first node
    $nodes = $nodes.split(',')

    log-info "nodes count: $($nodes.count)"
    log-info "nodes: $($nodes)"

    if($nodes[0] -inotmatch $env:COMPUTERNAME)
    {
        log-info "$env:COMPUTERNAME is not first node. exiting..."
        finish-script
        return
    }
<#
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
        log-info "downloading package $sfPackageUrl"
        log-info "(new-object net.webclient).DownloadFile($sfPackageUrl, $packageZip)"
        $result = (new-object net.webclient).DownloadFile($sfPackageUrl, $packageZip)
        log-info $result
        log-info ($error | out-string)
        log-info "Expand-Archive $packageZip -DestinationPath $packagePath -Force"
        Expand-Archive -path $packageZip -DestinationPath $packagePath -Force
    }

    Set-Location $packagePath
    log-info "current location: $packagePath"

    if(!(test-path $configurationFile))
    {
        log-info "error: $configurationFile does not exist"
        return
    }

    log-info "modifying json"
    $json = Get-Content -Raw $configurationFile
    $json = $json.Replace("[Thumbprint]",$thumbprint)
    $json = $json.Replace("[IssuerCommonName]",$commonname)
    $json = $json.Replace("[CertificateCommonName]",$commonname)
    
    log-info "saving json: $configurationFileMod"
    Out-File -InputObject $json -FilePath $configurationFileMod -Force
    # add nodes to json
    $json = Get-Content -Raw $configurationFileMod | convertfrom-json
    $nodeList = [collections.arraylist]@()
    $count = 0

    log-info "adding nodes"

    foreach($node in $nodes)
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
        .\RemoveServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod -Force
        .\CleanFabric.ps1
    }
    else
    {
        log-info "testing cluster"
        $error.Clear()
        $result = .\TestConfiguration.ps1 -ClusterConfigFilePath $configurationFileMod
        log-info $result

        if($result -imatch "false|fail|exception")
        {
            log-info "error: failed test: $($error | out-string)"
            return 1
        }

        log-info "creating cluster"
        $result = .\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod `
            -AcceptEULA `
            -NoCleanupOnFailure `
            -TimeoutInSeconds $timeout `
            -MaxPercentFailedNodes 0 `
            -Verbose
        
        log-info $result
        log-info "connecting to cluster (not currently working)"
        $result = Connect-ServiceFabricCluster -ConnectionEndpoint localhost:19000
        log-info $result 
        $result = Get-ServiceFabricNode |Format-Table
        log-info $result 
    }

    finish-script
    # todo remove
    $error.Clear()

    if(!$error)
    {
        return $true
    }

    return $false
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

main