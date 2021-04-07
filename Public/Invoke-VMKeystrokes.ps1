function Invoke-VMKeystrokes {
    <#
    .SYNOPSIS
        Send keystrokes to a VM console.

        Based on a function by William Lam and David Rodriguez:
        https://github.com/lamw/vghetto-scripts/blob/master/powershell/VMKeystrokes.ps1

    .DESCRIPTION
        Send keystrokes to a VM console using the  PutUsbScanCodes() method of the virtual machine object.
        The function does not require VM Tools.


    .PARAMETER VMName
        The target VM name.
    
    .PARAMETER StringInput
        A string of characters to send to the VM console, for example "root".

    .PARAMETER SpecialKeyInput
        An individual special key, for example F11.

    .INPUTS
        System.String. The VM name to process.

    .OUTPUTS
        None.

    .EXAMPLE
        Invoke-VMKeystrokes -VMName testvm01 -SpecialKeyInput F11 -Verbose

        Send the special key F11 to testvm01

    .EXAMPLE
        Invoke-VMKeystrokes -VMName testvm01 -StringInput "examplestring" -Verbose

        Send the string "examplestring" to testvm01

    .LINK

    .NOTES
        01       27/05/20     Initial version.           A McNair
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String]$VMName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ParameterSetName="StringInput")]
        [string]$StringInput,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ParameterSetName="SpecialKeyInput")]
        [string]$SpecialKeyInput
    )

    begin {

        Write-Verbose ("Function start.")

        ## Map subset of USB HID keyboard scancodes
        ## https://gist.github.com/MightyPork/6da26e382a7ad91b5496ee55fdc73db2
        $hidCharacterMap = @{
            "a"            = "0x04";
            "b"            = "0x05";
            "c"            = "0x06";
            "d"            = "0x07";
            "e"            = "0x08";
            "f"            = "0x09";
            "g"            = "0x0a";
            "h"            = "0x0b";
            "i"            = "0x0c";
            "j"            = "0x0d";
            "k"            = "0x0e";
            "l"            = "0x0f";
            "m"            = "0x10";
            "n"            = "0x11";
            "o"            = "0x12";
            "p"            = "0x13";
            "q"            = "0x14";
            "r"            = "0x15";
            "s"            = "0x16";
            "t"            = "0x17";
            "u"            = "0x18";
            "v"            = "0x19";
            "w"            = "0x1a";
            "x"            = "0x1b";
            "y"            = "0x1c";
            "z"            = "0x1d";
            "1"            = "0x1e";
            "2"            = "0x1f";
            "3"            = "0x20";
            "4"            = "0x21";
            "5"            = "0x22";
            "6"            = "0x23";
            "7"            = "0x24";
            "8"            = "0x25";
            "9"            = "0x26";
            "0"            = "0x27";
            "!"            = "0x1e";
            "@"            = "0x1f";
            "#"            = "0x20";
            "$"            = "0x21";
            "%"            = "0x22";
            "^"            = "0x23";
            "&"            = "0x24";
            "*"            = "0x25";
            "("            = "0x26";
            ")"            = "0x27";
            "_"            = "0x2d";
            "+"            = "0x2e";
            "{"            = "0x2f";
            "}"            = "0x30";
            "|"            = "0x31";
            ":"            = "0x33";
            "`""           = "0x34";
            "~"            = "0x35";
            "<"            = "0x36";
            ">"            = "0x37";
            "?"            = "0x38";
            "-"            = "0x2d";
            "="            = "0x2e";
            "["            = "0x2f";
            "]"            = "0x30";
            "\"            = "0x31";
            "`;"           = "0x33";
            "`'"           = "0x34";
            ","            = "0x36";
            "."            = "0x37";
            "/"            = "0x38";
            " "            = "0x2c";
            "F1"           = "0x3a";
            "F2"           = "0x3b";
            "F3"           = "0x3c";
            "F4"           = "0x3d";
            "F5"           = "0x3e";
            "F6"           = "0x3f";
            "F7"           = "0x40";
            "F8"           = "0x41";
            "F9"           = "0x42";
            "F10"          = "0x43";
            "F11"          = "0x44";
            "F12"          = "0x45";
            "TAB"          = "0x2b";
            "KeyUp"        = "0x52";
            "KeyDown"      = "0x51";
            "KeyLeft"      = "0x50";
            "KeyRight"     = "0x4f";
            "KeyESC"       = "0x29";
            "KeyBackSpace" = "0x2a";
            "KeyEnter"     = "0x28";
        } # hidCharacterMap

    } # begin
    
    process {
    
        Write-Verbose ("Processing VM " + $vmName)

        ## Get the VM object
        try {
            $vm = Get-VM -Name $vmName -ErrorAction Stop
            Write-Verbose ("Got VM object.")
        } # try
        catch {
            throw ("Failed to get VM object. " + $_.exception.message)
        } # catch

        if ($StringInput) {
            $charSet = $StringInput.ToCharArray()
            $specialKey = $false
            Write-Verbose ("Running in string input mode.")
        } # if
        if ($SpecialKeyInput) {
            $charSet = $SpecialKeyInput
            $specialKey = $true
            Write-Verbose ("Running in special character mode.")
        } # if


        Write-Verbose ("Processing characters.")

        $hidCodesEvents = @()

        foreach ($character in $charSet) {

            ## Check to see if we've mapped the character to HID code
            if ($hidCharacterMap.ContainsKey([string]$character)) {

                $hidCode = $hidCharacterMap[[string]$character]
                $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent

                ## Add leftShift modifer for capital letters and/or special characters
                if ((($character -cmatch "[A-Z]") -or ($character -match "[!|@|#|$|%|^|&|(|)|_|+|{|}|||:|~|<|>|?|*]")) -and (!$specialKey)) {
                    $modifer = New-Object Vmware.Vim.UsbScanCodeSpecModifierType
                    $modifer.LeftShift = $true
                    $tmp.Modifiers = $modifer
                } # if

                ## Convert to expected HID code format
                $hidCodeHexToInt = [Convert]::ToInt64($hidCode, "16")
                $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007

                $tmp.UsbHidCode = $hidCodeValue
                $hidCodesEvents += $tmp

            } # if
            else {
                ## This was not found in our character map.
                throw ("Unidentified character was passed: " + [string]$character)
            } # else

        } # foreach

        ## Call API to send keystrokes to VM
        Write-Verbose ("Sending keys to VM console.")

        try {
            $spec = New-Object Vmware.Vim.UsbScanCodeSpec
            $spec.KeyEvents = $hidCodesEvents
            $vm.Extensiondata.PutUsbScanCodes($spec) | Out-Null
        } # try
        catch {
            throw ("Attempt to send characters failed: " + $_.exception.message)
        } # catch

        Write-Verbose ("Completed VM " + $vmName)

    } # process

    end {
        Write-Verbose ("Function complete.")
    } # end

} # function