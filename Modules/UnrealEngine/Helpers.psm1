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
