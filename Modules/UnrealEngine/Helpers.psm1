function Write-Message
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Message,
        [switch]$Warn = $false,
        [switch]$Err = $false,
        [switch]$Fatal = $false
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
    if ($Err)
    {
        $Color = "Red"
        $Prefix = "ERROR"
    }
    if ($Fatal)
    {
        $Color = "Red"
        $Prefix = "FATAL"
    }

    Write-Host "[$Prefix]" $Message -ForegroundColor $Color

    if ($Fatal)
    {
        break Script
    }
}

function Start-Executable
{
    param(
        [string]$FileName,
        [string]$Arguments,
        [string]$WorkingDirectory
    )
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    if (Test-Path $FileName)
    {
        $processInfo.FileName = (Resolve-Path $FileName).Path
    }
    else
    {
        $Location = where.exe git
        $processInfo.FileName = $Location
    }

    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.UseShellExecute = $false
    $processInfo.Arguments = $Arguments
    if ($WorkingDirectory)
    {
        $processInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    return [PSCustomObject]@{
        StdOut = $stdout
        StdErr = $stderr
        ExitCode = $exitCode
    }
}

function Update-ThirdwebModule
{
    $PSHomePath = Join-Path -Path $HOME -ChildPath "Documents\PowerShell"
    $PSModulesPath = Join-Path -Path $PSHomePath -ChildPath "Modules"
    $ThirdwebModuleDirectoryPath = Join-Path -Path $PSModulesPath -ChildPath "Thirdweb"

    Write-Message "Checking for updates..."
    $GitFetch = Start-Executable "git" `
        -Arguments "fetch" `
        -WorkingDirectory $ThirdwebModuleDirectoryPath

    if (0 -ne $GitFetch.ExitCode)
    {
        throw "Failed to fetch status from github."
    }

    $GitStatus = Start-Executable "git" `
        -Arguments "status" `
        -WorkingDirectory $ThirdwebModuleDirectoryPath

    if (0 -ne $GitStatus.ExitCode)
    {
        throw "Failed to read current module status"
    }

    elseif ($GitStatus.StdOut -match "Your branch is behind")
    {
        Write-Host "Updating Thirdweb PowerShell module..." -ForegroundColor Blue
        $GitPull = Start-Executable "git" `
            -Arguments "pull" `
            -WorkingDirectory $ThirdwebModuleDirectoryPath

        if (0 -ne $GitPull.ExitCode)
        {
            throw "Failed to update Thirdweb PowerShell module"
        }
        Write-Host "Thirdweb PowerShell module updated!" -ForegroundColor Green
    }
    elseif ($GitStatus.StdOut -match "up to date")
    {
        Write-Host "Thirdweb PowerShell module is already up to date" -ForegroundColor Blue
    }
    else
    {
        throw "Could not determine the current status of the module"
    }

    $ThirdwebModuleImportLines = @"
# Thirdweb Module
Import-Module '$ThirdwebModulePath'
"@

    $PSProfileContent = Get-Content -Path $PSProfilePath -Raw

    if ($PSProfileContent -notlike "*# Thirdweb Module*")
    {
        Add-Content -Path $PSProfilePath -Value $ThirdwebModuleImportLines
        Write-Host "Added Thirdweb Module to Profile via Import" -ForegroundColor Blue
        Write-Host "To use, either close and reopen the terminal, or type . `$Profile" -ForegroundColor Blue
    }
}
