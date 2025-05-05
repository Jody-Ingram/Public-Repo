<#
Script  :  Windows-Find-Fastest-DNS.ps1
Version :  1.0
Date    :  5/2/2025
Author: Jody Ingram
Notes: Checks local ISP DNS against several open free DNS servers to determine the fastest connection. This includes a GUI.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Creates the Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Fastest DNS Finder"
$form.Size = New-Object System.Drawing.Size(600, 400)
$form.StartPosition = "CenterScreen"

# Creates the Form Button
$button = New-Object System.Windows.Forms.Button
$button.Text = "Test DNS Latency"
$button.Size = New-Object System.Drawing.Size(150, 30)
$button.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($button)

# Creates a specific DataGridView for the output
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(20, 60)
$grid.Size = New-Object System.Drawing.Size(540, 280)
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.SelectionMode = 'FullRowSelect'
$form.Controls.Add($grid)

# Defines a list of the most widely known, free public DNS servers
$dnsList = @(
    @{ Name = "Google DNS (8.8.8.8)"; IP = "8.8.8.8" },
    @{ Name = "Cloudflare (1.1.1.1)"; IP = "1.1.1.1" },
    @{ Name = "OpenDNS (208.67.222.222)"; IP = "208.67.222.222" },
    @{ Name = "Quad9 (9.9.9.9)"; IP = "9.9.9.9" },
    @{ Name = "Level3 (4.2.2.1)"; IP = "4.2.2.1" },
    @{ Name = "ControlD (76.76.2.0"; IP = "76.76.2.0" },  
    @{ Name = "AdGuard (94.140.14.14"; IP = "94.140.14.14" },
    @{ Name = "CleanBrowsing (185.228.168.9"; IP = "185.228.168.9" },
    @{ Name = "AdGuard (94.140.14.14"; IP = "94.140.14.14" }
)

# Adds currently discovered ISP DNS to the list
$currentDNS = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {$_.ServerAddresses -ne $null}
$currentDNS.ServerAddresses | Select-Object -Unique | ForEach-Object {
    $dnsList += @{ Name = "Current DNS ($_)" ; IP = "$_" }
}

# Creates the latency tester function
function Test-DNSLatency {
    param (
        [string]$IPAddress
    )
    try {
        $result = Test-Connection -ComputerName $IPAddress -Count 3 -ErrorAction Stop | Measure-Object -Property ResponseTime -Average
        return [math]::Round($result.Average, 2)
    } catch {
        return $null
    }
}

# Initiates the OnClick event from the button
$button.Add_Click({
    $grid.Columns.Clear()
    $grid.Rows.Clear()

    $grid.Columns.Add("Name", "Name") | Out-Null
    $grid.Columns.Add("IP", "IP") | Out-Null
    $grid.Columns.Add("Latency", "Latency (ms)") | Out-Null

    foreach ($dns in $dnsList) {
        $latency = Test-DNSLatency -IPAddress $dns.IP
        $displayLatency = if ($latency -ne $null) { "$latency" } else { "Unreachable" }
        $grid.Rows.Add($dns.Name, $dns.IP, $displayLatency) | Out-Null
    }
})

# Displays the GUI
$form.Topmost = $true
[void]$form.ShowDialog()
