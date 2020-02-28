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
# Released under MIT License - see https://opensource.org/licenses/MIT
# Brandon Bazan 2020 updates:
# Modified to allow publishing as a feature for newly created catalogs
# Returns published catalog URL for future use
Function CatalogToXML(
    [Parameter(Mandatory=$true)][string]$catName,
    [string]$catDesc,
    [string]$orgName,
    [string]$sprof,
    [string]$pubexternal,
    [string]$pubpass,
    [string]$cacheenabled,
    [string]$preseveid
)
{
  
    # Create properly formed xml of type application/vnd.vmware.admin.catalog+xml:
    [xml]$newcatalog = New-Object System.Xml.XmlDocument
    $dec = $newcatalog.CreateXmlDeclaration("1.0","UTF-8",$null)
    $newcatalog.AppendChild($dec) | Out-Null
    $root = $newcatalog.CreateNode("element","AdminCatalog",$null)
    $desc = $newcatalog.CreateNode("element","Description",$null)
    $catpubext = $newcatalog.CreateNode("element","PublishExternalCatalogParams",$null)
    $ispubextelem = $newcatalog.CreateNode("element","IsPublishedExternally",$null)
    $iscacheelem = $newcatalog.CreateNode("element","IsCacheEnabled",$null)
    $presidelem = $newcatalog.CreateNode("element","PreserveIdentityInfoFlag",$null)
    $pubpasselem = $newcatalog.CreateNode("element","Password",$null)
    $root.setAttribute("xmlns","http://www.vmware.com/vcloud/v1.5")
    $root.SetAttribute("name",$catName)
    $ispubextelem.InnerText = $pubexternal
    $iscacheelem.InnerText = $cacheenabled
    $presidelem.InnerText = $preseveid
    $pubpasselem.InnerText = $pubpass
    $desc.innerText = $catDesc
    $root.AppendChild($desc) | Out-Null
    $catpubext.AppendChild($ispubextelem) | Out-Null
    $catpubext.AppendChild($pubpasselem) | Out-Null
    $catpubext.AppendChild($iscacheelem) | Out-Null
    $catpubext.AppendChild($presidelem) | Out-Null
    $root.AppendChild($catpubext) | Out-Null
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
            #$sprofelem.setAttribute("href","https://chcdev.cloud.concepts.co.nz/api/vdcStorageProfile/d0897343-0d09-4090-89bc-e0819d2281be")
            $catsp.AppendChild($sprofelem) | Out-Null
            $root.AppendChild($catsp) | Out-Null
        } else {
            Write-Warning ("Could not match Storage Profile '$sprof' in this Org, default storage will be used.")
        }
    }
    $newcatalog.AppendChild($root) | Out-Null
    return ($newcatalog.InnerXml)
}

Function New-Catalog(
    [Parameter(Mandatory=$true)][string]$vCDHost,
    [Parameter(Mandatory=$true)][string]$OrgName,
    [Parameter(Mandatory=$true)][string]$CatalogName,
    [string]$CatalogDescription = "This is a catalog created from powershell",
    [string]$StorageProfile,
    [string]$IsPublishedExternally = "false",
    [string]$PublishCatalogPassword = $null,
    [string]$IsCacheEnabled = "false",
    [string]$PreserveIdentityInfoFlag = "false"
)
{
<#
.SYNOPSIS
Creates a new catalog in the specified vCloud Organization
.DESCRIPTION
New-Catalog provides an easy to use method for creating new Catalogs
within vCloud Director. It should work with any supported version of
the vCD API.
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
.PARAMETER IsPublishedExternally
An option to publish the new catalog publically.
.PARAMETER PublishCatalogPassword
An option to set a published catalog password
.PARAMETER IsCacheEnabled
An optional parameter for caching of content being enabled for this catalog
true for yes, false for no
.PARAMETER PreserveIdentityInfoFlag
An optional parameter to preserve identity of content within this catalog
true for yes, false for no
.OUTPUTS
The published URL of the newly created catalog like below
https://your-vcd-instance.com/vcsp/lib/UUID/
.EXAMPLE
    New-Catalog vCDHost www.mycloud.com -Org MyOrg -CatalogName 'Test' -CatalogDescription 'My Test Catalog' -IsPublishedExternally true -IsCacheEnabled false -PublishCatalogPassword P@ssW0rd -PreserveIdentityInfoFlag true
.EXAMPLE
    $published_url = New-Catalog vCDHost www.mycloud.com -Org MyOrg -CatalogName 'Test1' -CatalogDescription 'My Test Catalog' -IsPublishedExternally true -IsCacheEnabled false -PublishCatalogPassword P@ssW0rd -PreserveIdentityInfoFlag true
.NOTES
You must either have an existing PowerCLI connection to vCloud Director
(Connect-CIServer) in your current PowerShell session to use New-Catalog.
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
    $XMLcat = CatalogToXML -catName $CatalogName -catDesc $CatalogDescription -OrgName $OrgName -sprof $StorageProfile -pubexternal $IsPublishedExternally -pubpass $CatalogPassword -cacheenabled $IsCacheEnabled -preseveid $PreserveIdentityInfoFlag
    Write-Host 'Creating '  $CatalogName ' in ' $OrgName
    # Call VCD API to create catalog:
    Invoke-vCloud -URI ($org.href + '/catalogs') -vCloudToken $mySessionID -ContentType 'application/vnd.vmware.admin.catalog+xml' -Method POST -Body $XMLcat | Out-Null
    
    $catprops = get-catalog -name $CatalogName -org $OrgName
    #Returns published URL for catalog to be used to subscribe
    $PublishedURL = ( 'https://' + $vCDHost + $catprops.ExtensionData.PublishExternalCatalogParams.CatalogPublishedUrl)
    return $PublishedURL
}
# Export function from module:
Export-ModuleMember -Function New-Catalog