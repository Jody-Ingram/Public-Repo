<#
Script  :  MS365-Graph-Send-Mail.ps1
Version :  1.0
Date    :  3/16/2026
Author: Jody Ingram
Pre-reqs: Microsoft-Graph PowerShell Modules
Notes: This script connects to Microsoft Graph and then sends a test e-mail.
Instructions: Please adjust settings to fit the environment. Use task-specific App Registrations.
#>

# Install Microsoft Graph PowerShell modules if not already installed
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser -Force


# Set parameters
$TenantId = "TenantID_GOES_HERE"
$ClientId = "APP_REG_CLIENT_ID_GOES_HERE" # App reg for Azure Local. The app reg must have "Mail.Send" permissions granted in Azure AD. 
$From     = "JodyIngram@company.com" # Change 
$To       = "EmailGroup@company.com" # Change



# Connects to Microsoft Graph
Connect-MgGraph `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -Scopes "Mail.Send" `
    -NoWelcome # Suppresses the welcome message on successful connection



# Builds a test e-mail
$params = @{
    Message = @{
        Subject = "This is a test e-mail from Azure Automation!"
        Body = @{
            ContentType = "Text"
            Content = "This is a test e-mail sent from an Azure Automation runbook using Microsoft Graph PowerShell module."
        }
        ToRecipients = @(
            @{
                EmailAddress = @{
                    Address = $To
                }
            }
        )
    }
    SaveToSentItems = $true
}



# Sends the e-mail
Send-MgUserMail -UserId $From -BodyParameter $params



Write-Host "Test e-mail sent from $From to $To"



# Disconnects from Microsoft Graph
Disconnect-MgGraph
