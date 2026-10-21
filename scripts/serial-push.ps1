<#
    serial-push.ps1 - push a local file to the S905D3 board over the serial console.

    Board must be sitting at a root shell prompt on the console (see serial-console.ps1).
    Transfer is done as: base64 -> shell `echo ... >> tmp` -> `base64 -d` -> md5 verification.

    Usage:
        .\serial-push.ps1 -LocalFile .\rtl8xxxu.ko -RemotePath /root/rtl8xxxu.ko
        .\serial-push.ps1 -LocalFile .\rtl8723bu_nic.bin -RemotePath /lib/firmware/rtlwifi/rtl8723bu_nic.bin
#>
param(
    [string]$PortName = 'COM30',
    [int]$Baud = 115200,
    [Parameter(Mandatory=$true)][string]$LocalFile,
    [Parameter(Mandatory=$true)][string]$RemotePath,
    [int]$Chunk = 1024,
    [string]$TmpFile = '/tmp/xfer.b64',
    [int]$LineDelayMs = 8
)

$ErrorActionPreference = 'Stop'
$xoff = [string][char]0x13
$xon  = [string][char]0x11
$promptNeedle = '# '

function Open-Port {
    param([string]$Name,[int]$Rate)
    $sp = New-Object System.IO.Ports.SerialPort $Name,$Rate,'None',8,'One'
    $sp.DtrEnable  = $false
    $sp.RtsEnable  = $false
    $sp.Handshake  = [System.IO.Ports.Handshake]::None
    $sp.ReadTimeout  = 500
    $sp.WriteTimeout = 5000
    $sp.Open()
    return $sp
}

function Drain {
    param($P)
    $sb = New-Object System.Text.StringBuilder
    while ($P.BytesToRead -gt 0) {
        [void]$sb.Append($P.ReadExisting())
        Start-Sleep -Milliseconds 3
    }
    return $sb.ToString()
}

function Send-Raw {
    param($P,[string]$Text)
    # CR+LF: works whether or not the console's icrnl is still on.
    # (CR alone only forms a line while icrnl is enabled; if a previous
    #  stty/interaction cleared it, CR-only commands would just be echoed
    #  back without ever running.)
    $P.Write($Text + "`r`n")
}

function Wait-Text {
    param($P,[string]$Needle,[int]$TimeoutMs)
    $sb = New-Object System.Text.StringBuilder
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if ($P.BytesToRead -gt 0) {
            [void]$sb.Append($P.ReadExisting())
            if ($sb.ToString().Contains($Needle)) { break }
        } else {
            Start-Sleep -Milliseconds 30
        }
    }
    return $sb.ToString()
}

if (-not (Test-Path -LiteralPath $LocalFile)) { throw "local file not found: $LocalFile" }

$bytes = [System.IO.File]::ReadAllBytes($LocalFile)
$b64   = [Convert]::ToBase64String($bytes)
$md5   = (Get-FileHash -Algorithm MD5 -LiteralPath $LocalFile).Hash.ToLower()

$port = Open-Port -Name $PortName -Rate $Baud
try {
    Start-Sleep -Milliseconds 300
    [void]$port.ReadExisting()

    Send-Raw $port 'stty -echo'
    [void](Wait-Text $port $promptNeedle 1500)
    [void](Drain $port)

    Send-Raw $port ("rm -f $TmpFile; : > $TmpFile")
    [void](Wait-Text $port $promptNeedle 2000)
    [void](Drain $port)

    $total = [int][Math]::Ceiling($b64.Length / [double]$Chunk)
    $idx = 0
    for ($o = 0; $o -lt $b64.Length; $o += $Chunk) {
        $len  = [Math]::Min($Chunk, $b64.Length - $o)
        $part = $b64.Substring($o, $len)
        Send-Raw $port "echo '$part' >> $TmpFile"
        $idx++
        $r = Drain $port
        if ($r.Contains($xoff) -and -not $r.Contains($xon)) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 4000) {
                $r2 = Drain $port
                if ($r2.Contains($xon)) { break }
                Start-Sleep -Milliseconds 50
            }
        }
        Start-Sleep -Milliseconds $LineDelayMs
        if (($idx % 50) -eq 0) { Write-Host ("  sent $idx/$total chunks") -ForegroundColor DarkGray }
    }

    # keep local echo OFF during verification so the echoed command line
    # (which itself contains "MD5END") cannot match the end marker early.
    Send-Raw $port "base64 -d $TmpFile > $RemotePath; echo MD5START; md5sum $RemotePath; echo MD5END; ls -l $RemotePath; rm -f $TmpFile"
    $out = Wait-Text $port 'MD5END' 90000
    Send-Raw $port 'stty echo'
    Write-Host $out

    $m = [regex]::Match($out, '([0-9a-fA-F]{32})')
    if (-not $m.Success) {
        Write-Host 'could not parse remote md5 (is md5sum present?)' -ForegroundColor Yellow
        exit 3
    }
    $remoteMd5 = $m.Groups[1].Value.ToLower()
    if ($remoteMd5 -eq $md5) {
        Write-Host "OK  verified: $RemotePath  md5=$remoteMd5" -ForegroundColor Green
    } else {
        Write-Host "MISMATCH local=$md5 remote=$remoteMd5" -ForegroundColor Red
        exit 2
    }
} finally {
    if ($port -and $port.IsOpen) { $port.Close(); $port.Dispose() }
}
