using module .\Helpers.psm1
using module .\UnrealEngine.psm1
using module .\Clang.psm1

class Config
{
    [UnrealEngine[]] $Engines
    [string] $SourceDirectory
    [bool] $Loaded

    Config()
    {
        $this.Engines = @()
        $this.Loaded = $false
    }

    Config([bool]$Load)
    {
        if ($Load)
        {
            $Config = [Config]::Load()
            $this.Engines = $Config.Engines
            $this.SourceDirectory = $Config.SourceDirectory
            $this.Loaded = $true
        }
        else
        {
            $this.Engines = @()
            $this.Loaded = $false
        }
    }

    [void]
    AddUnrealEngine([UnrealEngine]$Engine)
    {
        if ( $this.HasUnrealEngineVersion($Engine.Version))
        {
            Write-Message -Warn "$( $Engine.Version ) already saved for $( $Engine.Path )"
            return
        }
        $this.Engines += $Engine
    }

    [bool]
    HasUnrealEngineVersion([string]$Version)
    {
        $AllVersions = $this.GetAllUnrealEngineVersions()
        ForEach ($EngineVersion in $AllVersions)
        {
            if ( $Version.ToString().StartsWith($Version))
            {
                return $true
            }
        }
        return $false
    }

    [string]
    GetUnrealEnginePath([string]$Version)
    {
        $AllEngines = $this.GetAllUnrealEngines()
        if (0 -eq $AllEngines.Count)
        {
            Write-Message -Err "No available engine versions to search."
            return ""
        }
        ForEach ($Engine in $AllEngines)
        {
            if ( $Engine.Version.ToString().StartsWith($Version))
            {
                return $Engine.Path
            }
        }
        Write-Message -Err "No engine version matched $Version"
        return ""
    }

    # Unreal Engine

    [UnrealEngine[]]
    GetSourceUnrealEngines()
    {
        return [UnrealEngine]::GetSourceEngines($this.SourceDirectory)
    }

    [UnrealEngine[]]
    GetCustomUnrealEngines()
    {
        $Existing = $( )
        foreach ($Engine in $this.Engines)
        {
            if (TestPath -Path $Engine.Path)
            {
                $Existing += $Engine
            }
        }
        return $Existing
    }

    [UnrealEngine[]]
    GetAllUnrealEngines()
    {
        $SourceEngines = $this.GetSourceUnrealEngines()
        $CustomEngines = $this.GetCustomUnrealEngines()
        $AllEngines = @()
        foreach ($Engine in $SourceEngines)
        {
            if ($Engine)
            {
                $AllEngines += $Engine
            }
        }
        foreach ($Engine in $CustomEngines)
        {
            if ($Engine)
            {
                $AllEngines += $Engine
            }
        }
        return $AllEngines
    }

    [Version[]]
    GetAllUnrealEngineVersions()
    {
        $AllEngines = $this.GetAllUnrealEngines()
        $Result = $( foreach ($Engine in $AllEngines)
        {
            $Engine.Version
        } ) | Sort-Object
        return $Result
    }

    [string[]]
    GetAllUnrealEngineStringVersions([bool]$StripPatchVersion, [bool]$Reverse)
    {
        $AllVersions = $this.GetAllUnrealEngineVersions()
        $StringVersions = $( foreach ($Version in $AllVersions)
        {
            if ($StripPatchVersion)
            {
                "{0}.{1}" -f $Version.Major, $Version.Minor
            }
            else
            {
                $Version.ToString()
            }
        } ) | Sort-Object
        if (-not $Reverse)
        {
            [array]::Reverse($StringVersions)
        }
        return $StringVersions
    }

    [string[]]
    GetAllUnrealEngineStringVersions()
    {
        return $this.GetAllUnrealEngineStringVersions($false, $false)
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
            try
            {
                [string]$DefaultJson = ([Config]::new() | ConvertTo-Json -Depth 2)
                New-Item -Path ([Config]::FilePath()) -ItemType "File" -Value $DefaultJson
            }
            catch
            {
                Write-Message -Error "Failed to create the config file at [Config]::FilePath()."
                return $null
            }
        }

        # Deserialize configuration from JSON
        $JsonContent = Get-Content -Path ([Config]::FilePath()) | ConvertFrom-Json
        $Config = [Config]::new()
        $JsonContent.Engines | ForEach-Object {
            $Config.AddUnrealEngine([UnrealEngine]::new($_.Version, $_.Path))
        }
        $Config.SourceDirectory = $JsonContent.SourceDirectory
        $Config.Loaded = $true
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
        $this.Engines | Format-Table
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

function Add-CustomEngineVerion
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try
    {
        $EngineVersion = [Version]::new($Version)
    }
    catch
    {
        Write-Message -Fatal "Invalid Engine Version '$Version'"
    }

    if (-not (Test-Path -Path $Path))
    {
        Write-Message -Fatal "Invalid Engine Path '$Path'"
    }
    $Config = [Config]::Load()
    $Config.AddUnrealEngine([UnrealEngine]::new($Version, $Path))
    $Config.Save()
}
