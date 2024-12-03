<#
.SYNOPSIS
Builds and manages Unreal Engine plugins across multiple platforms and engine versions.

.DESCRIPTION
The `Build-Plugin` function automates the process of compiling and packaging a plugin for different Unreal Engine versions and target platforms. The function allows users to specify engine versions, target platforms, output directories, and additional options for host binaries and reverse processing. It also provides functionality to save engine paths and list installed engine versions.

.PARAMETER OperationMode
Specifies the operation mode. Acceptable values are:
- Build: Compiles and packages the plugin for specified engine versions and platforms.
- Save: Saves the specified engine version and path to configuration.
- List: Lists all saved Unreal Engine installations.

.PARAMETER SpecifiedEngineVersions
An array of Unreal Engine versions to process. Default is 'All', which processes all saved engine versions.

.PARAMETER TargetPlatforms
An array of platforms to target during the build process. Defaults to Windows 64-bit, Android, Linux, and Linux ARM64.

.PARAMETER OutputDirectory
Specifies the output directory where the plugin packages will be saved. Defaults to the user's Downloads folder.

.PARAMETER PluginDirectory
The directory containing the plugin to be processed. If not specified, the script directory is used.

.PARAMETER EngineInstallationPath
The installation path of the specified Unreal Engine version. This is only used when saving a new engine version.

.PARAMETER IncludeHostBinaries
A switch to include host binaries in the package. If not specified, host binaries will not be included.

.PARAMETER ProcessInReverseOrder
A switch to process the saved engine versions in reverse order.

.EXAMPLE
Build-Plugin Build -SpecifiedEngineVersions '5.5' -TargetPlatforms 'Win64'

Builds the plugin for Unreal Engine version 5.5 targeting Windows 64-bit.

.EXAMPLE
Build-Plugin Save -SpecifiedEngineVersions '5.5' -EngineInstallationPath 'C:\Program Files\Epic Games\UE_5.5'

Saves the specified Unreal Engine version and installation path to the configuration.

.EXAMPLE
Build-Plugin List

Lists all saved Unreal Engine installations.

.NOTES
    Author: Nicholas St. Germain
    Created: 2024-03-20
    Dependencies: This script requires the ue4cli for CLI management of Unreal Engine tasks.
    Note: Ensure the appropriate Clang cross-compilation toolchains are installed for Linux target builds.
#>
function Build-Plugin
{
    [CmdletBinding()]
    param (
        [Actions]$OperationMode = [Actions]::Build,
        [string[]]$SpecifiedEngineVersions = 'All',
        [Platforms[]]$TargetPlatforms = @([Platforms]::Win64, [Platforms]::Android, [Platforms]::Linux, [Platforms]::LinuxArm64),
        [string]$OutputDirectory = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path,
        [string]$PluginDirectory,
        [string]$EngineInstallationPath,
        [switch]$IncludeHostBinaries = $false,
        [switch]$ProcessInReverseOrder = $false
    )

    Add-Type -AssemblyName 'PresentationFramework'

    $ErrorMessages = @{
        InvalidPluginDir = "ERROR: {0} PluginDirectory override specified. No .uplugin file found."
        NoUpluginFile = "ERROR: No .uplugin file found using default Script directory ({0}). Exiting..."
        NoEngineVersionsSaved = "Error: No Engine versions saved in config"
        AddEngineVersions = "Add Engine versions via the save command"
        SaveCommandExample = "Example: BuildPlugin.ps1 save -EngineVersion 5.5 -EnginePath 'C:\Program Files\Epic Games\UE_5.5'"
    }

    $ClangFolders = @{
        "5.5" = "v23_clang-18.1.0-rockylinux8"
        "5.4" = "v22_clang-16.0.6-centos7"
        "5.3" = "v22_clang-16.0.6-centos7"
        "5.2" = "v21_clang-15.0.1-centos7"
        "5.1" = "v20_clang-13.0.1-centos7"
        "5.0" = "v19_clang-11.0.1-centos7"
    }
    function Get-UPluginPath
    {
        param ([string]$Path)
        $UPluginPath = Get-ChildItem -Path $Path -Filter *.uplugin -File -ErrorAction SilentlyContinue
        if ($null -eq $UPluginPath)
        {
            return ""
        }
        return $UPluginPath
    }
    function Find-ParentWithUPlugin
    {
        param ([string]$Path)
        while ($Path -ne "")
        {
            $UPluginPath = Get-UPluginPath -Path $Path;
            if ($UPluginPath -ne "")
            {
                return $Path
            }
            $Path = Split-Path -Path $Path -Parent
        }
        return $Path
    }
    function Initialize-PluginDirectory
    {
        $PossiblePlugindDirectories = @($PluginDirectory, $PSScriptRoot, (Get-Location).Path).Where({ $_ })
        foreach ($PossiblePlugindDirectory in $PossiblePlugindDirectories)
        {
            $PluginDir = Find-ParentWithUPlugin -Path $PossiblePlugindDirectory
            if ($PluginDir)
            {
                return $PluginDir
            }
        }
        $ParamType = "No"
        if ($PluginDirectory)
        {
            $ParamType = "Invalid"
        }
        Log-Message -Err ($ErrorMessages.InvalidPluginDir -f $ParamType)
        Log-Message -Err "Attempted to check these folders and their parents:"
        foreach ($PossiblePlugindDirectory in $PossiblePlugindDirectories)
        {
            Log-Message -Err $PossiblePlugindDirectory
        }
        Break Script
    }

    function Log-Message
    {
        param (
            [Parameter(Mandatory = $true)]
            [string[]]$Message,
            [switch]$Warn = $false,
            [switch]$Err = $false
        )

        $Color = "Blue"
        $Prefix = "INFO"
        if ($Debug)
        {
            $Color = "Gray"
            $Prefix = "DEBUG"
        }
        if ($Warn)
        {
            $Color = "Yellow"
            $Prefix = "WARN"
        }
        elseif ($Err)
        {
            $Color = "Red"
            $Prefix = "ERROR"
        }
        Write-Host "[$Prefix]" $Message -ForegroundColor $Color
    }

    function Configure-ClangEnvironment
    {
        param ([string]$Version)

        if ( $TargetPlatforms.Contains([Platforms]::Linux))
        {
            $env:LINUX_MULTIARCH_ROOT = "C:\UnrealToolchains\$( $ClangFolders[$Version] )\"

            if (-not (Test-Path -Path $env:LINUX_MULTIARCH_ROOT))
            {
                Prompt-ClangInstallation $Version
            }
            Log-Message "Set Clang to $env:LINUX_MULTIARCH_ROOT"
        }
        else
        {
            Log-Message "Not building for linux. Skipping Clang config."
        }
    }

    function Prompt-ClangInstallation
    {
        param([string]$Version)

        $caption = "You do not have the Clang Cross-Compile Toolchain installed for UE $Version. ($ClangFolders[$Version])"
        $message = "Do you want to install it now?:"
        $response = [System.Windows.MessageBox]::Show($message, $caption, 'YesNo')
        $ClangInstallerName = $ClangFolders[$Version] + ".exe"
        $ClangDownloadUrl = "https://cdn.unrealengine.com/CrossToolchain_Linux/" + $ClangInstallerName

        if ('No' -eq $response)
        {
            Log-Message -Err "Error: Clang toolchain not installed for UE $Version. Download from $ClangDownloadUrl and retry."
            Break Script
        }

        $DownloadsDir = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        $ClangInstallerPath = Join-Path -Path $DownloadsDir -ChildPath $ClangInstallerName
        Log-Message "Downloading $ClangInstallerName to $DownloadsDir"
        Invoke-WebRequest -Uri $ClangDownloadUrl -OutFile $ClangInstallerPath

        $ClangInstallerProcess = Start-Process -FilePath $ClangInstallerPath -Wait -PassThru
        if (0 -ne $ClangInstallerProcess.ExitCode)
        {
            Log-Message -Err "Clang installation failed, exiting..."
            Break Script
        }
    }

    function Set-UnrealEngineRoot
    {
        param ([string]$DesiredRoot)

        if (-not $DesiredRoot)
        {
            Log-Message -Err "Error: No Unreal Engine root path set"
            Break Script
        }

        $ue4Command = Get-Command "ue4" -ErrorAction SilentlyContinue
        if ($null -eq $ue4Command)
        {
            Log-Message -Err "Error: ue4cli not installed"
            Log-Message -Err "Installation instructions at: https://docs.adamrehn.com/ue4cli/overview/introduction-to-ue4cli"
            Break Script
        }

        $currentRoot = ue4 root 2> $null
        if ($DesiredRoot -ne $currentRoot)
        {
            ue4 setroot $DesiredRoot 2> $null
        }
    }

    $ConfigFilePath = Join-Path -Path (New-Object -ComObject Shell.Application).NameSpace('shell:Profile').Self.Path -ChildPath ".build-plugin.json"
    if (-not (Test-Path -Path $ConfigFilePath))
    {
        Log-Message "Creating config file..."
        $DefaultConfig = [Config]::new()
        $DefaultConfigContent = $DefaultConfig | ConvertTo-Json
        New-Item -Path $ConfigFilePath -ItemType "File" -Value $DefaultConfigContent
    }

    # Deserialize configuration from JSON
    $JsonContent = Get-Content -Path $ConfigFilePath | ConvertFrom-Json
    $Configuration = [Config]::new()
    $JsonContent.EngineInstalls | ForEach-Object {
        $Configuration.AddEngineInstall([EngineInstall]::new($_.Version, $_.Path))
    }

    switch ($OperationMode)
    {
        Build {

            $PluginDirectory = Initialize-PluginDirectory
            $UPluginPath = Get-UPluginPath -Path $PluginDirectory
            $UPlugin = Get-Content -Path $UPluginPath | ConvertFrom-Json

            $Versions = $SpecifiedEngineVersions
            if ('All' -eq $SpecifiedEngineVersions)
            {
                $Versions = $Configuration.GetAllVersions($ProcessInReverseOrder)
            }
            if (0 -eq $Versions.count)
            {
                Log-Message -Err $ErrorMessages.NoEngineVersionsSaved
                Log-Message -Err $ErrorMessages.AddEngineVersions
                Log-Message -Err $ErrorMessages.SaveCommandExample
                Break Script
            }

            foreach ($Version in $Versions)
            {
                Log-Message "Building Plugin for UE_$Version"

                if (-not $Configuration.HasVersion($Version))
                {
                    Log-Message -Err "Error: No engine path saved for $Version"
                    continue
                }

                Set-UnrealEngineRoot($Configuration.GetVersionPath($Version))
                Configure-ClangEnvironment -Version $Version

                $UPluginFriendlyName = ($UPlugin.FriendlyName -Split " ") -Join ""
                $FolderNameParts = @($UPluginFriendlyName, $UPlugin.VersionName)

                if ($IncludeHostBinaries)
                {
                    $FolderNameParts += "WithHost"
                }

                $FolderNameParts += $Version
                $FullDestination = Join-Path -Path $OutputDirectory -ChildPath ($FolderNameParts -join "-")
                $PlatformNames = $TargetPlatforms -join "+"

                $BuildArgs = @(
                    "package",
                    "-TargetPlatforms=`"$PlatformNames`"",
                    "-Package=`"$FullDestination`""
                )

                if (-not $IncludeHostBinaries)
                {
                    $BuildArgs += "-NoHostPlatform"
                }

                $BuildPluginProcess = Start-Process ue4 `
                    -Wait `
                    -NoNewWindow `
                    -PassThru `
                    -WorkingDirectory $PluginDirectory `
                    -ArgumentList $BuildArgs

                Log-Message "Build completed successfully for $Version"
                if (0 -ne $BuildPluginProcess.ExitCode)
                {
                    Log-Message -Err "Plugin build failed, exiting..."
                    Break Script
                }
                $DestinationPath = $FullDestination + ".zip"
                $ExcludedZipFolders = @("Intermediate", "Binaries")
                Get-ChildItem -Path $FullDestination | Where-Object { -not ($_.PSIsContainer -and ($ExcludedZipFolders -contains $_.Name)) } | Compress-Archive -DestinationPath ($FullDestination + ".zip") -Force
                Log-Message "Compressed Zip created! $DestinationPath"
            }
        }
        Save {
            if ('All' -eq $SpecifiedEngineVersions[0])
            {
                Log-Message -Err "Error: No engine version specified"
                Break Script
            }

            $Configuration.AddVersion($SpecifiedEngineVersions, $EngineInstallationPath)
            Log-Message "Saving $SpecifiedEngineVersions as $EngineInstallationPath"
            $Configuration | ConvertTo-Json | Set-Content -Path $ConfigFilePath
        }
        List {
            Log-Message "Engine Versions:"
            foreach ($Install in $Configuration.EngineInstalls)
            {
                Log-Message "$( $Install.Version ) $( $Install.Path )"
            }
        }
        default {
            Log-Message -Err "Invalid mode selected. Please choose either 'build', 'save', or 'list'."
            Break Script
        }
    }
}

class EngineInstall
{
    [string] $Version
    [string] $Path

    EngineInstall([string]$Version, [string]$Path)
    {
        $this.Version = $Version
        $this.Path = $Path
    }
}

class Config
{
    [EngineInstall[]] $EngineInstalls

    Config()
    {
        $this.EngineInstalls = @()
    }

    [void]
    AddEngineInstall([EngineInstall]$install)
    {
        $this.EngineInstalls += $install
    }

    [bool]
    HasVersion([string]$Version)
    {
        ForEach ($EngineInstall in $this.EngineInstalls)
        {
            if ( $EngineInstall.Version.StartsWith($Version))
            {
                return $true
            }
        }
        return $false
    }

    [string]
    GetVersionPath([string]$Version)
    {
        ForEach ($EngineInstall in $this.EngineInstalls)
        {
            if ( $EngineInstall.Version.StartsWith($Version))
            {
                return $EngineInstall.Path
            }
        }
        return ""
    }

    [void]
    AddVersion([string]$Version, [string]$Path)
    {
        if ( $this.hasVersion($Version))
        {
            Log-Message -Warn $Version already saved for $Path
            return
        }
        $newEngineInstall = [EngineInstall]::new($Version, $Path)
        $this.AddEngineInstall($newEngineInstall)
    }

    [string[]]
    GetAllVersions([bool]$Reverse)
    {
        $Installs = $this.EngineInstalls;
        $Result = @()
        foreach ($Install in $Installs)
        {
            $Result += $Install.Version
        }
        $Result = $Result | Sort-Object
        if (!($Reverse))
        {
            [array]::Reverse($Result)
        }
        return $Result
    }
    [string[]]
    GetAllVersions()
    {
        return $this.GetAllVersions($false)
    }
}

enum Actions
{
    Build
    Save
    List
}

enum Platforms
{
    Win64
    Android
    Linux
    LinuxArm64
}

Export-ModuleMember -Function Build-Plugin 
