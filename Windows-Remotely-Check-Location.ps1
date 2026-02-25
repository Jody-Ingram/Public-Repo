<#
Script  :  Windows-Remotely-Check-Location.ps1
Version :  1.0
Date    :  2/25/2026
Author: Jody Ingram
Pre-reqs: Remote PowerShell access to target servers 
Notes: This script imports a list of servers and checks the specified path on each server to see if it exists.
#>

# Change the path to your servers list as needed
$Servers = Get-Content -Path "C:\Tools\Servers.txt" | Where-Object { $_ -and $_.Trim() -ne "" }


# Modify the path to check as needed
$PathToCheck = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Configuration Manager\Configuration Manager"

# Results array; also uses if statement to check if the server is online before attempting to check the path and handles any errors that may occur during the process.
$Results = foreach ($Server in $Servers) {
    try {
        if (Test-Connection -ComputerName $Server -Count 1 -Quiet) {
            $Exists = Invoke-Command -ComputerName $Server -ScriptBlock {
                param ($Path)
                Test-Path $Path
            } -ArgumentList $PathToCheck

            [PSCustomObject]@{
                Server     = $Server
                PathExists = $Exists
                Status     = "Online"
            }
        }
        else {
            [PSCustomObject]@{
                Server     = $Server
                PathExists = $null
                Status     = "Offline"
            }
        }
    }
    catch {
        [PSCustomObject]@{
            Server     = $Server
            PathExists = $null
            Status     = "Error: $($_.Exception.Message)"
        }
    }
}

# Outputs the results in a table format
$Results | Format-Table -AutoSize
