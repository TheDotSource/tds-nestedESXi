function Set-nestedESXi {
    <#
    .SYNOPSIS
        Configure a nested ESXi instance.

    .DESCRIPTION
        Configure a nested ESXi instance.
            * Add and remove vmk0 to regenerate MAC address
            * Configure management IP and subnet
            * Configure a DNS server
            * Set a hostname

        This is performed via the Guest Management API

    .PARAMETER vmName
        VM name of nested ESXi to configure.

    .PARAMETER mgmtIp
        The management IP to configure.

    .PARAMETER mgmtSubnet
        The management subnet to configure.

    .PARAMETER mgmtDNS
        The DNS address to configure.

    .PARAMETER hostName
        The hostname to configure.

    .INPUTS
        None.

    .OUTPUTS
        None.

    .EXAMPLE
        Set-nestedESXi -vmName pod01esx01 -mgmtIp 10.10.1.1 -mgmtSubnet 255.255.255.0 -mgmtDNS 10.10.1.20 -hostName podesx01.pod01.local -Verbose

        Configure the nested host in VM pod01esx01 with the IP and hostname.

    .LINK

    .NOTES
        01           Alistair McNair          Initial version.

    #>

    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$vmName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$mgmtIp,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$mgmtSubnet,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$mgmtDns,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$hostName
    )


    begin {

        Write-Verbose ("Function start.")

    } # begin

    process {

        Write-Verbose ("Processing nested system " + $vmName)

        ## Should process
        if ($PSCmdlet.ShouldProcess($vmName)) {

            ## Get the VM object
            try {
                $vm = Get-VM -Name $vmName -ErrorAction Stop
                Write-Verbose ("Got VM object.")
            } # try
            catch {
                Write-Debug ("Failed to get VM object.")
                throw ("Failed to get VM object. " + $_.exception.message)
            } # catch


            ## Prepare Guest Operation API for nested ESXi
            $guestOpMgr = Get-View $defaultVIServer.ExtensionData.Content.GuestOperationsManager
            $procMgr = Get-View $guestOpMgr.processManager


            ## Create Auth Session Object (using default appliance credentials)
            $auth = New-Object VMware.Vim.NamePasswordAuthentication
            $auth.username = "root"
            $auth.password = "VMware1!"
            $auth.InteractiveSession = $false


            ## Program Spec
            $progSpec = New-Object VMware.Vim.GuestProgramSpec


            # Full path to the command to run inside the guest
            $progSpec.programPath = "/bin/python"
            $progSpec.workingDirectory = "/tmp"


            ## Remove VMK0 and re-add it. The default VMK0 inherits the MAC address from the physical adapter, which causes issues with nested networking
            ## Removing and re-adding this adapter forces a new MAC address which is unique
            $progSpec.arguments = "++group=host/vim/tmp /bin/esxcli.py network ip interface remove --interface-name=vmk0"

            Write-Verbose ("Removing and adding VMK0 to generate new MAC address.")

            try {
                $procMgr.StartProgramInGuest($vm.ExtensionData.MoRef,$auth,$progSpec) | Out-Null
                Write-Verbose ("vmk0 removed.")
            } # try
            catch {
                Write-Debug ("Failed to remove vmk0")
                throw ("Failed to remove vmk0. " + $_.exception.message)
            } # catch

            Start-Sleep 5

            ## Create a new VMK0
            $progSpec.arguments = "++group=host/vim/tmp /bin/esxcli.py network ip interface add --interface-name=vmk0 --portgroup-name=`"Management Network`""

            try {
                $procMgr.StartProgramInGuest($vm.ExtensionData.MoRef,$auth,$progSpec) | Out-Null
                Write-Verbose ("vmk0 created.")
            } # try
            catch {
                Write-Debug ("Failed to create vmk0.")
                throw ("Failed to create vmk0. " + $_.exception.message)
            } # catch

            Start-Sleep 5


            Write-Verbose ("Configuring management IP and subnet.")


            ## Prepare command to set IP
            $progSpec.arguments = "++group=host/vim/tmp /bin/esxcli.py network ip interface ipv4 set -i vmk0 -I " + $mgmtIp + " -N " + $mgmtSubnet + " -t static"


            ## Execute nested host esxcli command
            try {
                $procMgr.StartProgramInGuest($VM.ExtensionData.MoRef,$auth,$progSpec) | Out-Null
                Write-Verbose ("Management IP and subnet configured to " + $mgmtIp + " / " + $mgmtSubnet)
            } # try
            catch {
                Write-Debug ("Failed to set management IP.")
                throw ("Failed to configure managament IP. " + $_.exception.message)
            } # catch


            ## Prepare command to set DNS
            $progSpec.arguments = ("/bin/esxcli.py network ip dns server add -s " + $mgmtDNS)


            Write-Verbose ("Configuring DNS address.")


            ## Execute nested host esxcli command
            try {
                $procMgr.StartProgramInGuest($vm.ExtensionData.MoRef,$auth,$progSpec) | Out-Null
                Write-Verbose ("DNS address was set to "  +$mgmtDns)
            } # try
            catch {
                Write-Debug ("Failed to configure DNS.")
                throw ("Failed to configure DNS " + $_.exception.message)
            } # catch


            Write-Verbose ("Configuring hostname.")


            ## Prepare command to set hostname
            $progSpec.arguments = ("/bin/esxcli.py system hostname set --host=" + $hostName)


            ## Execute nested host esxcli command
            try {
                $procMgr.StartProgramInGuest($VM.ExtensionData.MoRef,$auth,$progSpec) | Out-Null
                Write-Verbose ("Hostname set to " + $hostName)
            } # try
            catch {
                Write-Debug ("Failed to set hostname.")
                throw ("Failed to set hostname. " + $_.exception.message)
            } # catch


        } # if

        Write-Verbose ("Completed processing host.")

    } # process

    end {

        Write-Verbose ("Function complete.")
    } # end


} # function