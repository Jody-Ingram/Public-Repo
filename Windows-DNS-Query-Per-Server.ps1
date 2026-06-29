<#
Script  :  Windows-DNS-Query-Per-Server.ps1
Version :  1.0
Date    :  6/29/2026
Author: Jody Ingram
Pre-reqs: Requires permission to query DNS servers and access to run Resolve-DnsName.
Notes: This script queries DNS servers for specific DNS names and records the results.
#>

# List of DNS Servers
$DnsServers = @(
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
    "DNS_SERVER_NAME"
)

# DNS names to resolve; in this example, it was Azure Arc public endpoints.
$DnsNames = @(
    "his.arc.azure.com"
    "management.azure.com"
)

# Use the Windows-defined Desktop location
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$CsvPath = Join-Path $DesktopPath "Azure-DNS-Lookup-$TimeStamp.csv"

$Results = foreach ($DnsServer in $DnsServers) {
    foreach ($DnsName in $DnsNames) {

        Write-Host "Querying $DnsName using DNS server $DnsServer..." -ForegroundColor Cyan

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $Lookup = Resolve-DnsName `
                -Name $DnsName `
                -Server $DnsServer `
                -Type A `
                -DnsOnly `
                -ErrorAction Stop

            $Stopwatch.Stop()

            $IPv4Addresses = $Lookup |
                Where-Object { $_.Type -eq "A" -and $_.IPAddress } |
                Select-Object -ExpandProperty IPAddress -Unique

            $CNames = $Lookup |
                Where-Object { $_.Type -eq "CNAME" -and $_.NameHost } |
                Select-Object -ExpandProperty NameHost -Unique

            [PSCustomObject]@{
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                DNSServer         = $DnsServer
                QueryName         = $DnsName
                Status            = "Success"
                IPv4Addresses     = $IPv4Addresses -join "; "
                CNAMEs            = $CNames -join "; "
                ResponseTimeMs    = $Stopwatch.ElapsedMilliseconds
                Error             = ""
            }
        }
        catch {
            $Stopwatch.Stop()

            [PSCustomObject]@{
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                DNSServer         = $DnsServer
                QueryName         = $DnsName
                Status            = "Failed"
                IPv4Addresses     = ""
                CNAMEs            = ""
                ResponseTimeMs    = $Stopwatch.ElapsedMilliseconds
                Error             = $_.Exception.Message
            }
        }
    }
}

# Export results to the Desktop
$Results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

# Display results in the PowerShell window
$Results | Format-Table DNSServer, QueryName, Status, IPv4Addresses, ResponseTimeMs -AutoSize

Write-Host "`nDNS lookup report exported to:" -ForegroundColor Green
Write-Host $CsvPath -ForegroundColor Yellow
