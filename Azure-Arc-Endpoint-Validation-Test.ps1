<#
Script  :  Azure-Arc-Endpoint-Validation-Test.ps1
Version :  1.0
Date    :  7/22/2026
Author: Jody Ingram
Pre-reqs: Run this script in an elevated PowerShell session (Run as Administrator).
Notes: This script tests the ability of the host to reach the endpoints required for Azure Arc to function properly. It does not validate that the host is registered with Azure Arc, only that it can reach the endpoints.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidatePattern('^[a-z0-9]+$')]
    [string]$Region = 'eastus2',

    [Parameter()]
    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 30,

    [Parameter()]
    [string]$CsvPath = (Join-Path $env:TEMP 'AzureArcEndpointValidationResults.csv') # Default path for CSV output
)

# Forces the use of TLS 1.2 for all web requests in this script
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptName = 'Azure Arc Endpoint Validation Test'
$Version = '1.0'

function Write-TestResult {
    param (
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter()][string]$Detail = ''
    )

    $Color = switch ($Status) {
        'PASS'    { 'Green' }
        'FAIL'    { 'Red' }
        'WARNING' { 'Yellow' }
        default   { 'Gray' }
    }

    $Message = '{0,-22} {1}' -f ($Label + ':'), $Status
    if ($Detail) { $Message += " - $Detail" }
    Write-Host $Message -ForegroundColor $Color
}

function Test-TlsEndpoint {
    param (
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $TcpClient = $null
    $SslStream = $null
    $Certificate = $null
    $PolicyErrors = [System.Net.Security.SslPolicyErrors]::None
# Tests TCP Connection and TLS negotiation to the specified endpoint and returns a custom object with the results.
    try {
        $TcpClient = New-Object System.Net.Sockets.TcpClient
        $Connect = $TcpClient.BeginConnect($ComputerName, 443, $null, $null)

        if (-not $Connect.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "TCP connection timed out after $TimeoutSeconds seconds."
        }

        $TcpClient.EndConnect($Connect)

        $ValidationCallback = {
            param($TlsSender, $RemoteCertificate, $Chain, $SslPolicyErrors)
            $script:TlsCertificate = $RemoteCertificate
            $script:TlsPolicyErrors = $SslPolicyErrors
            return ($SslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None)
        }

        $script:TlsCertificate = $null
        $script:TlsPolicyErrors = [System.Net.Security.SslPolicyErrors]::None

        $SslStream = [System.Net.Security.SslStream]::new(
            $TcpClient.GetStream(),
            $false,
            $ValidationCallback
        )
        $SslStream.ReadTimeout = $TimeoutSeconds * 1000
        $SslStream.WriteTimeout = $TimeoutSeconds * 1000
        $SslStream.AuthenticateAsClient($ComputerName)

        if ($script:TlsCertificate) {
            $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($script:TlsCertificate)
        }
        $PolicyErrors = $script:TlsPolicyErrors

        [PSCustomObject]@{
            Succeeded    = $true
            Protocol     = [string]$SslStream.SslProtocol
            Subject      = if ($Certificate) { $Certificate.Subject } else { '' }
            Issuer       = if ($Certificate) { $Certificate.Issuer } else { '' }
            Thumbprint   = if ($Certificate) { $Certificate.Thumbprint } else { '' }
            PolicyErrors = [string]$PolicyErrors
            Error        = ''
        }
    }
    catch {
        if ($script:TlsCertificate) {
            $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($script:TlsCertificate)
        }

        [PSCustomObject]@{
            Succeeded    = $false
            Protocol     = ''
            Subject      = if ($Certificate) { $Certificate.Subject } else { '' }
            Issuer       = if ($Certificate) { $Certificate.Issuer } else { '' }
            Thumbprint   = if ($Certificate) { $Certificate.Thumbprint } else { '' }
            PolicyErrors = [string]$script:TlsPolicyErrors
            Error        = $_.Exception.Message
        }
    }
    finally {
        if ($SslStream) { $SslStream.Dispose() }
        if ($TcpClient) { $TcpClient.Dispose() }
        Remove-Variable TlsCertificate -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable TlsPolicyErrors -Scope Script -ErrorAction SilentlyContinue
    }
}

function Get-HttpStatusFromException {
    param ([Parameter(Mandatory = $true)]$Exception)

    if ($Exception.Response -and $null -ne $Exception.Response.StatusCode) {
        return [int]$Exception.Response.StatusCode
    }

    return $null
}

# Defines the list of Microsoft public endpoints to test
$Targets = @(
    [PSCustomObject]@{ Uri = 'https://download.microsoft.com'; Purpose = 'Windows agent install and automatic updates' }
    [PSCustomObject]@{ Uri = 'https://login.microsoftonline.com'; Purpose = 'Microsoft Entra authentication' }
    [PSCustomObject]@{ Uri = 'https://pas.windows.net'; Purpose = 'Microsoft Entra authentication' }
    [PSCustomObject]@{ Uri = 'https://management.azure.com'; Purpose = 'Azure Resource Manager onboarding' }
    [PSCustomObject]@{ Uri = "https://gbl.his.arc.azure.com/discovery?location=$Region&api-version=2.1"; Purpose = 'Azure Arc regional service discovery' }
    [PSCustomObject]@{ Uri = "https://$Region.his.arc.azure.com"; Purpose = 'Hybrid identity and metadata service' }
    [PSCustomObject]@{ Uri = "https://$Region.guestconfiguration.azure.com"; Purpose = 'Extensions and Machine Configuration' }
    [PSCustomObject]@{ Uri = "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$Region"; Purpose = 'Extension and connectivity notifications' }
)

Write-Host ''
Write-Host "$ScriptName - Version $Version" -ForegroundColor Cyan
Write-Host ('=' * 78) -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Region:   $Region"
Write-Host "Time:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
$IsAdministrator = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) # Checks if the current PowerShell session is running with elevated privileges (as Administrator)
Write-TestResult -Label 'Elevated session' -Status $(if ($IsAdministrator) { 'PASS' } else { 'WARNING' }) -Detail $(if ($IsAdministrator) { 'Administrator' } else { 'Run PowerShell as Administrator' })

Write-Host "`nSystem proxy information" -ForegroundColor Cyan
$WinHttpProxy = (& netsh winhttp show proxy 2>&1) -join ' '
Write-Host "WinHTTP: $WinHttpProxy"
Write-Host "PowerShell default proxy: $([System.Net.WebRequest]::DefaultWebProxy.GetProxy([Uri]'https://management.azure.com'))"

Write-Host "`nAzure Arc agent information" -ForegroundColor Cyan
$ArcService = Get-Service -Name HIMDS -ErrorAction SilentlyContinue
$AzcmAgentPath = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'

if ($ArcService) {
    Write-TestResult -Label 'Agent installed' -Status 'PASS' -Detail "HIMDS service is $($ArcService.Status)"
    if (Test-Path -LiteralPath $AzcmAgentPath) {
        $AgentVersion = (Get-Item -LiteralPath $AzcmAgentPath).VersionInfo.ProductVersion
        Write-TestResult -Label 'Agent executable' -Status 'PASS' -Detail "Version $AgentVersion"
    }
    else {
        Write-TestResult -Label 'Agent executable' -Status 'WARNING' -Detail 'azcmagent.exe was not found in the default path'
    }
}
else {
    Write-TestResult -Label 'Agent installed' -Status 'WARNING' -Detail 'HIMDS service was not found'
}
# Checks each endpoint's DNS resolution, TCP connectivity, TLS negotiation, and HTTPS request, and collects the results into a custom object for each endpoint.
$Results = foreach ($Target in $Targets) {
    $Uri = [Uri]$Target.Uri
    $DnsStatus = 'FAIL'
    $TcpStatus = 'SKIPPED'
    $TlsStatus = 'SKIPPED'
    $HttpStatus = 'N/A'
    $ResolvedIPs = ''
    $TlsProtocol = ''
    $CertificateSubject = ''
    $CertificateIssuer = ''
    $CertificateThumbprint = ''
    $CertificatePolicyErrors = ''
    $ErrorDetail = ''

    Write-Host "`n$('-' * 78)" -ForegroundColor DarkGray
    Write-Host "Endpoint: $($Uri.Host)" -ForegroundColor Cyan
    Write-Host "Purpose:  $($Target.Purpose)"
    try {
        $DnsRecords = Resolve-DnsName -Name $Uri.Host -Type A -ErrorAction Stop
        $ResolvedIPs = ($DnsRecords | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress -Unique) -join '; '
        if (-not $ResolvedIPs) { throw 'No IPv4 address was returned.' }
        $DnsStatus = 'PASS'
        Write-TestResult -Label 'DNS resolution' -Status 'PASS' -Detail $ResolvedIPs
    }
    catch {
        $ErrorDetail = $_.Exception.Message
        Write-TestResult -Label 'DNS resolution' -Status 'FAIL' -Detail $ErrorDetail
    }

    if ($DnsStatus -eq 'PASS') {
        $TcpTest = Test-NetConnection -ComputerName $Uri.Host -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
        if ($TcpTest.TcpTestSucceeded) {
            $TcpStatus = 'PASS'
            Write-TestResult -Label 'TCP 443' -Status 'PASS' -Detail "Remote address $($TcpTest.RemoteAddress)"
        }
        else {
            $TcpStatus = 'FAIL'
            $ErrorDetail = 'TCP 443 connection failed.'
            Write-TestResult -Label 'TCP 443' -Status 'FAIL' -Detail $ErrorDetail
        }
    }

    if ($TcpStatus -eq 'PASS') {
        $Tls = Test-TlsEndpoint -ComputerName $Uri.Host -TimeoutSeconds $TimeoutSeconds
        $TlsProtocol = $Tls.Protocol
        $CertificateSubject = $Tls.Subject
        $CertificateIssuer = $Tls.Issuer
        $CertificateThumbprint = $Tls.Thumbprint
        $CertificatePolicyErrors = $Tls.PolicyErrors

        if ($Tls.Succeeded) {
            $TlsStatus = 'PASS'
            Write-TestResult -Label 'TLS negotiation' -Status 'PASS' -Detail "$TlsProtocol; certificate trusted"
        }
        else {
            $TlsStatus = 'FAIL'
            $ErrorDetail = $Tls.Error
            Write-TestResult -Label 'TLS negotiation' -Status 'FAIL' -Detail $ErrorDetail
            if ($CertificateSubject) { Write-Host "Certificate subject: $CertificateSubject" -ForegroundColor Yellow }
            if ($CertificateIssuer) { Write-Host "Certificate issuer:  $CertificateIssuer" -ForegroundColor Yellow }
            if ($CertificatePolicyErrors) { Write-Host "Certificate errors:  $CertificatePolicyErrors" -ForegroundColor Yellow }
        }
    }

    if ($TlsStatus -eq 'PASS') {
        try {
            $WebParameters = @{
                Uri                = $Target.Uri
                Method             = 'Get'
                TimeoutSec         = $TimeoutSeconds
                MaximumRedirection = 5
                ErrorAction        = 'Stop'
                UseBasicParsing    = $true
            }
            $Response = Invoke-WebRequest @WebParameters
            $HttpStatus = [int]$Response.StatusCode
            Write-TestResult -Label 'HTTPS request' -Status 'PASS' -Detail "HTTP $HttpStatus"
        }
        catch {
            $ReturnedStatus = Get-HttpStatusFromException -Exception $_.Exception
            if ($null -ne $ReturnedStatus) {
                $HttpStatus = $ReturnedStatus
                Write-TestResult -Label 'HTTPS request' -Status 'PASS' -Detail "HTTP $HttpStatus returned (endpoint reached)"
            }
            else {
                $HttpStatus = 'FAILED'
                $ErrorDetail = $_.Exception.Message
                Write-TestResult -Label 'HTTPS request' -Status 'FAIL' -Detail $ErrorDetail
            }
        }
    }
# Creates the custom object for the endpoint with all the test results and details, and adds it to the $Results array.
    $OverallResult = if (($DnsStatus -eq 'PASS') -and ($TcpStatus -eq 'PASS') -and ($TlsStatus -eq 'PASS') -and ($HttpStatus -ne 'FAILED')) { 'PASS' } else { 'FAIL' }

    [PSCustomObject]@{
        ComputerName             = $env:COMPUTERNAME
        TestTime                 = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
        Region                   = $Region
        Endpoint                 = $Uri.Host
        RequestUri               = $Target.Uri
        Purpose                  = $Target.Purpose
        ResolvedIPAddresses      = $ResolvedIPs
        DNS                      = $DnsStatus
        TCP443                   = $TcpStatus
        TLS                      = $TlsStatus
        TLSProtocol              = $TlsProtocol
        HTTPStatus               = $HttpStatus
        CertificateSubject       = $CertificateSubject
        CertificateIssuer        = $CertificateIssuer
        CertificateThumbprint    = $CertificateThumbprint
        CertificatePolicyErrors  = $CertificatePolicyErrors
        Result                   = $OverallResult
        ErrorDetail              = $ErrorDetail
    }
}

Write-Host "`n$('=' * 78)" -ForegroundColor Cyan
Write-Host 'SUMMARY RESULTS' -ForegroundColor Cyan
Write-Host ('=' * 78) -ForegroundColor Cyan
$Results | Select-Object Endpoint, DNS, TCP443, TLS, HTTPStatus, Result | Format-Table -AutoSize

try {
    $CsvDirectory = Split-Path -Parent $CsvPath
    if ($CsvDirectory -and -not (Test-Path -LiteralPath $CsvDirectory)) {
        New-Item -Path $CsvDirectory -ItemType Directory -Force | Out-Null
    }
    $Results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $CsvPath" -ForegroundColor Cyan
}
catch {
    Write-Host "Unable to export CSV: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Reports overall result and exit with appropriate code
$FailedTests = @($Results | Where-Object Result -eq 'FAIL')
Write-Host "`n$('=' * 78)" -ForegroundColor Cyan
if ($FailedTests.Count -gt 0) {
    Write-Host "OVERALL RESULT: FAIL ($($FailedTests.Count) of $($Results.Count) endpoints failed)" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "OVERALL RESULT: PASS ($($Results.Count) of $($Results.Count) endpoints passed)" -ForegroundColor Green
    exit 0
}
