<#
Script  :  Azure-Local-Force-Cluster-Deployment.ps1
Version :  1.0
Date    :  4/24/2026
Author  :  Jody Ingram
Purpose :  Deploys Azure Local Cluster using ARM template, with custom retry logic for common timeout/cancel failure patterns.
#>

# Set parameters as needed
param(
    [string]$SubscriptionNameOrId = "SUBSCRIPTION_NAME",

    [string]$Location = "eastus",

    [string]$TemplateFile = "C:\Azure\azurelocalTemplate.json", # Set the location to your ARM template

    [string]$TemplateParameterFile = "C:\Azure\azurelocalParameters.json", # Set the location to your ARM template parameters file

    [string]$DeploymentName = ("azurelocalDeploy-" + (Get-Date -Format "yyyyMMdd-HHmm")),

    [int]$MaxRetries = 3,

    [int]$PollSeconds = 60
)

$ErrorActionPreference = "Stop"

# Import Modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop

# Prefixes messages with timestamps for better logging visibility
function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

# Checks the deployment and operations for known patterns of timeout/cancel failures that may be transient and worth retrying.
function Test-TimeoutLikeFailure {
    param(
        $Deployment,
        $Operations
    )

    if (-not $Deployment) { return $false }

    $raw = @(
        $Deployment | ConvertTo-Json -Depth 20
        if ($Operations) { $Operations | ConvertTo-Json -Depth 20 }
    ) -join "`n"

    return (
        $raw -match "No Updates were received from the HCI device in the last 60 minutes" -or
        $raw -match "No updates received for 60 minutes" -or
        $raw -match "CleanStuckJobInProgress" -or
        $raw -match "CloudDeploy_Deploy Operation cancelled" -or
        $raw -match "DeployClusterOperationFailed" -or
        $raw -match "PostArcNotificationFailed" -or
        $raw -match "HttpClient.Timeout" -or
        $raw -match "Operation cancelled" -or
        $raw -match "task was canceled"
    )
}
# Retrieves the current state of the deployment. This is used to check for terminal states and to get details on failures.
function Get-DeploymentTerminalState {
    param(
        [string]$Name
    )

    $dep = Get-AzSubscriptionDeployment -Name $Name -ErrorAction Stop
    return $dep
}

# Starts the ARM deployment at subscription scope
function Start-AzureLocalDeployment {
    param(
        [string]$Name,
        [string]$DeploymentLocation,
        [string]$TplFile,
        [string]$ParamFile
    )

    Write-Log "Starting subscription deployment '$Name' in location '$DeploymentLocation'..."

    $null = New-AzSubscriptionDeployment `
        -Name $Name `
        -Location $DeploymentLocation `
        -TemplateFile $TplFile `
        -TemplateParameterFile $ParamFile `
        -Verbose `
        -AsJob

    Write-Log "Deployment submitted."
}
# Polls the deployment status until it reaches a terminal state (Succeeded, Failed, Canceled).
function Wait-AzureLocalDeployment {
    param(
        [string]$Name,
        [int]$PollIntervalSeconds
    )

    while ($true) {
        Start-Sleep -Seconds $PollIntervalSeconds

        try {
            $dep = Get-DeploymentTerminalState -Name $Name
        }
        catch {
            Write-Log "Could not read deployment state. Retrying state check..."
            continue
        }

        Write-Log ("ProvisioningState = {0}" -f $dep.ProvisioningState)

        # Only return when ARM says the deployment is complete.
        switch ($dep.ProvisioningState) {
            "Succeeded" { return $dep }
            "Failed"    { return $dep }
            "Canceled"  { return $dep }
            default     { }
        }
    }
}
# Retrieves the operations for a given deployment, which can provide details on failures.
function Get-DeploymentFailureDetails {
    param(
        [string]$Name
    )

    try {
        $ops = Get-AzSubscriptionDeploymentOperation `
            -DeploymentName $Name `
            -ErrorAction Stop

        return $ops | Sort-Object Timestamp -Descending
    }
    catch {
        Write-Log "Unable to retrieve deployment operations."
        return $null
    }
}

# Connect to Azure
Connect-AzAccount

# Set subscription context
Write-Log "Setting Azure context to subscription $SubscriptionNameOrId"
Set-AzContext -Subscription $SubscriptionNameOrId -ErrorAction Stop | Out-Null

# Template file checks
if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
    throw "Template file not found: $TemplateFile"
}

if (-not (Test-Path -Path $TemplateParameterFile -PathType Leaf)) {
    throw "Template parameter file not found: $TemplateParameterFile"
}

# Deployment parameter checks
if ($MaxRetries -lt 1) {
    throw "MaxRetries must be 1 or higher."
}

if ($PollSeconds -lt 15) {
    throw "PollSeconds must be 15 or higher."
}

$attempt = 1
$lastFailure = $null

# Each retry uses a unique deployment name for clean history and logs
while ($attempt -le $MaxRetries) {
    $currentDeploymentName = "{0}-try{1}" -f $DeploymentName, $attempt

    Write-Log "=== Attempt $attempt of $MaxRetries ==="

    # Deploy ARM template again at subscription scope
    Start-AzureLocalDeployment `
        -Name $currentDeploymentName `
        -DeploymentLocation $Location `
        -TplFile $TemplateFile `
        -ParamFile $TemplateParameterFile

    $result = Wait-AzureLocalDeployment `
        -Name $currentDeploymentName `
        -PollIntervalSeconds $PollSeconds

    if ($result.ProvisioningState -eq "Succeeded") {
        Write-Log "Deployment succeeded on attempt $attempt."
        $result
        exit 0
    }

    Write-Log "Deployment ended with state '$($result.ProvisioningState)' on attempt $attempt."
    $lastFailure = $result

    $ops = Get-DeploymentFailureDetails `
        -Name $currentDeploymentName

    if ($ops) {
        Write-Log "Recent deployment operation details:"
        $ops |
            Select-Object -First 10 OperationId, ProvisioningState, Timestamp, TargetResource, StatusCode, StatusMessage |
            Format-List
    }

    $timeoutLike = Test-TimeoutLikeFailure `
        -Deployment $result `
        -Operations $ops

    # Retry only for known timeout/cancel style failures. Wait 5 minutes before retrying to allow transient issues to resolve.
    if ($timeoutLike -and $attempt -lt $MaxRetries) {
        Write-Log "Detected timeout/cancel pattern. Waiting 5 minutes before retry..."
        Start-Sleep -Seconds 300
        $attempt++
        continue
    }

    Write-Log "Failure was not recognized as auto-retryable, or max retries reached."
    break
}
# Fail if we exhausted retries or encountered a non-retryable failure. Output the last failure details for diagnostics. Azure Local deployment will cancel itself after timeout is reached.
Write-Error "Deployment did not succeed after $attempt attempt(s)."
if ($lastFailure) {
    $lastFailure | Format-List *
}
exit 1
