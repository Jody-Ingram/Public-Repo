<#
Script  :  Windows-Compare-Hostname-to-DNS.ps1
Version :  1.0
Date    :  6/24/2026
Author: Jody Ingram
Pre-reqs: Run with appropriate permissions on local machine to resolve DNS names.
Notes: This script compares the local hostname to the DNS PTR records for each IPv4 address.
#>

$LocalName = $env:COMPUTERNAME
$IPs = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "169.254*" -and
        $_.InterfaceAlias -notmatch "Loopback"
    }

foreach ($IP in $IPs) {
    $DNSName = (Resolve-DnsName $IP.IPAddress -Type PTR -ErrorAction SilentlyContinue).NameHost

    [PSCustomObject]@{
        IPAddress     = $IP.IPAddress
        LocalHostname = $LocalName
        DNSHostname   = $DNSName
        Match         = if ($DNSName) { # Reports true if the local hostname matches the DNS records.
            $DNSName.TrimEnd('.').Split('.')[0] -ieq $LocalName
        } else {
            "No DNS Record Found!"
        }
    }
}
