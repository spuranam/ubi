[cmdletbinding()]
param(
  $RoboConfigDestination = $pwd.path,
  $ZipLocation = '',
  $Proxy = '',
  [bool]$RunInBackground = $False,
  $RoboConfigFile = 'RoboConfig.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

if (-not $ZipLocation){
  write-Verbose "Setting ZipLocation to script's folder"
  $ZipLocation = "$PSScriptRoot"
}

if (-not $RoboConfigDestination){
  $RoboConfigDestination = $pwd.path
}

# Build parameters
$paramBootStrap= @{
  ZipLocation = $ZipLocation
  Regex       = 'RoboConfig.*zip$'
  ModulesPath = '/opt/microsoft/powershell/7/Modules'
  Verbose     = $true
}

# Map parameters
if ($Proxy){$paramBootStrap.add('Proxy',$Proxy)}

$configFile = Join-Path $RoboConfigDestination $RoboConfigFile

Function Install-BootstrapModule {

  [cmdletbinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(mandatory = $true)]
    [string]$ZipLocation,
    [string]$Proxy,
    [string]$ModulesPath,
    [string]$Regex,
    [string]$TempRoot = [System.IO.Path]::GetTempPath()
  )

  $ErrorActionPreference = 'Stop'
  Set-StrictMode -Version 1.0

  $tempName = New-Guid | Select-Object -exp Guid
  $tempFolder = Join-Path $TempRoot $tempName
  $tempModuleFolder = Join-Path $tempFolder module

  if ($pscmdlet.ShouldProcess("temp folder", "create")) {
    New-Item -ItemType Directory -Path $tempFolder | Out-Null
    New-Item -ItemType Directory -Path $tempModuleFolder | Out-Null
  }

  Trap {
    if ($pscmdlet.ShouldProcess("temp folder", "error cleanup")) {
      $tempFolder | Remove-Item -Recurse -Force
    }
    throw $_
  }

  if (-not $ModulesPath) {
    if ($PSVersionTable.PSVersion.Major -le 5) {
      $ModulesPath = "$HOME\Documents\WindowsPowerShell\Modules"
    } else {
      if (Get-Variable IsLinux -ErrorAction SilentlyContinue) {
        $ModulesPath = "$HOME/.local/share/powershell/Modules"
      } else {
        $ModulesPath = "$HOME\Documents\PowerShell\Modules"
      }
    }
  }

  if ($ZipLocation -match "https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)") {
    Write-Verbose "URL Location"
    $ProgressPreference = 'SilentlyContinue'
    $roboConfigArchivePath = Join-Path $tempFolder module.zip
    $downloadParams = @{
      Uri             = $ZipLocation
      OutFile         = $roboConfigArchivePath
      UseBasicParsing = $true
    }
    if ($Proxy) {
      $downloadParams.add('Proxy', $Proxy)
    }
    if ($pscmdlet.ShouldProcess("$ZipLocation -> $RoboConfigDestination", "Download")) {
      Write-Verbose "Invoke-WebRequest:"
      Write-Verbose "$($downloadParams | Out-String)"
      Invoke-WebRequest @downloadParams
    }
  } else {
    Write-Verbose "File Location"
    if (-not $ZipLocation) {
      $ZipLocation = $pwd.path
    }
    Write-Verbose "Looking for zip at $ZipLocation"

    if ($Regex) {
      $results = Get-ChildItem -file $ZipLocation | Where-Object name -match $Regex | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    } else {
      $results = Get-ChildItem -file $ZipLocation
    }

    $roboConfigArchivePath = $results | Select-Object -exp FullName
  }

  if ($pscmdlet.ShouldProcess("$roboConfigArchivePath", "test")) {

    if ($roboConfigArchivePath -is [array]) {
      Write-Error "Found more than one file, please specify a single file or a regular expression"
    }
    if (-not (Test-Path $roboConfigArchivePath -ea 0)) {
      Write-Error "Couldn't find module archive file at $ZipLocation!"
    }
  }

  if ($pscmdlet.ShouldProcess("$roboConfigArchivePath -> $RoboConfigDestination", "Expand")) {
    $expandParams = @{
      Path            = $RoboConfigArchivePath
      DestinationPath = $tempModuleFolder
      Force           = $true
    }
    Write-Verbose "Expand-Archive:"
    Write-Verbose "$($expandParams | Out-String)"
    Expand-Archive @expandParams -ErrorAction Stop
  }

  if ($pscmdlet.ShouldProcess("PS manifest file", "Search")) {
    foreach ($file in (Get-ChildItem -file $tempModuleFolder -Filter *.psd1)) {
      Write-Verbose "Checking $($file.FullName)"
      $manifest = Import-PowerShellDataFile $file.FullName -ea SilentlyContinue
      if ($manifest.RootModule -and $manifest.ModuleVersion) {
        $moduleName = $file.Name -replace "\.psd1", ''
        Write-Verbose "Found $moduleName ($($manifest.ModuleVersion))"
        break
      }
      $manifest = $null
    }
    if (-not $manifest) {
      throw "Couldn't find a manifest file in $tempFolder"
    }
  }

  $destinationFolder = Join-Path $modulesPath "$moduleName/$($manifest.ModuleVersion)"

  if ($pscmdlet.ShouldProcess("$destinationFolder", "Copy")) {
    New-Item -ItemType Directory -Path $destinationFolder -ErrorAction SilentlyContinue | Out-Null
    Get-ChildItem $tempModuleFolder | Copy-Item -Destination $destinationFolder -Recurse -Container -Force
  }

  if ($pscmdlet.ShouldProcess("temp folder", "Remove")) {
    $tempFolder | Remove-Item -Recurse -Force -Whatif:$false
  }

}

if ($RoboConfigDestination -ne $PSScriptRoot){
  Write-Output "Copying config files from $PSScriptRoot to $RoboConfigDestination"
  if (-not (Test-Path $RoboConfigDestination)){
    New-Item -ItemType Directory $RoboConfigDestination
  }
  Copy-Item -Path "$PSScriptRoot\*" -Destination $RoboConfigDestination -Recurse -force
  Write-Output "Removing read-only property from copied files"
  Get-ChildItem -file $RoboConfigDestination | Set-ItemProperty -Name IsReadOnly -Value $false
}

Write-Output "Install-BootstrapModule:"
Write-Output "$($paramBootStrap | Out-String)"
Install-BootstrapModule @paramBootStrap *>&1

if (-not (Test-Path $configFile)){
  Write-Error "Can't find $configFile"
}

Import-Module RoboConfig
Write-Output "Using RoboConfig version $(Get-Module RoboConfig|Select-Object -exp version)"
Invoke-RoboConfig -ConfigFile $configFile -ContinueAfterReboot -RunInBackground:$RunInBackground -Verbose *>&1 | Out-LogEntry -Date
