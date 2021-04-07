function Wait-EsxiInstaller {
    <#
    .SYNOPSIS
       For use with nested ESXi. Wait for the installer to be ready when booting from media.

    .DESCRIPTION
       For use with nested ESXi. Wait for the installer to be ready when booting from media.
       The ESXi installer runs VM Tools. This can be used to poll for installer readiness.
       Installer credentials are root and blank password.

    .PARAMETER vmName
        The name of the virtual machine that is booting the ESXi installer.

    .INPUTS
        System.String. Target nested ESXi VM.

    .OUTPUTS
        None.

    .EXAMPLE
        Wait-EsxiInstaller -vmName nestedEsxi01

        Wait for virtual machine nestedEsxi01 to boot into the ESXi installer.

    .LINK

    .NOTES
        01       Initial version.           A McNair
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$vmName
    )

    begin {
        Write-Verbose ("Function start.")

        Write-Verbose ("Configuring Guest Operations API")

        ## Prepare Guest Operation API for nested ESXi
        $guestOpMgr = Get-View $defaultVIServer.ExtensionData.Content.GuestOperationsManager -Verbose:$false
        $procMgr = Get-View $guestOpMgr.processManager -Verbose:$false

        ## Create Auth Session Object (using default appliance credentials)
        $auth = New-Object VMware.Vim.NamePasswordAuthentication
        $auth.username = "root"
        $auth.password = ""
        $auth.InteractiveSession = $false

        ## Program Spec
        $progSpec = New-Object VMware.Vim.GuestProgramSpec

        # Full path to the command to run inside the guest
        $progSpec.programPath = "/bin/python"
        $progSpec.workingDirectory = "/tmp"

        ## A null command is fine. We just want to test for a response.
        $progSpec.arguments = ""

        Write-Verbose ("Completed.")

    } # begin

    process {

        Write-Verbose ("Processing nested ESXi " + $vmName)

        ## Get the VM object
        try {
            $vm = Get-VM -Name $vmName -ErrorAction Stop -Verbose:$false
            Write-Verbose ("Got VM object.")
        } # try
        catch {
            throw ("Failed to get VM object. " + $_.exception.message)
        } # catch


        ## Poll the guest ops API until we get a response.
        Write-Verbose ("Waiting for ESXi installer to boot....")

        $installerBooted = $false

        while(!$installerBooted) {

            Start-Sleep 10

            try {
                $installerBooted = $procMgr.StartProgramInGuest($vm.ExtensionData.MoRef,$auth,$progSpec)
            }
            catch {
                Write-Verbose ("Waiting for ESXi installer to boot....")
            }

        } # while

        Start-Sleep 10
        
        Write-Verbose ("ESXi installer has booted.")

    } # process

    end {
        Write-Verbose ("Function complete.")
    } # end

} # function