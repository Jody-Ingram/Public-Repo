<#
Script  :  Web-GetCertInfo.ps1
Version :  1.0
Date    :  9/4/25
Author: Jody Ingram
Pre-reqs: N/A
Notes: This script opens a TCP + TLS stream against a URL to provide details on the web certificate currently bound to the URL.
#>

# Set the URL you wish to check the web certificate info of
$url = "https://www.microsoft.com"

# This uses .NET to parse the URL, turning it into a structured URI object
$hostname = ([System.Uri]$url).Host

# Creates a TCP connection to the host on port 443
$tcpClient = New-Object Net.Sockets.TcpClient($hostname, 443)

# Wraps the raw TCP stream in an SSL/TLS stream so it can negotiate encryption
$sslStream = New-Object Net.Security.SslStream($tcpClient.GetStream(), $false, ({ $true }))

# Starts the TLS handshake with the hostname
$sslStream.AuthenticateAsClient($hostname)

# Retrieves the certificate presented by the remote server
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate

# Output certificate details
Write-Host "Thumbprint : $($cert.Thumbprint)"
Write-Host "Valid From : $($cert.NotBefore)"
Write-Host "Valid To   : $($cert.NotAfter)"
Write-Host "Subject    : $($cert.Subject)"
Write-Host "Issuer     : $($cert.Issuer)"

<#
Optional components. Uncomment if needed.
------------------------------------------

This warns if the certificate is expired or expiring within 30 days
if ($cert.NotAfter -lt (Get-Date)) {
    Write-Warning "⚠️ Certificate has expired!"
}
elseif ($cert.NotAfter -lt (Get-Date).AddDays(30)) {
    Write-Warning "⚠️ Certificate expires within 30 days!"
}

Closes the SSL and TCP client stream when complete#$sslStream.Dispose()
$tcpClient.Close()

#>
