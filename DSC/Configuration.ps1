param(
    [PSCredential]$UserAccount,
    [string]$installScript = "$PSScriptRoot\azure-rm-dsc-sf-standalone-install.ps1",
    [string]$thumbprint,
    [string]$virtualMachineNamePrefix,
    [int]$virtualMachineCount,
    [Parameter(Mandatory = $false)]
    [string]$commonName = "",
    [string]$sourceVaultValue,
    [string]$certificateUrlValue,
    [string]$transcript,
    [string]$serviceFabricPackageUrl,
    [int]$nodeTypeCount = 1
)

$configurationData = @{
    AllNodes = @(
        @{
            NodeName                    = 'localhost'
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser        = $true
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
        [Parameter(Mandatory = $false)]
        [string]$commonName = "",
        [string]$sourceVaultValue,
        [string]$certificateUrlValue,
        [string]$transcript = ".\transcript.log",
        [string]$serviceFabricPackageUrl,
        [int]$nodeTypeCount
    )
    
    $ErrorActionPreference = "silentlycontinue"
    set-location $PSScriptRoot
    Start-Transcript -Path $transcript
        
    foreach ($key in $MyInvocation.BoundParameters.keys) {
        $value = (get-variable $key).Value 
        write-host "$key -> $value"
    }
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDsc
    write-host "current location: $((get-location).path)"
    write-host "useraccount: $($useraccount.username)"
    Write-host "install script: $installScript"

    Node localhost {

        User LocalUserAccount {
            Username             = $UserAccount.UserName
            Password             = $UserAccount
            Disabled             = $false
            Ensure               = "Present"
            FullName             = "Local User Account"
            Description          = "Local User Account"
            PasswordNeverExpires = $true
        }

        $credential = new-object Management.Automation.PSCredential -ArgumentList ".\$($userAccount.Username)", $userAccount.Password

        ScheduledTask 'cmdkey'
        {
            TaskName         = 'cmdkey'
            TaskPath         = '\CustomTasks'
            ActionExecutable = 'cmdkey.exe'
            ActionArguments  = "/add:$($virtualMachineNamePrefix)0000000 /user:$($virtualMachineNamePrefix)0000000\$($UserAccount.UserName) /pass:$($UserAccount.GetNetworkCredential().Password)"
            ScheduleType     = 'Once'
            StartTime        = "$((get-date).AddSeconds(60))"
            BuiltInAccount   = 'NETWORK SERVICE'
            LogonType        = 'ServiceAccount'
            Enable           = $true
        }

        Script Install-Standalone {
            GetScript            = {
                $retval = $false

                if ((get-itemProperty "HKLM:\SOFTWARE\Microsoft\Service Fabric" -ErrorAction SilentlyContinue).FabricVersion) {
                    $retval = $true
                }
            
                write-host "getScript is-fabricInstalled returning: $retval"

                @{ Result = $retval } 
            }

            SetScript            = { 
                write-host "powershell.exe -file $using:installScript -thumbprint $using:thumbprint -virtualMachineNamePrefix $using:virtualMachineNamePrefix -commonname $using:commonname -serviceFabricPackageUrl $using:serviceFabricPackageUrl"
                $result = Invoke-Expression -Command ("powershell.exe " `
                        + "-file $using:installScript " `
                        + "-thumbprint $using:thumbprint " `
                        + "-virtualMachineNamePrefix $using:virtualMachineNamePrefix " `
                        + "-virtualMachineCount $using:virtualMachineCount " `
                        + "-nodeTypeCount $using:nodeTypeCount" `
                        + "-commonName $using:commonName " `
                        + "-serviceFabricPackageUrl $using:serviceFabricPackageUrl " `
                        + "-sourceVaultValue $using:sourceVaultValue " `
                        + "-certificateUrlValue $using:certificateUrlValue") -Verbose -Debug
                    
                write-host "invoke result: $result"
                return @{ Result = $result }
            }

            TestScript           = { 
                $retval = $false

                if ((get-itemProperty "HKLM:\SOFTWARE\Microsoft\Service Fabric" -ErrorAction SilentlyContinue).FabricVersion) {
                    $retval = $true
                }
            
                write-host "getScript is-fabricInstalled returning: $retval"
                return $retval 
            }

            PsDscRunAsCredential = $credential
            #[ DependsOn = [string[]] ]
        }
    }

    stop-transcript
}

if ($thumbprint -and $virtualMachineNamePrefix -and $commonName) {
    write-host "sfstandaloneinstall"
    Install-Module -name ComputerManagementDsc -force
    SFStandaloneInstall -useraccount $UserAccount `
        -installScript $installScript `
        -thumbprint $thumbprint `
        -virtualMachineNamePrefix $virtualMachineNamePrefix `
        -virtualMachineCount $virtualMachineCount `
        -nodeTypeCount $nodeTypeCount `
        -commonname $commonName `
        -serviceFabricPackageUrl $serviceFabricPackageUrl `
        -sourceVaultValue $sourceVaultValue `
        -certificateUrlValue $certificateUrlValue `
        -configurationData $configurationData

    # Start-DscConfiguration .\SFStandaloneInstall -wait -force -debug -verbose
}
else {
    write-host "configuration.ps1: no args! exiting"
}
