<#
Script  :  Azure-FunctionApp-Runtime-Report.ps1
Version :  1.0
Date    :  5/28/2025
Author  :  Jody Ingram
Purpose :  Runs a report on Azure Function Apps and their runtime versions.
Notes   :  This may work better for most running inside Cloud Shell PowerShell, as it has the correct Az modules pre-installed.
#>

# Exports file location
$export = "FunctionApps_Runtime_Report_AllSubscriptions.csv"

# Pulls in a list of subscriptions
$subs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }

# Iterates through each subscription and collects Function App runtime info
$allResults = @()
foreach ($sub in $subs) {

    Write-Host "====== Checking subscription: $($sub.Name)  ($($sub.Id)) ======" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Discover Function Apps
    $functions = Get-AzWebApp -ErrorAction SilentlyContinue |
      Where-Object { $_.Kind -match 'functionapp' -and $_.Kind -notmatch 'slot' } |
      Select-Object Name, ResourceGroup, Kind, ServerFarmId

    if (-not $functions) {
        Write-Warning "No Function Apps found in subscription $($sub.Id)"
        continue
    }

    foreach ($f in $functions) {
        try {
            $app = Get-AzWebApp -Name $f.Name -ResourceGroupName $f.ResourceGroup -ErrorAction Stop

            # Convert app settings to hashtable
            $settingsMap = @{}
            if ($app.SiteConfig -and $app.SiteConfig.AppSettings) {
                foreach ($s in $app.SiteConfig.AppSettings) { $settingsMap[$s.Name] = $s.Value }
            }

            # Extract runtime info from environment variables
            $runtime = $settingsMap['FUNCTIONS_WORKER_RUNTIME']
            $extVersion = $settingsMap['FUNCTIONS_EXTENSION_VERSION']
            if ($extVersion) { $extVersion = $extVersion.TrimStart('~') }

            # Calls linuxFxVersion as fallback
            $linuxFx = $app.SiteConfig.LinuxFxVersion
            if (-not $runtime -and $linuxFx) {
                $parts = $linuxFx -split '\|', 2
                if ($parts[0]) { $runtime = $parts[0].ToLower() }
                if (-not $extVersion -and $parts.Count -ge 2) { $extVersion = $parts[1] }
            }

            $os = if ($app.Kind -match 'linux') { 'Linux' } else { 'Windows' }
            $planName = ($app.ServerFarmId -split '/')[-1]

            # Add subscription identifier column
            $allResults += [pscustomobject]@{
                SubscriptionId = $sub.Id
                Subscription   = $sub.Name
                Name           = $f.Name
                ResourceGroup  = $f.ResourceGroup
                OS             = $os
                AppServicePlan = $planName
                Runtime        = $runtime
                Version        = $extVersion
            }
        }
        catch {
            $allResults += [pscustomobject]@{
                SubscriptionId = $sub.Id
                Subscription   = $sub.Name
                Name           = $f.Name
                ResourceGroup  = $f.ResourceGroup
                OS             = $null
                AppServicePlan = $null
                Runtime        = 'ERROR'
                Version        = $_.Exception.Message
            }
        }
    }
}

# Export final combined CSV
$allResults | Export-Csv -Path $export -NoTypeInformation -Encoding UTF8
Write-Host "`n✅ Export complete: $export (All subscriptions)" -ForegroundColor Green
