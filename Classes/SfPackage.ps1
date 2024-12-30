class SfPackage {
    [string]$OrgUserName
    [string]$PackageName
    [string]$PackageId
    [string]$Namespace
    [string]$PackageVersionId
    [string]$VersionName
    [Version]$VersionNumber
    [string]$InstallKey
    [string]$SecurityType
  
    SfPackage([string]$OrgUserName, [Object]$Package) {
      if ($null -eq $OrgUserName) {
        throw 'OrgUserName cannot be null'
      }
      if ($null -eq $Package.SubscriberPackageNamespace) {
        throw 'Namespace cannot be null'
      }
      $this.OrgUserName = $OrgUserName
      $this.PackageName = $Package.SubscriberPackageName
      $this.PackageId = $Package.SubscriberPackageId
      $this.Namespace = $Package.SubscriberPackageNamespace
      $this.PackageVersionId = $Package.SubscriberPackageVersionId
      $this.VersionName = $Package.SubscriberPackageVersionName
      $this.VersionNumber = [Version]$Package.SubscriberPackageVersionNumber
      try {
        $projectRoot = Get-ProjectRoot
        $metadataFilePath = Join-Path $projectRoot "force-app/main/default/installedPackages/$($this.Namespace).installedPackage-meta.xml"
        if (Test-Path $metadataFilePath) {
          $metadataContent = Get-Content $metadataFilePath
          $metadataXml = [xml]$metadataContent
          $this.InstallKey = if ($null -ne $metadataXml.InstalledPackage.password) { $metadataXml.InstalledPackage.password } else { '' }
          $this.SecurityType = if ($null -ne $metadataXml.InstalledPackage.securityType) { $metadataXml.InstalledPackage.securityType } else { 'AdminsOnly' }
        } else {
          $this.InstallKey = ''
          $this.SecurityType = 'AdminsOnly'
        }
      } catch {
        Write-Warning "Error locating installed package metadata for $($this.Namespace): $_"
        $this.InstallKey = ''
        $this.SecurityType = 'AdminsOnly'
      }
    }
}