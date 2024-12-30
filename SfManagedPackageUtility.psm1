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
    [CmdletBinding(SupportsShouldProcess)]
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

        # Preview all changes at once
        $target = "Configuration file"
        $operation = "Update package versions:`n" + ($changes | ForEach-Object {
            $pkg = $_.Package
            switch ($_.Action) {
                "Update" { "  - Update $($pkg.Namespace) to version $($pkg.VersionNumber)" }
                "Add" { "  - Add $($pkg.Namespace) version $($pkg.VersionNumber)" }
            }
        } | Out-String)

        # Only proceed if user confirms all changes
        $shouldProcess = $PSCmdlet.ShouldProcess($target, $operation)
        if ($shouldProcess) {
            foreach ($change in $changes) {
                [SalesforcePackageManager]::UpdateConfigFromOrg($SourceOrg, $configPath, $change.Package.Namespace)
            }
        }
        # Return void to prevent boolean output
        return
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
    [CmdletBinding(SupportsShouldProcess)]
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
        
        # Preview all changes at once
        $target = "Target org: $TargetOrg"
        $operation = "Install/update packages:`n" + ($Mismatches | ForEach-Object {
            if ($null -eq $_.TargetPackage) {
                "  - Install $($_.Namespace) version $($_.SourceVersionNumber)"
            } else {
                "  - Update $($_.Namespace) from version $($_.TargetVersionNumber) to $($_.SourceVersionNumber)"
            }
        } | Out-String)

        # Only proceed if user confirms all changes
        $shouldProcess = $PSCmdlet.ShouldProcess($target, $operation)
        if ($shouldProcess) {
            # Install all packages in dependency order, respecting WhatIf preference
            [SalesforcePackageManager]::InstallPackagesFromConfig($TargetOrg, $ConfigPath, $WhatIfPreference)
        }
        # Return void to prevent boolean output
        return
    }
    catch {
        Write-Error "Failed to install packages: $_"
        return
    }
}
# Export only the public functions
Export-ModuleMember -Function @(
    'Update-ConfigFileFromOrg',
    'Install-SalesforcePackages'
)
