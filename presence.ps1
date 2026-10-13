<#
  VBAPL BricsCAD LISP - tells the office network this PC is on the build.

  Start.bat runs this. Every 15 seconds it broadcasts one small UDP packet
  (port 45753) on every local network this PC is on. The lisp-dev app listens
  for it and lists the PC under "Office PCs on the build": its name, user,
  which release it has, whether its files still match that release, and
  whether BricsCAD is open.

  It only SENDS. Nothing listens on this PC and nothing is installed, so no
  firewall rule or admin rights are needed here. Close the window to stop.

  It also keeps the office LISP available: every beacon touches
  %LOCALAPPDATA%\VBAPL\Lisp\heartbeat, and vbapl-lisp.exe hands the LISP to
  AutoCAD/BricsCAD only while that is fresh - so closing this window closes
  the LISP for drawings opened afterwards.

  Packet (JSON): { app, v, host, user, folder, release: { name, commit,
  builtAt, dirty }, intact, bricscad, licence: { state, startsLeft, daysLeft,
  reason, session }, started, seq }
#>
param(
  [int]$Port = 45753,
  [int]$Every = 15
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false

function Read-Json([string]$path) {
  if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json }
}

# Whether every file the release lists is still the bytes it shipped with.
# $null when this folder has no integrity.json to check against.
function Test-Intact {
  $manifest = Read-Json (Join-Path $root 'integrity.json')
  if (-not $manifest) { return $null }
  foreach ($f in $manifest.files.PSObject.Properties) {
    $full = Join-Path $root $f.Name
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLower() -ne $f.Value) { return $false }
  }
  $true
}

# The broadcast address of every IPv4 network this PC is on - 192.168.1.255
# for 192.168.1.20/24 - plus 255.255.255.255. Windows sends the plain
# 255.255.255.255 out of one adapter only, so each network gets its own.
function Get-Targets {
  $out = @('255.255.255.255')
  try {
    $nets = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixLength -lt 31 }
    foreach ($n in $nets) {
      $ip = [Net.IPAddress]::Parse($n.IPAddress).GetAddressBytes()
      $parts = for ($i = 0; $i -lt 4; $i++) {
        $bits = [Math]::Max(0, [Math]::Min(8, $n.PrefixLength - 8 * $i))
        $mask = (0xFF -shl (8 - $bits)) -band 0xFF
        $ip[$i] -bor ((-bnot $mask) -band 0xFF)
      }
      $out += ($parts -join '.')
    }
  } catch {
    # Get-NetIPAddress missing or refused: 255.255.255.255 alone still reaches
    # the main network.
  }
  @($out | Select-Object -Unique)
}

# The licence as vbapl-lisp.exe sees it - one JSON line; $null when the build
# has no helper or it does not answer.
function Get-Licence {
  $exe = Join-Path $root 'vbapl-lisp.exe'
  if (-not (Test-Path -LiteralPath $exe)) { return $null }
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe, 'status'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit(15000) | Out-Null
    $out | ConvertFrom-Json
  } catch { $null }
}

$heartbeat = Join-Path $env:LOCALAPPDATA 'VBAPL\Lisp\heartbeat'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $heartbeat) | Out-Null

$release = Read-Json (Join-Path $root 'RELEASE.json')
$started = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$udp = New-Object System.Net.Sockets.UdpClient
$udp.EnableBroadcast = $true

Write-Host ''
Write-Host '  VBAPL BricsCAD LISP' -ForegroundColor Cyan
Write-Host "  $root"
Write-Host ''
if ($release) {
  Write-Host "  Release  : $($release.name)  (source $($release.commit), built $($release.builtAt))"
} else {
  Write-Host '  Release  : unknown - this folder has no RELEASE.json' -ForegroundColor Yellow
}
$targets = Get-Targets
Write-Host "  Announcing this PC every $Every s on UDP $Port to: $($targets -join ', ')"
Write-Host '  Leave this window open - minimise it. Close it to stop.'
Write-Host ''

$seq = 0
$intact = $null
$licence = $null
try {
  while ($true) {
    # Re-checked every 4th beacon (about a minute): cheap for a folder of LISP,
    # and it catches a file edited in place while this runs.
    if ($seq % 4 -eq 0) {
      $intact = Test-Intact
      $licence = Get-Licence
      $targets = Get-Targets
    }
    $seq++
    $beacon = [ordered]@{
      app      = 'vbapl-lisp'
      v        = 1
      host     = $env:COMPUTERNAME
      user     = $env:USERNAME
      folder   = $root
      release  = if ($release) {
        [ordered]@{ name = $release.name; commit = $release.commit; builtAt = $release.builtAt; dirty = $release.dirty }
      } else { $null }
      intact   = $intact
      bricscad = [bool](Get-Process -Name 'bricscad', 'acad' -ErrorAction SilentlyContinue)
      licence  = if ($licence) {
        [ordered]@{ state = $licence.state; startsLeft = $licence.startsLeft; daysLeft = $licence.daysLeft; reason = $licence.reason; session = $licence.session }
      } else { $null }
      started  = $started
      seq      = $seq
    }
    $bytes = $utf8.GetBytes(($beacon | ConvertTo-Json -Compress -Depth 4))
    $sent = 0
    foreach ($t in $targets) {
      try { [void]$udp.Send($bytes, $bytes.Length, $t, $Port); $sent++ } catch { }
    }
    [IO.File]::WriteAllText($heartbeat, (Get-Date).ToUniversalTime().ToString('o'))
    $state = if ($intact -eq $false) { 'files CHANGED since the release' } elseif ($intact) { 'files match the release' } else { 'files not checked' }
    $lic = if (-not $licence) { '' }
      elseif ($licence.state -eq 'locked') { ' - LISP LOCKED' }
      elseif ($licence.state -eq 'office') { ' - in the office' }
      else { " - $($licence.startsLeft) starts / $($licence.daysLeft) days left" }
    Write-Host -NoNewline ("`r  {0}  announced #{1} on {2} network(s) - {3}{4}      " -f (Get-Date -Format 'HH:mm:ss'), $seq, $sent, $state, $lic)
    Start-Sleep -Seconds $Every
  }
} finally {
  $udp.Close()
}
