function New-nestedESXi {
    <#
    .SYNOPSIS
        Deploy a nested ESXi VM from template.

    .DESCRIPTION
        Deploy a nested ESXi VM from template.
        Configures 2 standard NICs (1500) MTU and 2 vSAN NICs (9000) MTU
        Configures cores, RAM and hard drives from paramters.
        Configures hard drives as SSD.

    .PARAMETER ovaIndex
        The index number of the DML item to deploy from.

    .PARAMETER dataStore
        The name of the target datastore to deploy to.

    .PARAMETER vmName
        The name of the VM being deployed.

    .PARAMETER esxRAM
        The amount of RAM to configure on the VM in GB.

    .PARAMETER esxCores
        The amount of core to configure on the VM.

    .PARAMETER esxHD01
        Optional. The capacity of additional hard drive 1 in GB.

    .PARAMETER esxHD02
        Optional. The capacity of additional hard drive 2 in GB.

    .PARAMETER esxHD03
        Optional. The capacity of additional hard drive 3 in GB.

    .PARAMETER esxNestedNet01
        The network to attach the first pair of NICs to.

    .PARAMETER esxNestedNet02
        The network to attach the second pair of NICs to.

    .PARAMETER esxiIsoPath
        Optional. Mount a piece of ISO media. For example, "[DATASTORE01] ISOs/VMware-VMvisor-Installer-7.0U1c-17325551.x86_64.iso"

    .PARAMETER bootMode
        Optional. Configure boot mode for BIOS or UEFI. Default VM boot mode is BIOS.

    .PARAMETER reserveMem
        Optional. Reserve all of the configured VM RAM. Avoid swap file creation.

    .INPUTS
        None.

    .OUTPUTS
        None.

    .EXAMPLE
        New-nestedESXi -dataStore DATASTORE01 -vmName podtest01 -vmHost esx01.lab.local -esxRAM 8
        -esxCores 8 -esxHD01 10 -esxHD02 80 -esxHD03 100 -esxNestedNet01 pg01pod01 -esxNestedNet02 pg02pod01
        -bootMode uefi -reserveMem $false

        Deploy a nested ESXi host using the specified paramters with UEFI boot mode. No ISO media mounted.

    .EXAMPLE
        New-nestedESXi -dataStore DATASTORE01 -vmName podtest01 -vmHost esx01.lab.local -esxRAM 8
        -esxCores 8 -esxHD01 10 -esxHD02 80 -esxHD03 100 -esxNestedNet01 pg01pod01 -esxNestedNet02 pg02pod01
        -esxiIsoPath "[DATASTORE01] ISOs/VMware-VMvisor-Installer-7.0U2-17630552.x86_64.iso" -bootMode bios -reserveMem $false

        Deploy a nested ESXi host using the specified paramters. with BIOS boot mode, mounting specified ISO media.

    .LINK

    .NOTES
        01           Alistair McNair          Initial version.

    #>

    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
    Param
    (

        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$dataStore,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$vmName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$vmHost,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxRAM,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxCores,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxHD01,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxHD02,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxHD03,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxNestedNet01,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$esxNestedNet02,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
        [string]$esxiIsoPath,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
        [ValidateSet("bios","uefi")]
        [string]$bootMode = "bios",
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [bool]$reserveMem
    )


    begin {

        Write-Verbose ("Function start.")

    } # begin


    process {

        ## Should process
        if ($PSCmdlet.ShouldProcess($vmName)) {

            Write-Verbose ("Creating virtual machine object " + $vmName)

            ## Create the VM object
            try {
                $vm = New-VM -VMHost $vmHost -Datastore $dataStore -Name $vmName -MemoryGB $esxRAM -NumCpu $esxCores -DiskGB 10 -ErrorAction Stop
                Write-Verbose ("Created virtual machine " + $vmName)
            } # try
            catch {
                throw ("Failed to create virtual machine " + $vmName + " , the CMDlet returned " + $_.exception.message)
            } # catch


            ## Enable Hardware Virtualisation option and set guest OS type to ESXi 6.5 or above.
            Write-Verbose ("Configuring hardware virtualisation, guest OS type and time synchronisation.")

            try {
                $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
                $spec.nestedHVEnabled = $true
                $spec.GuestId = 'vmkernel65Guest'
                $spec.Tools = New-Object VMware.Vim.ToolsConfigInfo
                $spec.Tools.syncTimeWithHost = $true
                $vm.ExtensionData.ReconfigVM($spec)

                Write-Verbose ("Completed.")
            } # try
            catch {
                throw ("Failed to configure VM object for " + $vmName + " , the CMDlet returned " + $_.exception.message)
            } # catch


            ## Remove existing BusLogic SCSI adapter, this will be replaced by a paravirtualised adapter
            Write-Verbose ("Changing VM SCSI controller to Paravirtualised.")

            try {
                $vmView = $vm | Get-View

                $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
                $spec.deviceChange = @()

                $oldCtrl = New-Object VMware.Vim.VirtualDeviceConfigSpec
                $oldCtrl.device = $vmView.Config.Hardware.Device | Where-Object {$_.DeviceInfo.Label -eq ("SCSI controller 0")}
                $oldCtrl.operation = "remove"
                $spec.deviceChange += $oldCtrl

                $newCtrl = New-Object VMware.Vim.VirtualDeviceConfigSpec
                $newCtrl.device = New-Object VMware.Vim.ParaVirtualSCSIController
                $newCtrl.device.busNumber = 0
                $newCtrl.device.DeviceInfo = New-Object VMware.Vim.Description
                $newCtrl.device.DeviceInfo.label = "SCSI controller 0"
                $newCtrl.device.DeviceInfo.summary = "VMware paravirtual SCSI"
                $newCtrl.device.key = -100
                $newCtrl.device.scsiCtlrUnitNumber = 7
                $newCtrl.operation = "add"
                $spec.deviceChange += $newCtrl

                $vmView.ReconfigVM_Task($spec)

                Write-Verbose ("Completed.")
            } # try
            catch {
                throw ("Failed to configure VM SCSI controller for " + $vmName + " , the CMDlet returned " + $_.exception.message)
            } # catch


            ## Remove all existing net adapters, these will be recreated with VMXNET3 adapters
            Write-Verbose ("Stripping existing NICs from VM.")

            try {
                $vm | Get-NetworkAdapter -Verbose:$false | Remove-NetworkAdapter -Confirm:$false -Verbose:$false -ErrorAction Stop
                Write-Verbose ("Removed existing NICs.")
            } # try
            catch {
                throw ("Failed to remove existing net adapters, CMDlet returned " + $_.exception.message)
            } # catch


            ## Add 2 new non-vsan net adapters (1500 MTU)
            try {
                for ($i = 1; $i -le 2; $i++) {

                    Write-Verbose ("Adding non-vSAN adapter " + $i + " of 2 to network " + $esxNestedNet01)
                    New-NetworkAdapter -VM $VM -NetworkName $esxNestedNet01 -StartConnected -Verbose:$false -ErrorAction Stop | Out-Null

                } # for

            } # try
            catch {
                throw ("Failed to add net adapter, the CMDlet returned " + $_.exception.message)
            } # catch


            ## Add 2 new vsan net adapters (9000 MTU)
            try {

                for ($i = 1; $i -le 2; $i++) {

                    Write-Verbose ("Adding vSAN adapter " + $i + " of 2 to network " + $esxNestedNet02)
                    New-NetworkAdapter -VM $VM -NetworkName $esxNestedNet02 -StartConnected -Verbose:$false -ErrorAction Stop | Out-Null

                } # for

            } # try
            catch {
                throw ("Failed to add net adapter, the CMDlet returned " + $_.exception.message)
            } # catch

            $i = 0

            foreach ($esxHD in @($esxHD01,$esxHD02,$esxHD03)) {

                $i++

                ## Add hard drives, if specified
                if ($esxHD) {

                    try {
                        $config = $VM | New-HardDisk -CapacityGB $esxHD -Controller "SCSI Controller 0" -StorageFormat Thin -Datastore $dataStore -Verbose:$false -ErrorAction Stop
                        Write-Verbose ("Hard disk " + $i + " specified of capacity " + $esxHD + "GB")
                    } # try
                    catch {
                        throw ("Failed to add hard disk, the CMDlet returned " + $_.exception.message)
                    } # catch

                    ## Tag this disk as SSD
                    try {
                        New-AdvancedSetting -Entity $VM -Name ("scsi0:" + $config.ExtensionData.UnitNumber + ".virtualSSD") -Value 1 -Confirm:$false -Verbose:$false -ErrorAction Stop | Out-Null
                        Write-Verbose ("Configured SSD emulation for device " + $config.ExtensionData.UnitNumber)
                    } # try
                    catch {
                        throw ("Failed to tag disk " + $config.ExtensionData.UnitNumber + " as SSD, the CMDlet returned " + $_.exception.message)
                    } # catch

                    Write-Verbose ("Finished configuring hard disk " + $i)

                } # if
                else {
                    Write-Verbose ("Hard disk " + $i + " was not specified.")
                } # else

            } # foeach


            ## If specified, set 100% memory reservation on this VM to avoid swap file creation
            if ($reserveMem) {
                Write-Verbose ("100% memory reservation has been specified for this VM.")

                try {
                    $guestConfig = New-Object VMware.Vim.VirtualMachineConfigSpec
                    $guestConfig.memoryReservationLockedToMax = $True
                    $config = $VM.ExtensionData.ReconfigVM_task($guestConfig)
                    Write-Verbose ("Memory reservation has been set.")
                } # try
                catch {
                    throw ("Failed to set memory reservation, the CMDlet returned " + $_.exception.message)
                } # catch

            } # if
            else {
                Write-Verbose ("Memory reservation has not been specified. VM swap files will be created.")
            } # else


            ## Set boot mode if specified, default config is BIOS
            if ($bootMode -eq "uefi") {

                Write-Verbose ("Setting boot mode to UEFI.")

                try {
                    $guestConfig = New-Object VMware.Vim.VirtualMachineConfigSpec
                    $guestConfig.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
                    $config = $vm.ExtensionData.ReconfigVM($guestConfig)

                    Write-Verbose ("Configured boot mode.")
                } # try
                catch {
                    throw ("Failed to configure boot mode, the CMDlet returned " + $_.exception.message)
                } # catch

            } # if


            ## Add a CD drive with the ESXi media mounted
            if ($esxiIsoPath) {

                Write-Verbose ("Mounting specified media " + $esxiIsoPath)

                try {
                    New-CDDrive -VM $vm -IsoPath $esxiIsoPath -StartConnected -ErrorAction Stop | Out-Null
                    Write-Verbose ("Media mounted.")
                } # try
                catch {
                    throw ("Failed to create CDROM drive, the CMDlet returned " + $_.exception.message)
                } # catch
            
            } # if

            ## Return VM object of nested host
            return $vm

        } # if

    } # process

    End {
        Write-Verbose ("Function complete.")

    } # end

} # function