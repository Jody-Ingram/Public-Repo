<#
Script  :  Azure-LAW-Table-Property-Search.ps1
Version :  1.0
Date    :  6/19/2026
Author  :  Jody Ingram
Purpose :  Searches Azure Log Analytics Workspace tables for specific properties. Change the tableSubType value in script to search for different properties.
#>

$Results = foreach ($Sub in Get-AzSubscription) {
    Set-AzContext -SubscriptionId $Sub.Id | Out-Null

    foreach ($Workspace in Get-AzOperationalInsightsWorkspace) {
        $Path = "/subscriptions/$($Sub.Id)/resourceGroups/$($Workspace.ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($Workspace.Name)/tables?api-version=2025-07-01"

        try {
            $Tables = ((Invoke-AzRestMethod -Method GET -Path $Path).Content |
                ConvertFrom-Json).value

            foreach ($Table in $Tables) {
                if ($Table.properties.schema.tableSubType -eq "Classic") {
                    [PSCustomObject]@{
                        Subscription  = $Sub.Name
                        ResourceGroup = $Workspace.ResourceGroupName
                        Workspace     = $Workspace.Name
                        Table         = $Table.name
                        TableType     = $Table.properties.schema.tableType
                        TableSubType  = $Table.properties.schema.tableSubType
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not inspect $($Workspace.Name): $($_.Exception.Message)"
        }
    }
}

$Results | Sort-Object Subscription, Workspace, Table | Format-Table -AutoSize
