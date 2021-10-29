#Requires -RunAsAdministrator
#Requires -Modules Hyper-V


# * Fixtures


$GUID_EFI_SYSTEM_PARTITION = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'


$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$VirtualDrivePath = $vmmsSettings.DefaultVirtualHardDiskPath


# * Fns


function New-VHDForWindowsVMSystemVolume
{
    [CmdletBinding()]
    param
    (
        [UInt64]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(16GB, 64TB)]
        $SizeBytes = 255GB,

        [UInt64]
        [ValidateNotNullOrEmpty()]
        $BlockSizeBytes = 1MB,

        [string]
        [ValidateNotNullOrEmpty()]
        $vhdName = ([guid]::NewGuid().toString() + ".vhdx"),

        [string]
        [ValidateNotNullOrEmpty()]
        $vhdPath = (Join-Path $VirtualDrivePath $vhdName)
    )


    $NewVHDParam = @{
        Path = $vhdPath
        SizeBytes = $SizeBytes
        BlockSizeBytes = $BlockSizeBytes
    }
    $VHD = New-VHD @NewVHDParam


    $disk = $VHD | Mount-VHD -PassThru | Initialize-Disk -PartitionStyle GPT -Passthru
    $disk | New-Partition -GptType $GUID_EFI_SYSTEM_PARTITION -Size 200MB `
      | Format-Volume -FileSystem FAT32 -NewFileSystemLabel ESP -confirm:$false `
      | Out-Null
    $disk | New-Partition -UseMaximumSize `
      | Format-Volume -FileSystem NTFS -NewFileSystemLabel WINNT -confirm:$false `
      | Out-Null


    $VHD | Format-Table | Out-String | Write-Host
    $disk | Get-Partition | Format-Table | Out-String | Write-Host
    $disk | Get-Partition | Get-Volume | Format-Table | Out-String | Write-Host


    Dismount-VHD -Path $NewVHDParam.Path


    return $VHD
}


function New-VHDForWindowsVMDataVolume
{
    #Requires -RunAsAdministrator
    #Requires -Modules Hyper-V
    [CmdletBinding()]
    param
    (
        [UInt64]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(16GB, 64TB)]
        $SizeBytes = 255GB,

        [UInt64]
        [ValidateNotNullOrEmpty()]
        $BlockSizeBytes = 1MB,

        [string]
        [ValidateNotNullOrEmpty()]
        $vhdName = ([guid]::NewGuid().toString() + ".vhdx"),

        [string]
        [ValidateNotNullOrEmpty()]
        $vhdPath = (Join-Path $VirtualDrivePath $vhdName)
    )


    $NewVHDParam = @{
        Path = $vhdPath
        SizeBytes = $SizeBytes
        BlockSizeBytes = $BlockSizeBytes
    }
    $VHD = New-VHD @NewVHDParam


    $disk = $VHD | Mount-VHD -PassThru | Initialize-Disk -PartitionStyle GPT -Passthru
    $disk | Get-Partition | Remove-Partition -confirm:$false
    $disk | New-Partition -UseMaximumSize `
      | Format-Volume -FileSystem NTFS -NewFileSystemLabel DATA -confirm:$false `
      | Out-Null


    $disk | Get-Partition | Format-Table | Out-String | Write-Host
    $disk | Get-Partition | Get-Volume | Format-Table | Out-String | Write-Host


    Dismount-VHD -Path $NewVHDParam.Path


    return $VHD
}
