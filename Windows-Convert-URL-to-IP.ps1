<#
Script  :  Windows-Convert-URL-to-IP.ps1
Version :  1.0
Date    :  5/9/2025
Author: Jody Ingram
Pre-reqs: N/A
Notes: This script imports a list of URLs and runs DNS resolution against them, exporting to results to a CSV file.
#>

# Option 1: Import from a list of servers (larger lists); change path as needed
$urls = Get-Content -Path "C:\PATH\urls.txt"

# Option 2: Add the server list to the script directly (smaller lists)
#$urls = @(
    "google.com",
    "microsoft.com",
    "openai.com",
    "cloudflare.com",
    "amazon.com"
#)


$results = @()

foreach ($url in $urls) {
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($url)
        foreach ($addr in $addresses) {
            $results += [PSCustomObject]@{
                URL       = $url
                IPAddress = $addr.IPAddressToString
            }
            Write-Output "$url : $($addr.IPAddressToString)"
        }
    } catch {
        $results += [PSCustomObject]@{
            URL       = $url
            IPAddress = "Resolution Failed"
        }
        Write-Output "$url : Resolution Failed"
    }
}

# Export result to CSV; changed path as needed

$csvPath = "C:\PATH\ResolvedIPs.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "`n[+] Results exported to: $csvPath" -ForegroundColor Green
