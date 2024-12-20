using module .\Helpers.psm1

enum ClangOS
{
    centos7
    rockylinux8
}

class Clang
{
    [string]$Release     # Example: "v19"
    [Version]$Version    # Example: "11.0.1"
    [Version[]]$Engines  # Example: "5.0"
    [ClangOS]$OS         # Example: "centos7"

    # Constructor to initialize the properties
    Clang([string]$release, [string]$version, [ClangOS]$os, [string[]]$engines)
    {
        try
        {
            $this.Version = [Version]::new($version)
        }
        catch
        {
            throw "Clang::Init::Invalid Clang Version '$version'"
        }

        $this.Release = $release
        foreach ($engine in $engines)
        {
            try
            {
                $this.Engines += [Version]::new($engine)
            }
            catch
            {
                throw "Clang::Init::Invalid Engine Version '$engine'"
            }

        }
        $this.OS = $os
    }

    # Method to construct the built folder name based on properties
    [string]
    GetFolderName()
    {
        return "{0}_clang-{1}-{2}" -f $this.Release, $this.Version, $this.OS
    }

    [string]
    GetInstallPath()
    {
        return Join-Path -Path "C:\UnrealToolchains" -ChildPath $this.GetFolderName()
    }

    [string]
    GetDownloadUrl()
    {
        return "https://cdn.unrealengine.com/CrossToolchain_Linux/{0}.exe" -f $this.GetFolderName()
    }

    [string]
    GetDownloadPath()
    {
        $DownloadsDir = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        $Filename = $this.GetFolderName() + ".exe"
        return Join-Path -Path $DownloadsDir -ChildPath $Filename
    }

    SetEnv()
    {
        $env:LINUX_MULTIARCH_ROOT = $this.GetInstallPath()
        Write-Message "Set Clang to $($this.GetInstallPath() )"
    }

    [boolean]
    IsInstalled()
    {
        return Test-Path -Path $this.GetInstallPath()
    }

    Install()
    {
        Write-Message "Downloading $($this.GetFolderName() ).exe to $($this.GetDownloadPath() )"
        Invoke-WebRequest -Uri $this.GetDownloadUrl() -OutFile $this.GetDownloadPath()

        $ClangInstallerProcess = Start-Process -FilePath $this.GetDownloadPath() -Wait -PassThru
        if (0 -ne $ClangInstallerProcess.ExitCode)
        {
            Write-Message -Fatal "Clang installation failed, exiting..."
        }
    }

    [Clang[]]
    static GetSupportedVersions()
    {
        return @(
            [Clang]::new("v23", "18.1.0", [ClangOS]::rockylinux8, @("5.5.0")),
            [Clang]::new("v22", "16.0.6", [ClangOS]::centos7, @("5.4.0", "5.3.0")),
            [Clang]::new("v21", "15.0.1", [ClangOS]::centos7, @("5.2.0")),
            [Clang]::new("v20", "13.0.1", [ClangOS]::centos7, @("5.1.0")),
            [Clang]::new("v19", "11.0.1", [ClangOS]::centos7, @("5.0.0"))
        )
    }


    [Clang]
    static FromEngineVersion([string]$EngineVersion)
    {
        # Normalize the input EngineVersion to "major.minor" (ignore patch or prerelease data)
        $NormalizedVersionString = ($EngineVersion -split '[.-]')[0..1] -join '.'
        $NormalizedVersion = [Version]::new("$NormalizedVersionString$( ".0" )")
        # Find Clang version(s) that support the given Unreal Engine version
        $matchedClang = [Clang]::GetSupportedVersions() | Where-Object {
            $_.Engines -contains $normalizedVersion
        }

        if ($matchedClang.Count -eq 0)
        {
            $AvailableVersions = ([Clang]::GetSupportedVersions() | ForEach-Object { $_.Engines }) -join ", "
            Write-Message -Fatal "No engine versions found matching '$NormalizedVersion'. Available engine versions are: $AvailableVersions. Ensure the major and minor version match an available engine version."
        }
        elseif ($matchedClang.Count -gt 1)
        {
            Write-Message -Fatal "Multiple Clang versions found for engine version '$NormalizedVersion'. Specify a more accurate pattern."
        }
        else
        {
            return $matchedClang[0]
        }
        throw "Something went wrong..."
    }

    [Clang]
    static FromEngineVersion([Version]$version)
    {
        return FromEngineVersion($version.ToString())
    }
}

function Install-Clang
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EngineVersion
    )
    if (-not $Clang.IsInsatalled())
    {
        $Clang = [Clang]::FromEngineVersion($EngineVersion)
        Write-Message "Installing Clang $($Clang.GetFolderName() )"
        $Clang.Install()
    }
    else
    {
        Write-Message "Clang $($Clang.GetFolderName() ) already installed"
    }
}

function Set-Clang
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EngineVersion
    )

    $Clang = [Clang]::FromEngineVersion($EngineVersion)

    if (-not $Clang.IsInstalled())
    {
        Add-Type -AssemblyName 'PresentationFramework'

        $caption = "Missing Clang Toolchain"
        $message = "You do not have the Clang Cross-Compile Toolchain installed for UE v{0}. (Clang {1}). Install?" -f $EngineVersion,$Clang.GetFolderName()
        $response = [System.Windows.MessageBox]::Show($message, $caption, 'YesNo')

        if ('No' -eq $response)
        {
            Write-Message -Fatal "Error: Automatic Installation denied. Download from $($Clang.GetDownloadUrl() ) and retry."
        }
        $Clang.Install()
    }
    $env:LINUX_MULTIARCH_ROOT = $Clang.GetInstallPath()

    Write-Message "Set Clang to $($Clang.GetInstallPath() )"
}
