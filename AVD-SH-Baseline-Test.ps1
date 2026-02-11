<#
Script  :  AVD-SH-Baseline-Test.ps1
Version :  1.0
Date    :  2/2/2026
Author: Jody Ingram
Notes: This script runs various tests on multiple AVD Session Hosts and exports results.
#>

param(
    [Parameter(Mandatory)]
    [string]$Target,

    [int]$PingCount = 50,

    [string]$OutputPath
)

Write-Host "=== Baseline Network Test ===" -ForegroundColor Cyan
Write-Host "Target      : $Target"
Write-Host "Computer    : $env:COMPUTERNAME"
Write-Host "User        : $env:USERNAME"
Write-Host "Timestamp   : $(Get-Date)"
Write-Host "--------------------------------`n"

# --- ICMP Ping ---
Write-Host "Running ICMP Ping ($PingCount packets)..."

$pingResults = Test-Connection -ComputerName $Target -Count $PingCount -ErrorAction Stop

$pingStats = [PSCustomObject]@{
    Test          = "ICMP"
    Target        = $Target
    Sent          = $PingCount
    Received      = $pingResults.Count
    PacketLossPct = [math]::Round((($PingCount - $pingResults.Count) / $PingCount) * 100, 2)
    MinMs         = ($pingResults.ResponseTime | Measure-Object -Minimum).Minimum
    AvgMs         = [math]::Round(($pingResults.ResponseTime | Measure-Object -Average).Average, 2)
    MaxMs         = ($pingResults.ResponseTime | Measure-Object -Maximum).Maximum
}

$pingStats | Format-List
Write-Host ""

# --- TCP Test ---
Write-Host "Running TCP 443 Test..."

$tcp = Test-NetConnection -ComputerName $Target -Port 443 -InformationLevel Detailed

$tcpStats = [PSCustomObject]@{
    Test            = "TCP"
    Target          = $Target
    Port            = 443
    TcpSucceeded    = $tcp.TcpTestSucceeded
    RemoteAddress   = $tcp.RemoteAddress
    InterfaceAlias  = $tcp.InterfaceAlias
    SourceAddress   = $tcp.SourceAddress
    RTTMs           = $tcp.PingReplyDetails.RoundtripTime
}

$tcpStats | Format-List
Write-Host ""

# --- Traceroute ---
Write-Host "Running Traceroute..."

$traceRaw = tracert -d $Target

$traceHops = $traceRaw |
    Select-String "^\s*\d+" |
    ForEach-Object {
        $parts = ($_ -replace '\s+', ' ').Trim().Split(' ')
        [PSCustomObject]@{
            Hop = $parts[0]
            RTT1 = $parts[1]
            RTT2 = $parts[2]
            RTT3 = $parts[3]
            Address = $parts[-1]
        }
    }

$traceHops | Format-Table -AutoSize
Write-Host ""

# --- Consolidated Report ---
$report = @(
    $pingStats
    $tcpStats
)

if ($OutputPath) {
    Write-Host "Exporting report to $OutputPath"
    $report | Export-Csv -Path $OutputPath -NoTypeInformation
}

Write-Host "=== Baseline Test Complete ===" -ForegroundColor Green
