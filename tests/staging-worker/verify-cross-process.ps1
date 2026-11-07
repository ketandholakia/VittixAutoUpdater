param(
  [Parameter(Mandatory = $true)][string]$WorkerPath
)

$ErrorActionPreference = 'Stop'
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$base = Join-Path $localAppData ('VAU-T03-INT-' + [Guid]::NewGuid().ToString('N'))
$logRoot = Join-Path $env:TEMP ('VAU-T03-Logs-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base) | Out-Null
[IO.Directory]::CreateDirectory($logRoot) | Out-Null
$evidence = [Collections.Generic.List[object]]::new()

function Start-Worker([string]$Name, [string]$Action, [int]$HoldMs, [string]$OwnedPath = '') {
  $stdout = Join-Path $logRoot ($Name + '.out')
  $stderr = Join-Path $logRoot ($Name + '.err')
  $argumentLine = '"' + $base + '" ' + $HoldMs + ' ' + $Action
  if ($OwnedPath) { $argumentLine += ' "' + $OwnedPath + '"' }
  $proc = Start-Process -FilePath $WorkerPath -ArgumentList $argumentLine `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  return [pscustomobject]@{ Name = $Name; Process = $proc; Out = $stdout; Err = $stderr }
}

function Read-Stage([string]$Path) {
  $deadline = [DateTime]::UtcNow.AddSeconds(10)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $Path) {
      $line = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
        Where-Object { $_ -like 'STAGE=*' } | Select-Object -First 1
      if ($line) { return $line.Substring(6) }
    }
    Start-Sleep -Milliseconds 50
  }
  throw "Worker did not publish its staging path: $Path"
}

try {
  # Eight independent processes allocate at once, then clean their own tree.
  $workers = @()
  1..8 | ForEach-Object { $workers += Start-Worker ("parallel$_") 'cleanup' 1200 }
  foreach ($worker in $workers) {
    $stage = Read-Stage $worker.Out
    $evidence.Add([pscustomobject]@{ PID = $worker.Process.Id; Path = $stage; Scenario = 'parallel-allocation' })
  }
  $workers | ForEach-Object { $_.Process.WaitForExit() }
  $paths = @($evidence | Where-Object Scenario -eq 'parallel-allocation' | ForEach-Object Path)
  if (($paths | Sort-Object -Unique).Count -ne 8) { throw 'Cross-process staging paths collided' }
  foreach ($worker in $workers) {
    $worker.Process.Refresh()
    $contents = Get-Content $worker.Out -Raw
    if ($contents -notmatch 'CLEANED=1' -or $contents -match 'ERROR=') { throw "Worker $($worker.Name) reported failure: $contents" }
  }

  # One process removes only its directory while another remains active.
  $ownerA = Start-Worker 'owner-a' 'cleanup' 250
  $ownerB = Start-Worker 'owner-b' 'keep' 2200
  $pathA = Read-Stage $ownerA.Out
  $pathB = Read-Stage $ownerB.Out
  $evidence.Add([pscustomobject]@{ PID = $ownerA.Process.Id; Path = $pathA; Scenario = 'isolated-cleanup' })
  $evidence.Add([pscustomobject]@{ PID = $ownerB.Process.Id; Path = $pathB; Scenario = 'independent-live-operation' })
  $ownerA.Process.WaitForExit()
  $ownerA.Process.Refresh()
  if (-not (Test-Path -LiteralPath $pathB)) { throw 'Cleanup of owner A affected owner B staging' }
  $ownerB.Process.WaitForExit()
  $ownerB.Process.Refresh()
  if ((Get-Content $ownerA.Out -Raw) -notmatch 'CLEANED=1' -or
      (Get-Content $ownerB.Out -Raw) -notmatch 'COMPLETE=1') { throw 'Isolation worker reported failure' }

  # Terminating one independent worker must not disturb a live peer.
  $cancelled = Start-Worker 'cancelled-owner' 'keep' 30000
  $survivor = Start-Worker 'surviving-owner' 'keep' 2200
  $cancelledPath = Read-Stage $cancelled.Out
  $survivorPath = Read-Stage $survivor.Out
  $evidence.Add([pscustomobject]@{ PID = $cancelled.Process.Id; Path = $cancelledPath; Scenario = 'terminated-peer' })
  $evidence.Add([pscustomobject]@{ PID = $survivor.Process.Id; Path = $survivorPath; Scenario = 'surviving-peer' })
  Stop-Process -Id $cancelled.Process.Id -Force
  $cancelled.Process.WaitForExit()
  if (-not (Test-Path -LiteralPath (Join-Path $survivorPath 'worker.pid'))) {
    throw 'Termination of one worker affected another process staging'
  }
  $survivor.Process.WaitForExit()
  if ((Get-Content $survivor.Out -Raw) -notmatch 'COMPLETE=1') { throw 'Surviving worker did not complete' }
  foreach ($orphanPath in @($cancelledPath, $survivorPath)) {
    $orphanCleanup = Start-Worker ('peer-clean-' + [Guid]::NewGuid().ToString('N')) 'delete' 0 $orphanPath
    $orphanCleanup.Process.WaitForExit()
    if ((Get-Content $orphanCleanup.Out -Raw) -notmatch 'CLEANED=1') { throw "Peer cleanup failed for $orphanPath" }
  }

  # Kill an operation to demonstrate the diagnosable stale artifact behavior.
  $stale = Start-Worker 'stale-owner' 'keep' 30000
  $stalePath = Read-Stage $stale.Out
  $evidence.Add([pscustomobject]@{ PID = $stale.Process.Id; Path = $stalePath; Scenario = 'terminated-stale-artifact' })
  Stop-Process -Id $stale.Process.Id -Force
  $stale.Process.WaitForExit()
  if (-not (Test-Path -LiteralPath (Join-Path $stalePath 'worker.pid'))) {
    throw 'Terminated process did not leave its identifiable marker'
  }
  $cleaner = Start-Worker 'stale-cleaner' 'delete' 0 $stalePath
  $cleaner.Process.WaitForExit()
  $cleaner.Process.Refresh()
  if ((Get-Content $cleaner.Out -Raw) -notmatch 'CLEANED=1') { throw 'Stale artifact cleanup failed' }

  $compactEvidence = foreach ($item in $evidence) {
    [pscustomobject]@{
      PID = $item.PID
      Scenario = $item.Scenario
      Path = Join-Path (Split-Path $base -Leaf) (Split-Path $item.Path -Leaf)
    }
  }
  [pscustomobject]@{ Result = 'PASS'; Base = $base; Evidence = $compactEvidence } |
    ConvertTo-Json -Depth 5 -Compress
}
finally {
  if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
  if (Test-Path -LiteralPath $logRoot) { Remove-Item -LiteralPath $logRoot -Recurse -Force }
}
