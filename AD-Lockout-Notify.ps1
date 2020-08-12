# AD Lockout Notify
# Written by Jody Ingram
# This script sends an e-mail when any Active Directory Account gets locked out.
# This script also automatically unlocks a specified username

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
$AccountLockOutEvent = Get-EventLog -LogName "Security" -InstanceID 4740 -Newest 1
$LockedAccount = $($AccountLockOutEvent.ReplacementStrings[0])
$AccountLockOutEventTime = $AccountLockOutEvent.TimeGenerated
$AccountLockOutEventMessage = $AccountLockOutEvent.Message
$messageParameters = @{ 
Subject = "Account Locked Out: $LockedAccount" 
Body = "Account $LockedAccount was locked out on $AccountLockOutEventTime.`n`nEvent Details:`n`n$AccountLockOutEventMessage"
From = "LockOut@Email.com" 
To = "USER@Email.com" 
SmtpServer = "SMTP-SERVER-ADDRESS" 
} 
Send-MailMessage @messageParameters

# This can be used to automatically unlock a user in a worst case scenario

Unlock-ADAccount -identity USERNAME

# To run this script, you will need to create a scheduled task:

# Triggers: On an event - On event - Log: Security, Source: Microsoft Windows Security Auditing, EventID: 4740

# Action: PowerShell.exe -nologo -File "C:\TEMP\AccountLockoutNotification.ps1"

# Click the "Run with highest privileges" box.