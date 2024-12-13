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
