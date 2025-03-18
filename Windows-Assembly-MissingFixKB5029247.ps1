<#
Script  :  Windows-Assembly-MissingFixKB5029247.ps1
Version :  1.0
Date    :  9/11/2024
Author: Microsoft
Pre-reqs: N/A
Notes: This script pulls down library files and uses them to restore privledges to the Windows assembly store. This is used to fix an issue where Windows Updates fail and Roles cannot be installed to Server OSs. -Jody Ingram
#>

function enable-privilege {
 param(
  ## The privilege to adjust. This set is taken from
  ## http://msdn.microsoft.com/en-us/library/bb530716(VS.85).aspx
  [ValidateSet(
   "SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege",
   "SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege",
   "SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege",
   "SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege",
   "SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege",
   "SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege",
   "SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege",
   "SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege",
   "SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege",
   "SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege",
   "SeUndockPrivilege", "SeUnsolicitedInputPrivilege")]
  $Privilege,
  ## The process on which to adjust the privilege. Defaults to the current process.
  $ProcessId = $pid,
  ## Switch to disable the privilege, rather than enable it.
  [Switch] $Disable
 )

 ## Taken from P/Invoke.NET with minor adjustments.
 $definition = @'
 using System;
 using System.Runtime.InteropServices;
  
 public class AdjPriv
 {
  [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
  internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
   ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
  
  [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
  internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
  [DllImport("advapi32.dll", SetLastError = true)]
  internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  internal struct TokPriv1Luid
  {
   public int Count;
   public long Luid;
   public int Attr;
  }
  
  internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
  internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
  internal const int TOKEN_QUERY = 0x00000008;
  internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
  public static bool EnablePrivilege(long processHandle, string privilege, bool disable)
  {
   bool retVal;
   TokPriv1Luid tp;
   IntPtr hproc = new IntPtr(processHandle);
   IntPtr htok = IntPtr.Zero;
   retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
   tp.Count = 1;
   tp.Luid = 0;
   if(disable)
   {
    tp.Attr = SE_PRIVILEGE_DISABLED;
   }
   else
   {
    tp.Attr = SE_PRIVILEGE_ENABLED;
   }
   retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
   retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
   return retVal;
  }
 }
'@

 $processHandle = (Get-Process -id $ProcessId).Handle
 $type = Add-Type $definition -PassThru
 $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable)
}

function Search-Registry {
<#
.SYNOPSIS
Searches registry key names, value names, and value data (limited).

.DESCRIPTION
This function can search registry key names, value names, and value data (in a limited fashion). It outputs custom objects that contain the key and the first match type (KeyName, ValueName, or ValueData).

.EXAMPLE
Search-Registry -Path HKLM:\SYSTEM\CurrentControlSet\Services\* -SearchRegex "svchost" -ValueData

.EXAMPLE
Search-Registry -Path HKLM:\SOFTWARE\Microsoft -Recurse -ValueNameRegex "ValueName1|ValueName2" -ValueDataRegex "ValueData" -KeyNameRegex "KeyNameToFind1|KeyNameToFind2"

#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)]
        [Alias("PsPath")]
        # Registry path to search
        [string[]] $Path,
        # Specifies whether or not all subkeys should also be searched
        [switch] $Recurse,
        [Parameter(ParameterSetName="SingleSearchString", Mandatory)]
        # A regular expression that will be checked against key names, value names, and value data (depending on the specified switches)
        [string] $SearchRegex,
        [Parameter(ParameterSetName="SingleSearchString")]
        # When the -SearchRegex parameter is used, this switch means that key names will be tested (if none of the three switches are used, keys will be tested)
        [switch] $KeyName,
        [Parameter(ParameterSetName="SingleSearchString")]
        # When the -SearchRegex parameter is used, this switch means that the value names will be tested (if none of the three switches are used, value names will be tested)
        [switch] $ValueName,
        [Parameter(ParameterSetName="SingleSearchString")]
        # When the -SearchRegex parameter is used, this switch means that the value data will be tested (if none of the three switches are used, value data will be tested)
        [switch] $ValueData,
        [Parameter(ParameterSetName="MultipleSearchStrings")]
        # Specifies a regex that will be checked against key names only
        [string] $KeyNameRegex,
        [Parameter(ParameterSetName="MultipleSearchStrings")]
        # Specifies a regex that will be checked against value names only
        [string] $ValueNameRegex,
        [Parameter(ParameterSetName="MultipleSearchStrings")]
        # Specifies a regex that will be checked against value data only
        [string] $ValueDataRegex
    )

    begin {
        switch ($PSCmdlet.ParameterSetName) {
            SingleSearchString {
                $NoSwitchesSpecified = -not ($PSBoundParameters.ContainsKey("KeyName") -or $PSBoundParameters.ContainsKey("ValueName") -or $PSBoundParameters.ContainsKey("ValueData"))
                if ($KeyName -or $NoSwitchesSpecified) { $KeyNameRegex = $SearchRegex }
                if ($ValueName -or $NoSwitchesSpecified) { $ValueNameRegex = $SearchRegex }
                if ($ValueData -or $NoSwitchesSpecified) { $ValueDataRegex = $SearchRegex }
            }
            MultipleSearchStrings {
                # No extra work needed
            }
        }
    }

    process {
        foreach ($CurrentPath in $Path) {
            Get-ChildItem $CurrentPath -Recurse:$Recurse | 
                ForEach-Object {
                    $Key = $_

                    if ($KeyNameRegex) { 
                        Write-Verbose ("{0}: Checking KeyNamesRegex" -f $Key.Name) 
        
                        if ($Key.PSChildName -match $KeyNameRegex) { 
                            Write-Verbose "  -> Match found!"
                            return [PSCustomObject] @{
                                Key = $Key
                                Reason = "KeyName"
                            }
                        } 
                    }
        
                    if ($ValueNameRegex) { 
                        Write-Verbose ("{0}: Checking ValueNamesRegex" -f $Key.Name)
            
                        if ($Key.GetValueNames() -match $ValueNameRegex) { 
                            Write-Verbose "  -> Match found!"
                            return [PSCustomObject] @{
                                Key = $Key
                                Reason = "ValueName"
                            }
                        } 
                    }
        
                    if ($ValueDataRegex) { 
                        Write-Verbose ("{0}: Checking ValueDataRegex" -f $Key.Name)
            
                        if (($Key.GetValueNames() | % { $Key.GetValue($_) }) -match $ValueDataRegex) { 
                            Write-Verbose "  -> Match!"
                            return [PSCustomObject] @{
                                Key = $Key
                                Reason = "ValueData"
                            }
                        }
                    }
                }
        }
    }
}


$KB = "KB4593226"


$logfile = [System.IO.Path]::Combine($rootDir, "Modify-" + [datetime]::Now.ToString("yyyyMMdd-HHmm-ss") + ".log")

Start-Transcript -Path "$PWD\$logfile"


 #$a = gc C:\Temp\ResolvedKBs.txt | select -Unique

$a  = Search-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages" -Recurse -KeyNameRegex $KB

foreach ($b in $a) {

    $KeyName = $null
    $GetCurrentError = $null
    $keyName = $b.Key.Name

    if ($KeyName -like "*$kb*"){

    Write-Host -f Green " FOUND $KeyName"

    $bb = $KeyName.Trim('HKEY_LOCAL_MACHINE').trim("\")

    $bb

    #$bb = "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\$keyName"

    $uname = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    enable-privilege SeTakeOwnershipPrivilege 

    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$BB",[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::takeownership)
    # You must get a blank acl for the key b/c you do not currently have access
    $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
    $me = [System.Security.Principal.NTAccount]"$uname"
    $acl.SetOwner($me)
    $key.SetAccessControl($acl)

    # After you have set owner you need to get the acl with the perms so you can modify it.
    $acl = $key.GetAccessControl()
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule ("$uname","FullControl","Allow")
    $acl.SetAccessRule($rule)
    $key.SetAccessControl($acl)

    $key.Close()  
       
    Set-ItemProperty -Path "HKLM:\$bb" -Name Currentstate -Value 0 -Type DWord
    
    }
     

}
Stop-Transcript
pause
