<#
Script  :  Azure-Toggle-UDR-Management.ps1
Version :  1.0
Date    :  6/20/2025
Author  :  Jody Ingram
Notes: This script toggles a UDR for a specific Azure Subnet on or off.
Launcher:

# Disable (detach) the UDR
.\Update-SubnetRoute.ps1 -Action disable

# Re-enable (attach) the UDR
.\Update-SubnetRoute.ps1 -Action enable

#>


# Define parameters for script's execution
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId           = "Subscription_ID",
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName       = "RESOURCE-GROUP-NAME",
    [Parameter(Mandatory=$false)]
    [string]$VNetName                = "VNET-NAME",
    [Parameter(Mandatory=$false)]
    [string]$SubnetName              = "SNET-NAME",
    [Parameter(Mandatory=$false)]
    [string]$RouteTableName          = "Route-Table-Name",
    [Parameter(Mandatory=$true)]
    [ValidateSet("disable","enable")]
    [string]$Action
)


# Checks for Azure PowerShell Module(s)
if (-not (Get-Module -ListAvailable -Name Az.Network)) {
    Write-Error "Az.Network module not found. Install with `Install-Module Az.Network` first."
    exit 1
}

# Authenticate and set subscription context
Connect-AzAccount -ErrorAction Stop | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

# Fetch the VNet and subnet config
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop
$subnetConfig = $vnet.Subnets | Where-Object Name -EQ $SubnetName
if (-not $subnetConfig) {
    Write-Error "Subnet '$SubnetName' not found in VNet '$VNetName'."
    exit 1
}

if ($Action -eq "disable") {
    # Remove the route table association
    Write-Host "🔌 Detaching route table from subnet..."
    $subnetConfig.RouteTable = $null
}
else {
    # Retrieve the route table object
    $rt = Get-AzRouteTable -ResourceGroupName $ResourceGroupName -Name $RouteTableName -ErrorAction Stop
    Write-Host "🔗 Attaching route table '$RouteTableName' to subnet..."
    $subnetConfig.RouteTable = $rt
}

# Pushes the update
Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null

Write-Host "✅ Action '$Action' completed successfully on subnet '$SubnetName'."
