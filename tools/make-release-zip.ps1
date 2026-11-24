[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$IncludeTestLogs
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) {
    $OutputPath = Join-Path $repo 'VittixAutoUpdater.zip'
}
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

$archiveArgs = @('--format=zip', "--output=$OutputPath", 'HEAD')
if (-not $IncludeTestLogs) {
    $archiveArgs += @('--', ':(exclude,glob,top)docs/security/*.log')
}

& git -C $repo archive @archiveArgs
if ($LASTEXITCODE -ne 0) {
    throw "git archive failed with exit code $LASTEXITCODE"
}
Write-Output $OutputPath
