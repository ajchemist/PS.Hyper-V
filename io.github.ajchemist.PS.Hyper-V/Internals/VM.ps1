#Requires -RunAsAdministrator
#Requires -Modules Hyper-V


$ErrorActionPreference = "Stop"


$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$VirtualDrivePath = $vmmsSettings.DefaultVirtualHardDiskPath


$GUID_EFI_SYSTEM_PARTITION = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'


function New-WindowsZerobootVirtualDisk
{
    [CmdletBinding()]
    Param
    (
        [System.IO.FileInfo]
        [parameter(Mandatory = $true)]
        [ValidateScript(
             {
                 if( -Not ($_ | Test-Path) )
                 {
                     throw "File or folder does not exist: $_"
                 }
                 return $true
             })]
        $imagePath,

        [string]
        $vhdName = [System.IO.Path]::GetFileNameWithoutExtension($imagePath) + "-zeroboot.vhdx",

        [string]
        $vhdPath = (Join-Path $VirtualDrivePath $vhdName)
    )


    $img = (get-windowsImage -imagePath $imagePath | out-gridview -passthru)
    $img | Out-String


    $vhd = New-VHD -Path $vhdPath -SizeBytes 127GB -Dynamic -BlockSizeBytes 1MB
    $disk = $vhd | Mount-VHD -Passthru
    $vol_esp = $disk `
    | Initialize-Disk -PartitionStyle GPT -Passthru `
    | New-Partition -AssignDriveLetter -GptType $GUID_EFI_SYSTEM_PARTITION -Size 200MB `
    | Format-Volume -FileSystem FAT32 -NewFileSystemLabel ESP -confirm:$false
    $vol_sys = $disk `
    | New-Partition -AssignDriveLetter -UseMaximumSize `
    | Format-Volume -FileSystem NTFS -NewFileSystemLabel WINNT -confirm:$false


    Expand-WindowsImage -ImagePath $imagePath -Index $img.imageIndex -ApplyPath (-join($vol_sys.DriveLetter,":"))
    bcdboot (-join($vol_sys.DriveLetter,":\Windows")) /s (-join($vol_esp.DriveLetter,":")) /l ko-kr /f UEFI /v
    Dismount-VHD -Path $vhdPath


    Write-Host $vhdPath
    return $vhd
}


function New-WindowsVMFromZeroboot
{
    [CmdletBinding()]
    Param
    (
        [System.IO.FileInfo]
        [parameter(Mandatory = $true)]
        [ValidateScript(
             {
                 if( -Not ($_ | Test-Path) )
                 {
                     throw "File or folder does not exist: $_"
                 }
                 return $true
             })]
        $ParentPath,

        [string]
        $templateName = "",

        [string]
        [ValidateNotNullOrEmpty()]
        $VMName = ($(if (!([string]::IsNullOrEmpty($templateName))) { "${templateName}-" }) + (Get-ChronoVersionString))

        [Switch]
        [parameter(Mandatory = $false)]
        $PassThru
    )


    try
    {
        $SystemVHDPath = (Join-Path $VirtualDrivePath "${VMName}-system.vhdx")
        $VolumeVHDPath = (Join-Path $VirtualDrivePath "${VMName}-volume.vhdx")


        $SystemVHD = New-VHD -Differencing -ParentPath $ParentPath -Path $SystemVHDPath
        $VolumeVHD = New-VHDForWindowsVMDataVolume -vhdPath $VolumeVHDPath


        $NewVMParam = @{
            Name = $VMName
            Generation = 2
            SwitchName = (Get-VMSwitch -SwitchType External)[0].Name
        }
        $VM = New-VM @NewVMParam


        $vmScsiController0 = $VM | Get-VMScsiController -ControllerNumber 0
        $vmScsiController0 | Add-VMHardDiskDrive -Path $SystemVHDPath
        $vmScsiController0 | Add-VMHardDiskDrive -Path $VolumeVHDPath


        # default configuration
        $VM | Set-VMProcessor -count 2 -maximum 98


        $VMFirmwareParam = @{
            VM = $VM
            EnableSecureBoot = 1
            BootOrder = @((Get-VMHardDiskDrive $VM)[0], (Get-VMNetworkAdapter $VM)[0])
        }
        Set-VMFirmware @VMFirmwareParam
        Enable-VMTPM -VM $VM # Windows 11


        # Get-VMIntegrationService -VM $VM -Name "Guest Service Interface" | Enable-VMIntegrationService
        $VM | Get-VMIntegrationService | Where-Object {$_.Enabled -eq $false } | ForEach-Object -Process { Enable-VMIntegrationService $_ }


        return $VM
    }
    catch
    {
        Write-Error $_.Exception.Message
    }
}


function New-LinuxVMFromZeroboot
{
    [CmdletBinding()]
    Param
    (
        [System.IO.FileInfo]
        [parameter(Mandatory = $true)]
        [ValidateScript(
             {
                 if( -Not ($_ | Test-Path) )
                 {
                     throw "File or folder does not exist: $_"
                 }
                 return $true
             })]
        $ParentPath,

        [string]
        [parameter(Mandatory = $true)]
        $VMName
    )


    try
    {
        $SystemVHDPath = (Join-Path $VirtualDrivePath "${VMName}-system.vhdx")
        $SystemVHD = New-VHD -Differencing -ParentPath $ParentPath -Path $SystemVHDPath


        $NewVMParam = @{
            Name = $VMName
            Generation = 2
            SwitchName = (Get-VMSwitch -SwitchType External)[0].Name
        }
        $VM = New-VM @NewVMParam


        $vmScsiController0 = $VM | Get-VMScsiController -ControllerNumber 0
        $vmScsiController0 | Add-VMHardDiskDrive -Path $SystemVHDPath


        # default configuration
        $VM | Set-VMProcessor -count 2 -maximum 98


        $VMFirmwareParam = @{
            VM = $VM
            BootOrder = @((Get-VMHardDiskDrive $VM)[0], (Get-VMNetworkAdapter $VM)[0])
            EnableSecureBoot = 1
        }
        Set-VMFirmware @VMFirmwareParam


        # Get-VMIntegrationService -VM $VM -Name "Guest Service Interface" | Enable-VMIntegrationService
        $VM | Get-VMIntegrationService | Where-Object {$_.Enabled -eq $false } | ForEach-Object -Process { Enable-VMIntegrationService $_ }


        return $VM
    }
    catch
    {
        Write-Error $_.Exception.Message
    }
}


function New-Ubuntu2004VMFromZeroboot
{
    Param
    (
        [System.IO.FileInfo]
        [parameter(Mandatory = $true)]
        $ParentPath,

        [string]
        $templateName = "ubuntu2004"

        [string]
        [ValidateNotNullOrEmpty()]
        $VMName = ($(if (!([string]::IsNullOrEmpty($templateName))) { "${templateName}-" }) + (Get-ChronoVersionString))

        [Switch]
        [parameter(Mandatory = $False)]
        $PassThru
    )
    return New-LinuxVMFromZeroboot -ParentPath $ParentPath -VMName $VMName
}
