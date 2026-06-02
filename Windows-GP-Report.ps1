<#
Script  :  Windows-GP-Report.ps1
Version :  1.0
Date    :  5/4/2026
Author: Jody Ingram
Pre-reqs: Run CMD or PowerShell as Administrator
Notes: This script generates a simple Group Policy report for the local machine and saves it to a timestamped directory under C:\Temp\GPReport. It creates both an HTML and a text report, and opens the folder and HTML report if they are created successfully.
#>

$BaseDir = "C:\Temp\GPReport"
$TimeStamp = Get-Date -Format 'MM-dd-yyyy_HH-mm-ss'
$OutDir = Join-Path $BaseDir "$env:COMPUTERNAME-$TimeStamp"
$Report = Join-Path $OutDir "GPReport-$env:COMPUTERNAME.html"
$TextReport = Join-Path $OutDir "GPReport-$env:COMPUTERNAME.txt"

$ErrorActionPreference = 'Stop'

# Create base directory if it does not exist
if (-not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}

# Create output directory
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Generate reports
gpresult /h "$Report" /f
gpresult /r > "$TextReport"

# Open folder and report only if created successfully
if (Test-Path $OutDir) {
    Start-Process $OutDir
}

if (Test-Path $Report) {
    Start-Process $Report
} else {
    Write-Warning "GPResult HTML report was not created."
}

Write-Host "Reports saved to: $OutDir"
``
