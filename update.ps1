<#
  Install or update the VBAPL BricsCAD LISP from the build repo.

    Update.bat                     empty folder -> installs the latest release into it
                                   existing install -> updates it to the latest release
    Switch Version.bat             lists the published releases; moves to the one you pick
    update.ps1 -Version <commit>   move to that release
    update.ps1 -Yes                do not ask before changing anything
    update.ps1 -Path <dir>         work on that folder instead of the current one
    update.ps1 -Repo <url>         install from another build repo (a test one)

  The same job as agentic-claude-manager-build's update.ps1. Published with
  every release next to Update.bat, but not listed in integrity.json: the
  manifest covers what BricsCAD loads, not the tool that rewrites it.
#>
param(
  [switch]$Yes,
  [string]$Path,
  [string]$Version,
  [switch]$Choose,
  [string]$Repo
)

$ErrorActionPreference = 'Stop'

# The build repo. tool-dev\build\release.ps1 publishes to the same one.
$REPO_URL = 'https://github.com/vivekbholetech01-hub/tool-build.git'
$REPO_NAME = 'tool-build'
$INSTALLER_FILES = @('update.ps1', 'Update.bat', 'Switch Version.bat')

$repoUrl = if ($Repo) { $Repo } else { $REPO_URL }
$utf8 = New-Object System.Text.UTF8Encoding $false

function Fail([string]$msg) {
  Write-Host ''
  Write-Host "  $msg" -ForegroundColor Red
  Write-Host ''
  exit 1
}

# One argument as CreateProcess expects it (the CommandLineToArgvW rules).
function ConvertTo-Arg([string]$a) {
  if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
  $out = '"'
  $bs = 0
  foreach ($ch in $a.ToCharArray()) {
    if ($ch -eq '\') { $bs++; continue }
    if ($ch -eq '"') { $out += ('\' * ($bs * 2 + 1)) + '"'; $bs = 0; continue }
    $out += ('\' * $bs) + $ch
    $bs = 0
  }
  $out + ('\' * ($bs * 2)) + '"'
}

# git with stdout and stderr kept apart - PowerShell 5.1 turns a native
# program's stderr into error records, which under 'Stop' ends the script.
function Invoke-Git([string[]]$A) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'git'
  $psi.Arguments = (@('-C', $root) + $A | ForEach-Object { ConvertTo-Arg $_ }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch { return [pscustomobject]@{ Code = -1; Out = ''; Err = $_.Exception.Message } }
  $err = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out.Trim(); Err = $err.Result.Trim() }
}

function Git([string[]]$A, [string]$failMsg) {
  $r = Invoke-Git $A
  if ($r.Code -ne 0) { Fail ("$failMsg`n  git said: " + (@($r.Err, $r.Out) -join ' ').Trim()) }
  $r.Out
}

function Get-Sha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

# ------------------------------------------------------------------ the folder
$root = if ($Path) { $Path } else { (Get-Location).Path }
try {
  if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
  $root = (Resolve-Path -LiteralPath $root).Path
} catch { Fail "Cannot use that folder: $root" }

Write-Host ''
Write-Host '  VBAPL BricsCAD LISP - install / update' -ForegroundColor Cyan
Write-Host "  $root"
Write-Host ''

# Places where "install here" is never what was meant - usually a .bat started
# from a shortcut or an elevated prompt that handed it System32.
$refuse = @($env:SystemRoot, (Join-Path $env:SystemRoot 'System32'), $env:ProgramFiles,
  ${env:ProgramFiles(x86)}, $env:USERPROFILE, $env:TEMP) | Where-Object { $_ }
foreach ($b in $refuse) {
  if ($root.TrimEnd('\') -ieq $b.TrimEnd('\')) {
    Fail "Refusing to install into $root.`n  Make a folder for the LISP (C:\VBAPL\Lisp, say) and run this from inside it."
  }
}
if ($root -match '^[A-Za-z]:\\?$') {
  Fail "Refusing to install into a drive root ($root).`n  Make a folder for the LISP and run this from inside it."
}

if ((Invoke-Git @('--version')).Code -ne 0) {
  Fail "git is not installed, or not on PATH.`n  Install Git for Windows (https://git-scm.com), then run this again."
}

# --------------------------------------------------------- install or update?
$isRepo = Test-Path -LiteralPath (Join-Path $root '.git')
if ($isRepo) {
  $remote = (Invoke-Git @('remote', 'get-url', 'origin')).Out
  # The build repo was called lisp-build before it became tool-build. An
  # install made then is still ours: point it at the new name and carry on.
  $oldNames = @('lisp-build')
  $known = $remote -and ($remote -match [regex]::Escape($REPO_NAME) -or ($oldNames | Where-Object { $remote -match [regex]::Escape($_) }))
  if (-not $known) {
    Fail "This folder is already a git repository, but not this one:`n    $(if ($remote) { $remote } else { '(no origin remote)' })`n  Run this in an empty folder instead."
  }
  if ($remote -notmatch [regex]::Escape($REPO_NAME) -and -not $Repo) {
    $null = Git @('remote', 'set-url', 'origin', $repoUrl) 'Could not point this install at the renamed build repo.'
    Write-Host "  The build repo is now $repoUrl - this install follows it."
  }
  $mode = 'update'
} else {
  # Only the installer itself may already be here. Anything else is somebody's
  # work, and an install must never land on top of it.
  $ours = $INSTALLER_FILES + @('desktop.ini', 'Thumbs.db')
  $strangers = @(Get-ChildItem -Force -LiteralPath $root | Where-Object { $ours -notcontains $_.Name })
  if ($strangers.Count) {
    Write-Host '  This folder is not empty:' -ForegroundColor Yellow
    $strangers | Select-Object -First 8 | ForEach-Object { Write-Host "    $($_.Name)" }
    if ($strangers.Count -gt 8) { Write-Host "    ... and $($strangers.Count - 8) more" }
    Fail "Refusing to install on top of files that are not ours.`n  Run this in an empty folder."
  }
  $mode = 'install'
}

if ($mode -eq 'install') {
  Write-Host "  Installing from $repoUrl"
  Write-Host ''
  $null = Git @('init', '-q') "git init failed in $root"
  $null = Git @('symbolic-ref', 'HEAD', 'refs/heads/main') 'Could not name the branch.'
  $null = Git @('remote', 'add', 'origin', $repoUrl) 'Could not add the remote.'
  $dirty = @()
} else {
  $before = Git @('rev-parse', '--short', 'HEAD') 'This install has no release checked out.'
  $relFile = Join-Path $root 'RELEASE.json'
  if (Test-Path -LiteralPath $relFile) {
    $rel = [IO.File]::ReadAllText($relFile, $utf8) | ConvertFrom-Json
    Write-Host "  Installed : $before  (source $($rel.commit), built $($rel.builtAt))"
  } else {
    Write-Host "  Installed : $before"
  }
  # Tracked files someone edited in place. The update puts them back - say so
  # first, because that edit is about to disappear.
  $dirty = @((Git @('status', '--porcelain', '--untracked-files=no') 'git status failed.') -split "`r?`n" |
      Where-Object { $_ -and $_ -notmatch '(update\.ps1|Update\.bat|Switch Version\.bat)"?$' })
  if ($dirty.Count) {
    Write-Host ''
    Write-Host '  These files were changed on this machine and WILL be put back to the release:' -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "    $_" }
  }
}

Write-Host '  Fetching...'
$f = Invoke-Git @('fetch', '-q', 'origin', 'main')
if ($f.Code -ne 0) {
  Fail ("git could not fetch the release:`n    $($f.Err)`n  Common reasons: no network; no access to this private repo (run 'gh auth status');`n" +
    "  or the folder is nested too deep for Windows' 260-character path limit -`n  install somewhere shorter, like C:\VBAPL\Lisp.")
}

# ------------------------------------------------------------ which release?
$target = 'origin/main'
if ($Choose) {
  $installed = if ($mode -eq 'update') { Git @('rev-parse', 'HEAD') 'git rev-parse failed.' } else { '' }
  $rows = @((Git @('log', '-25', '--format=%H|%h|%ad|%s', '--date=format:%d %b %Y %H:%M', 'origin/main') 'Could not read the release history.') -split "`r?`n" | Where-Object { $_ })
  if (-not $rows.Count) { Fail 'No releases found on main.' }
  Write-Host ''
  Write-Host '  Published releases (newest first):'
  Write-Host ''
  for ($i = 0; $i -lt $rows.Count; $i++) {
    $c = $rows[$i].Split('|', 4)
    $mark = if ($c[0] -eq $installed) { '  <- installed' } else { '' }
    $tag = if ($i -eq 0) { ' (latest)' } else { '' }
    Write-Host ('   {0,2}. {1}  {2}  {3}{4}{5}' -f ($i + 1), $c[1], $c[2], $c[3], $tag, $mark)
  }
  Write-Host ''
  $pick = Read-Host '  Switch to which number? (Enter = cancel)'
  if (-not $pick) { Write-Host '  Cancelled - nothing was changed.'; Write-Host ''; exit 0 }
  $n = 0
  if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $rows.Count) { Fail "Not a number from the list: $pick" }
  $Version = $rows[$n - 1].Split('|')[0]
}
if ($Version) {
  $resolved = (Invoke-Git @('rev-parse', '--verify', '--quiet', "$Version^{commit}")).Out
  if (-not $resolved) { Fail "No release $Version in the release history." }
  if ((Invoke-Git @('merge-base', '--is-ancestor', $resolved, 'origin/main')).Code -ne 0) {
    Fail "$Version is not a published release (not on main)."
  }
  $target = $resolved
}
$after = Git @('rev-parse', '--short', $target) 'Could not resolve the release.'

if ($mode -eq 'update') {
  if ($before -eq $after -and -not $dirty.Count) {
    Write-Host ''
    $what = if ($Version) { "That release ($before) is already installed" } else { "Already up to date ($before)" }
    Write-Host "  $what. Nothing to do." -ForegroundColor Green
    Write-Host ''
    exit 0
  }
  Write-Host "  Available : $after$(if ($Version) { ' (chosen)' })"
  Write-Host ''
  $ahead = (Invoke-Git @('log', '--oneline', '--no-decorate', "HEAD..$target")).Out
  if ($ahead) {
    Write-Host '  Releases to apply:'
    $ahead -split "`r?`n" | ForEach-Object { Write-Host "    $_" }
  } else {
    $back = (Invoke-Git @('log', '--oneline', '--no-decorate', "$target..HEAD")).Out
    if ($back) {
      Write-Host '  Going BACK - these newer releases will be left:' -ForegroundColor Yellow
      $back -split "`r?`n" | ForEach-Object { Write-Host "    $_" }
      Write-Host '  (Update.bat brings you to the latest again.)'
    }
  }
  Write-Host ''
}

if (-not $Yes) {
  $verb = if ($mode -eq 'install') { 'Install here' } elseif ($Version) { "Switch to $after" } else { 'Apply this update' }
  $answer = Read-Host "  $verb`? (y/N)"
  if ($answer -notmatch '^(y|yes)$') {
    Write-Host '  Cancelled - nothing was changed.'
    Write-Host ''
    exit 0
  }
}

# Going back to an older release would also bring back its older installer.
# Keep the one running now - it is the newest this machine has seen.
$savedInstaller = @{}
if ($Version) {
  foreach ($name in $INSTALLER_FILES) {
    $p = Join-Path $root $name
    if (Test-Path -LiteralPath $p) { $savedInstaller[$name] = [IO.File]::ReadAllBytes($p) }
  }
}

# ------------------------------------------------------------------- apply
Write-Host ''
Write-Host '  Applying...'
if ($mode -eq 'install') {
  # -f: the installer pair is sitting here untracked, and git will not write a
  # tracked file over an untracked one even when the bytes are identical. Safe,
  # because the folder was refused above if it held anything else.
  $null = Git @('checkout', '-q', '-f', '-B', 'main', $target) 'Could not check the release out into this folder.'
} else {
  $null = Git @('reset', '-q', '--hard', $target) 'git reset failed - this install has NOT been updated.'
}
foreach ($name in $savedInstaller.Keys) {
  [IO.File]::WriteAllBytes((Join-Path $root $name), $savedInstaller[$name])
}

# ------------------------------------------------------------------ verify
# Every file BricsCAD loads, against the hashes the release was built with.
$manifestFile = Join-Path $root 'integrity.json'
if (-not (Test-Path -LiteralPath $manifestFile)) {
  Fail 'This release has no integrity.json, so nothing here can be checked. Ask for a new release.'
}
$manifest = [IO.File]::ReadAllText($manifestFile, $utf8) | ConvertFrom-Json
$problems = @()
$listed = @{}
foreach ($entry in $manifest.files.PSObject.Properties) {
  $listed[$entry.Name] = $true
  $full = Join-Path $root $entry.Name
  if (-not (Test-Path -LiteralPath $full)) { $problems += "missing  $($entry.Name)" }
  elseif ((Get-Sha256 $full) -ne $entry.Value) { $problems += "changed  $($entry.Name)" }
}
if ($problems.Count) {
  Write-Host ''
  $problems | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
  Fail 'These files do not match the release. Run Update.bat again; if it repeats, the release itself is bad.'
}
$rel = [IO.File]::ReadAllText((Join-Path $root 'RELEASE.json'), $utf8) | ConvertFrom-Json
Write-Host ''
Write-Host "  Installed $after - release $($rel.name), $($rel.files) LISP file(s), built $($rel.builtAt)" -ForegroundColor Green
Write-Host '  Every file matches the release.'
Write-Host ''
Write-Host "  Build folder: $root"
if ($mode -eq 'install') {
  Write-Host '  First time on this machine (app\index.html > Getting started has the detail):'
  Write-Host '    1. AutoCAD/BricsCAD: add this folder to the support file search path and'
  Write-Host '       the trusted locations.'
  Write-Host '    2. APPLOAD > Startup Suite > add vbapl.lsp from this folder.'
  Write-Host '    3. On the office network, double-click Start.bat and leave it open.'
}
if (Get-Process -Name 'bricscad', 'acad' -ErrorAction SilentlyContinue) {
  Write-Host '  AutoCAD/BricsCAD is open: drawings already open keep the old routines -' -ForegroundColor Yellow
  Write-Host '  re-run Start.bat, then reopen the drawing.' -ForegroundColor Yellow
}
Write-Host ''
exit 0
