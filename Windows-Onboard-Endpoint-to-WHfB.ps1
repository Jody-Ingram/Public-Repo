<#
Script  :  Windows-Onboard-Endpoint-to-WHfB.ps1
Version :  1.0
Date    :  3/20/25
Author: Jody Ingram
Pre-reqs: Active Directory PowerShell Module, RunAs Domain Admin level account, PSExec.exe module from SysInternals
Notes: This script onboards the user's endpoint device into Windows Hello for Business.
#>

# Variables
$domain = "company.com" # Change to the appropriate domain for your environment
$adGroup = "GPO-Machines-Workstations-Hello" # AD Group currently used for WHfB
$psexecPath = "C:\Tools\PsExec.exe"  # Update this path to where PsExec.exe is stored
$smtpServer = "smtp.company.com"    # Update with your SMTP server
$fromEmail = "SecurityAlerts@company.com" # Update with the sender email
$instructionsLink = "https://company.sharepoint.com/:w:/t/WindowsHelloforBusiness/index.html" # Please change this accordingly

# Prompt for device name
$deviceName = Read-Host "Please enter the hostname of the device to onboard:"

# Add the device to the AD group
Try {
    Add-ADGroupMember -Identity $adGroup -Members "$deviceName$" -ErrorAction Stop
    Write-Host "Successfully added $deviceName to $adGroup" -ForegroundColor Green
} Catch {
    Write-Host "Failed to add $deviceName to the AD group: $_" -ForegroundColor Red
    exit
}

# Run 'GPUpdate /force' remotely and silently using PSExec
Try {
    Start-Process -FilePath $psexecPath -ArgumentList "\\$deviceName -s cmd /C echo N | gpupdate /force" -NoNewWindow -Wait
    Write-Host "Group Policy updated on $deviceName" -ForegroundColor Green
} Catch {
    Write-Host "Failed to update Group Policy on $deviceName`: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Prompt for the user's email address
$userEmail = Read-Host "Enter the email of the user" # This is the user who will receive an email with instructions on enabling the Windows Hello authentication methods.

# Send notification email
Try {
    $subject = "Windows Hello for Business Enrollment"
    $body = "Hello,`n`nYour device ($deviceName) has been enrolled in Windows Hello for Business. Please follow the instructions at the link below to complete the authentication setup:`n`n$instructionsLink`n`nThank you."
    Send-MailMessage -To $userEmail -From $fromEmail -Subject $subject -Body $body -SmtpServer $smtpServer
    Write-Host "Email sent successfully to $userEmail" -ForegroundColor Green
} Catch {
    Write-Host "Failed to send email: $_" -ForegroundColor Red
    exit
}

# Final confirmation
Write-Host "Device $deviceName has been successfully enrolled in Windows Hello for Business." -ForegroundColor Cyan
