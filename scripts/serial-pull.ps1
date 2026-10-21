param(
    [string]$PortName = 'COM30',
    [int]$Baud = 115200,
    [Parameter(Mandatory=$true)][string]$RemotePath,
    [Parameter(Mandatory=$true)][string]$LocalFile,
    [int]$Retries = 3
)

# Pull a file from the board to the host over the serial console.
# Board must be sitting at a root shell prompt on /dev/console.
# Transport: board runs `base64 <file>` between two markers; host decodes it,
# then verifies against the board's own md5sum.

$ErrorActionPreference = 'Stop'

function Open-Port {
    param([string]$Name,[int]$Rate)
    $sp = New-Object System.IO.Ports.SerialPort $Name,$Rate,'None',8,'One'
    $sp.DtrEnable  = $false
    $sp.RtsEnable  = $false
    $sp.Handshake  = [System.IO.Ports.Handshake]::None
    $sp.ReadBufferSize  = 65536
    $sp.WriteBufferSize = 8192
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

function Send {
    param($P,[string]$T)
    # CR+LF: works whether or not the console's icrnl is still on (CR alone
    # only forms a line while icrnl is enabled; see serial-push.ps1).
    $P.Write($T + "`r`n")
}

function Read-Until {
    param($P,[string]$Needle,[int]$TimeoutMs)
    $sb = New-Object System.Text.StringBuilder
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if ($P.BytesToRead -gt 0) {
            [void]$sb.Append($P.ReadExisting())
            if ($sb.ToString().Contains($Needle)) { break }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
    return $sb.ToString()
}

$port = Open-Port -Name $PortName -Rate $Baud
try {
    Start-Sleep -Milliseconds 300
    [void]$port.ReadExisting()

    Send $port 'stty -echo'
    [void](Read-Until $port '# ' 2000)
    [void](Drain $port)

    # 1. board-side md5
    Send $port "md5sum $RemotePath"
    $m = Read-Until $port '# ' 8000
    $mm = [regex]::Match($m, '([0-9a-fA-F]{32})')
    if (-not $mm.Success) { throw "cannot md5 $RemotePath on board: $m" }
    $boardMd5 = $mm.Groups[1].Value.ToLower()
    Write-Host "board md5: $boardMd5"

    $ok = $false
    for ($try = 1; $try -le $Retries -and -not $ok; $try++) {
        # 2. stream base64 between markers ('#' is not in the base64 alphabet)
        Send $port "echo '#S64#'; base64 $RemotePath; echo '#E64#'"
        $r = Read-Until $port '#E64#' 120000
        $s = $r.IndexOf('#S64#')
        $e = $r.IndexOf('#E64#')
        if ($s -lt 0 -or $e -le $s) { Write-Host "marker parse failed, retry $try"; continue }

        $b64 = $r.Substring($s + 5, $e - $s - 5) -replace '\s',''
        try {
            $bytes = [Convert]::FromBase64String($b64)
        } catch {
            Write-Host "base64 decode error, retry $try"; continue
        }

        $tmp = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        $localMd5 = (Get-FileHash -Algorithm MD5 -LiteralPath $tmp).Hash.ToLower()
        if ($localMd5 -eq $boardMd5) {
            Move-Item -LiteralPath $tmp -Destination $LocalFile -Force
            $ok = $true
            Write-Host ("OK  {0} <- {1}  ({2} bytes, md5={3})" -f $LocalFile, $RemotePath, $bytes.Length, $localMd5) -ForegroundColor Green
        } else {
            Remove-Item -LiteralPath $tmp -Force
            Write-Host "md5 mismatch (local=$localMd5), retry $try" -ForegroundColor Yellow
        }
    }

    Send $port 'stty echo'
    if (-not $ok) { throw "failed to pull $RemotePath after $Retries attempts" }
} finally {
    if ($port -and $port.IsOpen) { $port.Close(); $port.Dispose() }
}
