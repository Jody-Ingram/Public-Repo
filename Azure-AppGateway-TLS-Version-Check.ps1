<#
Script  :  Azure-AppGateway-TLS-Version-Check.ps1
Version :  1.0
Date    :  8/11/2025
Author: Jody Ingram
Pre-reqs: Azure PowerShell Modules: Az.Accounts and Az.Network
Notes: 
#>

# Connects to Azure; prompts for authentication account
Connect-AzAccount

# Subscription Names
$SubscriptionNames = @(
  'SUBSCRIPTION_NAME_1','SUBSCRIPTION_NAME_2','SUBSCRIPTION_NAME_3','SUBSCRIPTION_NAME_4','SUBSCRIPTION_NAME_5',
  'SUBSCRIPTION_NAME_6'
)

# Output CSV paths / modify as needed
$PoliciesCsv  = "C:\Temp\AppGw-TlsPolicies.csv"
$ListenersCsv = "C:\Temp\AppGw-ListenerEffectiveTls.csv"

# Creates output folder if it does not exist
$outDir = Split-Path $PoliciesCsv -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# Collections
$policyRows   = New-Object System.Collections.Generic.List[object]
$listenerRows = New-Object System.Collections.Generic.List[object]

# Helper to pull RG name from object ID
function Get-ResourceGroupFromObject {
    param([object]$Obj)
    if ($Obj.PSObject.Properties.Name -contains 'ResourceGroupName' -and $Obj.ResourceGroupName) {
        return $Obj.ResourceGroupName
    }
    if ($Obj.Id) {
        $parts = $Obj.Id -split '/'
        $rgIdx = [Array]::IndexOf($parts, 'resourceGroups')
        if ($rgIdx -ge 0 -and $rgIdx + 1 -lt $parts.Count) { return $parts[$rgIdx + 1] }
    }
    return ''
}

# Iterates through each subscription
foreach ($subName in $SubscriptionNames) {
    try {
        Set-AzContext -Subscription $subName -ErrorAction Stop | Out-Null
        Write-Host "Scanning subscription: $subName"
    } catch {
        Write-Warning "Could not set context to '$subName' : $($_.Exception.Message)"
        continue
    }

    $gateways = Get-AzApplicationGateway -ErrorAction SilentlyContinue
    if (-not $gateways) {
        Write-Host "  No Application Gateways found."
        continue
    }

    foreach ($gw in $gateways) {
        try {
            $rg = Get-ResourceGroupFromObject $gw
            $gwName = $gw.Name

            # ---------- Global SSL Policy ----------
            $globalPolicy = $gw.SslPolicy
            $globalMin  = $null
            $globalType = $null
            $globalName = $null
            if ($globalPolicy) {
                $globalMin  = $globalPolicy.MinProtocolVersion
                $globalType = $globalPolicy.PolicyType
                $globalName = $globalPolicy.PolicyName
            }

            $listeners = $gw.HttpListeners
            $globalListenersCount = 0
            if ($listeners) { $globalListenersCount = ([array]($listeners | Where-Object { -not $_.SslProfile })).Count }

            $policyRows.Add([pscustomobject]@{
                Subscription        = $subName
                ResourceGroup       = $rg
                AppGateway          = $gwName
                PolicyScope         = 'Global'
                PolicyType          = $globalType
                PolicyName          = $globalName
                MinProtocolVersion  = $globalMin
                ListenersUsingScope = $globalListenersCount
            })

            # Defines SSL profiles
            $profiles = $gw.SslProfiles
            if ($profiles) {
                foreach ($prof in $profiles) {
                    $profPolicy = $prof.SslPolicy
                    $profMin  = $null
                    $profType = $null
                    $profName = $null
                    if ($profPolicy) {
                        $profMin  = $profPolicy.MinProtocolVersion
                        $profType = $profPolicy.PolicyType
                        $profName = $profPolicy.PolicyName
                    }

                    $listenersUsingCount = 0
                    if ($listeners) {
                        $listenersUsingCount = (
                            [array]($listeners | Where-Object { $_.SslProfile -and $_.SslProfile.Id -eq $prof.Id })
                        ).Count
                    }

                    $policyRows.Add([pscustomobject]@{
                        Subscription        = $subName
                        ResourceGroup       = $rg
                        AppGateway          = $gwName
                        PolicyScope         = "SslProfile:$($prof.Name)"
                        PolicyType          = $profType
                        PolicyName          = $profName
                        MinProtocolVersion  = $profMin
                        ListenersUsingScope = $listenersUsingCount
                    })
                }
            }

            # Checks each TLS Listener
            if ($listeners) {
                foreach ($lst in $listeners) {
                    $listenerName = $lst.Name

                    # Checks hostname singular vs plural 
                    $hostName = $null
                    if ($lst.PSObject.Properties.Name -contains 'HostName' -and $lst.HostName) { $hostName = $lst.HostName }
                    elseif ($lst.PSObject.Properties.Name -contains 'HostNames' -and $lst.HostNames) { $hostName = ($lst.HostNames -join ',') }

                    # Port number call
                    $frontendPort = $null
                    try {
                        $frontendPortObj = $gw.FrontendPorts | Where-Object { $_.Id -eq $lst.FrontendPort.Id }
                        if ($frontendPortObj) { $frontendPort = $frontendPortObj.Port }
                    } catch {}

                    # Checks SSL policy for override
                    $scope  = 'Global'
                    $effMin = $globalMin

                    if ($lst.SslProfile) {
                        $prof = $profiles | Where-Object { $_.Id -eq $lst.SslProfile.Id }
                        if ($prof -and $prof.SslPolicy) {
                            $scope  = "SslProfile:$($prof.Name)"
                            $effMin = $prof.SslPolicy.MinProtocolVersion
                        } else {
                            $scope = 'SslProfile:(unresolved)'
                        }
                    }

                    $listenerRows.Add([pscustomobject]@{
                        Subscription       = $subName
                        ResourceGroup      = $rg
                        AppGateway         = $gwName
                        Listener           = $listenerName
                        HostName           = $hostName
                        FrontendPort       = $frontendPort
                        EffectivePolicy    = $scope
                        EffectiveMinTLS    = $effMin
                    })
                }
            }
        } catch {
            Write-Warning "  Error processing AppGW '$($gw.Name)' in RG '$rg' : $($_.Exception.Message)"
            continue
        }
    }
}

# Exports CSV files to specified location
$policyRows   | Sort-Object Subscription, ResourceGroup, AppGateway, PolicyScope | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $PoliciesCsv
$listenerRows | Sort-Object Subscription, ResourceGroup, AppGateway, Listener    | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ListenersCsv

Write-Host "`nDone."
Write-Host "Policies summary:      $PoliciesCsv"
Write-Host "Listeners (effective): $ListenersCsv"
