# Thirdweb Powershell Utility Module
A collection of powershell cli commands used internally and shared for public good.

## Submodules

### Unreal Engine
Commands related to Clang, Unreal Engine and Plugins

#### Commandlets
* **Install-UnrealEngine** - Install a version of unreal engine from source
* **Get-AvailableUnrealEngineVersions** - List all available release version tags from unreal engine's github
* **Install-Clang** - Install an engine-mapped version of Clang (Linux Cross-Compile Toolchain)
* **Set-Clang** - Set the Clang environment variable to an engine-version mapped version of Clang's path
* **Build-Plugin** - Build an unreal engine plugin

### Config
Commands related to configuration of the module across all submodules

#### Commandlets
* **Set-ConfigSourceDirectory** - Set the directory used to install Unreal Engine source versions
* **Get-ConfigSourceDirectory** - Get the current directory stored
* **Get-InstalledEngineVersion** - List the installed source versions of Unreal Engine
* **Add-SourceEngineVerion** - Manually add a source engine version located outside of the default source directory

### Helpers
Internal Commands used within other commands
* **Write-Message** - Logger that adds colorization and log level prefix to Write-Host
