function Invoke-EsxiInstallKeys {
    <#
    .SYNOPSIS


    .DESCRIPTION


    .PARAMETER Credential
        The credential item to be encrpyted with the specified key and saved.



    .INPUTS
        None.

    .OUTPUTS
        None.

    .EXAMPLE

    .LINK

    .NOTES
        01       27/05/20     Initial version.           A McNair
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String]$VMName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
        [switch]$cpuWarning
    )

    begin {
        Write-Verbose ("Function start.")

        ## Build key and timing sequence required to do a basic ESXi install.
        ## Set special character or string, and a wait period after the keystroke is sent.
        $keySequence = @()

        ##
        $keySequence += [pscustomobject]@{"value" = "KeyEnter"; "wait" = 5; "type" = "specialKey"}
        $keySequence += [pscustomobject]@{"value" = "F11"; "wait" = 10; "type" = "specialKey"}
        $keySequence += [pscustomobject]@{"value" = "KeyEnter"; "wait" = 5; "type" = "specialKey"}
        $keySequence += [pscustomobject]@{"value" = "KeyEnter"; "wait" = 5; "type" = "specialKey"}
        
        $keySequence += [pscustomobject]@{"value" = $Credential.GetNetworkCredential().password; "wait" = 1; "type" = "string"}
        $keySequence += [pscustomobject]@{"value" = "TAB"; "wait" = 1; "type" = "specialKey"}
        $keySequence += [pscustomobject]@{"value" = $Credential.GetNetworkCredential().password; "wait" = 1; "type" = "string"}
        $keySequence += [pscustomobject]@{"value" = "KeyEnter"; "wait" = 5; "type" = "specialKey"}

        ## Close the CPU warning dialogue if specified
        if ($cpuWarning) {
            $keySequence += [pscustomobject]@{"value" = "KeyEnter"; "wait" = 5; "type" = "specialKey"}
        } # if

        $keySequence += [pscustomobject]@{"value" = "F11"; "wait" = 180; "type" = "specialKey"}
        $keySequence += [pscustomobject]@{"value" = "KeyEnter"; "wait" = 1; "type" = "specialKey"}
    } # begin

    process {

        Write-Verbose ("Processing VM " + $vmName)

        ## Iternate through command sequence for this VM
        foreach ($key in $keySequence) {

            switch ($key.type) {

                ## Process this input as a special key
                "specialKey" {

                    Write-Verbose ("Sending special key.")

                    ## Invoke the keystroke
                    try {
                        Invoke-VMKeystrokes -VMName $VMName -SpecialKeyInput $key.value -Verbose -ErrorAction Stop
                    } # try
                    catch {
                        throw ("Attempt to send special keystroke failed. " + $_.exception.message)
                    } # catch

                } # specialKey

                ## Process this input as a string value
                "string" {

                    Write-Verbose ("Sending standard key.")

                    ## Invoke the keystroke
                    try {
                        Invoke-VMKeystrokes -VMName $VMName -StringInput $key.value -Verbose -ErrorAction Stop
                    } # try
                    catch {
                        throw ("Attempt to send standard keystroke failed. " + $_.exception.message)
                    } # catch

                } # string

                default {
                    throw ("Unrecognised command type: " + $key.type)
                } # default

            } # switch

            ## Wait for the specified time before executing next keystroke
            Write-Verbose ("Waiting " + $key.wait + " seconds until next keystroke.")
            Start-Sleep $key.wait

        } # foreach


        Write-Verbose ("Completed VM " + $vmName)

    } # process

    end {
        Write-Verbose ("Function complete.")
    } # end

} # function