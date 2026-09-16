<#
Script  :  AD-GetADObjectListfromOU.ps1
Version :  1.0
Date    :  9/16/26
Author: Jody Ingram
Pre-reqs: N/A
Notes: This script retrieves a list of Active Directory computer objects from a specified Organizational Unit (OU).
#>

# Imports the module needed to run this script
Import-Module ActiveDirectory

# Specify the AD OU
$OU = "OU=Servers,OU=Servers,DC=company,DC=com"

Get-ADComputer -SearchBase $OU -SearchScope Subtree -Filter * `
    -Properties DNSHostName, Enabled |
    Sort-Object Name |
    Select-Object Name, DNSHostName, Enabled, DistinguishedName

# Uncomment if needed to export to .csv

# Export-Csv "$env:USERPROFILE\Desktop\OU-Computers.csv" -NoTypeInformation
