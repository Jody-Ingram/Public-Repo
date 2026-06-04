<#
Script  :  Windows-Task-Create-RDP-Disconnect-Alert.ps1
Version :  1.0
Date    :  6/4/2026
Author: Jody Ingram
Pre-reqs: Run with appropriate permissions on local machine to create scheduled tasks.
Notes: This script creates a scheduled task to run the RDP disconnect alert script when specific RDP disconnect events occur.
#>

$TaskName = 'Alert - Bad RDP Disconnect'
$ScriptPath = 'C:\Tools\RDPDisconnectMonitor\Windows-Alert-Send-RDP-Disconnect.ps1' # Change if your script is in a different location

$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Send email when bad RDP transport disconnect events occur.</Description>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>
        &lt;QueryList&gt;
          &lt;Query Id="0" Path="Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational"&gt;
            &lt;Select Path="Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational"&gt;
              *[System[(EventID=142 or EventID=143 or EventID=226)]]
            &lt;/Select&gt;
          &lt;/Query&gt;
        &lt;/QueryList&gt;
      </Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>SYSTEM</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$ScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$XmlPath = 'C:\Tools\RDPDisconnectMonitor\BadRdpDisconnectTask.xml'
$TaskXml | Set-Content -Path $XmlPath -Encoding Unicode

schtasks.exe /Create /TN $TaskName /XML $XmlPath /F
