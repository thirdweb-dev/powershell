$PSHomePath = Join-Path -Path $HOME -ChildPath "Documents\PowerShell"
$PSModulesPath = Join-Path -Path $PSHomePath -ChildPath "Modules"
$ThirdwebModuleDirectoryPath = Join-Path -Path $PSModulesPath -ChildPath "Thirdweb"
$ThirdwebModulePath = Join-Path -Path $ThirdwebModuleDirectoryPath -ChildPath "Thirdweb.psm1"
$PSProfilePath = Join-Path -Path $PSHomePath -ChildPath "Microsoft.PowerShell_profile.ps1"

$ThirdwebModuleGitRepo = "git@github.com:thirdweb-dev/powershell.git"

if (-not (Test-Path -Path $PSModulesPath))
{
    Write-Host "Creating PowerShell modules directory..." -ForegroundColor Blue
    New-Item -Path $PSModulesPath -ItemType Directory -Force
}

if (-not (Test-Path -Path $ThirdwebModulePath))
{
    Write-Host "Creating PowerShell profile..." -ForegroundColor Blue
    New-Item -Path $PSProfilePath -ItemType File -Force
}

If (Test-Path -Path $ThirdwebModuleDirectoryPath)
{
    Write-Host "Checking for updates..." -ForegroundColor Blue
    $GitFetchProcess = Start-Process "git" `
        -ArgumentList "fetch" `
        -WorkingDirectory $ThirdwebModuleDirectoryPath `
        -NoNewWindow `
        -RedirectStandardOutput `
        -Wait `
        -PassThru

    if (0 -ne $GitFetchProcess.ExitCode)
    {
        throw "Failed to fetch status from github."
    }
    
    $GitStatusProcess = Start-Process "git" `
        -ArgumentList "status" `
        -WorkingDirectory $ThirdwebModuleDirectoryPath `
        -NoNewWindow `
        -RedirectStandardOutput `
        -Wait `
        -PassThru
    $GitStatusResult = $GitStatusProcess.StandardOutput.ReadToEnd()

    if (0 -ne $GitStatusProcess.ExitCode)
    {
        throw "Failed to read current module status"
    }
    elseif ($GitStatusResult -match "Your branch is behind")
    {
        Write-Host "Updating Thirdweb PowerShell module..." -f ForegroundColor Blue
        $GitPullProcess = Start-Process "git" `
            -ArgumentList "pull" `
            -WorkingDirectory $ThirdwebModuleDirectoryPath `
            -NoNewWindow `
            -RedirectStandardOutput `
            -Wait `
            -PassThru

        if (0 -ne $GitPullProcess.ExitCode)
        {
            throw "Failed to update Thirdweb PowerShell module"
        }
        Write-Host "Thirdweb PowerShell module updated!" -ForegroundColor Green
    } elseif ($GitStatusResult -match "up to date") {
        Write-Host "Thirdweb PowerShell module is already up to date" -ForegroundColor Blue
    } else {
        throw "Could not determine the current status of the module"
    }
}
else
{
    Write-Host "Installing Thirdweb PowerShell module..." -ForegroundColor Blue 
    $GitCloneProcess = Start-Process git `
        -ArgumentList "clone $ThirdwebModuleGitRepo Thirdweb" `
        -WorkingDirectory "$PSModulesPath" `
        -Wait `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput `

    if (0 -ne $GitCloneProcess.ExitCode)
    {
        throw "Failed to clone module from github"
    }
    Write-Host "Thirdweb PowerShell module installed successfully!" -ForegroundColor Green
}

$ThirdwebModuleImportLines = @"

# Thirdweb Module
Import-Module '$ThirdwebModulePath'

"@

$PSProfileContent = Get-Content -Path $PSProfilePath -ErrorAction SilentlyContinue

if ($PSProfileContent -notcontains $ThirdwebModuleImportLines) {
    Add-Content -Path $PSProfilePath -Value $ThirdwebModuleImportLines
    Write-Host "Added Thirdweb Module to Profile via Import" -ForegroundColor Blue
    Write-Host "To use, either close and reopen the terminal, or type `. $Profile" -ForegroundColor Blue
}
