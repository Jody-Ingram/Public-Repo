<#
Script  :  Azure-New-Sub-Email-Alert.ps1
Version :  1.0
Date    :  2/1/2025
Author  :  Jody Ingram
Notes: This script sends a notification to someone when a new Azure Subscription is created. This could be used for updating the Microsoft Unified Support Agreement, etc. Adjust values as needed.
#>

# The recipient who receives this notification
$recipientEmail = "firstname.lastname@company.com"

# Connects and authenticates with Azure
Connect-AzAccount

# Get subscriptions created within the last 24 hours or when the alert is flagged
$recentSubscriptions = Get-AzSubscription | Where-Object {$_.State -eq "Enabled" -and $_.CreatedAt -gt (Get-Date).AddDays(-1)} # -1 = 24 hours

# Checks for recent subscriptions
if ($recentSubscriptions) {
  # Checks the list of recently created subscriptions for the one with the newest timestamp (Uses CreatedAt value)
  $mostRecentSubscription = $recentSubscriptions | Sort-Object CreatedAt -Descending | Select-Object -First 1
}

  if ($mostRecentSubscription) {
    $subscriptionName = $mostRecentSubscription.Name
    $subscriptionID = $mostRecentSubscription.Id

    Write-Host "Subscription Name: $subscriptionName"
    Write-Host "Subscription ID: $subscriptionID"
  }

# Body of notification email    
$body = @"
<html>
<body style="font-family: Calibri, sans-serif;">
  <div style="background-color: #f2f2f2; padding: 20px;">
    <h2 style="color: #333;">New Azure Subscription Created</h2>
  </div>

  <div style="padding: 20px;">
    <p>Microsoft,</p>

    <p>A new Azure subscription has been created for COMPANY:</p>

    <table style="width: 100%; border-collapse: collapse; margin-top: 20px;">
      <tr>
        <td style="padding: 8px; border: 1px solid #ddd; background-color: #f9f9f9;">Subscription Name:</td>
        <td style="padding: 8px; border: 1px solid #ddd;"$subscriptionName</td>
      </tr>
      <tr>
        <td style="padding: 8px; border: 1px solid #ddd; background-color: #f9f9f9;">Subscription ID:</td>
        <td style="padding: 8px; border: 1px solid #ddd;">$subscriptionID</td>
      </tr>      
      <tr>
        <td style="padding: 8px; border: 1px solid #ddd; background-color: #f9f9f9;">Created By:</td>
        <td style="padding: 8px; border: 1px solid #ddd;">Cloud Team</td> 
      </tr>
      <tr>
        <td style="padding: 8px; border: 1px solid #ddd; background-color: #f9f9f9;">Date Created:</td>
        <td style="padding: 8px; border: 1px solid #ddd;">$(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</td> 
      </tr>
      </table>

    <p>Please let us know if you have any questions.</p>


    <p>Thank you,<br>
       Cloud Team</p>
  </div>
</body>
</html>
"@

# CC Recipients
$ccRecipients = "person1@company.com, person2@company.com"

Send-MailMessage -To $recipientEmail -CC $ccRecipients -Subject "New Azure Subscription Creation" -Body $body -BodyAsHtml -SmtpServer smtp.company.com -From "CloudTeam@company.com"

# Test to single person. Uncomment to use.
#Send-MailMessage -To jody@company.com -Subject "New Company Azure Subscription Creation" -Body $body -BodyAsHtml -SmtpServer smtp.company.com -From "CloudTeam@company.com"
