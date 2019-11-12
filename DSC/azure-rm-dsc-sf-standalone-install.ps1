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
    [Parameter(Mandatory = $false)]
    [string]$commonName = "",
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

function main() {
    $VerbosePreference = $DebugPreference = "continue"
    $Error.Clear()
    $packagePath = "$psscriptroot\$([io.path]::GetFileNameWithoutExtension($packageName))"
    $packageZip = "$psscriptroot\$packageName"
    $logFile = "$psscriptroot\install.log"
    $currentLocation = (get-location).Path
    $configurationFileMod = "$([io.path]::GetFileNameWithoutExtension($configurationFile)).mod.json"
    $startTime = get-date
    log-info "-------------------------------"
    log-info "starting $startTime"
    log-info "whoami $(whoami)"
    log-info "script path: $psscriptroot"
    log-info "log file: $logFile"
    log-info "current location: $currentLocation"
    log-info "configuration file: $configurationFileMod"

    # verify and acl cert
    $cert = get-item Cert:\LocalMachine\My\$thumbprint

    if ($cert) {
        log-info "found cert: $cert"
        $machineKeyFileName = [regex]::Match((certutil -store my $thumbprint), "Unique container name: (.+?)\s").groups[1].value

        if (!$machineKeyFileName) {
            log-info "error: unable to find file for cert: $machineKeyFileName"
            finish-script
            return 1
        }

        $certFile = "c:\programdata\microsoft\crypto\rsa\machinekeys\$machineKeyFileName"
        
        if (!(test-path $certFile)) {
            $certFile = "c:\programdata\microsoft\crypto\keys\$machineKeyFileName"
        }

        if (!(test-path $certFile)) {
            Write-Error "unable to find $certFile"
            return
        }

        log-info "cert file: $certFile"
        log-info "cert file: $(cacls $certFile)"

        log-info "setting acl on cert"
        $acl = get-acl -path $certFile
        $rule = new-object security.accesscontrol.filesystemaccessrule("NT AUTHORITY\NETWORK SERVICE", "Read", "Allow")
        log-info "setting acl: $rule"
        $acl.AddAccessRule($rule)
        set-acl -path $certFile -AclObject $acl
        log-info "acl set"
        log-info "cert file: $(cacls $certFile)"

    }
    else {
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


    # read and modify config with thumb and nodes if first node
    $nodes = [collections.arraylist]@()

    for ($i = 0; $i -lt $virtualMachineCount; $i++) {
        $node = "$virtualMachineNamePrefix$($i.tostring('D7'))"
        write-host "adding node to list: $node"
        [void]$nodes.Add($node)
    }

    log-info "nodes count: $($nodes.count)"
    log-info "nodes: $($nodes)"

    #$Action = New-ScheduledTaskAction -Execute 'cmdkey.exe' -Argument "/general:$($nodes[0]) /user:$($credential.UserName) /pass:$($credential.Password)"
    #$Trigger = New-ScheduledTaskTrigger -Once -At "$((get-date).AddSeconds(5))"
    #$Settings = New-ScheduledTaskSettingsSet
    #$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings
    #Register-ScheduledTask -TaskName 'network service cmdkey' -InputObject $Task -User 'networkservice' # -Password 'passhere'

    if ($nodes[0] -inotmatch $env:COMPUTERNAME) {
        log-info "$env:COMPUTERNAME is not first node. exiting..."

        while(((get-date) - $startTime).TotalSeconds -lt $timeout)
        {
            if((get-process).ProcessName -ieq "fabricgateway") { 
                log-info "$((get-process).ProcessName)"
                break 
            }
            start-sleep -Seconds 1
        }    

        finish-script
        return
    }

    #
    # todo needed?
    #log-info "start sleeping $($timeout / 4) seconds"
    log-info "start sleeping 60 seconds"
    #start-sleep -seconds ($timeout / 4)
    start-sleep -seconds 60
    log-info "resuming"
    #>
    log-info "waiting for nodes"
    $retry = $true

    while($retry -and (((get-date) - $startTime).TotalSeconds -lt $timeout))
    {
        $retry = $false

        foreach($node in $nodes)
        {
            log-info "checking $node"
            
            if(!(test-path "\\$node\c$"))
            {
                log-info "$node unavailable"
                $retry = $true
            }
        }

        start-sleep -Seconds 1
    }

    if ($force -and (test-path $packagePath)) {
        log-info "deleting package"
        [io.directory]::Delete($packagePath, $true)
    }

    if (!(test-path $packagePath)) {
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

    if (!(test-path $configurationFile)) {
        log-info "error: $configurationFile does not exist"
        return
    }

    log-info "modifying json"
    $json = Get-Content -Raw $configurationFile
    $json = $json.Replace("[Thumbprint]", $thumbprint)
    $json = $json.Replace("[IssuerCommonName]", $commonName)
    $json = $json.Replace("[CertificateCommonName]", $commonName)
        
    if ($diagnosticShare) {
        $json = $json.Replace("c:\\ProgramData\\SF\\DiagnosticsStore", $diagnosticShare)
    }
    else {
        log-info "creating diagnostic store"
        md d:\diagnosticsStore
        log-info "sharing diagnostic store"
        icacls d:\diagnosticsStore /grant "NT AUTHORITY\NETWORK SERVICE:(OI)(CI)(F)"
        net share diagnosticsStore=d:\diagnosticsStore /GRANT:everyone,FULL /GRANT:"NT AUTHORITY\NETWORK SERVICE",FULL
        log-info (net share)
        #$share = "\\\\$((@((Resolve-DnsName $env:COMPUTERNAME).ipaddress) -imatch "$subnetPrefix\..+\..+\.")[0])\\diagnosticsStore"
        $share = "\\\\$($env:COMPUTERNAME)\\diagnosticsStore"
        log-info "new share $share"
        $json = $json.Replace("c:\\ProgramData\\SF\\DiagnosticsStore", $share)
    }

    log-info "saving json: $configurationFileMod"
    Out-File -InputObject $json -FilePath $configurationFileMod -Force
    # add nodes to json
    $json = Get-Content -Raw $configurationFileMod | convertfrom-json
    $nodeList = [collections.arraylist]@()
    $count = 0
    $isSeedNode = $true

    log-info "adding nodes"

    foreach ($node in $nodes) {
        #[int]$toggle = !$toggle
        $nodeList.Add(@{
                nodeName      = $node
                iPAddress     = (@((Resolve-DnsName $node).ipaddress) -imatch "$subnetPrefix\..+\..+\.")[0]
                nodeTypeRef   = "NodeType0"
                faultDomain   = "fd:/dc1/r$count"
                upgradeDomain = "UD$count"
                isSeedNode    = $isSeedNode.tostring()
            })
        
        if (++$count -gt 4) {
            $isSeedNode = $false
            $count = 0
        }
        
    }

    $json.nodes = $nodeList.toarray()
    log-info "saving json with nodes"
    Out-File -InputObject ($json | convertto-json -Depth 99) -FilePath $configurationFileMod -Force

    if ($remove) {
        log-info "removing cluster"
        $result = .\RemoveServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod -Force
        log-info "remove result: $result"
        $result = .\CleanFabric.ps1
        log-info "clean result: $result"
        $error.Clear()
    }
    else {
        log-info "testing cluster"
        $error.Clear()
        $result = .\TestConfiguration.ps1 -ClusterConfigFilePath $configurationFileMod
        log-info $result

        if ($result -imatch "false|fail|exception") {
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

        log-info "extracting standalonelogcollector"
        md C:\temp\standalonelogcollector
        Expand-Archive .\Tools\Microsoft.Azure.ServiceFabric.WindowsServer.SupportPackage.zip c:\temp\standalonelogcollector
    }

    finish-script

    if (!$error) {
        return $true
    }

    return $false
}

function log-info($data) {
    $data = "$(get-date)::$data"
    write-host $data
    out-file -InputObject $data -FilePath $logFile -append
}

function finish-script() {
    Set-Location $currentLocation
    $VerbosePreference = $DebugPreference = "silentlycontinue"
    log-info "all errors: $($error | out-string)"
    log-info "finished. total seconds: $(((get-date) - $startTime).TotalSeconds)"
    
}

return main
