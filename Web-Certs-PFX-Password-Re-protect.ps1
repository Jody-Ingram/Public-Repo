<#
Script  : Web-Certs-PFX-Password-Re-protect.ps1
Version :  1.0
Date    :  9/11/25
Author: Jody Ingram
Pre-reqs: N/A
Notes: This script exports a PFX certificate and re-protects it with a new password.
#>

# Path to your downloaded PFX certificate
$certPath   = "C:\Temp\DownloadedCert.pfx"

# Path to export the protected cert
$outPath   = "C:\Temp\ExportedCert.pfx"

# Set the new password to protect the certificate
$newPass   = "PFXPassword@101!" # Change password

# Load as byte array properly
$certBytes = [System.IO.File]::ReadAllBytes($certPath)

# Import into cert object (marks exportable)
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import($certBytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

# Secure the new password
$securePwd = ConvertTo-SecureString -String $newPass -Force -AsPlainText

# Exports the cert with new password
$bytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $securePwd)
[System.IO.File]::WriteAllBytes($outPath, $bytes)

Write-Host "✅ Exported protected PFX to $outPath"
