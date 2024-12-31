using namespace System.Collections.Generic

class PackageConfig {
    [string]$Namespace
    [string]$PackageId
    [string]$Version
    [string]$Password
    [string[]]$DependentPackages
    [string]$SecurityType
  
    PackageConfig([string]$namespace, [string]$packageId, [string]$version, [string]$password, [string]$securityType = "AdminsOnly") {
      if ([string]::IsNullOrWhiteSpace($namespace)) {
        throw "Namespace cannot be null or empty"
      }
      if ([string]::IsNullOrWhiteSpace($packageId)) {
        throw "PackageId cannot be null or empty"
      }
      if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Version cannot be null or empty"
      }
      
      # Validate version format (major.minor.patch.build)
      if (-not ($version -match '^\d+\.\d+\.\d+\.\d+$')) {
        throw "Invalid version format. Expected format: major.minor.patch.build (e.g. 1.0.0.1)"
      }
      
      try {
        # Verify version can be parsed
        [Version]::new($version) | Out-Null
      }
      catch {
        throw "Invalid version format: $_"
      }
      
      $this.Namespace = $namespace
      $this.PackageId = $packageId
      $this.Version = $version
      $this.Password = $password
      $this.DependentPackages = @()
      $this.SecurityType = if ($securityType -in @("AdminsOnly", "AllUsers")) { $securityType } else { "AdminsOnly" }
    }
  
    # Creates PackageConfig objects from a JSON configuration file
    static [PackageConfig[]] FromJson([string]$jsonPath) {
      if (-not (Test-Path $jsonPath)) {
        throw "Configuration file not found: $jsonPath"
      }
      $config = Get-Content $jsonPath | ConvertFrom-Json
      $packages = @()
      foreach ($pkg in $config.packages) {
        $package = [PackageConfig]::new($pkg.namespace, $pkg.packageId, $pkg.version, $pkg.password, $pkg.securityType)
        if ($pkg.dependentPackages) {
          $package.DependentPackages = $pkg.dependentPackages
        }
        $packages += $package
      }
      return $packages
    }
}
