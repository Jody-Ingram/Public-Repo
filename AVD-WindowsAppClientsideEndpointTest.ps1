<#
Script  :  AVD-WindowsAppClientsideEndpointTest.ps1
Version :  1.0
Date    :  9/16/26
Author: Jody Ingram
Pre-reqs: N/A
Notes: This script tests the DNS resolution and TCP connectivity of specified Windows App endpoints.
#>

$Endpoints = @(
    "example.windows.cloud.microsoft",
    "example.service.windows.cloud.microsoft",
    "example.windows.static.microsoft"
)

foreach ($Endpoint in $Endpoints) {
    Write-Host ""
    Write-Host "Testing $Endpoint" -ForegroundColor Cyan

    try {
        Resolve-DnsName $Endpoint -ErrorAction Stop | Out-Null
        Write-Host "DNS Resolution: SUCCESS" -ForegroundColor Green
    }
    catch {
        Write-Host "DNS Resolution: FAILED" -ForegroundColor Red
        continue
    }

    $Result = Test-NetConnection -ComputerName $Endpoint -Port 443 -WarningAction SilentlyContinue

    if ($Result.TcpTestSucceeded) {
        Write-Host "TCP 443: SUCCESS" -ForegroundColor Green
    }
    else {
        Write-Host "TCP 443: FAILED" -ForegroundColor Red
    }
}
