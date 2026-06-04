<#
Script  :  Windows-SMTP-Test.ps1
Version :  1.0
Date    :  6/4/2026
Author: Jody Ingram
Pre-reqs: Run with appropriate permissions on local machine to send emails.
Notes: This script tests SMTP email functionality by sending a test email.
#>

# Change values
$SmtpServer = 'smtp.company.org'
$From = 'RDPAlert@company.org'
$To = 'jodyingram@company.org'

Send-MailMessage `
  -SmtpServer $SmtpServer `
  -From $From `
  -To $To `
  -Subject "SMTP test from $env:COMPUTERNAME" `
  -Body "This is a test email from $env:COMPUTERNAME"
