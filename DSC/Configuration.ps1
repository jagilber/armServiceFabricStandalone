param(
    [PSCredential]$UserAccount,
    [string]$installScript = "$PSScriptRoot\azure-rm-dsc-sf-standalone-install.ps1",
    [string]$thumbprint,
    [string]$virtualMachineNamePrefix,
    [int]$virtualMachineCount,
    [string]$commonName,
    [string]$sourceVaultValue,
    [string]$certificateUrlValue,
    [string]$transcript,
    [string]$serviceFabricPackageUrl,
    [string]$azureClientId,
    [string]$azureSecret,
    [string]$azureTenant
)

$configurationData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    )
}

configuration SFStandaloneInstall
{
    param(
        #[Parameter(Mandatory=$true)]
        #[ValidateNotNullorEmpty()]
        [PSCredential]$UserAccount,
        [string]$installScript = "$PSScriptRoot\azure-rm-dsc-sf-standalone-install.ps1",
        [string]$thumbprint,
        [string]$virtualMachineNamePrefix,
        [int]$virtualMachineCount,
        [string]$commonName,
        [string]$sourceVaultValue,
        [string]$certificateUrlValue,
        [string]$transcript = ".\transcript.log",
        [string]$serviceFabricPackageUrl,
        [string]$azureClientId,
        [string]$azureSecret,
        [string]$azureTenant
    )
    
    $ErrorActionPreference = "silentlycontinue"
    set-location $PSScriptRoot
    Start-Transcript -Path $transcript
        
    foreach ($key in $MyInvocation.BoundParameters.keys)
    {
        $value = (get-variable $key).Value 
        write-host "$key -> $value"
    }
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    write-host "current location: $((get-location).path)"
    write-host "useraccount: $($useraccount.username)"
    Write-host "install script:$installScript"

    Node localhost {

        User LocalUserAccount
        {
            Username = $UserAccount.UserName
            Password = $UserAccount
            Disabled = $false
            Ensure = "Present"
            FullName = "Local User Account"
            Description = "Local User Account"
            PasswordNeverExpires = $true
        }

        $credential = new-object Management.Automation.PSCredential -ArgumentList ".\$($userAccount.Username)", $userAccount.Password
        $firstNode = $false
        $nodes = [collections.arraylist]@()
    
        for($i = 0; $i -lt $virtualMachineCount; $i++)
        {
            $node = "$virtualMachineNamePrefix$i"
            write-host "adding node to list: $node"
            [void]$nodes.Add($node)
        }

        if($nodes[0] -imatch $env:COMPUTERNAME)
        {
            write-host "$env:COMPUTERNAME is first node."
            $firstNode = $true
        }
        else 
        {
            write-host "$env:COMPUTERNAME is not first node."
        }

        Script Install-Standalone
        {
            GetScript = { 
                    $result = $false

                    if($firstNode)
                    {
                        $result = winrm g winrm/config/client
                    }
                    else 
                    {
                        $result = ((get-itemproperty "HKLM:\SOFTWARE\Microsoft\Service Fabric").FabricVersion)
                    }
                    
                    @{ Result = $result}
            }

            SetScript = { 
                    write-host "powershell.exe -file $using:installScript -thumbprint $using:thumbprint -virtualMachineNamePrefix $using:virtualMachineNamePrefix -commonname $using:commonname -serviceFabricPackageUrl $using:serviceFabricPackageUrl"
                    $result = Invoke-Expression -Command ("powershell.exe -file $using:installScript " `
                        + "-thumbprint $using:thumbprint " `
                        + "-virtualMachineNamePrefix $using:virtualMachineNamePrefix " `
                        + "-virtualMachineCount $using:virtualMachineCount " `
                        + "-commonname $using:commonname " `
                        + "-serviceFabricPackageUrl $using:serviceFabricPackageUrl " `
                        + "-azureClientId $using:azureClientId " `
                        + "-azureSecret $using:azureSecret " `
                        + "-azureTenant $using:azureTenant " `
                        + "-sourceVaultValue $using:sourceVaultValue " `
                        + "-certificateUrlValue $using:certificateUrlValue") -Verbose -Debug
                    
                    write-host "invoke result: $result"
                    
                    @{ Result = $result}
            }

            TestScript = { 
                
                    $retval = $false

                    if($firstNode)
                    {   
                        write-host "testscript first node"

                        if((get-itemproperty "HKLM:\SOFTWARE\Microsoft\Service Fabric" -ErrorAction SilentlyContinue).FabricVersion)
                        {
                            $retval = $true
                        }
                    }
                    else 
                    {
                        write-host "testscript not first node"
                        $retval = [bool](winrm g winrm/config/client) -imatch "trustedhosts = ."
                    }

                    write-host "testscript returning: $retval"
                    return $retval
            }

            PsDscRunAsCredential = $credential
            #[ DependsOn = [string[]] ]
        }
    }

    stop-transcript
}

if($thumbprint -and $virtualMachineNamePrefix -and $commonName)
{
    write-host "sfstandaloneinstall"
    SFStandaloneInstall -useraccount $UserAccount `
        -installScript $installScript `
        -thumbprint $thumbprint `
        -virtualMachineNamePrefix $virtualMachineNamePrefix `
        -virtualMachineCount $virtualMachineCount `
        -commonname $commonName `
        -serviceFabricPackageUrl $serviceFabricPackageUrl `
        -azureClientId $azureClientId `
        -azureSecret $azureSecret `
        -azureTenant $azureTenant `
        -sourceVaultValue $sourceVaultValue `
        -certificateUrlValue $certificateUrlValue `
        -ConfigurationData $configurationData

    # Start-DscConfiguration .\SFStandaloneInstall -wait -force -debug -verbose
}
else
{
    write-host "configuration.ps1: no args! exiting"
}
