if (Get-Command $Command -ErrorAction Ignore) {
    Set-Location "$env:USERPROFILE\Homestead"
    & vagrant provision
}
else {
    Write-Host 'Vagrant nem talalhato'
}
