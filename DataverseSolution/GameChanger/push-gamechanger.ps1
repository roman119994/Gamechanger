& "$env:LOCALAPPDATA\Microsoft\PowerAppsCLI\pac.cmd" solution sync

if ($LASTEXITCODE -ne 0) {
    Write-Host "Solution sync failed. Stopping."
    exit $LASTEXITCODE
}

git add .

git status --short

$message = Read-Host "Commit message"

if ([string]::IsNullOrWhiteSpace($message)) {
    Write-Host "Commit message cannot be empty. Stopping."
    exit 1
}

git commit -m "$message"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Nothing committed. Stopping."
    exit $LASTEXITCODE
}

git push

if ($LASTEXITCODE -ne 0) {
    Write-Host "Push failed."
    exit $LASTEXITCODE
}

Write-Host "GameChanger synced, committed, and pushed successfully."