class VersionMismatch {
    [String]$Namespace
    [Object]$SourcePackage
    [Object]$TargetPackage
    [string]$MostRecentVersionId
    [Boolean]$TargetNeedsUpdate
    [String]$SourceVersionNumber
    [String]$TargetVersionNumber
  
    VersionMismatch([String]$Namespace, [SfPackage]$SourcePackage, $TargetPackage) {
      if ($null -eq $Namespace) {
        throw 'Namespace cannot be null'
      }
      $this.Namespace = $Namespace
      $this.SourcePackage = $SourcePackage
      $this.TargetPackage = $TargetPackage
      $this.TargetNeedsUpdate = if ($null -ne $this.SourcePackage) {
        if ($null -eq $this.TargetPackage) {
          $true
        } else {
          $this.SourcePackage.VersionNumber -gt $this.TargetPackage.VersionNumber
        }
      } else {
        $false
      }
      if ($this.TargetNeedsUpdate) {
        $this.MostRecentVersionId = $this.SourcePackage.PackageVersionId
      } else {
        $this.MostRecentVersionId = if ($null -ne $this.TargetPackage) { $this.TargetPackage.PackageVersionId } else { $null }
      }
      $this.SourceVersionNumber = if ($null -ne $this.SourcePackage) { $this.SourcePackage.VersionNumber.ToString() } else { "" }
      $this.TargetVersionNumber = if ($null -eq $this.TargetPackage) { "" } else { $this.TargetPackage.VersionNumber.ToString() }
    }
}