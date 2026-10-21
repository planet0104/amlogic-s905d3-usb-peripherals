<#
    serial-console.ps1  —  Amlogic S905D3 串口控制台

    板子侧接线(只接三根线, 3.3V TTL 电平, 引脚位置以官方引脚图为准):
        TTL 模块 TX  ->  板子 UART2_RX
        TTL 模块 RX  <-  板子 UART2_TX
        TTL 模块 GND <-> 板子 GND
        TTL 模块 VCC ->  不接

    用法:
        .\serial-console.ps1                          交互式控制台(默认 COM30 / 115200)
        .\serial-console.ps1 -PortName COM7           指定端口
        .\serial-console.ps1 -Command "ls -l /root"   执行单条命令后退出, 便于脚本化
        .\serial-console.ps1 -Command "uname -a" -PortName COM7
        .\serial-console.ps1 -CommandFile cmds.txt     按文件逐条下发(推荐, 见下)

    说明:
        - 回车发 CR+LF: 板子 console 的 icrnl 可能被之前的 stty 关掉,
          只发 CR 时命令只回显不执行; CR+LF 两种情况都能成行(多一个空提示符, 无害)。
        - UART 只接了 TX/RX/GND, 因此 DTR/RTS/流控一律关闭。
        - 若提示端口被占用, 说明串口助手(SSCOM/XCOM/MobaXterm 等)还开着, 先关掉。
#>

param(
    [string]$PortName = 'COM30',
    [int]$Baud = 115200,
    [string]$Command,
    [string]$CommandFile,
    [int]$QuietMs = 600
)

$ErrorActionPreference = 'Stop'

function Open-SerialPort {
    param([string]$Name, [int]$BaudRate)

    $sp = New-Object System.IO.Ports.SerialPort $Name, $BaudRate, 'None', 8, 'One'
    # UART 只有 TX/RX/GND 三根线, 不要开 DTR/RTS
    $sp.DtrEnable = $false
    $sp.RtsEnable = $false
    $sp.Handshake = [System.IO.Ports.Handshake]::None
    $sp.ReadTimeout = 500
    $sp.WriteTimeout = 1000
    $sp.Open()

    return $sp
}

# 一直读到连续 $QuietMs 毫秒没有新数据为止
function Read-UntilQuiet {
    param($P, [int]$Quiet)

    $sb = New-Object System.Text.StringBuilder
    $idle = 0
    while ($idle -lt $Quiet) {
        if ($P.BytesToRead -gt 0) {
            [void]$sb.Append($P.ReadExisting())
            $idle = 0
        } else {
            Start-Sleep -Milliseconds 40
            $idle += 40
        }
    }

    return $sb.ToString()
}

function Send-Line {
    param($P, [string]$Line)

    # 发 CR+LF 而不是只发 CR。
    # 板子 console 正常情况下 icrnl 会把 CR 转成 NL, 但该标志可能被
    # 之前的 stty/交互改掉; 一旦 icrnl 关闭, 只发 CR 就永远不构成一行,
    # shell 会"只回显不执行"。CR+LF 在两种情况下都能成行 (icrnl 开着时
    # 会多打一个空提示符, 无害)。
    $P.Write($Line + "`r`n")
}

# ---------------- main ----------------

try {
    $port = Open-SerialPort -Name $PortName -BaudRate $Baud
} catch {
    Write-Host "Cannot open $PortName : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Is another serial terminal holding this port? Close it and retry." -ForegroundColor Yellow
    exit 1
}

try {
    Start-Sleep -Milliseconds 400
    [void]$port.ReadExisting()      # 丢掉连接瞬间的残留数据

    if ($CommandFile) {
        # 从文件逐条下发命令: 每行一条, 以 # 开头为空行会被忽略。
        # 命令里含 ; " ' 等字符时必须走这个入口, 用 -Command 会被 PowerShell 拆散。
        $cmds = Get-Content -LiteralPath $CommandFile -Encoding UTF8
        foreach ($c in $cmds) {
            $t = $c.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            [Console]::Out.WriteLine(">>> $t")
            Send-Line $port $t
            [Console]::Out.Write((Read-UntilQuiet $port $QuietMs))
            [Console]::Out.WriteLine()
        }
        exit 0
    }

    if ($Command) {
        Send-Line $port $Command
        [Console]::Out.Write((Read-UntilQuiet $port $QuietMs))
        [Console]::Out.WriteLine()
        exit 0
    }

    Write-Host "Connected to $PortName @ $Baud 8N1, type exit to quit" -ForegroundColor Green

    while ($true) {
        Write-Host -NoNewline '[local] > ' -ForegroundColor Cyan
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }
        if ($line -eq 'exit' -or $line -eq 'quit') { break }
        if ($line -eq '') { continue }

        Send-Line $port $line
        [Console]::Out.Write((Read-UntilQuiet $port $QuietMs))
        [Console]::Out.WriteLine()
    }
} finally {
    if ($port -and $port.IsOpen) {
        $port.Close()
        $port.Dispose()
    }
}
