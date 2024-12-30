using namespace System.Collections.Generic
using module "./VersionMismatch.ps1"
using module "./PackageConfig.ps1"
using module "./SfPackage.ps1"

class SalesforcePackageManager
{
  # Compares package versions between config and org, returns needed updates
  static [VersionMismatch[]] ComparePackagesWithConfig([string]$OrgUserName, [string]$ConfigPath)
  {
    if (-not (Test-Path $ConfigPath))
    {
      $ConfigPath = Join-Path $PSScriptRoot "SfPackageConfig.json"
      if (-not (Test-Path $ConfigPath))
      {
        throw "Configuration file not found at specified path or in script root"
      }
    }
      
    $configPackages = [PackageConfig]::FromJson($ConfigPath)
    $orgPackages = [SalesforcePackageManager]::GetOrgPackageVersions($OrgUserName)
      
    $differences = New-Object System.Collections.Generic.List[VersionMismatch]
    $orgLookup = @{}
    foreach ($package in $orgPackages)
    {
      $orgLookup[$package.Namespace] = $package
    }
      
    foreach ($configPkg in $configPackages)
    {
      $orgPkg = $orgLookup[$configPkg.Namespace]
      $mockPackageData = @{
        SubscriberPackageName = $configPkg.Namespace
        SubscriberPackageId = $configPkg.PackageId
        SubscriberPackageNamespace = $configPkg.Namespace
        SubscriberPackageVersionId = $configPkg.PackageId
        SubscriberPackageVersionName = $configPkg.Version
        SubscriberPackageVersionNumber = $configPkg.Version
      }
      $configSfPkg = [SfPackage]::new("config", [PSCustomObject]$mockPackageData)
      $configSfPkg.InstallKey = $configPkg.Password
      $configSfPkg.SecurityType = $configPkg.SecurityType
        
      if ($null -eq $orgPkg)
      {
        # Package not installed in org
        $mismatch = [VersionMismatch]::new($configPkg.Namespace, $configSfPkg, $null)
        $differences.Add($mismatch)
      } elseif ([Version]$configPkg.Version -gt $orgPkg.VersionNumber)
      {
        # Package needs update
        $mismatch = [VersionMismatch]::new($configPkg.Namespace, $configSfPkg, $orgPkg)
        $differences.Add($mismatch)
      }
    }
      
    return $differences
  }

  static [void] UpdateConfigFromOrg([string]$OrgUserName, [string]$ConfigPath)
  {
    if (-not (Test-Path $ConfigPath))
    {
      $ConfigPath = Join-Path $PSScriptRoot "SfPackageConfig.json"
      if (-not (Test-Path $ConfigPath))
      {
        throw "Configuration file not found at specified path or in script root"
      }
    }

    # Get current config and packages
    $configContent = Get-Content $ConfigPath | ConvertFrom-Json
    if (-not $configContent.packages)
    {
      $configContent | Add-Member -NotePropertyName "packages" -NotePropertyValue @() -Force
    }
      
    # Get org packages
    $orgPackages = [SalesforcePackageManager]::GetOrgPackageVersions($OrgUserName)
      
    # Update versions and IDs for existing packages and add new ones
    foreach ($orgPkg in $orgPackages)
    {
      $configPkg = $configContent.packages | Where-Object { $_.namespace -eq $orgPkg.Namespace }
      if ($null -ne $configPkg)
      {
        # Update existing package
        $configPkg.version = $orgPkg.VersionNumber.ToString()
        $configPkg.packageId = $orgPkg.PackageVersionId
      } else
      {
        # Add new package
        $newPkg = @{
          namespace = $orgPkg.Namespace
          packageId = $orgPkg.PackageVersionId
          version = $orgPkg.VersionNumber.ToString()
          password = $orgPkg.InstallKey
          securityType = $orgPkg.SecurityType
          dependsOnPackages = @()
        }
        $configContent.packages += $newPkg
      }
    }

    # Save updated config
    $configContent | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath
    Write-Host "Updated package versions and IDs in config file from $OrgUserName"
  }

  static [PackageConfig[]] GetConfiguredPackages([string]$ConfigPath)
  {
    if (-not (Test-Path $ConfigPath))
    {
      $ConfigPath = Join-Path $PSScriptRoot "SfPackageConfig.json"
      if (-not (Test-Path $ConfigPath))
      {
        throw "Configuration file not found at specified path or in script root"
      }
    }
    return [PackageConfig]::FromJson($ConfigPath)
  }
  
  static [SfPackage[]] GetOrgPackageVersions([string]$OrgUserName)
  {
    if ([string]::IsNullOrWhiteSpace($OrgUserName))
    {
      throw "OrgUserName cannot be null or empty"
    }

    $Command = "sf package installed list --target-org $OrgUserName --json"
    try
    {
      $Result = Invoke-Expression $Command | ConvertFrom-Json
        
      # Validate JSON response structure
      if ($null -eq $Result)
      {
        throw "Invalid JSON response: Response is null"
      }
      if ($null -eq $Result.status)
      {
        throw "Invalid JSON response: Missing 'status' field"
      }
      if ($null -eq $Result.result)
      {
        throw "Invalid JSON response: Missing 'result' field"
      }
        
      if ($Result.status -ne 0)
      {
        throw "There was an error retrieving packages from $OrgUserName. $($Result.Message)"
      }

      $packages = @()
      foreach ($package in $Result.result)
      {
        try
        {
          # Validate required package fields
          if ($null -eq $package)
          {
            Write-Warning "Skipping null package entry"
            continue
          }
            
          if ([string]::IsNullOrWhiteSpace($package.SubscriberPackageNamespace))
          {
            Write-Verbose "Skipping package with empty namespace"
            continue
          }

          # Validate all required fields exist
          $requiredFields = @(
            'SubscriberPackageName',
            'SubscriberPackageId',
            'SubscriberPackageVersionId',
            'SubscriberPackageVersionName',
            'SubscriberPackageVersionNumber'
          )

          $missingFields = $requiredFields | Where-Object { 
            $null -eq $package.$_ -or [string]::IsNullOrWhiteSpace($package.$_)
          }

          if ($missingFields.Count -gt 0)
          {
            Write-Warning "Package $($package.SubscriberPackageNamespace) missing required fields: $($missingFields -join ', ')"
            continue
          }

          $sfPackage = [SfPackage]::new($OrgUserName, $package)
          $packages += $sfPackage
        } catch
        {
          Write-Warning "Error processing package $($package.SubscriberPackageNamespace): $_"
          continue
        }
      }

      if ($packages.Count -eq 0)
      {
        Write-Warning "No valid packages found in org $OrgUserName"
      }

      return $packages
    } catch
    {
      $errorMessage = "Error retrieving packages from $OrgUserName"
      if ($_.Exception.Message)
      {
        $errorMessage += ": $($_.Exception.Message)"
      }
      throw $errorMessage
    }
  }
  
  static [void] InstallPackage([string]$OrgUserName, [string]$PackageId, [string]$InstallKey, [string]$SecurityType = "AdminsOnly")
  {
    # Input validation
    if ([string]::IsNullOrWhiteSpace($OrgUserName))
    {
      throw "OrgUserName cannot be null or empty"
    }
    if ([string]::IsNullOrWhiteSpace($PackageId))
    {
      throw "PackageId cannot be null or empty"
    }
      
    try
    {
      # Validate and normalize SecurityType
      $validSecurityTypes = @("AdminsOnly", "AllUsers")
      if (-not ($SecurityType -in $validSecurityTypes))
      {
        Write-Warning "Invalid SecurityType '$SecurityType'. Defaulting to 'AdminsOnly'"
        $SecurityType = "AdminsOnly"
      }

      # Build command with proper escaping and parameter handling
      $commandParams = @(
        "--package `"$PackageId`"",
        "--target-org `"$OrgUserName`"",
        "--no-prompt",
        "--json",
        "--security-type `"$SecurityType`"",
        "--wait 99"
      )

      if (-not [string]::IsNullOrWhiteSpace($InstallKey))
      {
        $commandParams += "--installation-key `"$InstallKey`""
      }

      $Command = "sf package install $($commandParams -join ' ')"

      Write-Verbose "Executing command: $Command"

      # Execute command and process response
      $Result = Invoke-Expression $Command | ConvertFrom-Json
        
      # Validate JSON response
      if ($null -eq $Result)
      {
        throw "Invalid JSON response: Response is null"
      }
      if ($null -eq $Result.status)
      {
        throw "Invalid JSON response: Missing 'status' field"
      }

      if ($Result.status -ne 0)
      {
        $errorMsg = if ($Result.message)
        { 
          $Result.message 
        } elseif ($Result.error)
        { 
          $Result.error 
        } else
        { 
          "Unknown error occurred" 
        }
        throw "Installation failed: $errorMsg"
      }

      Write-Host "Package $PackageId successfully installed in $OrgUserName"
    } catch
    {
      $errorMessage = "Error installing package $PackageId in $OrgUserName"
      if ($_.Exception.Message)
      {
        $errorMessage += ": $($_.Exception.Message)"
      }
      throw $errorMessage
    }
  }
  
  static [void] InstallPackagesFromConfig([string]$OrgUserName, [string]$ConfigPath, [string[]]$Namespaces)
  {
    # Get packages that need updates
    $versionMismatches = [SalesforcePackageManager]::ComparePackagesWithConfig($OrgUserName, $ConfigPath)
    
    # Filter by namespace if specified
    if ($null -ne $Namespaces -and $Namespaces.Count -gt 0) {
      $versionMismatches = $versionMismatches | Where-Object { $_.Namespace -in $Namespaces }
    }
    if ($versionMismatches.Count -eq 0) {
      Write-Host "All packages are up to date."
      return
    }

    # Get all configured packages for dependency resolution
    $allPackages = [SalesforcePackageManager]::GetConfiguredPackages($ConfigPath)
    
    # Create lookup of packages needing updates
    $needsUpdate = @{}
    foreach ($mismatch in $versionMismatches) {
      $needsUpdate[$mismatch.Namespace] = $true
    }
      
    # Build dependency graph
    $dependencyGraph = @{}
    foreach ($pkg in $allPackages)
    {
      $dependencyGraph[$pkg.Namespace] = $pkg.DependsOnPackages
    }

    # Validate dependencies
    foreach ($pkg in $allPackages)
    {
      foreach ($dep in $pkg.DependsOnPackages)
      {
        if (-not $dependencyGraph.ContainsKey($dep))
        {
          throw "Package $($pkg.Namespace) has undefined dependency: $dep"
        }
      }
    }

    # Install packages in dependency order
    $installed = @{}
    function Install-WithDependencies($pkg)
    {
      if ($installed[$pkg.Namespace])
      {
        return
      }

      # Install dependencies first
      foreach ($dep in $pkg.DependsOnPackages)
      {
        $depPkg = $allPackages | Where-Object { $_.Namespace -eq $dep }
        # Only install dependency if it needs an update
        if ($needsUpdate[$dep]) {
          Install-WithDependencies $depPkg
        }
      }
            
      # Only install if package needs an update
      if ($needsUpdate[$pkg.Namespace]) {
        Write-Host "Installing package: $($pkg.Namespace)"
        [SalesforcePackageManager]::InstallPackage($OrgUserName, $pkg.PackageId, $pkg.Password, $pkg.SecurityType)
      }
      $installed[$pkg.Namespace] = $true
    }

    # Install only packages that need updates, in dependency order
    foreach ($pkg in $allPackages)
    {
      if ($needsUpdate[$pkg.Namespace]) {
        Install-WithDependencies $pkg
      }
    }
  }
}
