<#
Script  :  Windows-RDP-Disconnect-Investigation.ps1
Version :  1.0
Date    :  5/4/2026
Author: Jody Ingram
Pre-reqs: Run with appropriate permissions to access event logs
Notes: This script investigates RDP disconnect events on a Windows machine.
#>

# Adjust these values as needed
$StartTime = Get-Date '2026-05-29 09:00:00'
$EndTime   = Get-Date '2026-05-29 12:30:00'
$UserHint  = 'USERNAME'   # Example: jody.ingram

$OutDir = "$env:USERPROFILE\Desktop\RDP-Disconnect-$env:COMPUTERNAME"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$Queries = @(
    @{
        Name    = 'RdpCoreTS'
        LogName = 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
        Ids     = 102,131,140,142,143,226
    },
    @{
        Name    = 'LocalSessionManager'
        LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
        Ids     = 21,22,23,24,25,39,40
    },
    @{
        Name    = 'RemoteConnectionManager'
        LogName = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'
        Ids     = 1149
    },
    @{
        Name    = 'Security'
        LogName = 'Security'
        Ids     = 4624,4634,4647,4778,4779
    },
    @{
        Name    = 'System'
        LogName = 'System'
        Ids     = 50,56,36874,36888
    },
    @{
        Name    = 'Application'
        LogName = 'Application'
        Ids     = $null
    }
)

$Results = foreach ($Query in $Queries) {

    if ($null -eq $Query.Ids) {
        $RawEvents = Get-WinEvent -FilterHashtable @{
            LogName   = $Query.LogName
            StartTime = $StartTime
            EndTime   = $EndTime
        } -ErrorAction SilentlyContinue
    }
    else {
        $RawEvents = Get-WinEvent -FilterHashtable @{
            LogName   = $Query.LogName
            Id        = $Query.Ids
            StartTime = $StartTime
            EndTime   = $EndTime
        } -ErrorAction SilentlyContinue
    }

    $RawEvents | Select-Object `
        TimeCreated,
        MachineName,
        @{Name='EventGroup';Expression={$Query.Name}},
        LogName,
        Id,
        ProviderName,
        LevelDisplayName,
        @{
            Name='Message'
            Expression={($_.Message -replace "`r|`n", " ")}
        }
}

$CorrelationPath = "$OutDir\RDP-Disconnect-Correlation.csv"
$ImportantPath   = "$OutDir\RDP-Disconnect-Important-Only.csv"

$Results |
    Sort-Object TimeCreated |
    Export-Csv $CorrelationPath -NoTypeInformation

$Results |
    Where-Object {
        $_.Message -like "*$UserHint*" -or
        $_.Id -in 102,140,142,143,226,24,40,4779,4647
    } |
    Sort-Object TimeCreated |
    Export-Csv $ImportantPath -NoTypeInformation

Write-Host "Export complete:"
Write-Host $CorrelationPath
Write-Host $ImportantPath
