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
. $PSScriptRoot\Classes\PackageConfig.ps1
. $PSScriptRoot\Classes\SfPackage.ps1
. $PSScriptRoot\Classes\VersionMismatch.ps1
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
Update-ConfigFileFromOrg -SourceOrg myorg@example.com -Namespace "ns1,ns2" -ConfigPath "./config.json"
Updates only the specified packages in the given config file.
  
.PARAMETER SourceOrg
The username or alias of the source org to get package versions from.
  
.PARAMETER ConfigPath
Optional. The path to the configuration file. If not specified, looks for PackageConfig.json in the project root directory.
.PARAMETER Namespace
Optional. Comma-separated list of package namespaces to update. If not specified, all packages will be updated.
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
      [String]$ConfigPath,
      
      [Parameter(Mandatory = $false)]
      [ValidatePattern('^[a-zA-Z0-9_]+(,[a-zA-Z0-9_]+)*$')]
      [String]$Namespace
    )
    
    try {
        # Get current packages from org for comparison
        $orgPackages = [SalesforcePackageManager]::GetOrgPackageVersions($SourceOrg)
        if ($Namespace) {
            $namespaces = $Namespace.Split(',').Trim()
            $orgPackages = $orgPackages | Where-Object { $_.Namespace -in $namespaces }
        }
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
        # Preview changes
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
            $target = "Package '$($orgPkg.Namespace)'"
            $operation = switch ($action) {
                "Update" { "Update version to $($orgPkg.VersionNumber) and ID to $($orgPkg.PackageVersionId)" }
                "Add" { "Add new package (version $($orgPkg.VersionNumber))" }
                "Skip" { "No changes needed" }
            }
            if ($action -ne "Skip" -and $PSCmdlet.ShouldProcess($target, $operation)) {
                [SalesforcePackageManager]::UpdateConfigFromOrg($SourceOrg, $configPath, $orgPkg.Namespace)
            }
        }
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
Install-SalesforcePackages -TargetOrg myorg@example.com -Namespace "ns1,ns2" -Confirm:$false
Installs only the specified packages without prompting for confirmation.
.EXAMPLE
Install-SalesforcePackages -TargetOrg myorg@example.com -WhatIf
Shows what changes would be made without actually making them.
  
.PARAMETER TargetOrg
The username or alias of the target org to install packages in.
  
.PARAMETER ConfigPath
Optional. The path to the configuration file. If not specified, looks for PackageConfig.json in the project root directory.
.PARAMETER Namespace
Optional. Comma-separated list of package namespaces to install. If not specified, all packages will be installed in dependency order.
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
      [String]$ConfigPath,
      
      [Parameter(Mandatory = $false)]
      [ValidatePattern('^[a-zA-Z0-9_]+(,[a-zA-Z0-9_]+)*$')]
      [String]$Namespace
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
        
        # Filter by namespace if specified
        if ($Namespace) {
            $namespaces = $Namespace.Split(',').Trim()
            $Mismatches = $Mismatches | Where-Object { $_.Namespace -in $namespaces }
        }
        if ($null -eq $Mismatches -or $Mismatches.Count -eq 0) {
            Write-Host "No package updates needed"
            return
        }
        
        $UpdateNeeded = $Mismatches | Where-Object { $_.TargetNeedsUpdate }
        if ($UpdateNeeded.Count -eq 0) {
            Write-Host "No package updates needed"
            return
        }
        # Preview changes for each package
        foreach ($update in $UpdateNeeded) {
            $target = "Package '$($update.Namespace)'"
            $operation = if ($null -eq $update.TargetPackage) {
                "Install new package (version $($update.SourceVersionNumber))"
            } else {
                "Update from version $($update.TargetVersionNumber) to $($update.SourceVersionNumber)"
            }
            if ($PSCmdlet.ShouldProcess($target, $operation)) {
                # Convert namespace string to array for single package
                $namespaceArray = @($update.Namespace)
                [SalesforcePackageManager]::InstallPackagesFromConfig($TargetOrg, $ConfigPath, $namespaceArray)
            }
        }
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