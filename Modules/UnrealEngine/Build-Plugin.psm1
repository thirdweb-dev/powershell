using module .\UnrealEngine.psm1
using module .\Helpers.psm1
using module .\Clang.psm1

<#
.SYNOPSIS
Builds and manages Unreal Engine plugins across multiple platforms and engine versions.

.DESCRIPTION
The `Build-Plugin` function automates the process of compiling and packaging a plugin for different Unreal Engine versions and target platforms. The function allows users to specify engine versions, target platforms, output directories, and additional options for host binaries and reverse processing. It also provides functionality to save engine paths and list installed engine versions.

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
        Write-Message -Err ($ErrorMessages.InvalidPluginDir -f $ParamType)
        Write-Message -Err "Attempted to check these folders and their parents:"
        foreach ($PossiblePlugindDirectory in $PossiblePlugindDirectories)
        {
            Write-Message -Err $PossiblePlugindDirectory
        }
        Break Script
    }

    function Set-UnrealEngineRoot
    {
        param ([string]$DesiredRoot)

        if (-not $DesiredRoot)
        {
            Write-Message -Err "Error: No Unreal Engine root path set"
            Break Script
        }

        $ue4Command = Get-Command "ue4" -ErrorAction SilentlyContinue
        if ($null -eq $ue4Command)
        {
            Write-Message -Err "Error: ue4cli not installed"
            Write-Message -Err "Installation instructions at: https://docs.adamrehn.com/ue4cli/overview/introduction-to-ue4cli"
            Break Script
        }

        $currentRoot = ue4 root 2> $null
        if ($DesiredRoot -ne $currentRoot)
        {
            ue4 setroot $DesiredRoot 2> $null
        }
    }

    $Configuration = [Config]::Load()

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
        Write-Message -Err $ErrorMessages.NoEngineVersionsSaved
        Write-Message -Err $ErrorMessages.AddEngineVersions
        Write-Message -Err $ErrorMessages.SaveCommandExample
        Break Script
    }

    foreach ($Version in $Versions)
    {
        Write-Message "Building Plugin for UE_$Version"

        if (-not $Configuration.HasVersion($Version))
        {
            Write-Message -Err "Error: No engine path saved for $Version"
            continue
        }

        Set-UnrealEngineRoot($Configuration.GetVersionPath($Version))
        if ( $TargetPlatforms.Contains([Platforms]::Linux))
        {
            Install-Clang -EngineVersion $Version
        }

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

        if (0 -ne $BuildPluginProcess.ExitCode)
        {
            Write-Message -Err "Plugin build failed, exiting..."
            Break Script
        }
        Write-Message "Build completed successfully for $Version"

        $DestinationPath = $FullDestination + ".zip"
        $ExcludedZipFolders = @()
        if (!($IncludeHostBinaries))
        {
            $ExcludedZipFolders += "Intermediate"
            $ExcludedZipFolders += "Binaries"
        }
        Get-ChildItem -Path $FullDestination | Where-Object { -not ($_.PSIsContainer -and ($ExcludedZipFolders -contains $_.Name)) } | Compress-Archive -DestinationPath ($FullDestination + ".zip") -Force
        Write-Message "Compressed Zip created! $DestinationPath"
    }
}
