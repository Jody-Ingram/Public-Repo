<#
Script  :  Azure-DNS-Conditional-Forwarder-Rule-Creator.ps1
Version :  3.0
Date    :  8/4/2026
Author  :  Jody Ingram
Purpose : Creates a local, non-replicated DNS Conditional Forwarder on:
          1. Azure DNS servers, forwarding to Azure platform DNS (168.63.129.16)
          2. On-premises DNS servers, forwarding to Azure domain controllers

Notes   : - Prompts for the DNS zone name so the script does not need to be edited.
          - Displays a separate confirmation window before making changes.
          - Creates each forwarder as local/non-AD-integrated by omitting ReplicationScope.
          - Will not automatically remove an existing replicated conditional forwarder.
#>


[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# DNS SERVER GROUPS

$AzureDnsServers = @(
    'AZUREDNS.domain.com',
    'AZUREDNS.domain.com',
    'AZUREDNS.domain.com',
    'AZUREDNS.domain.com'    
)

$OnPremDnsServers = @(
    'ONPREMDNS.domain.com',
    'ONPREMDNS.domain.com',
    'ONPREMDNS.domain.com',
    'ONPREMDNS.domain.com'
)

# Azure DNS servers forward the requested zone to Azure platform DNS.
$AzureForwarderIps = @(
    '168.63.129.16'
)

# On-premises DNS servers forward the requested zone to Azure DNS/DC servers.
$OnPremForwarderIps = @(
    'ON-PREM IP',
    'ON-PREM IP',
    'ON-PREM IP',
    'ON-PREM IP'
)

# FUNCTIONS
function Test-DnsZoneName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $normalizedName = $Name.Trim().TrimEnd('.')

    if ([string]::IsNullOrWhiteSpace($normalizedName) -or $normalizedName.Length -gt 253) {
        return $false
    }

    $dnsPattern = '^[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(?:\.[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$'
    return $normalizedName -match $dnsPattern
}

function Get-ConditionalForwarderName {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

        while ($true) {
            $zoneName = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter the DNS domain/zone to create as a Conditional Forwarder.`r`n`r`nExample: blob.core.windows.net",
                'DNS Conditional Forwarder',
                ''
            )

            if ([string]::IsNullOrWhiteSpace($zoneName)) {
                return $null
            }

            $zoneName = $zoneName.Trim().TrimEnd('.').ToLowerInvariant()

            if (Test-DnsZoneName -Name $zoneName) {
                return $zoneName
            }

            [System.Windows.Forms.MessageBox]::Show(
                "'$zoneName' does not appear to be a valid DNS zone name.",
                'Invalid DNS Zone',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }
    catch {
        Write-Warning 'The graphical prompt could not be opened. Falling back to a console prompt.'

        while ($true) {
            $zoneName = Read-Host 'Enter the DNS domain/zone to create, or press Enter to cancel'

            if ([string]::IsNullOrWhiteSpace($zoneName)) {
                return $null
            }

            $zoneName = $zoneName.Trim().TrimEnd('.').ToLowerInvariant()

            if (Test-DnsZoneName -Name $zoneName) {
                return $zoneName
            }

            Write-Host "'$zoneName' does not appear to be a valid DNS zone name." -ForegroundColor Red
        }
    }
}

function Confirm-ConditionalForwarderDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZoneName
    )

    $confirmationText = @"
DNS Conditional Forwarder: $ZoneName

AZURE DNS SERVERS
Servers: $($AzureDnsServers.Count)
Forward to: $($AzureForwarderIps -join ', ')

ON-PREMISES DNS SERVERS
Servers: $($OnPremDnsServers.Count)
Forward to: $($OnPremForwarderIps -join ', ')

Replication: Local only; not Active Directory-integrated
Each DNS server will be configured separately.

Proceed with these changes?
"@

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

        $response = [System.Windows.Forms.MessageBox]::Show(
            $confirmationText,
            'Confirm DNS Conditional Forwarder',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        return $response -eq [System.Windows.Forms.DialogResult]::Yes
    }
    catch {
        Write-Host $confirmationText -ForegroundColor Yellow
        return (Read-Host 'Type YES to continue') -eq 'YES'
    }
}

function Set-LocalConditionalForwarder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentName,

        [Parameter(Mandatory)]
        [string[]]$DnsServers,

        [Parameter(Mandatory)]
        [string]$ZoneName,

        [Parameter(Mandatory)]
        [string[]]$MasterServers
    )

    foreach ($dnsServer in $DnsServers) {
        Write-Host "`n[$EnvironmentName] Configuring $dnsServer..." -ForegroundColor Cyan

        try {
            $remoteResult = Invoke-Command `
                -ComputerName $dnsServer `
                -ArgumentList $ZoneName, $MasterServers `
                -ErrorAction Stop `
                -ScriptBlock {
                    param(
                        [string]$ZoneName,
                        [string[]]$MasterServers
                    )

                    Import-Module DnsServer -ErrorAction Stop

                    $requiredCommands = @(
                        'Get-DnsServerZone',
                        'Add-DnsServerConditionalForwarderZone',
                        'Set-DnsServerConditionalForwarderZone'
                    )

                    foreach ($commandName in $requiredCommands) {
                        if (-not (Get-Command -Name $commandName -Module DnsServer -ErrorAction SilentlyContinue)) {
                            throw "Required DnsServer command '$commandName' is unavailable on $env:COMPUTERNAME."
                        }
                    }

                    $desiredMasterServers = @(
                        $MasterServers |
                            ForEach-Object { $_.ToString() } |
                            Sort-Object
                    )

                    # Conditional forwarders are stored as DNS zones.
                    $existingZone = Get-DnsServerZone -Name $ZoneName -ErrorAction SilentlyContinue

                    if ($existingZone) {
                        if ([string]$existingZone.ZoneType -ne 'Forwarder') {
                            throw "A DNS zone named '$ZoneName' already exists as type '$($existingZone.ZoneType)'. It was not changed."
                        }

                        if ([bool]$existingZone.IsDsIntegrated) {
                            throw "The existing conditional forwarder '$ZoneName' is AD-integrated/replicated. It was not changed."
                        }

                        $existingMasterServers = @(
                            $existingZone.MasterServers |
                                ForEach-Object { $_.ToString() } |
                                Sort-Object
                        )

                        if (($existingMasterServers -join ',') -eq ($desiredMasterServers -join ',')) {
                            $action = 'No Change'
                        }
                        else {
                            Set-DnsServerConditionalForwarderZone `
                                -Name $ZoneName `
                                -MasterServers $desiredMasterServers `
                                -ErrorAction Stop

                            $action = 'Updated'
                        }
                    }
                    else {
                        # Do not specify ReplicationScope. This creates a local-only forwarder.
                        Add-DnsServerConditionalForwarderZone `
                            -Name $ZoneName `
                            -MasterServers $desiredMasterServers `
                            -ErrorAction Stop

                        $action = 'Created'
                    }

                    $verifiedZone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop

                    if ([string]$verifiedZone.ZoneType -ne 'Forwarder') {
                        throw "Verification failed: '$ZoneName' is type '$($verifiedZone.ZoneType)' instead of Forwarder."
                    }

                    if ([bool]$verifiedZone.IsDsIntegrated) {
                        throw "Verification failed: '$ZoneName' is AD-integrated/replicated."
                    }

                    $verifiedMasterServers = @(
                        $verifiedZone.MasterServers |
                            ForEach-Object { $_.ToString() } |
                            Sort-Object
                    )

                    if (($verifiedMasterServers -join ',') -ne ($desiredMasterServers -join ',')) {
                        throw "Verification failed: the configured master-server list does not match the requested list."
                    }

                    [pscustomobject]@{
                        ComputerName     = $env:COMPUTERNAME
                        Action           = $action
                        ZoneName         = $ZoneName
                        MasterServers    = $verifiedMasterServers -join ', '
                        ReplicationScope = 'Local only'
                    }
                }

            Write-Host "[$dnsServer] $($remoteResult.Action) successfully." -ForegroundColor Green

            [pscustomobject]@{
                Environment      = $EnvironmentName
                DnsServer        = $dnsServer
                Status           = 'Success'
                Action           = $remoteResult.Action
                ZoneName         = $remoteResult.ZoneName
                MasterServers    = $remoteResult.MasterServers
                ReplicationScope = $remoteResult.ReplicationScope
                Error            = $null
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Host "[$dnsServer] Failed: $errorMessage" -ForegroundColor Red

            [pscustomobject]@{
                Environment      = $EnvironmentName
                DnsServer        = $dnsServer
                Status           = 'Failed'
                Action           = 'None'
                ZoneName         = $ZoneName
                MasterServers    = $MasterServers -join ', '
                ReplicationScope = 'Local only'
                Error            = $errorMessage
            }
        }
    }
}

# MAIN

try {
    $conditionalForwarderName = Get-ConditionalForwarderName

    if (-not $conditionalForwarderName) {
        Write-Host 'Operation cancelled. No DNS changes were made.' -ForegroundColor Yellow
        return
    }

    if (-not (Confirm-ConditionalForwarderDeployment -ZoneName $conditionalForwarderName)) {
        Write-Host 'Operation cancelled. No DNS changes were made.' -ForegroundColor Yellow
        return
    }

    Write-Host "`nStarting Conditional Forwarder deployment for '$conditionalForwarderName'..." -ForegroundColor Cyan

    $azureResults = @(
        Set-LocalConditionalForwarder `
            -EnvironmentName 'Azure' `
            -DnsServers $AzureDnsServers `
            -ZoneName $conditionalForwarderName `
            -MasterServers $AzureForwarderIps
    )

    $onPremResults = @(
        Set-LocalConditionalForwarder `
            -EnvironmentName 'On-Premises' `
            -DnsServers $OnPremDnsServers `
            -ZoneName $conditionalForwarderName `
            -MasterServers $OnPremForwarderIps
    )

    $allResults = @($azureResults) + @($onPremResults)

    Write-Host "`nDeployment Results" -ForegroundColor Cyan
    $allResults |
        Select-Object Environment, DnsServer, Status, Action, ReplicationScope, Error |
        Format-Table -AutoSize

    $logDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeZoneName = $conditionalForwarderName -replace '[^A-Za-z0-9.-]', '_'
    $logPath = Join-Path $logDirectory "DNS-Conditional-Forwarder-$safeZoneName-$timestamp.csv"

    $allResults | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8

    $successCount = @($allResults | Where-Object Status -eq 'Success').Count
    $failureCount = @($allResults | Where-Object Status -eq 'Failed').Count

    $completionText = @"
Conditional Forwarder deployment finished.

Zone: $conditionalForwarderName
Successful servers: $successCount
Failed servers: $failureCount

Report:
$logPath
"@

    Write-Host "`n$completionText" -ForegroundColor $(if ($failureCount -eq 0) { 'Green' } else { 'Yellow' })

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

        $completionIcon = if ($failureCount -eq 0) {
            [System.Windows.Forms.MessageBoxIcon]::Information
        }
        else {
            [System.Windows.Forms.MessageBoxIcon]::Warning
        }

        [System.Windows.Forms.MessageBox]::Show(
            $completionText,
            'DNS Conditional Forwarder Complete',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $completionIcon
        ) | Out-Null
    }
    catch {
        # Console output above is sufficient when a GUI is unavailable.
    }
}
catch {
    Write-Host "`nThe script stopped because of an unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
