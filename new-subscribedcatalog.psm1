# PS Module to create vCD catalogs from supplied parameters
# Requires that you are already connected to the vCD API
# (Connect-CIServer) prior to running the command.
# 
# If you do not specify a storage profile then the catalog
# will be created on the first storage found in the first
# VDC created for the organisation.
#
# Requires 'Invoke-vCloud' module from PSGet (Install-Module Invoke-vCloud)
#
# Copyright 2018 Jon Waite, All Rights Reserved
# Modified to allow creation of subscribed catalog
# 2020 Brandon Bazan https://ifitisnotbroken.wordpress.com/
# Released under MIT License - see https://opensource.org/licenses/MIT
# Addition of subscription parameters for creating a catalog with an external subscription
# February 2020 added minor creation and error reporting
#
Function CatalogToXML(
    [Parameter(Mandatory=$true)][string]$catName,
    [string]$catDesc,
    [string]$orgName,
    [string]$sprof,
    [string]$subscribed,
    [string]$location,
    [string]$localcopy,
    [string]$subpass
)
{
    
    # Create properly formed xml of type application/vnd.vmware.admin.catalog+xml:
    [xml]$newcatalog = New-Object System.Xml.XmlDocument
    $dec = $newcatalog.CreateXmlDeclaration("1.0","UTF-8",$null)
    $newcatalog.AppendChild($dec) | Out-Null
    $root = $newcatalog.CreateNode("element","AdminCatalog",$null)
    $desc = $newcatalog.CreateNode("element","Description",$null)
    $catsubext = $newcatalog.CreateNode("element","ExternalCatalogSubscriptionParams",$null)
    $issubextelem = $newcatalog.CreateNode("element","SubscribeToExternalFeeds",$null)
    $locationelem = $newcatalog.CreateNode("element","Location",$null)
    $subpasselem = $newcatalog.CreateNode("element","Password",$null)
    $localelem = $newcatalog.CreateNode("element","LocalCopy",$null)
    $root.setAttribute("xmlns","http://www.vmware.com/vcloud/v1.5")
    $root.SetAttribute("name",$catName)
    $issubextelem.InnerText = $subscribed
    $locationelem.InnerText = $location
    $subpasselem.InnerText = $subpass
    $localelem.InnerText = $localcopy
    $desc.innerText = $catDesc
    $root.AppendChild($desc) | Out-Null
    $catsubext.AppendChild($issubextelem) | Out-Null
    $catsubext.AppendChild($locationelem) | Out-Null
    $catsubext.AppendChild($subpasselem) | Out-Null
    $catsubext.AppendChild($localelem) | Out-Null
    $root.AppendChild($catsubext) | Out-Null
    # Attempt to match Storage Profile specified (if any) and use that for catalog creation XML:
    if ($sprof) {
        $sprofhref = ""
        $vdcs = Get-OrgVdc -Org $orgName
        foreach($vdc in $vdcs){
            $sprofs = $vdc.ExtensionData.VdcStorageProfiles.VdcStorageProfile
            foreach($vdcsprof in $sprofs){
                if ($vdcsprof.Name -eq $sprof) {
                    $sprofhref = $vdcsprof.href
                }
            } # each VDC Storage Profile in this VDC
        } # each VDC in this Org
        if ($sprofhref) {
            # Found/matched this storage profile, add specification to the catalog creation XML:
            Write-Host ("Matched Storage Profile '$sprof' in this Org, catalog will be created in this Storage Profile.")
            $catsp = $newcatalog.CreateNode("element","CatalogStorageProfiles",$null)
            $sprofelem = $newcatalog.CreateNode("element","VdcStorageProfile",$null)
            $sprofelem.setAttribute("href",$sprofhref)
            $catsp.AppendChild($sprofelem) | Out-Null
            $root.AppendChild($catsp) | Out-Null
        } else {
            Write-Warning ("Could not match Storage Profile '$sprof' in this Org, default storage will be used.")
        }
    }
    $newcatalog.AppendChild($root) | Out-Null
    return ($newcatalog.InnerXml)
}

Function New-SubscribedCatalog(
    [Parameter(Mandatory=$true)][string]$vCDHost,
    [Parameter(Mandatory=$true)][string]$OrgName,
    [Parameter(Mandatory=$true)][string]$CatalogName,
    [string]$CatalogDescription = "This is a catalog created from powershell",
    [string]$StorageProfile,
    [string]$SubscribeToExternalFeeds = "false",
    [string]$LocationURL = $null,
    [string]$SubscribeCatalogPassword = $null,
    [string]$localcopysync = "false"
)
{
<#
.SYNOPSIS
Creates a new catalog with subscribed option in the specified vCloud Organization
.DESCRIPTION
New-subscribedCatalog provides a method of creating new subscribed Catalogs
within vCloud Director.
.PARAMETER vCDHost
A mandatory parameter which provides the cloud endpoint to be used.
.PARAMETER OrgName
A mandatory parameter containing the vCloud Organization Name for
which the catalog should be created.
.PARAMETER CatalogName
A mandatory parameter containing the name of the new catalog.
.PARAMETER CatalogDescription
An optional description of the new catalog.
.PARAMETER StorageProfile
An optional storage profile on which the new catalog should be created,
if not specified any available storage profile will be used.
.PARAMETER SubscribeToExternalFeeds
A boolean option to subscribe to an external feed within the new catalog.
.PARAMETER LocationURL
A URL that points to the published catalog feed
.PARAMETER SubscribeCatalogPassword
The password set on the published catalog feed, not required
.OUTPUTS
Error and status reporting on the creation of the catalog
.EXAMPLE
New-SubscribedCatalog vCDHost www.mycloud.com -Org MyOrg -CatalogName 'Test' -CatalogDescription 'My Test Catalog' -SubscribeToExternalFeeds 'true' -LocationURL https://mycloud.com/vcsp/lib/UUID/ -SubscribeCatalogPassword 'P@ssw0rd'
.NOTES
Allows passing of variables into parameters
Works well with new-catalog module which returns published catalog URL
You must either have an existing PowerCLI connection to vCloud Director
(Connect-CIServer) in your current PowerShell session to use New-SubscribedCatalog.
If you are not connected as a 'System' level administrator you will only
be able to create catalogs in your currently logged in Organization.
#>
    $mySessionID = ($Global:DefaultCIServers | Where-Object { $_.Name -eq $vCDHost }).SessionID
    if (!$mySessionID) {            # If we didn't find an existing PowerCLI session for our URI
        Write-Error ("No vCloud session found for this URI, connect first using Connect-CIServer.")
        Return
    }

    $org = Get-Org -Name $OrgName
    if (!$org) {
        Write-Error ("Could not match $OrgName to a vCD Organization, exiting.")
        Return
    }

    # Construct 'body' XML representing the new catalog to be created:
    $XMLcat = CatalogToXML -catName $CatalogName -catDesc $CatalogDescription -OrgName $OrgName -sprof $StorageProfile <#-pubexternal $IsPublishedExternally -pubpass $CatalogPassword -cacheenabled $IsCacheEnabled -preseveid $PreserveIdentityInfoFlag#> -subscribed $SubscribeToExternalFeeds -location $LocationURL -subpass $SubscribeCatalogPassword -localcopy $localcopysync
    
    # Call VCD API to create catalog:
    Invoke-vCloud -URI ($org.href + '/catalogs') -vCloudToken $mySessionID -ContentType 'application/vnd.vmware.admin.catalog+xml' -Method POST -Body $XMLcat | Out-Null

    $newcatversion = Get-catalog -Org $OrgName -name $CatalogName
    if (!$newcatversion.ExtensionData.Tasks -ne $true) { #Reports on the initial sync and reports error
        if ($newcatversion.ExtensionData.Tasks.Task[0].Status -eq 'running'){
            Write-Host "The $newcatversion catalog is currently syncing" -ForegroundColor Green
        }elseif($newcatversion.ExtensionData.Tasks.Task[0].Status -eq 'error'){
            $catalogerror = $newcatversion.ExtensionData.Tasks.task[0].Error
            Write-Host "Catalog appears created but not fully functional" -ForegroundColor Red
            Write-Host "Please check the following error(401 errors indicate password problems)" -ForegroundColor Red 
            $catalogerror
        }else{
        Write-Host "Catalog Created but passing an unknown status, please check the vCloud Director instance" -ForegroundColor Yellow
        }

    }else{ Write-Host "Subscribed Catalog $CatalogName was created and began syncing without error" -ForegroundColor Green
     }#End of else statement
}# Export function from module
Export-ModuleMember -Function New-SubscribedCatalog