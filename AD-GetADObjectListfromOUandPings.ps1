<#
Script  :  AD-GetADObjectListfromOUandPings.ps1
Version :  1.0
Date    :  9/16/26
Pre-reqs: N/A
Notes: This script retrieves a list of Active Directory computer objects from a specified Organizational Unit (OU) and pings each computer to check its availability.
#>

# Imports the module needed to run this script
Import-Module ActiveDirectory

# Specify the AD OU
$OU = "OU=Servers,OU=Machines,DC=company,DC=com"


$Results = Get-ADComputer -SearchBase $OU -SearchScope Subtree `
    -Filter * -Properties DNSHostName | Sort-Object Name | ForEach-Object {

    $Target = if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name }
    Write-Host "Pinging $Target..."

    [PSCustomObject]@{
        Name      = $_.Name
        Target    = $Target
        Enabled   = $_.Enabled
        PingReply = Test-Connection -ComputerName $Target -Count 1 `
                        -Quiet -ErrorAction SilentlyContinue
    }
}

$Results | Format-Table -AutoSize
$Results | Export-Csv "$env:USERPROFILE\Desktop\Computer-Ping-Results.csv" `
    -NoTypeInformation
