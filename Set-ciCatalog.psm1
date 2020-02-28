# Author Brandon Bazan https://ifitisnotbroken.wordpress.com/
# PS Module to create externally published vCD Catalogs
# Requires that you are already connected to a vCD instance
# (Connect-CIServer) prior to running the command.
#
# Requires 'Invoke-vCloud' module from PSGet (Install-Module Invoke-vCloud)
Function CatalogToXML(
    [Parameter(Mandatory=$true)][string]$catName,
    [string]$orgName,
    [string]$pubexternal,
    [string]$pubpass
)
{
    # Create properly formed xml of type application/vnd.vmware.admin.publishExternalCatalogparams+xml:
    [xml]$setcatalog = New-Object System.Xml.XmlDocument
    $dec = $setcatalog.CreateXmlDeclaration("1.0","UTF-8",$null)
    $setcatalog.AppendChild($dec) | Out-Null
    $root = $setcatalog.CreateNode("element","PublishExternalCatalogParams",$null)
    $ispubextelem = $setcatalog.CreateNode("element","IsPublishedExternally",$null)
    $pubpasselem = $setcatalog.CreateNode("element","Password",$null)
    $root.setAttribute("xmlns","http://www.vmware.com/vcloud/v1.5")
    $ispubextelem.InnerText = $pubexternal
    $pubpasselem.InnerText = $pubpass
    $root.AppendChild($ispubextelem) | Out-Null
    $root.AppendChild($pubpasselem) | Out-Null
    $setcatalog.AppendChild($root) | Out-Null
    return ($setcatalog.InnerXml)
}

Function set-cicatalog(
    [Parameter(Mandatory=$true)][string]$vCDHost,
    [Parameter(Mandatory=$true)][string]$OrgName,
    [Parameter(Mandatory=$true)][string]$CatalogName,
    [string]$IsPublishedExternally = "false",
    [string]$PublishCatalogPassword = $null
)
{
<#
.SYNOPSIS
Updates an existing catalog in the specified vCloud Organization
to be published externally
.DESCRIPTION
set-cicatalog provides a method for modifying already created Catalogs
within vCloud Director.
.PARAMETER vCDHost
A mandatory parameter for connected vCD instance
.PARAMETER OrgName
A mandatory parameter containing the vCloud Organization Name for
which the catalog should be created.
.PARAMETER CatalogName
A mandatory parameter containing the name of the catalog to be published.
.PARAMETER IsPublishedExternally
An option to publish the already created catalog publically.
.PARAMETER PublishCatalogPassword
An option to set a published catalog password
.OUTPUTS
The published URL of the newly created catalog like below
https://your-vcd-instance.com/vcsp/lib/UUID/
Can be captured as a variable
.EXAMPLE
set-cicatalog vCDHost www.my-vcd-instance.com -Org MyOrg -CatalogName 'Test' -CatalogDescription 'My Test Catalog' -IsPublishedExternally true -PublishCatalogPassword P@ssW0rd
.EXAMPLE
$published_url = set-cicatalog vCDHost www.my-vcd-instance.com -Org MyOrg -CatalogName 'Test' -CatalogDescription 'My Test Catalog' -IsPublishedExternally true -PublishCatalogPassword P@ssW0rd
.NOTES
You must either have an existing PowerCLI connection to vCloud Director
(Connect-CIServer) in your current PowerShell session to use set-cicatalog.
If you are not connected as a 'System' level administrator you will only
be able to modify catalogs in your currently logged in Organization.
#>
    $mySessionID = ($Global:DefaultCIServers | Where-Object { $_.Name -eq $vCDHost }).SessionID
    if (!$mySessionID) {  # If we didn't find an existing PowerCLI session for our URI
        Write-Error ("No vCloud session found for this URI, connect first using Connect-CIServer.")
        Return
    }

    $org = Get-Org -Name $OrgName
    if (!$org) {
        Write-Error ("Could not match $OrgName to a vCD Organization, exiting.")
        Return
    }
    $cat = Get-Catalog -Name $CatalogName -Org $org
    if (!$cat){
        Write-Error ("Could note match $CatalogName within $org")
    }
    # Construct 'body' XML representing the new catalog to be created:
    $XMLcat = CatalogToXML -catName $CatalogName -OrgName $OrgName -pubexternal $IsPublishedExternally -pubpass $CatalogPassword
    
    # Call VCD API to create catalog:
    Invoke-vCloud -URI ($cat.href + '/action/publishToExternalOrganizations') -vCloudToken $mySessionID -ContentType 'application/vnd.vmware.admin.publishExternalCatalogparams+xml' -Method POST -Body $XMLcat | Out-Null
    
    $catprops = get-catalog -name $CatalogName -org $OrgName
    #Returns published URL for catalog to be used to subscribe
    $PublishedURL = ( 'https://' + $vCDHost + $catprops.ExtensionData.PublishExternalCatalogParams.CatalogPublishedUrl)
    return $PublishedURL
}
#End of set-cicatalog function
# Export function from module:
Export-ModuleMember -Function set-cicatalog