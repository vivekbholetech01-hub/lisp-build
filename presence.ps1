<#
  VBAPL BricsCAD LISP - the session Start.bat opens. One per Windows user.

  ONE AT A TIME. The first thing it does is take a named mutex
  (Local\VBAPL-Lisp-Start). If another session already holds it, this one
  says so, brings that window forward and closes - without unlocking, so a
  second double-click never uses up one of the 100 starts. Windows drops the
  mutex the moment the session's window closes (however it closes), so
  Start.bat works again straight away.

  Then, in order:
    0. approve only on a PC not approved yet: asks for the admin password -
               the admin types it, once (vbapl-lisp.exe approve, via stdin)
    1. unlock  vbapl-lisp.exe unlock - the 7 days / 100 starts licence
    2. page    opens app\index.html (Commands, Getting started)
    3. announce every 15 seconds, one small UDP packet (port 45753) on every
               local network: the tool-dev app lists the PC under "Office PCs
               on the build" - name, user, release, whether its files still
               match it, BricsCAD/AutoCAD open, licence. It only SENDS: no
               firewall rule or admin rights needed on this PC.

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
  [int]$Every = 15,
  # Skip opening the page - for running this without a browser (tests).
  [switch]$NoPage
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false
$TITLE = 'VBAPL LISP'

# ----------------------------------------------------------- one at a time
$first = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\VBAPL-Lisp-Start', [ref]$first)
if (-not $first) {
  # Retitle this window first, so bringing "VBAPL LISP" forward finds the
  # running session's window, not this one.
  $Host.UI.RawUI.WindowTitle = "$TITLE - already running"
  Write-Host ''
  Write-Host '  VBAPL LISP is already running on this PC.' -ForegroundColor Yellow
  Write-Host "  Use the open '$TITLE' window (taskbar). Close it first to start again."
  Write-Host '  Nothing was unlocked and no start was used.'
  Write-Host ''
  try { [void](New-Object -ComObject WScript.Shell).AppActivate($TITLE) } catch { }
  Start-Sleep -Seconds 5
  exit 5
}
$Host.UI.RawUI.WindowTitle = $TITLE

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

# Runs vbapl-lisp.exe with one argument: its exit code and what it printed.
# It is a windowless program, so its output is read from a pipe. $stdin, when
# given, goes in through a pipe too - never on the command line, where any
# program on the PC could read it.
function Invoke-Helper([string]$arg, [string]$stdin = $null) {
  $exe = Join-Path $root 'vbapl-lisp.exe'
  if (-not (Test-Path -LiteralPath $exe)) { return $null }
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe, $arg
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardInput = ($null -ne $stdin)
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($null -ne $stdin) {
      $bytes = $utf8.GetBytes($stdin + "`n")
      $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
      $p.StandardInput.Close()
    }
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit(15000) | Out-Null
    [pscustomobject]@{ Code = $p.ExitCode; Out = $out.TrimEnd() }
  } catch { $null }
}

# The licence as vbapl-lisp.exe sees it; $null when it does not answer.
function Get-Licence {
  $r = Invoke-Helper 'status'
  if (-not $r) { return $null }
  try { $r.Out | ConvertFrom-Json } catch { $null }
}

$heartbeat = Join-Path $env:LOCALAPPDATA 'VBAPL\Lisp\heartbeat'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $heartbeat) | Out-Null

$release = Read-Json (Join-Path $root 'RELEASE.json')
$started = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host ''
Write-Host '  VBAPL BricsCAD LISP' -ForegroundColor Cyan
Write-Host ''
# The one path the Getting started page and AutoCAD/BricsCAD need on this PC.
Write-Host '  Build folder (use this path in AutoCAD / BricsCAD):'
Write-Host "    $root" -ForegroundColor White
Write-Host ''
if ($release) {
  Write-Host "  Release  : $($release.name)  (source $($release.commit), built $($release.builtAt))"
} else {
  Write-Host '  Release  : unknown - this folder has no RELEASE.json' -ForegroundColor Yellow
}
Write-Host ''

# ----------------------------------------------------------------- approve
# Once per PC: the admin types the admin password here. Staff never need it -
# and while the PC is not approved, the LISP stays locked.
$before = Get-Licence
if ($before -and $before.approved -eq $false) {
  Write-Host '  This PC is not approved yet.' -ForegroundColor Yellow
  Write-Host '  The admin types the admin password here - once. (Enter on its own skips.)'
  for ($try = 1; $try -le 3; $try++) {
    $secure = Read-Host -AsSecureString '  Admin password'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    if (-not $plain) { break }
    $answer = Invoke-Helper 'approve' $plain
    $plain = $null
    if (-not $answer) { break }
    Write-Host $answer.Out -ForegroundColor $(if ($answer.Code -eq 0) { 'Green' } else { 'Yellow' })
    if ($answer.Code -eq 0 -or $answer.Code -eq 3) { break }   # 3: no internet - asking again will not help
  }
  Write-Host ''
}

# ------------------------------------------------------------------ unlock
# One "start" - only ever run by the session that holds the mutex.
$unlock = Invoke-Helper 'unlock'
if (-not $unlock) {
  Write-Host '  vbapl-lisp.exe is missing or would not run - copy the whole release folder again.' -ForegroundColor Red
} else {
  $unlock.Out -split "`r?`n" | ForEach-Object { Write-Host $_ -ForegroundColor $(if ($unlock.Code -eq 0) { 'Green' } else { 'Yellow' }) }
  if ($unlock.Code -ne 0) {
    Write-Host '  AutoCAD / BricsCAD will not load the office LISP until this PC is unlocked.' -ForegroundColor Yellow
  }
}
Write-Host ''

# -------------------------------------------------------------------- page
$page = Join-Path $root 'app\index.html'
if (-not $NoPage -and (Test-Path -LiteralPath $page)) {
  try { Start-Process -FilePath $page } catch { }
}

# ---------------------------------------------------------------- announce
$udp = New-Object System.Net.Sockets.UdpClient
$udp.EnableBroadcast = $true
$targets = Get-Targets
Write-Host "  Announcing this PC every $Every s on UDP $Port to: $($targets -join ', ')"
Write-Host '  Leave this window open - minimise it. Close it to stop; Start.bat starts it again.'
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
  # Closing the window ends the process, which drops the mutex anyway; this is
  # for the tidy exits (Ctrl+C).
  try { $mutex.ReleaseMutex() } catch { }
  $mutex.Dispose()
}
