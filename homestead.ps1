$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

function RefreshPath {
    $path = @(
        [System.Environment]::GetEnvironmentVariable("Path", "Machine"),
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    )
    $env:Path = $path -join ";"
                
}

function Find($collection, [scriptblock]$predicate) {
    foreach ($_ in $collection) {
        if ((& $predicate) -eq $true) {
            return $_
        }
    }

    return $null
}

function WhereCommand([string]$command) {
    $meta = Get-Command $command -ErrorAction Ignore
    if ($null -eq $meta) {
        return $null
    }
    else {
        return $meta.Path
    }
}

function Get-Downloader {
    $downloader = New-Object System.Net.WebClient
    $downloader.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $downloader.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()

    return $downloader
}

function Download-File([string]$url, [string]$file) {
    $downloader = Get-Downloader
    $downloader.DownloadFile($url, $file)
}

function Out-FileUtf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $LiteralPath,
        [switch] $Append,
        [switch] $NoClobber,
        [AllowNull()] [int] $Width,
        [Parameter(ValueFromPipeline)] $InputObject
    )

    #requires -version 3

    [System.IO.Directory]::SetCurrentDirectory($PWD)
    $LiteralPath = [IO.Path]::GetFullPath($LiteralPath)

    if ($NoClobber -and (Test-Path $LiteralPath)) {
        Throw [IO.IOException] "The file '$LiteralPath' already exists."
    }

    $sw = New-Object IO.StreamWriter $LiteralPath, $Append
  
    $htOutStringArgs = @{ }
    if ($Width) {
        $htOutStringArgs += @{ Width = $Width }
    }

    try {
        $Input | Out-String -Stream @htOutStringArgs | % { $sw.WriteLine($_) }
    }
    finally {
        $sw.Dispose()
    }
}

if ($null -eq (WhereCommand choco)) {
    Write-Host "Chocolatey telep�t�se"
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    RefreshPath
}
else {
    Write-Host "Chocolatey m�r telep�tve van"
}

if ($null -eq (WhereCommand node)) {
    Write-Host "Node telep�t�se"
    & choco install -y node
    RefreshPath
}
else {
    Write-Host "Node m�r telep�tve van"
}

if ($null -eq (WhereCommand cmder)) {
    Write-Host "cmder �s UNIX eszk�z�k telep�t�se"
    & choco install -y cmder
    RefreshPath
}
else {
    Write-Host "cmder �s UNIX eszk�z�k m�r telep�tve vannak"
}

if ($null -eq (WhereCommand vagrant)) {
    Write-Host "Vagrant telep�t�se (ez sok�ig eltarthat)"
    $links = (Invoke-WebRequest "https://www.vagrantup.com/downloads.html" -UseBasicParsing).Links
    $link = Find $links { $oh = [string]$_.outerHTML; $oh.Contains('data-os="windows"') -and $oh.Contains('data-arch="x86_64"') }
    $href = $link.href
    Download-File $href "vagrant.msi"
    Start-Process msiexec -Wait -ArgumentList @("/I", (Resolve-Path "vagrant.msi"))
    Remove-Item "vagrant.msi"
    RefreshPath
}
else {
    Write-Host "Vagrant m�r telep�tve van"
}

Write-Host "Hosts File Editor telep�t�se"
Download-File "https://github.com/scottlerch/HostsFileEditor/releases/download/v1.2.0/HostsFileEditorSetup-1.2.0.msi" "hfe.msi"
Start-Process msiexec -Wait -ArgumentList @("/I", (Resolve-Path "hfe.msi"))
Remove-Item "hfe.msi"

$selectedVm = 0
$vms = @(
    @(
        "VirtualBox",
        {
            $links = (Invoke-WebRequest "https://www.virtualbox.org/wiki/Downloads" -UseBasicParsing).Links
            $link = Find $links { $_.class -eq "ext-link" }
            $href = $link.href
            Download-File $href "vbox.exe"
            Start-Process vbox.exe -Wait
            Remove-Item "vbox.exe"
        }
    ),
    @(
        "VMWare",
        {
            Download-File "https://www.vmware.com/go/getplayer-win" "vmware.exe"
            Start-Process vmware.exe -Wait
            Remove-Item "vmware.exe"
        },
        "vmware_workstation"
    ),
    @(
        "Hyper-V",
        { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -ErrorAction Stop },
        "hyperv"
    ),
    @("M�r van telep�tve VM")
)

Write-Host "VM telep�t�se"
Write-Host "V�lassz ki egyet, vagy nyomj ENTER-t az alap�rtelmezetthez (VirtualBox)"
0..($vms.Count - 1) | % { "{0}: {1}" -f $_, $vms[$_][0] }

while ($true) {
    try {
        $choice = Read-Host
        $selectedVm = 0
        if ($choice -ne "") {
            $selectedVm = [int]::Parse($choice)
        }
        if ($selectedVm -lt $vms.Count) {
            if ($selectedVm -eq ($vms.Count - 1)) {
                $selectedVm = -1
                Write-Host "VM telep�t�s �tugr�sa"
                break
            }
            Write-Host "VM telep�t�se (ez sok�ig eltarthat)"
            & $vms[$selectedVm][1]
            break
        }
    }
    catch {
        # ...
    }
}

$bat = @"
@echo off

set cwd=%cd%
set homesteadVagrant="%HOMEDRIVE%%HOMEPATH%\Homestead\"

cd /d %homesteadVagrant% && vagrant %*
cd /d %cwd%

set cwd=
set homesteadVagrant=

"@
Set-Location $env:windir
(Write-Output $bat) | Out-FileUtf8NoBom "homestead.bat"

if (Test-Path "$env:USERPROFILE\Homestead\" -PathType Container) {
    Write-Host "Homestead m�r telep�tve van"
} else {
    Write-Host "Homestead telep�t�se"
    Set-Location $env:USERPROFILE
    Start-Process mkdir Code -Wait
    Start-Process git @("clone", "https://github.com/laravel/homestead.git", "Homestead") -Wait
    Set-Location Homestead
    Start-Process git @("checkout", "release") -Wait
    & .\init.bat

    if ($selectedVm -eq -1) {
        Write-Host "Homestead.yaml f�jlt neked kell szerkeszteni, mivel van m�r VM telep�tve"
    } elseif ($selectedVm -ne 0) {
        $yaml = [string](Get-Content "Homestead.yaml")
        $providerRe = [regex]"(provider:) \S+"
        $providerRe.Replace($yaml, "`$1 $($vms[$selectedVm][2])", 1) | Out-FileUtf8NoBom "Homestead.yaml"
    }

    Write-Host "Vagrant Box els? futtat�sa..."
    & vagrant provision
}

Write-Host @"
K�sz! P�r hasznos parancs vagranthoz:

  homestead up
    Bootolja a homestead virtu�lis g�pet

  homestead up --provision
    Homestead.yaml beli v�ltoztat�sok �letbe l�ptet�se
    �s a homestead virtu�lis g�p bootol�sa

  homestead halt
    Kegyelmes m�don le�ll�tja a homestead virtu�lis g�pet

  homestead ssh
    Ezzel kapsz egy termin�lt a homestead virtu�lis g�pbe
"@
