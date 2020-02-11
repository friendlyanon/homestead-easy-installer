#requires -version 3 -RunAsAdministrator

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

function Install-IfNecessary {
    param([string] $Command, [string] $Name, [scriptblock] $Installer, [switch] $Long)

    if (Get-Command $Command -ErrorAction Ignore) {
        Write-Host "$Name mar telepitve van"
    }
    else {
        Write-Host "$Name telepitese" + (Iif $Long ' (ez sokaig eltarthat)' '')
        & $Installer
        Use-NewPath
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

function Iif($Condition, $TrueCase, $FalseCase) {
    if ($Condition) { $TrueCase } else { $FalseCase }
}

function Install-RemoteFile {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [string] $Url, [switch] $Msi)

    $File = 'installer.' + (Iif $Msi msi exe)
    Get-RemoteFile $Url $File
    if ($Msi) {
        Start-Process -Wait msiexec '/I', (Resolve-Path $File)
    }
    else {
        Start-Process -Wait $File
    }
    Remove-Item $File
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

    [System.IO.Directory]::SetCurrentDirectory($PWD)
    $LiteralPath = [IO.Path]::GetFullPath($LiteralPath)

    if ($NoClobber -and (Test-Path $LiteralPath)) {
        throw [IO.IOException] "The file '$LiteralPath' already exists."
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

if ($false -eq (Test-Connection -ComputerName 'chocolatey.org' -Quiet)) {
    Write-Host 'Internet eleres szukseges'
    break
}

Install-IfNecessary choco Chocolatey {
    Invoke-Expression ((Get-Downloader).DownloadString('https://chocolatey.org/install.ps1'))
}

Install-IfNecessary node Node { & choco install -y nodejs }

Install-IfNecessary cmder 'cmder es UNIX eszkozok' { & choco install -y cmder }

Install-IfNecessary -Long vagrant Vagrant {
    (Find (Get-Document 'https://www.vagrantup.com/downloads.html').Links `
        { $_.outerHTML.Contains('data-os="windows"') -and $_.outerHTML.Contains('data-arch="x86_64"') }).href | `
        Install-RemoteFile -Msi
}

Write-Host 'Hosts File Editor telepitese'
'https://github.com/scottlerch/HostsFileEditor/releases/download/v1.2.0/HostsFileEditorSetup-1.2.0.msi' | `
    Install-RemoteFile -Msi

$SelectedVm = 0
$Vms = @(
    @(
        'VirtualBox',
        {
            (Find (Get-Document 'https://www.virtualbox.org/wiki/Downloads').Links `
                { $_.class -eq 'ext-link' }).href | `
                Install-RemoteFile
        }
    ),
    @(
        'Hyper-V',
        { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -ErrorAction Stop },
        'hyperv'
    ),
    @(, 'Mar van telepitve VM')
)

Write-Host 'VM telepitese'
Write-Host 'Valassz ki egyet, vagy nyomj ENTER-t az alapertelmezetthez (VirtualBox)'
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
                Write-Host 'VM telepites atugrasa'
                break
            }
            Write-Host 'VM telepitese (ez sokaig eltarthat)'
            & $Vms[$SelectedVm][1]
            break
        }
    }
    catch {
        # ...
    }
}

Set-Location $env:windir
@'
@echo off

set cwd=%cd%
set homesteadVagrant="%HOMEDRIVE%%HOMEPATH%\Homestead\"

cd /d %homesteadVagrant% && vagrant %*
cd /d %cwd%

set cwd=
set homesteadVagrant=

'@ | Out-FileUtf8NoBom 'homestead.bat'

if (Test-Path "$env:USERPROFILE\.ssh\id_rsa" -PathType Leaf) {
    Write-Host 'SSH kulcs telepitve van'
}
else {
    Write-Host 'SSH kulcs telepitese'
    Write-Host 'Addj meg egy emailt az SSH kulcshoz: ' -NoNewline
    $Email = Read-Host
    if ([string]::IsNullOrEmpty($Email)) {
        $Email = 'easy.installer@hometsead.com'
    }
    Write-Host 'Addj meg egy jelszot az SSH kulcshoz: ' -NoNewline
    $Password = Read-Host -AsSecureString
    if ([string]::IsNullOrEmpty($Password)) {
        $Password = ''
    }

    Start-Process -Wait ssh-keygen -ArgumentList @(
        '-t',
        'rsa',
        '-b',
        '4096',
        '-C',
        $Email,
        '-f',
        "$env:USERPROFILE\.ssh\id_rsa",
        '-N',
        $Password
    )

    Set-Service ssh-agent -StartupType Manual
    Start-Process -Wait ssh-agent '-s'
}

if (Test-Path "$env:USERPROFILE\Homestead\" -PathType Container) {
    Write-Host 'Homestead mar telepitve van'
}
else {
    Write-Host 'Homestead telepitese'
    Set-Location $env:USERPROFILE
    New-Item Code -ItemType Directory
    Start-Process -Wait git clone, 'https://github.com/laravel/homestead.git', Homestead
    Set-Location Homestead
    Start-Process -Wait git checkout, release
    & .\init.bat

    if ($SelectedVm -eq -1) {
        Write-Host 'Homestead.yaml fajlt neked kell szerkeszteni, mivel van mar VM telepitve'
        Write-Host 'Szerkesztes utan futtasd a `homestead up --provision` parancsot'
    }
    else {
        if ($SelectedVm -ne 0) {
            $Yaml = [string](Get-Content 'Homestead.yaml')
            $ProviderRe = [regex]'(provider:) \S+'
            $ProviderRe.Replace($Yaml, "`$1 $($Vms[$SelectedVm][2])", 1) | Out-FileUtf8NoBom 'Homestead.yaml'
        }

        Write-Host 'Vagrant Box elso futtatasa...'
        & vagrant provision
    }
}

if (Test-Path "$env:USERPROFILE\Code\" -PathType Container) {
    Write-Host 'Code mappa mar letezik'
}
else {
    Write-Host 'Code mappa letrehozasa'
    Set-Location $env:USERPROFILE
    Start-Process -Wait mkdir Code
}

Write-Host @'

Kesz! Par hasznos parancs vagranthoz:

  homestead up
    Bootolja a homestead virtualis gepet

  homestead up --provision
    Homestead.yaml beli valtoztatasok eletbe leptetese
    es a homestead virtualis gep bootolasa

  homestead halt
    Kegyelmes modon leallitja a homestead virtualis gepet

  homestead ssh
    Ezzel kapsz egy terminalt a homestead virtualis gepbe

'@
