<#
Script  :  MS365-Get-VivaInsightsLicensedUsers.ps1
Version :  2.0
Date    :  9/24/25
Pre-reqs: N/A
Notes: This script runs a report via Microsoft.Graph, checks AD attributes in Entra ID and returns with information from a scope of users.
#>

# Imports the module needed to run this script
Import-Module Microsoft.Graph

# Set the execution policy to allow the script to run
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Connect to Microsoft Graph with minimum rights required to read users
Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.Read.All" -NoWelcome

# Load all users with the WORKPLACE_ANALYTICS_INSIGHTS_USER service plan
Write-Host "Loading All Users with the WORKPLACE_ANALYTICS_INSIGHTS_USER service plan. This might take some time..." -ForegroundColor Yellow
$users = Get-MgUser -Filter "assignedPlans/any(c:c/servicePlanId eq b622badb-1b45-48d5-920f-4b27a2c0996c and c/capabilityStatus eq 'Enabled')" `
    -All -ConsistencyLevel eventual -CountVariable count `
    -Property "Id","Mail","Department","JobTitle","CompanyName","EmployeeType","OfficeLocation","City","State","DisplayName"

# Prepare an array to hold user details
$userDetails = @()

# For each user, get the required details including their manager's UPN
Write-Host "Building user data for $($users.Count) users." -ForegroundColor Yellow
foreach ($user in $users) {
    $managerUpn = $null
    $managerId = Get-MgUserManager -UserId $user.Id -ErrorAction SilentlyContinue

    if ($managerId) {
        $manager = Get-MgUser -UserId $managerId.Id -Property UserPrincipalName
        $managerUpn = $manager.UserPrincipalName
    }
    else {
        Write-Host "No manager found for user: $($user.Mail)" -ForegroundColor DarkYellow
    }

    # Added additional attributes to the array -Jody
    $userDetails += [PSCustomObject]@{
        PersonId     = $user.Mail
        ManagerId    = $managerUpn
        Department   = $user.Department
        JobTitle     = $user.JobTitle
        CompanyName  = $user.CompanyName
        EmployeeType = $user.EmployeeType
        OfficeLocation = $user.OfficeLocation
        City         = $user.City
        State        = $user.State
        DisplayName  = $user.DisplayName
    }
}

# Export the user details to a CSV file
try {
    $userDetails | Export-Csv -Path "EntraUsersExport.csv" -NoTypeInformation
    Write-Host "Finished processing. See results here: .\EntraUsersExport.csv" -ForegroundColor Yellow
}
catch {
    Write-Host "Encountered an error while exporting results: $($_)"
}

# Disconnect from Microsoft Graph
Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Yellow
Disconnect-MgGraph
