& "$env:LOCALAPPDATA\Microsoft\PowerAppsCLI\pac.cmd" solution sync

if ($LASTEXITCODE -ne 0) {
    Write-Host "Solution sync failed. Stopping."
    exit $LASTEXITCODE
}

git add .
git status --short