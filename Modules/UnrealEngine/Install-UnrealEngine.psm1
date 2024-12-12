using module .\Helpers.psm1
using module .\Config.psm1

function Install-UnrealEngine
{
    [CmdletBinding()]
    param (
        [string]$Version,
        [string]$Path,
        [switch]$IncludePreviews = $false
    )


    if (-not $Path)
    {
        $Config = [Config]::Load()
        $Path = $Config.SourceDirectory
    }

    $UERepo = "git@github.com:EpicGames/UnrealEngine.git"
    # If no version is specified, retrieve tags and prompt user selection
    if (-not $Version)
    {
        $tags = git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' $UERepo

        # Get unique tags, optionally filter out previews
        $uniqueTags = $tags |
                ForEach-Object { ($_ -split '\s+')[1] } |
                Where-Object { -not $_.EndsWith('^{}') } |
                ForEach-Object { $_ -replace '^refs/tags/', '' } |
                Sort-Object -Unique

        # Filter out preview versions if the -IncludePreviews switch is not set
        if (-not $IncludePreviews)
        {
            $uniqueTags = $uniqueTags | Where-Object { -not $_.ToLower().Contains('preview') }
        }

        # Prompt the user to select a version
        Write-Message "Available Unreal Engine versions:"
        for ($i = 0; $i -lt $uniqueTags.Count; $i++) {
            Write-Message "$( $i + 1 ): $( $uniqueTags[$i] )"
        }

        $selection = Read-Host "Select a version (enter the corresponding number)"
        if ($selection -and $selection -as [int] -and ($selection -gt 0 -and $selection -le $uniqueTags.Count))
        {
            $Version = @($uniqueTags[$selection - 1])
        }
        else
        {
            Write-Message -Fatal "Invalid selection. Exiting..."
        }
    }
    $VersionShort = $Version -replace '-release', ''
    $FullPath = Join-Path -Path $Path -ChildPath $VersionShort
    Write-Message "Installing Unreal Engine version $Version to $FullPath"
    $ArgumentList = "clone --depth 1 -b {0}-release {1} {2}" -f $VersionShort, $UERepo, $VersionShort
    $GitCloneProcess = Start-Process git `
                    -Wait `
                    -NoNewWindow `
                    -PassThru `
                    -WorkingDirectory $Path `
                    -ArgumentList $ArgumentList

    if (0 -ne $GitCloneProcess.ExitCode)
    {
        Write-Message -Fatal "Git clone failed, exiting..."
    }

    $SetupProcess = Start-Process (Join-Path -Path $FullPath -ChildPath ".\Setup.bat") `
                    -Wait `
                    -NoNewWindow `
                    -PassThru `
                    -WorkingDirectory $FullPath

    if (0 -ne $SetupProcess.ExitCode)
    {
        Write-Message -Err "setup failed, exiting..."
    }

    $GenerateProjectFilesProcess = Start-Process (Join-Path -Path $FullPath -ChildPath ".\GenerateProjectFiles.bat") `
                    -Wait `
                    -NoNewWindow `
                    -PassThru `
                    -WorkingDirectory $FullPath

    if (0 -ne $GenerateProjectFilesProcess.ExitCode)
    {
        Write-Message -Err "setup failed, exiting..."
    }
}
