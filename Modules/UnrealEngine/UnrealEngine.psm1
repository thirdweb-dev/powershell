using module .\Helpers.psm1

enum Platforms
{
    Win64
    Android
    Linux
    LinuxArm64
}

class UnrealEngine
{
    [Version] $Version
    [string] $Path

    UnrealEngine([string]$InVersion, [string]$InPath)
    {
        try
        {
            $this.Version = [Version]::new($InVersion)
        }
        catch
        {
            throw "UnrealEngine::Invalid Engine Version::$InVersion"
        }
        $this.Path = $InPath
    }

    [UnrealEngine[]]
    static GetAvailableVersions()
    {
        $tags = git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' git@github.com:EpicGames/UnrealEngine.git

        # Get unique tags, optionally filter out previews
        $uniqueTags = $tags |
                ForEach-Object { ($_ -split '\s+')[1] } |
                Where-Object { -not $_.EndsWith('^{}') } |
                Where-Object { $_.StartsWith('5.') } |
                ForEach-Object { $_ -replace '^refs/tags/', '' } |
                Where-Object { $_.ToLower().Contains('release') } |
                ForEach-Object { $_ -replace '-release', '' } |
                Sort-Object -Unique

        return $uniqueTags | ForEach-Object { [UnrealEngine]::new($_, "") }
    }

    [UnrealEngine[]]
    static GetSourceEngines([string]$Path)
    {
        if (-not (Test-Path $Path))
        {
            Write-Message -Warn "Source directory '$Path' does not exist."
            return @()
        }

        $childFolders = Get-ChildItem -Path $Path -Directory

        if (-not $childFolders)
        {
            Write-Message -Warn "No installed Unreal Engine versions found in '$Path'."
            return @()
        }

        $installedEngines = foreach ($folder in $childFolders)
        {
            try
            {
                $folderVersion = [Version]::Parse($folder.Name)
                [UnrealEngine]::new($folderVersion, $folder.FullName)
            }
            catch
            {
                Write-Message -Warn "Invalid engine version folder: '$( $folder.Name )'"
            }
        }

        return $installedEngines | Sort-Object { $_.Version } -Descending
    }

    [string]
    GetVersionString([bool]$StripPatch)
    {
        if ($StripPatch) {
            return "{0}.{1}" -f $this.Version.Major, $this.Version.Minor
        }
        return $this.Version.ToString()
    }

    [string]
    GetVersionString()
    {
        return $this.GetVersionString($false)
    }
}

function Get-AvailableUnrealEngineVersions
{
    [UnrealEngine]::GetAvailableVersions() | Format-Table
}

function Set-UnrealEngineRoot
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $ue4Command = Get-Command "ue4" -ErrorAction SilentlyContinue
    if ($null -eq $ue4Command)
    {
        Write-Message -Err "ue4cli not installed"
        Write-Message -Err "Installation instructions at: https://docs.adamrehn.com/ue4cli/overview/introduction-to-ue4cli"
        break Script
    }

    $CurrentPath = ue4 root 2> $null
    if ($Path -ne $CurrentPath)
    {
        ue4 setroot $Path 2> $null
        Write-Message "Set unreal engine root to $Path"
    }
}
