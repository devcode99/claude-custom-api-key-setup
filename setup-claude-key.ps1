<#
.SYNOPSIS
  Configure Claude Code (CLI + VS Code extension) on Windows to use an API key,
  optionally against a custom Anthropic-compatible base URL.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1
  powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1 -Key sk-ant-...
  powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1 -Key mykey -Url https://my.proxy -Bearer
  powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1 -Uninstall

.PARAMETER Key
  API key / token. Prompted (hidden) if omitted.
.PARAMETER Url
  Custom API base URL. Omit to use api.anthropic.com.
.PARAMETER Bearer
  Send key as ANTHROPIC_AUTH_TOKEN (Authorization: Bearer) instead of
  ANTHROPIC_API_KEY. Many proxies / gateways need this.
.PARAMETER NoUserEnv
  Don't set persistent Windows user environment variables.
.PARAMETER Launch
  Launch claude when done without asking.
.PARAMETER NoLaunch
  Don't launch claude when done.
.PARAMETER Uninstall
  Remove everything this script added.
#>
[CmdletBinding()]
param(
  [string]$Key = "",
  [string]$Url = "",
  [switch]$Bearer,
  [switch]$NoUserEnv,
  [switch]$Launch,
  [switch]$NoLaunch,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$ClaudeDir    = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
$SettingsFile = Join-Path $ClaudeDir "settings.json"
$StateFile    = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR ".claude.json" } else { Join-Path $env:USERPROFILE ".claude.json" }
$AllVars      = @("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL")

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host " v  $m" -ForegroundColor Green }
function Warn($m) { Write-Host " !  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host " x  $m" -ForegroundColor Red; exit 1 }

function Load-Json($path) {
  if (-not (Test-Path $path)) { return [pscustomobject]@{} }
  $text = (Get-Content -Raw -Path $path -Encoding UTF8)
  if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{} }
  try { return $text | ConvertFrom-Json } catch { Die "Invalid JSON in ${path}: $($_.Exception.Message)" }
}

function Save-Json($path, $obj) {
  $json = $obj | ConvertTo-Json -Depth 100
  # Write UTF-8 *without* BOM (Windows PowerShell 5.1's -Encoding UTF8 adds one)
  [System.IO.File]::WriteAllText($path, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Set-Prop($obj, $name, $value) {
  if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

function Remove-Prop($obj, $name) {
  if ($obj.PSObject.Properties[$name]) { $obj.PSObject.Properties.Remove($name) }
}

function Backup($path) {
  if (Test-Path $path) { Copy-Item $path "$path.bak.$(Get-Date -Format yyyyMMddHHmmss)" }
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if ($Uninstall) {
  Info "Removing Claude API key configuration"
  foreach ($v in $AllVars) {
    [Environment]::SetEnvironmentVariable($v, $null, "User")
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
  }
  Ok "Removed user environment variables"
  if (Test-Path $SettingsFile) {
    Backup $SettingsFile
    $s = Load-Json $SettingsFile
    if ($s.PSObject.Properties["env"]) {
      foreach ($v in $AllVars) { Remove-Prop $s.env $v }
      if (@($s.env.PSObject.Properties).Count -eq 0) { Remove-Prop $s "env" }
    }
    Save-Json $SettingsFile $s
    Ok "Removed keys from $SettingsFile"
  }
  Warn "Open a new terminal / restart VS Code for changes to take effect."
  exit 0
}

# ---------------------------------------------------------------------------
# Gather input
# ---------------------------------------------------------------------------
$interactive = [string]::IsNullOrEmpty($Key)
if ($interactive) {
  $secure = Read-Host "Enter your Claude API key (input hidden)" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $Key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  if ([string]::IsNullOrEmpty($Url)) {
    $Url = Read-Host "Custom API base URL (leave empty for Anthropic default)"
  }
  if ($Url -and -not $Bearer) {
    $ans = Read-Host "Does your service expect 'Authorization: Bearer' auth? [y/N]"
    if ($ans -match '^[yY]') { $Bearer = $true }
  }
}

$Key = ($Key -replace '\s', '')
$Url = ($Url -replace '\s', '').TrimEnd('/')

if (-not $Key) { Die "API key is empty." }
if ($Key.Length -lt 20) { Warn "Key is shorter than 20 characters; is it complete?" }
if ($Url) {
  if ($Url -notmatch '^https?://') { Die "Base URL must start with http:// or https://" }
} elseif (-not $Key.StartsWith("sk-ant-")) {
  Warn "Key doesn't start with 'sk-ant-'. If it's for another service, pass -Url."
}

if ($Bearer) { $KeyVar = "ANTHROPIC_AUTH_TOKEN"; $OtherVar = "ANTHROPIC_API_KEY" }
else         { $KeyVar = "ANTHROPIC_API_KEY";    $OtherVar = "ANTHROPIC_AUTH_TOKEN" }

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

# ---------------------------------------------------------------------------
# 1. Persistent user environment variables (Windows equivalent of .bashrc).
#    New terminals / apps pick these up; we also set them for this session.
# ---------------------------------------------------------------------------
if (-not $NoUserEnv) {
  Info "Setting user environment variables"
  [Environment]::SetEnvironmentVariable($KeyVar, $Key, "User")
  [Environment]::SetEnvironmentVariable($OtherVar, $null, "User")
  if ($Url) { [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $Url, "User") }
  else      { [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $null, "User") }
  Ok "$KeyVar$(if ($Url) { ", ANTHROPIC_BASE_URL" })"
}
Set-Item "Env:$KeyVar" $Key
Remove-Item "Env:$OtherVar" -ErrorAction SilentlyContinue
if ($Url) { Set-Item Env:ANTHROPIC_BASE_URL $Url } else { Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# 2. %USERPROFILE%\.claude\settings.json "env" block (CLI + VS Code extension)
# ---------------------------------------------------------------------------
Info "Writing $SettingsFile"
Backup $SettingsFile
$s = Load-Json $SettingsFile
if (-not $s.PSObject.Properties["env"] -or $null -eq $s.env) { Set-Prop $s "env" ([pscustomobject]@{}) }
Set-Prop $s.env $KeyVar $Key
Remove-Prop $s.env $OtherVar
if ($Url) { Set-Prop $s.env "ANTHROPIC_BASE_URL" $Url } else { Remove-Prop $s.env "ANTHROPIC_BASE_URL" }
Save-Json $SettingsFile $s
Ok "env.$KeyVar set$(if ($Url) { ", env.ANTHROPIC_BASE_URL=$Url" })"

# ---------------------------------------------------------------------------
# 3. %USERPROFILE%\.claude.json: pre-approve the key (skips the "Detected a
#    custom API key" prompt) and mark onboarding complete.
#    Claude Code identifies approved keys by their last 20 characters.
# ---------------------------------------------------------------------------
Info "Pre-approving key in $StateFile"
Backup $StateFile
$st = Load-Json $StateFile
$tail = $Key.Substring([Math]::Max(0, $Key.Length - 20))
$r = if ($st.PSObject.Properties["customApiKeyResponses"] -and $st.customApiKeyResponses) { $st.customApiKeyResponses } else { [pscustomobject]@{} }
$approved = [object[]]@(@($r.approved) | Where-Object { $_ -and $_ -ne $tail }) + $tail
$rejected = [object[]]@(@($r.rejected) | Where-Object { $_ -and $_ -ne $tail })
Set-Prop $r "approved" $approved
Set-Prop $r "rejected" $rejected
Set-Prop $st "customApiKeyResponses" $r
Set-Prop $st "hasCompletedOnboarding" $true
Save-Json $StateFile $st
Ok "Key approved (...$($Key.Substring($Key.Length - 4))), onboarding marked complete"

# ---------------------------------------------------------------------------
# 4. Finish
# ---------------------------------------------------------------------------
Write-Host ""
Ok "Setup complete."
Write-Host @"

Next steps:
  * Open a NEW terminal (existing ones keep the old environment)
  * VS Code: fully quit and reopen VS Code so the Claude Code extension
    picks up the new settings
  * Check status: run 'claude' then type /status

"@

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Warn "'claude' not found on PATH. Install it: irm https://claude.ai/install.ps1 | iex"
  exit 0
}

if (-not $Launch -and -not $NoLaunch -and $interactive) {
  $ans = Read-Host "Launch claude now to confirm it works? [Y/n]"
  if ($ans -notmatch '^[nN]') { $Launch = $true }
}
if ($Launch) { & claude }
