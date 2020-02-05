$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

function Use-NewPath {
    $Path = @(
        [System.Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [System.Environment]::GetEnvironmentVariable('Path', 'User')
    )
    $env:Path = $Path -join ';'
}

function Find($Collection, [scriptblock] $Predicate) {
    $Fn = [Func[object, bool]] { param($_) & $Predicate }
    return [Linq.Enumerable]::FirstOrDefault($Collection, $Fn)
}

function Get-Document([string] $Uri) {
    return Invoke-WebRequest $Uri -UseBasicParsing
}

function Install-IfNecessary([string] $Command, [string] $Name, [scriptblock] $Installer) {
    if (Get-Command $Command -ErrorAction Ignore) {
        Write-Output "$Name már telepítve van"
    }
    else {
        & $Installer
    }
}

function Get-Downloader {
    $Downloader = New-Object System.Net.WebClient
    $Downloader.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $Downloader.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()

    return $Downloader
}

function Get-RemoteFile([string] $Url, [string] $Filename) {
    (Get-Downloader).DownloadFile($Url, $Filename)
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

    $Sw = New-Object IO.StreamWriter $LiteralPath, $Append
  
    $OutStringArgs = @{ }
    if ($Width) {
        $OutStringArgs.Width = $Width
    }

    try {
        $Input | Out-String -Stream @OutStringArgs | % { $Sw.WriteLine($_) }
    }
    finally {
        $Sw.Dispose()
    }
}

Install-IfNecessary choco Chocolatey {
    Write-Host "$Name telepítése"
    Invoke-Expression ((Get-Downloader).DownloadString('https://chocolatey.org/install.ps1'))
    Use-NewPath
}

Install-IfNecessary node Node {
    Write-Host "$Name telepítése"
    & choco install -y node
    Use-NewPath
}

Install-IfNecessary cmder 'cmder és UNIX eszközök' {
    Write-Host "$Name telepítése"
    & choco install -y cmder
    Use-NewPath
}

Install-IfNecessary vagrant Vagrant {
    Write-Host "$Name telepítése (ez sokáig eltarthat)"
    $Link = Find (Get-Document 'https://www.vagrantup.com/downloads.html').Links `
    { $_.outerHTML.Contains('data-os="windows"') -and $_.outerHTML.Contains('data-arch="x86_64"') }
    Get-RemoteFile $Link.href 'vagrant.msi'
    Start-Process -Wait msiexec '/I', (Resolve-Path 'vagrant.msi')
    Remove-Item 'vagrant.msi'
    Use-NewPath
}

Write-Host 'Hosts File Editor telepítése'
Get-RemoteFile 'https://github.com/scottlerch/HostsFileEditor/releases/download/v1.2.0/HostsFileEditorSetup-1.2.0.msi' 'hfe.msi'
Start-Process -Wait msiexec '/I', (Resolve-Path 'hfe.msi')
Remove-Item 'hfe.msi'

$SelectedVm = 0
$Vms = @(
    @(
        'VirtualBox',
        {
            $Link = Find (Get-Document 'https://www.virtualbox.org/wiki/Downloads').Links `
            { $_.class -eq 'ext-link' }
            Get-RemoteFile $Link.href 'vbox.exe'
            Start-Process -Wait 'vbox.exe'
            Remove-Item 'vbox.exe'
        }
    ),
    @(
        'VMWare',
        {
            Get-RemoteFile 'https://www.vmware.com/go/getplayer-win' 'vmware.exe'
            Start-Process -Wait 'vmware.exe'
            Remove-Item 'vmware.exe'
        },
        'vmware_workstation'
    ),
    @(
        'Hyper-V',
        { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -ErrorAction Stop },
        'hyperv'
    ),
    @('Már van telepítve VM')
)

Write-Host 'VM telepítése'
Write-Host 'Válassz ki egyet, vagy nyomj ENTER-t az alapértelmezetthez (VirtualBox)'
0..($Vms.Count - 1) | % { '{0}: {1}' -f $_, $Vms[$_][0] }

while ($true) {
    try {
        $Choice = Read-Host
        $SelectedVm = 0
        if ($Choice -ne '') {
            $SelectedVm = [int]::Parse($Choice)
        }
        if ($SelectedVm -lt $Vms.Count) {
            if ($SelectedVm -eq ($Vms.Count - 1)) {
                $SelectedVm = -1
                Write-Host 'VM telepítás átugrása'
                break
            }
            Write-Host 'VM telepítése (ez sokáig eltarthat)'
            $Vms[$SelectedVm][1].Invoke()
            break
        }
    }
    catch {
        # ...
    }
}

$Bat = @'
@echo off

set cwd=%cd%
set homesteadVagrant="%HOMEDRIVE%%HOMEPATH%\Homestead\"

cd /d %homesteadVagrant% && vagrant %*
cd /d %cwd%

set cwd=
set homesteadVagrant=

'@
Set-Location $env:windir
(Write-Output $Bat) | Out-FileUtf8NoBom 'homestead.bat'

if (Test-Path "$env:USERPROFILE\Homestead\" -PathType Container) {
    Write-Host 'Homestead már telepítve van'
}
else {
    Write-Host 'Homestead telepítése'
    Set-Location $env:USERPROFILE
    Start-Process -Wait mkdir Code
    Start-Process -Wait git clone, 'https://github.com/laravel/homestead.git', Homestead
    Set-Location Homestead
    Start-Process -Wait git checkout, release
    & .\init.bat

    if ($SelectedVm -eq -1) {
        Write-Host 'Homestead.yaml fájlt neked kell szerkeszteni, mivel van már VM telepítve'
    }
    elseif ($SelectedVm -ne 0) {
        $Yaml = [string](Get-Content 'Homestead.yaml')
        $ProviderRe = [regex]'(provider:) \S+'
        $ProviderRe.Replace($Yaml, "`$1 $($Vms[$SelectedVm][2])", 1) | Out-FileUtf8NoBom 'Homestead.yaml'
    }

    Write-Host 'Vagrant Box els? futtatása...'
    & vagrant provision
}

Write-Host @'

Kész! Pár hasznos parancs vagranthoz:

  homestead up
    Bootolja a homestead virtuális gépet

  homestead up --provision
    Homestead.yaml beli változtatások életbe léptetése
    és a homestead virtuális gép bootolása

  homestead halt
    Kegyelmes módon leállítja a homestead virtuális gépet

  homestead ssh
    Ezzel kapsz egy terminált a homestead virtuális gépbe

'@
