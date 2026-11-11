# SPDX-License-Identifier: GPL-3.0-or-later
# Sends a PS5 payload ELF to an ELF loader (default: port 9021, as used by
# ps5-payload-elfldr / etaHEN), the Windows equivalent of
#
#   socat -t 99999999 - TCP:<ps5-ip>:9021 < payload.elf
#
#   pwsh -File tools/send-elf.ps1 -Ip 192.168.1.50 -Elf dist\airplay-installer.elf
param(
    [Parameter(Mandatory = $true)][string]$Ip,
    [Parameter(Mandatory = $true)][string]$Elf,
    [int]$Port = 9021,
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Elf)) { throw "ELF not found: $Elf" }

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Elf))
Write-Host ("sending {0:N0} bytes to {1}:{2} ..." -f $bytes.Length, $Ip, $Port)

$client = New-Object System.Net.Sockets.TcpClient
$client.NoDelay = $true
$iar = $client.BeginConnect($Ip, $Port, $null, $null)
if (-not $iar.AsyncWaitHandle.WaitOne(TimeSpan.FromSeconds(10))) {
    $client.Close()
    throw "connect timed out - is the ELF loader running on the console?"
}
$client.EndConnect($iar)

$stream = $client.GetStream()
$stream.WriteTimeout = $TimeoutSeconds * 1000
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()

# The loader keeps the connection open while the payload runs; wait briefly so
# the console can report obvious errors, then detach.
Start-Sleep -Milliseconds 800
try {
    $client.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send)
} catch { }
$client.Close()
Write-Host "sent. Check the console screen for the 'PS5 AirPlay' shortcut."
