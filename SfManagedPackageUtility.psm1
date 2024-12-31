# Use .NET namespace for generic collections
using namespace System.Collections.Generic
# Internal helper function
function Get-ProjectRoot {
    $projectFile = "sfdx-project.json"
    if (Test-Path $projectFile) {
      return (Get-Item -Path ".\" -Verbose).FullName
    } else {
      throw "Current directory is not a Salesforce project root directory. Please navigate to the project root directory and try again."
    }
}
# Dot source the class files in dependency order
. $PSScriptRoot\Classes\SfPackage.ps1
. $PSScriptRoot\Classes\VersionMismatch.ps1
. $PSScriptRoot\Classes\PackageConfig.ps1
. $PSScriptRoot\Classes\SalesforcePackageManager.ps1
<# 
.SYNOPSIS
Updates the package configuration file with versions and IDs from a source org.
  
.DESCRIPTION
Takes a source org and updates the package configuration file with the current versions and package IDs from that org.
Preserves other settings like passwords, security types, and dependencies.
.EXAMPLE
Update-ConfigFileFromOrg -SourceOrg myorg@example.com
Updates all package versions in the default config file from the specified org.
.EXAMPLE
Update-ConfigFileFromOrg -SourceOrg myorg@example.com -ConfigPath "./config.json"
Updates packages in the given config file.
  
.PARAMETER SourceOrg
The username or alias of the source org to get package versions from.
  
.PARAMETER ConfigPath
Optional. The path to the configuration file. If not specified, looks for PackageConfig.json in the project root directory.
#>
function Update-ConfigFileFromOrg {
    param (
      [Parameter(Mandatory = $true)]
      [ValidateNotNullOrEmpty()]
      [String]$SourceOrg,
      
      [Parameter(Mandatory = $false)]
      [ValidateScript({
        if([string]::IsNullOrWhiteSpace($_)) { return $true }
        if(Test-Path $_) { return $true }
        throw "Config file path does not exist: $_"
      })]
      [String]$ConfigPath
    )
    
    try {
        # Get current packages from org for comparison
        $orgPackages = [SalesforcePackageManager]::GetOrgPackageVersions($SourceOrg)
        # Get current config for comparison
        $configPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            Join-Path (Get-ProjectRoot) "PackageConfig.json"
        } else {
            $ConfigPath
        }
        $currentConfig = if (Test-Path $configPath) {
            Get-Content $configPath | ConvertFrom-Json
        } else {
            @{ packages = @() }
        }
        # Build list of changes
        $changes = @()
        foreach ($orgPkg in $orgPackages) {
            $configPkg = $currentConfig.packages | Where-Object { $_.namespace -eq $orgPkg.Namespace }
            $action = if ($null -ne $configPkg) {
                if ($configPkg.version -ne $orgPkg.VersionNumber.ToString() -or 
                    $configPkg.packageId -ne $orgPkg.PackageVersionId) {
                    "Update"
                } else {
                    "Skip"
                }
            } else {
                "Add"
            }
            if ($action -ne "Skip") {
                $changes += @{
                    Package = $orgPkg
                    Action = $action
                }
            }
        }

        if ($changes.Count -eq 0) {
            Write-Host "No updates needed"
            return
        }

        # Preview changes
        Write-Host "Updating package versions in config file..."
        foreach ($change in $changes) {
            $pkg = $change.Package
            switch ($change.Action) {
                "Update" { Write-Host "  - Update $($pkg.Namespace) to version $($pkg.VersionNumber)" }
                "Add" { Write-Host "  - Add $($pkg.Namespace) version $($pkg.VersionNumber)" }
            }
        }

        # Apply changes
        [SalesforcePackageManager]::UpdateConfigFromOrg($SourceOrg, $ConfigPath)
    } catch {
        Write-Error "Failed to update config file: $_"
    }
}
<# 
.SYNOPSIS
Installs or updates packages in a target org based on the configuration file.
  
.DESCRIPTION
Compares package versions between the configuration file and target org, then installs or updates packages as needed.
Handles package dependencies, installation keys, and security types from the configuration.

The installation process includes an automatic retry mechanism:
- Failed package installations will be retried up to 3 times
- Successfully installed packages are removed from the retry queue
- There is a 5-second delay between retry attempts
- Clear status messages indicate which packages succeeded or failed
.EXAMPLE
Install-SalesforcePackages -TargetOrg myorg@example.com
Installs or updates all packages defined in the default config file, respecting dependencies.
.EXAMPLE
Install-SalesforcePackages -TargetOrg myorg@example.com -Confirm:$false
Installs packages without prompting for confirmation.
.EXAMPLE
Install-SalesforcePackages -TargetOrg myorg@example.com -WhatIf
Shows what changes would be made without actually making them.
  
.PARAMETER TargetOrg
The username or alias of the target org to install packages in.
  
.PARAMETER ConfigPath
Optional. The path to the configuration file. If not specified, looks for PackageConfig.json in the project root directory.
#>
function Install-SalesforcePackages {
    param (
      [Parameter(Mandatory = $true)]
      [ValidateNotNullOrEmpty()]
      [String]$TargetOrg,
      
      [Parameter(Mandatory = $false)]
      [ValidateScript({
        if([string]::IsNullOrWhiteSpace($_)) { return $true }
        if(Test-Path $_) { return $true }
        throw "Config file path does not exist: $_"
      })]
      [String]$ConfigPath
    )
    
    try {
        # Get current config path
        $configPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            Join-Path (Get-ProjectRoot) "PackageConfig.json"
        } else {
            $ConfigPath
        }
        
        # Get list of packages that need updates
        $Mismatches = [SalesforcePackageManager]::ComparePackagesWithConfig($TargetOrg, $configPath)
        
        if ($null -eq $Mismatches -or $Mismatches.Count -eq 0) {
            Write-Host "No package updates needed"
            return
        }
        
        # Preview changes
        Write-Host "Installing/updating packages in $TargetOrg..."
        foreach ($mismatch in $Mismatches) {
            if ($null -eq $mismatch.TargetPackage) {
                Write-Host "  - Install $($mismatch.Namespace) version $($mismatch.SourceVersionNumber)"
            } else {
                Write-Host "  - Update $($mismatch.Namespace) from version $($mismatch.TargetVersionNumber) to $($mismatch.SourceVersionNumber)"
            }
        }
        
        # Install packages
        [SalesforcePackageManager]::InstallPackagesFromConfig($TargetOrg, $ConfigPath)
    }
    catch {
        Write-Error "Failed to install packages: $_"
    }
}
# Export only the public functions
Export-ModuleMember -Function @(
    'Update-ConfigFileFromOrg',
    'Install-SalesforcePackages'
)
