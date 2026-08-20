<#
Script  :  Azure-Tag-Sync.ps1
Version :  1.0
Date    :  8/14/2026
Author  :  Jody Ingram
Purpose :  Synchronizes tags from a Resource Group to its VMs.
#>

Connect-AzAccount

Set-AzContext -Subscription "SUBSCRIPTION_NAME" # Set to correct subscription context. Can be changed without re-running Connect-AzAccount.

$resourceGroupName = "RG-RESOURCEGROUP-REGION" # Set to correct Resource Group name.

$rg = Get-AzResourceGroup -Name $resourceGroupName
$rgTags = $rg.Tags

$vms = Get-AzVM -ResourceGroupName $resourceGroupName

foreach ($vm in $vms) {

    $tagsToUpdate = @{}

    foreach ($tag in $rgTags.GetEnumerator()) {

        # Ignore the Resource Group's Role tag. Change value if you wish to exclude another tag.
        if ($tag.Key -eq "Role") {
            continue
        }
# Add tag if VM is missing it and/or update values
        if (
            (-not $vm.Tags.ContainsKey($tag.Key)) -or
            ($vm.Tags[$tag.Key] -ne $tag.Value)
        ) {
            $tagsToUpdate[$tag.Key] = $tag.Value
        }
    }

    if ($tagsToUpdate.Count -gt 0) {

        Write-Host "$($vm.Name): Updating tags..." -ForegroundColor Yellow

        $tagsToUpdate.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key) = $($_.Value)"
        }

        Update-AzTag `
            -ResourceId $vm.Id `
            -Tag $tagsToUpdate `
            -Operation Merge
    }
    else {
        Write-Host "$($vm.Name): Tags already match RG." -ForegroundColor Green
    }
}
