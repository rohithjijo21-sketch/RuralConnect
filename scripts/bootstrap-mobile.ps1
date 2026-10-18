$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
foreach($appName in @('passenger','driver','bus')){
 $appPath=Join-Path $repoRoot "apps/$appName"
 Push-Location $appPath
 try{
  # Flutter creates native projects without overwriting the authored Dart entry point.
  if(-not(Test-Path android)){$authoredEntry=Get-Content -LiteralPath lib/main.dart -Raw;flutter create --platforms android,ios --org in.ruralconnect --project-name "ruralconnect_$appName" --no-pub .;if($LASTEXITCODE -ne 0){throw 'Flutter create failed'};Set-Content -LiteralPath lib/main.dart -Value $authoredEntry;Remove-Item -LiteralPath test/widget_test.dart -ErrorAction SilentlyContinue}
  flutter pub get;if($LASTEXITCODE -ne 0){throw 'Flutter pub get failed'}
 }finally{Pop-Location}
}
node (Join-Path $PSScriptRoot 'configure-mobile.mjs')
Write-Output 'Native targets generated. Follow docs/operations/mobile.md before GPS testing.'
