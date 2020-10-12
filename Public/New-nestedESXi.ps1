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

    .PARAMETER reserveMem
        Optional. Reserve all of the configured VM RAM. Avoid swap file creation.

    .INPUTS
        None.

    .OUTPUTS
        None.

    .EXAMPLE
        New-nestedESXi -ovfPath C:\DML\esxi_67u2\esxi_67u2.ovf -dataStore datastore01 -vmName nestedVM01
        -vmHost host01.local -esxRAM 16 -esxCores 4 -esxHD01 20 -esxHD02 30 -esxHD03 40
        -esxNestedNet01 pg01Pod02 -esxNestedNet02 pg02Pod02 -reserveMem $true -Verbose

        Deploy a nested ESXi host using the specified paramters.

    .LINK

    .NOTES
        01           Alistair McNair          Initial version.

    #>

    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$ovfPath,
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [bool]$reserveMem
    )


    begin {

        Write-Verbose ("Function start.")

    } # begin


    process {

        Write-Verbose ("Processing nested ESXI host on VM " + $vmName)

        ## Should process
        if ($PSCmdlet.ShouldProcess($vmName)) {

            Write-Verbose ("Deploying OVA: " + $ovfPath)

            ## Import the OVA
            try {
                Import-VApp -Source $ovfPath -Name $vmName -VMHost $vmHost -DiskStorageFormat Thin -Datastore $dataStore -Verbose:$false -ErrorAction Stop | Out-Null
                Write-Verbose ("Deployed OVA.")
            } # try
            catch {
                throw ("Failed to deploy OVA " + $ovfPath + " , the CMDlet returned " + $_.exception.message)
            } # catch


            ## Get the VM object
            try {
                $vm = Get-VM -Name $vmName -Verbose:$false -ErrorAction Stop
                Write-Verbose ("Got VM object.")
            } # try
            catch {
                throw ("Failed to get VM object, CMDlet returned " + $_.exception.message)
            } # catch


            Write-Verbose ("Stripping existing NICs from VM.")


            ## Remove all existing net adapters
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


            ## Configure CPU and RAM
            try {
                $config = Set-VM -VM $VM -MemoryGB $esxRAM -CoresPerSocket $esxCores -NumCpu $esxCores -Confirm:$false -Verbose:$false -ErrorAction Stop
                Write-Verbose ("Host CPU and RAM set to " + $esxRAM + "GB and " + $esxCores + " cores.")
            } # try
            catch {
                throw ("Failed to configure host RAM and CPU, CMDlet returned " + $_.exception.message)
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


            ## Power on nested host
            try {
                Write-Verbose ("Waiting for nested host to boot.")
                $config = Start-VM -VM $VM -Verbose:$false -ErrorAction Stop  | Wait-Tools -Verbose:$false
                Write-Verbose ("Host booted.")
            } # try
            catch {
                throw ("Failed to power on nested host, the CMDlet returned " + $_.exception.message)
            } # catch


            ## Return VM object of nested host
            return $vm

        } # if

    } # process

    End {
        Write-Verbose ("Function complete.")

    } # end

} # function