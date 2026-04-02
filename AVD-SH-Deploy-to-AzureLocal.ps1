<#
Script  :  AVD-SH-Deploy-to-AzureLocal.ps1
Version :  1.0
Date    :  3/16/2026
Author: Jody Ingram
Notes: This script deploys a Session Host to an AVD Host Pool that is connected to Azure Local.
Requirements:
# - PowerShell 5.1 or later. PowerShell 7.2 is recommended.
# - Requires Az.Accounts, Az.Resources, Az.DesktopVirtualization, Az.ConnectedMachine
# - Requires Bicep CLI in PATH for New-AzResourceGroupDeployment with .bicep
# - Uses Azure Arc Run Command for the in-guest AVD agent install
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configurations. Modify as needed.

$Config = [ordered]@{
    # Azure
    SubscriptionName   = 'SUBSCRIPTION_NAME'
    SubscriptionId     = 'SUBSCRIPTION_ID'
    ResourceGroupName  = 'RG-AzureLocal-AVD-Prod-eus'
    Location           = 'eastus'

    # AVD
    HostPoolName       = 'vdpool-eus-azl-dsk-prs-p-01'
    GenerateRegistrationToken = $false
    RegistrationTokenHours    = 24
    RegistrationToken         = '<PASTE_HOST_POOL_REGISTRATION_TOKEN_HERE>'   # Placeholder. If GenerateRegistrationToken = $true, this is ignored.

    # Azure Local / VM
    NamePrefix         = 'sh-azl-it-p'     # 11 Character max since it's a prefix (Azure adds the sequence numbers)
    VmSequence         = '01'
    ClusterHint        = 'DataCenter1'   # Used for custom location resolution
    CustomLocationName = 'DataCenter1'  # Datacenter Location
    ImageName          = 'IMG-Win11Enterprise-25H2-3-20-2026'   # Image name here; use the latest image date from Azure Gallery
    IsMarketplaceImage = $false    # Adding this here incase we need to use marketplace images for testing instead of Azure Local gallery images.
    LogicalNetworkName = 'lnet-datacenter1-guest-static-v713'  
    VcpuCount          = 8    # CPU Count. Adjust as needed.
    MemoryGB           = 16   # RAM in GB. Adjust as needed.

    # Domain Join
    DomainToJoin       = 'domain.org'
    DomainTargetOU     = 'OU=AVD,OU=Workstations,OU=Machines,DC=domain,DC=org'  
    DomainJoinUpn      = 'domain_join_account@whs.int'
    DomainJoinPassword = '<PASSWORD>'      # Placeholder - supply real value

    # Local Admin
    LocalAdminUsername = 'LocalAdminAcct'
    LocalAdminPassword = '<PASSWORD>'  # This is a temp password and will be rotated post deployment

    # Tags
    OwnerTagValue      = 'firstname.lastname@company.org'

    # You can specify the user to assign this to during deployment, but they must already be in the appropriate hostpool workspace AD group. 
    AssignedUserUpn    = ''                # Example: 'jody.ingram@company.org' ; leave blank to skip direct assignment

    # Wait settings
    ArcWaitMinutes         = 45
    SessionHostWaitMinutes = 30
}

# Helper functions
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==== $Message ====" -ForegroundColor Cyan
}

function Ensure-Module {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing module [$Name] for current user..." -ForegroundColor Yellow
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
    }

    Import-Module $Name -Force
}

function Resolve-CustomLocationName {
    param(
        [Parameter(Mandatory)][string]$ClusterHint
    )

    $customLocations = Get-AzResource -ResourceType 'Microsoft.ExtendedLocation/customLocations' -ErrorAction SilentlyContinue
    if (-not $customLocations) {
        return $null
    }

    $matches = $customLocations | Where-Object {
        $_.Name -match [regex]::Escape($ClusterHint) -or
        $_.ResourceGroupName -match [regex]::Escape($ClusterHint) -or
        $_.Id -match [regex]::Escape($ClusterHint)
    }

    if ($matches.Count -eq 1) {
        return $matches[0].Name
    }

    return $null
}

function Wait-ForArcConnected {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$MachineName,
        [int]$TimeoutMinutes = 45
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    do {
        try {
            $machine = Get-AzConnectedMachine -ResourceGroupName $ResourceGroupName -Name $MachineName -ErrorAction Stop
            Write-Host "Arc status for [$MachineName]: $($machine.Status) / $($machine.ProvisioningState)"
            if ($machine.Status -eq 'Connected' -and $machine.ProvisioningState -eq 'Succeeded') {
                return $machine
            }
        }
        catch {
            Write-Host "Arc machine [$MachineName] not ready yet."
        }

        Start-Sleep -Seconds 30
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for Arc machine [$MachineName] to become Connected."
}

function Wait-ForSessionHost {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$HostPoolName,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [int]$TimeoutMinutes = 30
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    do {
        try {
            $hosts = Get-AzWvdSessionHost `
                -ResourceGroupName $ResourceGroupName `
                -HostPoolName $HostPoolName `
                -SubscriptionId $SubscriptionId `
                -ErrorAction Stop

            $match = $hosts | Where-Object {
                $_.Name -match "/$([regex]::Escape($VmName))(\.|$)" -or
                $_.Name -match "/$([regex]::Escape($VmName))$"
            }

            if ($match) {
                return $match | Select-Object -First 1
            }
        }
        catch {
            Write-Host "Session host not visible in AVD yet."
        }

        Start-Sleep -Seconds 30
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for session host [$VmName] to appear in host pool [$HostPoolName]."
}

# Validates the config prior to deploying

$VmName = "{0}-{1}" -f $Config.NamePrefix, $Config.VmSequence

if ($Config.NamePrefix.Length -gt 11) {
    throw "NamePrefix [$($Config.NamePrefix)] is longer than 11 characters."
}
if ($VmName.Length -gt 15) {
    throw "Final VM name [$VmName] exceeds 15 characters."
}
if ([string]::IsNullOrWhiteSpace($Config.DomainJoinPassword) -or $Config.DomainJoinPassword -like '<*') {
    throw "Populate DomainJoinPassword first."
}
if ([string]::IsNullOrWhiteSpace($Config.LocalAdminPassword) -or $Config.LocalAdminPassword -like '<*') {
    throw "Populate LocalAdminPassword first."
}

# Add the registration token of the appropriate host pool. I added the piece to generate the reg key but have not fully tested it. -Jody

if (-not $Config.GenerateRegistrationToken) {
    if ([string]::IsNullOrWhiteSpace($Config.RegistrationToken) -or $Config.RegistrationToken -like '<*') {
        throw "Either paste a real RegistrationToken or set GenerateRegistrationToken = `$true."
    }
}

# Validates required modules are loaded and imported into PowerShell session. Installs if not found.

Write-Step "Loading required modules"
Ensure-Module -Name Az.Accounts
Ensure-Module -Name Az.Resources
Ensure-Module -Name Az.DesktopVirtualization
Ensure-Module -Name Az.ConnectedMachine

if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) {
    throw "Bicep CLI was not found in PATH. Install Bicep or run this from Azure Cloud Shell."
}

# Azure Auth Logon and Subscription Context

Write-Step "Connecting to Azure"
Connect-AzAccount | Out-Null
Set-AzContext -SubscriptionId $Config.SubscriptionId | Out-Null

$rg = Get-AzResourceGroup -Name $Config.ResourceGroupName -ErrorAction Stop
Write-Host "Using subscription: $($Config.SubscriptionName) [$($Config.SubscriptionId)]"
Write-Host "Using resource group: $($rg.ResourceGroupName)"

# Custom Location Discovery (We specify in the config via the Cluster Hint)

if ([string]::IsNullOrWhiteSpace($Config.CustomLocationName) -or $Config.CustomLocationName -like '<*') {
    Write-Step "Attempting custom location auto-discovery"
    $resolvedCustomLocation = Resolve-CustomLocationName -ClusterHint $Config.ClusterHint
    if ($resolvedCustomLocation) {
        $Config.CustomLocationName = $resolvedCustomLocation
        Write-Host "Resolved CustomLocationName to [$($Config.CustomLocationName)]" -ForegroundColor Green
    }
    else {
        throw "CustomLocationName is still not set. Populate it with the Azure Local custom location resource name."
    }
}

# Registers session host to host pool using the registration token.

if ($Config.GenerateRegistrationToken) {
    Write-Step "Generating host pool registration token"

    $expiration = (Get-Date).ToUniversalTime().AddHours([int]$Config.RegistrationTokenHours).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')

    New-AzWvdRegistrationInfo `
        -HostPoolName $Config.HostPoolName `
        -ResourceGroupName $Config.ResourceGroupName `
        -ExpirationTime $expiration | Out-Null

    $Config.RegistrationToken = (Get-AzWvdHostPoolRegistrationToken `
        -HostPoolName $Config.HostPoolName `
        -ResourceGroupName $Config.ResourceGroupName).Token

    if ([string]::IsNullOrWhiteSpace($Config.RegistrationToken)) {
        throw "Registration token generation returned an empty token."
    }

    Write-Host "Registration token generated successfully." -ForegroundColor Green
}

# Session Host Build Template

Write-Step "Writing temporary Bicep template"

$domainJoinUserName = ($Config.DomainJoinUpn -split '@')[0]

$bicep = @'
@maxLength(15)
param name string
param location string
param vCPUCount int = 2
param memoryMB int = 8192
param adminUsername string
@secure()
param adminPassword string
@description('Image resource name. Example: IMG-Win11Enterprise-25H2-2-20-2026')
param imageName string
@description('True if the image is a Marketplace Gallery image; false for Azure Local gallery image.')
param isMarketplaceImage bool = false
@description('Existing Azure Local logical network name.')
param hciLogicalNetworkName string
@description('Existing Azure custom location name tied to the Azure Local instance.')
param customLocationName string
param tags object = {}
@description('Optional AD domain name to join. Leave empty to skip domain join.')
param domainToJoin string = ''
@description('Optional OU path.')
param domainTargetOu string = ''
@description('Domain join username without the @domain suffix.')
param domainJoinUserName string = ''
@secure()
param domainJoinPassword string = ''

var nicName = 'nic-${name}'
var customLocationId = resourceId('Microsoft.ExtendedLocation/customLocations', customLocationName)
var imageId = isMarketplaceImage
  ? resourceId('Microsoft.AzureStackHCI/marketplaceGalleryImages', imageName)
  : resourceId('Microsoft.AzureStackHCI/galleryImages', imageName)
var logicalNetworkId = resourceId('Microsoft.AzureStackHCI/logicalNetworks', hciLogicalNetworkName)

resource hybridComputeMachine 'Microsoft.HybridCompute/machines@2023-10-03-preview' = {
  name: name
  location: location
  kind: 'HCI'
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
}

resource nic 'Microsoft.AzureStackHCI/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: logicalNetworkId
          }
        }
      }
    ]
  }
}

resource virtualMachine 'Microsoft.AzureStackHCI/virtualMachineInstances@2024-01-01' = {
  name: 'default'
  scope: hybridComputeMachine
  properties: {
    hardwareProfile: {
      vmSize: 'Custom'
      processors: vCPUCount
      memoryMB: memoryMB
    }
    osProfile: {
      adminUsername: adminUsername
      adminPassword: adminPassword
      computerName: name
      windowsConfiguration: {
        provisionVMAgent: true
        provisionVMConfigAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        id: imageId
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
}

resource domainJoin 'Microsoft.HybridCompute/machines/extensions@2023-10-03-preview' = if (!empty(domainToJoin)) {
  parent: hybridComputeMachine
  location: location
  name: 'domainJoinExtension'
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      name: domainToJoin
      OUPath: domainTargetOu
      User: '${domainToJoin}\\${domainJoinUserName}'
      Restart: true
      Options: 3
    }
    protectedSettings: {
      Password: domainJoinPassword
    }
  }
}
'@

$bicepPath = Join-Path $env:TEMP "deploy-azlocal-avd-$VmName.bicep"
Set-Content -Path $bicepPath -Value $bicep -Encoding UTF8

# Deploys Azure Local VM (SH)

Write-Step "Deploying Azure Local VM [$VmName]"

$templateParams = @{
    name                = $VmName
    location            = $Config.Location
    vCPUCount           = [int]$Config.VcpuCount
    memoryMB            = ([int]$Config.MemoryGB * 1024)
    adminUsername       = $Config.LocalAdminUsername
    adminPassword       = $Config.LocalAdminPassword
    imageName           = $Config.ImageName
    isMarketplaceImage  = [bool]$Config.IsMarketplaceImage
    hciLogicalNetworkName = $Config.LogicalNetworkName
    customLocationName  = $Config.CustomLocationName
    tags                = @{
        Owner = $Config.OwnerTagValue
    }
    domainToJoin        = $Config.DomainToJoin
    domainTargetOu      = $Config.DomainTargetOU
    domainJoinUserName  = $domainJoinUserName
    domainJoinPassword  = $Config.DomainJoinPassword
}

$deploymentName = "dep-$VmName-$(Get-Date -Format 'yyyyMMddHHmmss')"

$deployment = New-AzResourceGroupDeployment `
    -Name $deploymentName `
    -ResourceGroupName $Config.ResourceGroupName `
    -TemplateFile $bicepPath `
    -TemplateParameterObject $templateParams `
    -Verbose

if ($deployment.ProvisioningState -ne 'Succeeded') {
    throw "VM deployment did not complete successfully. ProvisioningState = $($deployment.ProvisioningState)"
}

# Tags the Azure Arc machine resource
$machineResourceId = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroupName)/providers/Microsoft.HybridCompute/machines/$VmName"
Update-AzTag -ResourceId $machineResourceId -Tag @{ Owner = $Config.OwnerTagValue } -Operation Merge | Out-Null

# Arc machine connectivity. (This can be slow sometimes, but is mandatory)
Write-Step "Waiting for Arc machine connectivity"
$arcMachine = Wait-ForArcConnected `
    -ResourceGroupName $Config.ResourceGroupName `
    -MachineName $VmName `
    -TimeoutMinutes $Config.ArcWaitMinutes

Write-Host "Arc machine is connected." -ForegroundColor Green

# Installs AVD Agent and Boot Loader

Write-Step "Installing AVD agent and boot loader"

$sourceScript = @"
`$ErrorActionPreference = 'Stop'
`$workDir = 'C:\Temp\AVDInstall'
New-Item -ItemType Directory -Path `$workDir -Force | Out-Null

`$registrationToken = @'
$($Config.RegistrationToken)
'@

`$agentMsi = Join-Path `$workDir 'AVDAgent.msi'
`$bootMsi  = Join-Path `$workDir 'AVDBootLoader.msi'

Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2310011' -OutFile `$agentMsi
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2311028' -OutFile `$bootMsi

Start-Process msiexec.exe -ArgumentList "/i `"`$agentMsi`" /quiet REGISTRATIONTOKEN=`"`$registrationToken`"" -Wait -NoNewWindow
Start-Process msiexec.exe -ArgumentList "/i `"`$bootMsi`" /quiet" -Wait -NoNewWindow

Write-Output 'AVD agent and boot loader installed successfully.'
"@

$runCommandName = 'InstallAVDAgent'

$runResult = New-AzConnectedMachineRunCommand `
    -ResourceGroupName $Config.ResourceGroupName `
    -MachineName $VmName `
    -Location $Config.Location `
    -RunCommandName $runCommandName `
    -SourceScript $sourceScript

Write-Host "Run command submitted/completed for [$VmName]."

# Waits for the Session Host to register and appear in host pool
Write-Step "Waiting for VM to appear in host pool"

$sessionHost = Wait-ForSessionHost `
    -ResourceGroupName $Config.ResourceGroupName `
    -HostPoolName $Config.HostPoolName `
    -VmName $VmName `
    -SubscriptionId $Config.SubscriptionId `
    -TimeoutMinutes $Config.SessionHostWaitMinutes

$sessionHostName = ($sessionHost.Name -split '/', 2)[1]
Write-Host "Session host registered: $sessionHostName" -ForegroundColor Green


# Creates the direct assignment user if specified

if (-not [string]::IsNullOrWhiteSpace($Config.AssignedUserUpn)) {
    Write-Step "Assigning personal desktop to user [$($Config.AssignedUserUpn)]"

    Update-AzWvdSessionHost `
        -ResourceGroupName $Config.ResourceGroupName `
        -HostPoolName $Config.HostPoolName `
        -Name $sessionHostName `
        -AssignedUser $Config.AssignedUserUpn `
        -SubscriptionId $Config.SubscriptionId | Out-Null

    Write-Host "Assigned session host to $($Config.AssignedUserUpn)" -ForegroundColor Green
}
else {
    Write-Host "AssignedUserUpn not set - skipping direct user assignment."
}


# Final output of deployment process details

Write-Step "Complete"

[pscustomobject]@{
    SubscriptionId      = $Config.SubscriptionId
    ResourceGroupName   = $Config.ResourceGroupName
    HostPoolName        = $Config.HostPoolName
    VMName              = $VmName
    CustomLocationName  = $Config.CustomLocationName
    LogicalNetworkName  = $Config.LogicalNetworkName
    ImageName           = $Config.ImageName
    ArcStatus           = $arcMachine.Status
    SessionHostName     = $sessionHostName
    OwnerTag            = $Config.OwnerTagValue
    AssignedUserUpn     = $Config.AssignedUserUpn
}
