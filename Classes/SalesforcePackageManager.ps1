using namespace System.Collections.Generic

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
  
  static [void] InstallPackagesFromConfig([string]$OrgUserName, [string]$ConfigPath) 
  {
      # Get packages that need updates
      $versionMismatches = [SalesforcePackageManager]::ComparePackagesWithConfig($OrgUserName, $ConfigPath)
      if ($versionMismatches.Count -eq 0) {
          Write-Host "All packages are up to date."
          return
      }
  
      # Get all configured packages
      $configuredPackages = [SalesforcePackageManager]::GetConfiguredPackages($ConfigPath)
      
      # Create lookup of packages needing updates
      $needsUpdate = @{}
      foreach ($mismatch in $versionMismatches) {
          $needsUpdate[$mismatch.Namespace] = $true
      }
  
      # Track packages that need installation
      $packagesToInstall = $configuredPackages | Where-Object { $needsUpdate[$_.Namespace] }
      $maxRetries = 3
      $retryCount = 0
      
      while ($packagesToInstall.Count -gt 0 -and $retryCount -lt $maxRetries) {
          if ($retryCount -gt 0) {
              Write-Host "`nRetry attempt $retryCount of $maxRetries for remaining packages..."
          }
          
          $successfulInstalls = @()
          
          foreach ($pkg in $packagesToInstall) {
              Write-Host "Installing package: $($pkg.Namespace)"
              try {
                  [SalesforcePackageManager]::InstallPackage($OrgUserName, $pkg.PackageId, $pkg.Password, $pkg.SecurityType)
                  $successfulInstalls += $pkg
                  Write-Host "Successfully installed package: $($pkg.Namespace)" -ForegroundColor Green
              }
              catch {
                  Write-Warning "Failed to install package $($pkg.Namespace): $_"
              }
          }
          
          # Remove successful installations from the retry list
          if ($successfulInstalls.Count -gt 0) {
              $packagesToInstall = $packagesToInstall | Where-Object { $_ -notin $successfulInstalls }
          }
          
          $retryCount++
          
          # If there are still packages to install and we haven't hit max retries
          if ($packagesToInstall.Count -gt 0 -and $retryCount -lt $maxRetries) {
              Write-Host "`n$($packagesToInstall.Count) package(s) failed to install. Retrying in 5 seconds..."
              Start-Sleep -Seconds 5
          }
      }
      
      if ($packagesToInstall.Count -gt 0) {
          $failedPackages = $packagesToInstall.Namespace -join ", "
          Write-Warning "Failed to install the following packages after $maxRetries attempts: $failedPackages"
      }
  }
}
