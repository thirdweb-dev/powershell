using module .\Helpers.psm1
using module .\UnrealEngine.psm1
using module .\Clang.psm1

class Config
{
    [UnrealEngine[]] $Engines
    [string] $SourceDirectory

    Config()
    {
        $this.Engines = @()
    }

    [void]
    AddEngine([UnrealEngine]$Engine)
    {
        if ($this.hasVersion($Engine.Version))
        {
            Write-Message -Warn "$($Engine.Version) already saved for $($Engine.Path)"
            return
        }
        $this.Engines += $Engine
    }

    [bool]
    HasVersion([string]$Version)
    {
        ForEach ($Engine in $this.Engines)
        {
            if ( $Engine.Version.ToString().StartsWith($Version))
            {
                return $true
            }
        }
        return $false
    }

    [string]
    GetVersionPath([string]$Version)
    {
        if (-not $this.Engines -or $this.Engines.Count -eq 0) {
            Write-Message -Warn "No available engine versions to search."
            return ""
        }
        ForEach ($Engine in $this.Engines)
        {
            if ( $Engine.Version.ToString().StartsWith($Version))
            {
                return $Engine.Path
            }
        }
        return ""
    }


    [string[]]
    GetAllVersions([bool]$Reverse)
    {
        $Result = @()
        foreach ($Engine in $this.Engines)
        {
            $Result += $Engine.Version
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

    [string]
    static FilePath()
    {
        $ProfilePath = (New-Object -ComObject Shell.Application).NameSpace('shell:Profile').Self.Path
        return Join-Path -Path $ProfilePath -ChildPath ".thirdweb-powershell.json"
    }

    [Config]
    static Load()
    {
        if (-not (Test-Path -Path ([Config]::FilePath())))
        {
            Write-Message "Creating config file..."
            try {
                [string]$DefaultJson = ([Config]::new() | ConvertTo-Json -Depth 2)
                New-Item -Path ([Config]::FilePath()) -ItemType "File" -Value $DefaultJson
            } catch {
                Write-Message -Error "Failed to create the config file at [Config]::FilePath()."
                return $null
            }
        }

        # Deserialize configuration from JSON
        $JsonContent = Get-Content -Path ([Config]::FilePath()) | ConvertFrom-Json
        $Config = [Config]::new()
        $JsonContent.Engines | ForEach-Object {
            $Config.AddEngine([UnrealEngine]::new($_.Version, $_.Path))
        }
        $Config.SourceDirectory = $JsonContent.SourceDirectory
        return $Config
    }

    SetSourceDirectory([string]$Path)
    {
        $this.SourceDirectory = $Path
    }

    Save()
    {
        Write-Message "Saving config"
        $this | ConvertTo-Json -Depth 5 | Set-Content -Path ([Config]::FilePath())
    }

    List()
    {
        Write-Message "Engine Versions:"
        foreach ($Engine in $this.Engines)
        {
            Write-Message "$( $Engine.Version ) $( $Engine.Path )"
        }
    }


}

function Set-ConfigSourceDirectory
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $Config = [Config]::Load()
    $Config.SetSourceDirectory($Path)
    $Config.Save()
}

function Get-ConfigSourceDirectory
{
    Write-Host ([Config]::Load()).SourceDirectory
}

function Get-InstalledEngineVersions
{
    param (
        [string]$SourceDirectory = $null
    )

    if (-not $SourceDirectory)
    {
        # Load source directory from the config as a fallback
        $Config = [Config]::Load()
        $SourceDirectory = $Config.SourceDirectory
    }

    if (-not (Test-Path $SourceDirectory))
    {
        Write-Message -Warn "Source directory '$SourceDirectory' does not exist."
        return @()
    }

    # Get child directories (engine folders)
    $childFolders = Get-ChildItem -Path $SourceDirectory -Directory

    if (-not $childFolders)
    {
        Write-Message -Warn "No installed Unreal Engine versions found in '$SourceDirectory'."
        return @()
    }

    $installedEngines = foreach ($folder in $childFolders)
    {
        try
        {
            # Parse folder name into a [Version] object
            $folderVersion = [Version]::Parse($folder.Name)
            # Detect corresponding Clang version
            $clangVersion = try
            {
                $clang = [Clang]::FromEngineVersion($folderVersion)
                $clang.Version.ToString()  # Clang version as string
            }
            catch
            {
                "N/A"  # If no Clang version is found or an error occurs
            }

            # Create UnrealEngine object and add ClangVersion
            $engine = [UnrealEngine]::new($folderVersion, $folder.FullName)
            $engine | Add-Member -MemberType NoteProperty -Name "Clang" -Value $clangVersion
            $engine
        }
        catch
        {
            # Handle invalid folder names gracefully
            Write-Message -Warn "Invalid engine version folder: '$( $folder.Name )'"
        }
    }

    # Reverse sort the UnrealEngine objects by their Version
    $sortedEngines = $installedEngines | Sort-Object { $_.Version } -Descending

    # Output the sorted list with ClangVersion
    Write-Message "Installed Engine Versions"
    $sortedEngines | Format-Table Version, Path, Clang
}

function Add-SourceEngineVerion
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if ('All' -eq $SpecifiedEngineVersions[0])
    {
        Write-Message -Err "Error: No engine version specified"
        Break Script
    }
    $Config = [Config]::Load()
    $Config.AddEngine([UnrealEngine]::new($Version, $Path))
    $Config.Save()
}
