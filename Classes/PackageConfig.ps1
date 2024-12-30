class PackageConfig {
  [string]$Namespace
  [string]$PackageId
  [string]$Version
  [string]$Password
  [string[]]$DependsOnPackages
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
      $this.DependsOnPackages = @()
      $this.SecurityType = if ($securityType -in @("AdminsOnly", "AllUsers")) { $securityType } else { "AdminsOnly" }
  }

  # Creates PackageConfig objects from a JSON configuration file
  static [PackageConfig[]] FromJson([string]$jsonPath) {
      if (-not (Test-Path $jsonPath)) {
          throw "Configuration file not found: $jsonPath"
      }
      
      $config = Get-Content $jsonPath | ConvertFrom-Json
      
      # First, create a lookup of all valid namespaces
      $validNamespaces = @{}
      foreach ($pkg in $config.packages) {
          $validNamespaces[$pkg.namespace] = $true
      }
      
      # Sort packages by dependencies first
      $packages = @()
      $processed = @{}
      $processing = @{}
      
      function Add-Package($pkg) {
          # Skip if already processed
          if ($processed[$pkg.namespace]) {
              return
          }
          
          # Check for circular dependencies
          if ($processing[$pkg.namespace]) {
              throw "Circular dependency detected for package: $($pkg.namespace)"
          }
          
          $processing[$pkg.namespace] = $true
          
          # Process dependencies first
          if ($pkg.dependsOnPackages) {
              foreach ($dep in $pkg.dependsOnPackages) {
                  if (-not $validNamespaces[$dep]) {
                      throw "Invalid dependency '$dep' for package '$($pkg.namespace)'"
                  }
                  $depPkg = $config.packages | Where-Object { $_.namespace -eq $dep }
                  Add-Package $depPkg
              }
          }
          
          # Create and add the package
          $package = [PackageConfig]::new($pkg.namespace, $pkg.packageId, $pkg.version, $pkg.password, $pkg.securityType)
          if ($pkg.dependsOnPackages) {
              $package.DependsOnPackages = $pkg.dependsOnPackages
          }
          $packages += $package
          
          $processed[$pkg.namespace] = $true
          $processing[$pkg.namespace] = $false
      }
      
      # Process all packages in dependency order
      foreach ($pkg in $config.packages) {
          Add-Package $pkg
      }
      
      return $packages
  }
}