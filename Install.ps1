$PSHomePath = Join-Path -Path $HOME -ChildPath "Documents\PowerShell"
$PSModulesPath = Join-Path -Path $PSHomePath -ChildPath "Modules"
$ThirdwebModuleDirectoryPath = Join-Path -Path $PSModulesPath -ChildPath "Thirdweb"
$ThirdwebModulePath = Join-Path -Path $ThirdwebModuleDirectoryPath -ChildPath "Modules\Thirdweb.psd1"
$PSProfilePath = Join-Path -Path $PSHomePath -ChildPath "Microsoft.PowerShell_profile.ps1"

$ThirdwebModuleGitRepo = "git@github.com:thirdweb-dev/powershell.git"

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

    $StdOut = $process.StandardOutput.ReadToEnd()
    $StdErr = $process.StandardError.ReadToEnd()
    $ExitCode = $process.ExitCode

    return [PSCustomObject]@{
        StdOut = $StdOut
        StdErr = $StdErr
        ExitCode = $ExitCode
    }
}

if (-not (Test-Path -Path $PSModulesPath))
{
    Write-Host "Creating PowerShell modules directory..." -ForegroundColor Blue
    New-Item -Path $PSModulesPath -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -Path $ThirdwebModulePath))
{
    Write-Host "Creating PowerShell profile..." -ForegroundColor Blue
    New-Item -Path $PSProfilePath -ItemType File -Force | Out-Null
}

If (Test-Path -Path $ThirdwebModuleDirectoryPath)
{
    Write-Host "Checking for updates..." -ForegroundColor Blue
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
}
else
{
    Write-Host "Installing Thirdweb PowerShell module..." -ForegroundColor Blue
    $GitClone = Start-Executable "git" `
        -Arguments "clone $ThirdwebModuleGitRepo Thirdweb" `
        -WorkingDirectory "$PSModulesPath"

    if (0 -ne $GitClone.ExitCode)
    {
        throw "Failed to clone module from github"
    }
    Write-Host "Thirdweb PowerShell module installed successfully!" -ForegroundColor Green
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
