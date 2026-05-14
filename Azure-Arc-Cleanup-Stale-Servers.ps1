<#
Script  : Azure-Arc-Cleanup-Stale-Servers.ps1
Version : 1.2
Date    : 05-14-2026
Author  : Jody Ingram

Pre-reqs:
- Azure Automation Account with System-assigned Managed Identity
- Az.ResourceGraph, Az.Resources PowerShell Modules imported in the Automation Account

Purpose:
- Identifies Azure Arc-enabled servers that have been disconnected for 60 days.
- Defaults to report-only mode.
- Deletes stale Arc server resources only when -Delete is set to $true.

Notes:
- This removes stale Azure Arc resource objects from Azure.
- This does NOT uninstall the Azure Connected Machine Agent from servers that still exist.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [int]$DaysDisconnected = 60,

    [ValidateNotNullOrEmpty()]
    [string[]]$Subscription,

    [ValidateNotNullOrEmpty()]
    [string]$ManagementGroup,

    # Set $Delete to $true only after validating output.
    [bool]$Delete = $false,

    # Safety guard to prevent accidental large-scale deletion.
    [int]$MaxDeleteCount = 50
)

Write-Output "Starting Azure Arc stale server cleanup runbook."
Write-Output "DaysDisconnected threshold: $DaysDisconnected"
Write-Output "Delete mode: $Delete"
Write-Output "MaxDeleteCount: $MaxDeleteCount"

# Prevents scoping to both Subscription and Management Group at the same time.
if ($Subscription -and $ManagementGroup) {
    Write-Error "Specify either -Subscription or -ManagementGroup, not both."
    return
}

# Checks for required PowerShell modules in Azure Automation.
$requiredModules = @(
    'Az.Accounts',
    'Az.ResourceGraph',
    'Az.Resources'
)

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -Name $mod -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Error "Required module '$mod' is not available in this Automation Account. Import it before running this runbook."
        return
    }
}

# Disables Azure Context autosave since we are using Resource Graph to find and remove Arc machines, and the ConnectMachine module is not required to be installed in the Automation Account.
try {
    Disable-AzContextAutosave -Scope Process | Out-Null

    $azureContext = (Connect-AzAccount -Identity -ErrorAction Stop).Context

    Write-Output "Connected to Azure using Managed Identity."
    Write-Output "Tenant ID: $($azureContext.Tenant.Id)"
    Write-Output "Account: $($azureContext.Account.Id)"
}
catch {
    Write-Error "Failed to authenticate using Managed Identity. Ensure the Automation Account identity is enabled and has RBAC permissions. Error: $_"
    return
}

# KQL Query to find Azure Arc machines in Disconnected state for more than the specified number of days.
$kqlQuery = @"
Resources
| where type =~ 'microsoft.hybridcompute/machines'
| where properties.status =~ 'Disconnected'
| where todatetime(properties.lastStatusChange) < ago($($DaysDisconnected)d)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    status = tostring(properties.status),
    lastStatusChange = todatetime(properties.lastStatusChange)
| order by lastStatusChange asc
"@

Write-Output "Searching for Azure Arc servers disconnected for more than $DaysDisconnected days..."

# Query Azure Resource Graph with pagination support.
$staleServers = [System.Collections.Generic.List[object]]::new()
$skipToken = $null

try {
    do {
        $params = @{
            Query = $kqlQuery
            First = 1000
        }

        if ($skipToken) {
            $params['SkipToken'] = $skipToken
        }

        if ($Subscription) {
            $params['Subscription'] = $Subscription
            Write-Output "Query scope: Subscription(s): $($Subscription -join ', ')"
        }
        elseif ($ManagementGroup) {
            $params['ManagementGroup'] = $ManagementGroup
            Write-Output "Query scope: Management Group: $ManagementGroup"
        }
        else {
            Write-Warning "No Subscription or ManagementGroup was provided. Query will use the current accessible tenant/subscription context."
        }

        $result = Search-AzGraph @params -ErrorAction Stop

        # Handles different Az.ResourceGraph return shapes depending on module version.
        if ($null -ne $result.Data) {
            $pageItems = @($result.Data)
        }
        else {
            $pageItems = @($result | Where-Object { $_.id })
        }

        if ($pageItems.Count -gt 0) {
            $staleServers.AddRange([object[]]$pageItems)
        }

        if ($result.PSObject.Properties.Name -contains 'SkipToken') {
            $skipToken = $result.SkipToken
        }
        else {
            $skipToken = $null
        }

    } while ($skipToken)
}
catch {
    Write-Error "Failed to query Azure Resource Graph. Confirm the managed identity has Reader permissions and the Az.ResourceGraph module is installed. Error: $_"
    return
}

if ($staleServers.Count -eq 0) {
    Write-Output "No stale Azure Arc servers found matching the criteria."
    return
}

Write-Output "Found $($staleServers.Count) stale Azure Arc server resource(s)."

# Always output findings before any deletion to allow review, especially when Delete mode is enabled. Can be removed or commented later out if not needed.
Write-Output "Stale Arc server candidates:"
foreach ($server in $staleServers) {
    Write-Output "Name: $($server.name) | Subscription: $($server.subscriptionId) | RG: $($server.resourceGroup) | Location: $($server.location) | LastStatusChange: $($server.lastStatusChange)"
}

# Report-only mode - exit before deletion if Delete switch is not set.
if (-not $Delete) {
    Write-Output "Delete is set to false. Report-only mode completed. No resources were deleted."
    return
}

# Safety cap before deleting.
if ($staleServers.Count -gt $MaxDeleteCount) {
    Write-Error "Delete mode is enabled, but $($staleServers.Count) resources were found, which exceeds MaxDeleteCount of $MaxDeleteCount. No resources were deleted."
    return
}

Write-Warning "Delete mode is enabled. Beginning stale Azure Arc resource deletion."

$successCount = 0
$failCount = 0

foreach ($server in $staleServers) {

    # ShouldProcess allows manual WhatIf support while Delete controls scheduled run behavior.
    if ($PSCmdlet.ShouldProcess($server.id, "Delete stale Azure Arc server '$($server.name)'")) {
        try {
            Remove-AzResource `
                -ResourceId $server.id `
                -Force `
                -ErrorAction Stop

            Write-Output "Successfully deleted stale Arc server: $($server.name)"
            $successCount++
        }
        catch {
            Write-Error "Failed to delete stale Arc server '$($server.name)'. Error: $_"
            $failCount++
        }
    }
}

Write-Output ""
Write-Output "Azure Arc stale server cleanup completed."
Write-Output "Deleted: $successCount"
Write-Output "Failed: $failCount"
Write-Output "Total Found: $($staleServers.Count)"
