if (Get-Command vagrant -ErrorAction Ignore) {
    Set-Location "$env:USERPROFILE\Homestead"
    & vagrant up --provision
}
else {
    Write-Host 'Vagrant nem talalhato'
}
