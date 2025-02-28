<#
Script  :  Citrix-Machine-Catalog-Report.ps1
Version :  1.0
Date    :  2/28/25
Author: Jody Ingram
Pre-reqs: Citrix PowerShell Module
Notes: This script pulls and exports a list of servers inside Citrix Machine Catalogs.
#>

# Load the Citrix PowerShell snap-ins
Add-PSSnapin Citrix*

# Define the Machine Catalog name
$machineCatalogName = "MACHINE CATALOG NAME"

# Get the list of machines in the Citrix Machine Catalog
$serverList = Get-BrokerMachine -CatalogName $machineCatalogName

# Extract the server names
$serverNames = $serverList | Select-Object -ExpandProperty MachineName

# Define the output directory and file path
$outputDirectory = "C:\Temp\Citrix_Machine_Catalog_Reports"
$outputFilePath = "$outputDirectory\ServerList.txt"

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory
}

# Export the server names to a CSV file
$serverNames | Out-File -FilePath $outputFilePath

Write-Host "Server names have been exported to $outputFilePath"
