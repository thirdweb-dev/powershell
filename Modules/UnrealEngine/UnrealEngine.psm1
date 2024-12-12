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

    UnrealEngine([string]$version, [string]$path)
    {
        $this.Version = [Version]::new($version)
        $this.Path = $path
    }


    [UnrealEngine[]]
    static GetAvailableVersions()
    {
        $tags = git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' git@github.com:EpicGames/UnrealEngine.git

        # Get unique tags, optionally filter out previews
        $uniqueTags = $tags |
                ForEach-Object { ($_ -split '\s+')[1] } |
                Where-Object { -not $_.EndsWith('^{}') } |
                ForEach-Object { $_ -replace '^refs/tags/', '' } |
                Where-Object { $_.ToLower().Contains('release') } |
                ForEach-Object { $_ -replace '-release', '' } |
                Sort-Object -Unique

        return $uniqueTags | ForEach-Object { [UnrealEngine]::new($_, "") }
    }
}

function Get-AvailableUnrealEngineVersions
{

    [UnrealEngine]::GetAvailableVersions() | Format-Table
}
