<#
Script  :  Azure-NSG-Comparison.ps1
Version :  1.0
Date    :  5/22/25
Author: Jody Ingram
Notes: This script compares two NSGs. It exports any rules that are on NSG1, but not on NSG2.
#>

# Authenticate to Azure; Change to appropriate subscription
Connect-AzAccount -SubscriptionName SUBSCRIPTION_NAME

# Change to the export directory you wish to use; the script creates it if it doesn't exist
$exportDir = "C:\Tools\NSG-Compare"
if (-not (Test-Path -Path $exportDir)) {
    New-Item -ItemType Directory -Path $exportDir | Out-Null
}

# Set your NSG and RG names
$resourceGroup1 = "RG-RESOURCEGROUP-1"
$nsgName1 = "NSG-NAME-1"

$resourceGroup2 = "RG-RESOURCEGROUP-2"
$nsgName2 = "NSG-NAME-2"

# If NSGs are in two different subscriptions, you can use the following command to set the context to the correct subscription.
# Set-AzContext SubscriptionName "OTHER_SUBSCRIPTION_NAME"


# Defines the normalized rules so the script only looks at the data it needs to compare; excludes default NSG rules
function Get-NormalizedRules {
    param (
        [string]$resourceGroup,
        [string]$nsgName
    )

    $rules = (Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Name $nsgName).SecurityRules

    $rules | Select-Object `
        @{Name='Direction';Expression={$_.Direction}}, `
        @{Name='Access';Expression={$_.Access}}, `
        @{Name='Protocol';Expression={$_.Protocol}}, `
        @{Name='SourceAddress';Expression={$_.SourceAddressPrefix}}, `
        @{Name='SourcePort';Expression={$_.SourcePortRange}}, `
        @{Name='DestinationAddress';Expression={$_.DestinationAddressPrefix}}, `
        @{Name='DestinationPort';Expression={$_.DestinationPortRange}}
}

# Get and normalize both NSG rule sets
$rules1 = Get-NormalizedRules -resourceGroup $resourceGroup1 -nsgName $nsgName1
$rules2 = Get-NormalizedRules -resourceGroup $resourceGroup2 -nsgName $nsgName2

# Compare rules in NSG1 that are not in NSG2
$diffOnlyInNSG1 = Compare-Object -ReferenceObject $rules1 -DifferenceObject $rules2 `
    -Property Direction, Access, Protocol, SourceAddress, SourcePort, DestinationAddress, DestinationPort `
    -PassThru | Where-Object { $_.SideIndicator -eq "<=" }

# Outputs to PowerShell
Write-Host "IP Rules in ${nsgName1} but not in ${nsgName2}`n" -ForegroundColor Yellow
$diffOnlyInNSG1 | Format-Table

# Export results to CSV
$exportPath = Join-Path -Path $exportDir -ChildPath "${nsgName1}-unique-rules.csv"
$diffOnlyInNSG1 | Export-Csv -Path $exportPath -NoTypeInformation -Encoding utf8

Write-Host "Exported to $exportPath" -ForegroundColor Cyan
