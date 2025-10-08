<#
Script  :  AVD-SH-Reboot-Automation.ps1
Version :  1.0
Date    :  10/8/2025
Author: Jody Ingram
Notes: This script reboots AVD personal session hosts on a 30-day uptime schedule. 

Azure Automation:
This will connect to Azure using an Automation Account's Managed Identity. It reboots all VMs in specified resource groups that matches the AVD host naming convention (SH-itec-p-* and SH-ecct-t-*). 
#>

# Disable script context autosave after session is complete
Disable-AzContextAutosave -Scope Process

# Authenticate using system-assigned Managed Identity of the Automation Account
try {
    Connect-AzAccount -Identity -Subscription "WS_AVD_EA" | Out-Null
    Write-Output "[$(Get-Date -Format 'u')] Connected to Azure using Managed Identity."
}
catch {
    Write-Error "Failed to connect to Azure with Managed Identity. $_"
    Exit 1
}

# Variables 
$targetResourceGroup = "RG-AVD-Test-eus2" # Modify target Resource Group
$hostNamePatterns = @('SH-itec-p-', 'SH-ecct-t-') # Modify host name patterns as needed
$region = "eastus2"

Write-Output "[$(Get-Date -Format 'u')] Searching for session hosts in resource group: $targetResourceGroup (Region: $region)"

# Get VMs in the specified RG using our naming convention
$vms = Get-AzVM -ResourceGroupName $targetResourceGroup -Status `
        | Where-Object {
            ($_.Name -match '^SH-itec-p-' -or $_.Name -match '^SH-ecct-t-') ` # Modify name(s) as needed
            -and $_.Location -eq $region
        }

if (-not $vms) {
    Write-Output "[$(Get-Date -Format 'u')] No matching AVD session hosts found in $targetResourceGroup."
    Exit 0
}

Write-Output "[$(Get-Date -Format 'u')] Found $($vms.Count) matching session hosts."

# Iterate through the VM list and reboot the machines that meet the criteria
foreach ($vm in $vms) {
    $vmName = $vm.Name
    $vmStatus = ($vm.Statuses | Where-Object { $_.Code -match 'PowerState' }).DisplayStatus

    Write-Output "[$(Get-Date -Format 'u')] Processing $vmName ($vmStatus)"

    if ($vmStatus -eq 'VM deallocated' -or $vmStatus -eq 'VM stopped') {
        Write-Output "[$(Get-Date -Format 'u')] Skipping $vmName (currently stopped/deallocated)."
        continue
    }

    try {
        Restart-AzVM -Name $vmName -ResourceGroupName $targetResourceGroup -Force -ErrorAction Stop
        Write-Output "[$(Get-Date -Format 'u')] Successfully initiated reboot for $vmName."
    }
    catch {
        Write-Error "[$(Get-Date -Format 'u')] Failed to reboot $vmName. $_"
    }
}

Write-Output "[$(Get-Date -Format 'u')] Runbook complete."
