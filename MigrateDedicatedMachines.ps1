<#
.SYNOPSIS
via an exported CSV from an existing dedicated VDI catalog (Power Managed), migrate machines to Citrix Cloud with new hosting connection mappings

.DESCRIPTION
requires a clean export of an existing catalog, and any multiple assignments removed

.EXAMPLE
.\MigrateDedicatedMachines.ps1

.NOTES
Export required information from existing catalogs

$CatalogName = 'CATALOGNAMEHERE'
$ExportLocation = 'PATH HERE\vms.csv'

Get-BrokerMachine -CatalogName $CatalogName -MaxRecordCount 100000 | Select-Object `
@{Name='AssociatedUserUPNs';Expression={[string]::join("", ($_.AssociatedUserUPNs))}},`
@{Name='AssociatedUserSIDs';Expression={[string]::join("", ($_.AssociatedUserSIDs))}},`
@{Name='AssociatedUserNames';Expression={[string]::join("", ($_.AssociatedUserNames))}},`
@{Name='AssociatedUserFullNames';Expression={[string]::join("", ($_.AssociatedUserFullNames))}},`
@{Name='AssignedUserSIDs';Expression={[string]::join("", ($_.AssignedUserSIDs))}},
*  -ErrorAction SilentlyContinue | Export-CSV -NoTypeInformation $ExportLocation

.LINK
#>

Add-PSSnapin citrix*

Get-XDAuthentication

$VMs = $null
$HostingConnectionName = $null
$DestCatalogName = $null
$PublishedName = $null
$DeliveryGroupName = $null

# Optionally set configuration without being prompted
#$VMs = Import-csv -Path 'Path to CSV Here'
#$HostingConnectionName = "Hosting Connection Name Here"
#$DestCatalogName = "Catalog Name Here"
#$PublishedName = "Display name Here"
#$DeliveryGroupName = "Delivery Group Name here"

# If Not Manually set, prompt for variable configurations
if ($null -eq $VMS) {
    Write-Verbose "Please Select a CSV Import File" -Verbose
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter = 'Comma Separated (*.csv)|*.*'
    }
    $null = $FileBrowser.ShowDialog()

    $VMS = Import-csv -Path $FileBrowser.FileName
}

if ($null -eq $HostingConnectionName) {
    $HostingConnectionName = Get-BrokerHypervisorConnection | Select-Object Name,State,IsReady | Out-GridView -PassThru -Title "Select a Hosting Connection"
}

if ($null -eq $DestCatalogName) {
    $DestCatalogName = Get-BrokerCatalog | Select-Object Name,AllocationType,PersistUserChanges,ProvisioningType,SessionSupport,ZoneName | Out-GridView -PassThru -Title "Select a Destination Catalog"
}

if ($null -eq $DeliveryGroupName) {
    $DeliveryGroupName = Get-BrokerDesktopGroup | Select-Object Name,DeliveryType,Description,DesktopKind,Enabled,SessionSupport | Out-GridView -PassThru -Title "Select a Desktop Group"
}


$Catalog = (Get-BrokerCatalog -Name $DestCatalogName)
$HostingConnectionDetail = (Get-BrokerHypervisorConnection | Where-Object {$_.Name -eq $HostingConnectionName})

$Count = ($VMS | Measure-Object).Count
$StartCount = 1
Write-Verbose "There are $Count machines to process" -Verbose

function AddVMtoCatalog {
    if ($null -eq (Get-BrokerMachine -MachineName $VM.MachineName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Adding $($VM.MachineName) to Catalog $($Catalog.Name)" -Verbose
        New-BrokerMachine -CatalogUid $Catalog.Uid -HostedMachineId $VM.HostedMachineId -HypervisorConnectionUid $HostingConnectionDetail.Uid -MachineName $VM.SID -Verbose | Out-Null
    }
    else {
        Write-Warning "Machine $($VM.MachineName) already exists in catalog $($VM.CatalogName)" -Verbose
    }
}

function AddVMtoDeliveryGroup {
    $DG = (Get-BrokerMachine -MachineName $VM.MachineName).DesktopGroupName
    if ($Null -eq $DG) {
        Write-Verbose "Adding $($VM.MachineName) to DesktopGroup $DeliveryGroupName" -Verbose
        Add-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $DeliveryGroupName -Verbose
    }
    else {
        Write-Warning "$($VM.MachineName) already a member of: $DG"
    } 
}

function AddUsertoVM {
    Write-Verbose "Adding $($VM.AssociatedUserNames) to $($VM.MachineName)" -Verbose
    Add-BrokerUser $VM.AssociatedUserNames -PrivateDesktop $VM.MachineName -Verbose
}

function SetVMDisplayName {
    if ($null -ne $PublishedName) {
        Write-Verbose "Setting Published Name for $($VM.MachineName) to $PublishedName" -Verbose
        Set-BrokerMachine -MachineName $VM.MachineName -PublishedName $PublishedName -Verbose
    }
}

foreach ($VM in $VMs) {
    $OutputColor = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = "Green"
    Write-Output "VERBOSE: Processing machine $StartCount of $Count" -Verbose
    $host.ui.RawUI.ForegroundColor = $OutputColor

    AddVMtoCatalog
    AddVMtoDeliveryGroup
    SetVMDisplayName
    AddUsertoVM
    
    $StartCount += 1
}
