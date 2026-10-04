Set-Location "G:\NewGDP\go-sports"
$names = @("bump","set","spike","block","serve","dive")
$first = $null
foreach ($n in $names) {
  $out = "art_src\gemini\raw\act_${n}_v1.png"
  $refs = @()
  if ($first) { $refs = @($first) }
  $ok = $false
  for ($try = 0; $try -lt 2 -and -not $ok; $try++) {
    try {
      & .\tools\gemini_icon.ps1 -PromptFile "art_src\gemini\prompts\act_$n.txt" -OutFile $out -ReferenceImages $refs -AspectRatio 1:1 -ImageSize 1K
      $ok = $true
    } catch {
      Write-Output "FAIL $n try $try : $($_.Exception.Message)"
      if ($_.Exception.Message -match "429") { Start-Sleep -Seconds 32 } else { break }
    }
  }
  if ($ok -and -not $first) { $first = $out }
  Start-Sleep -Seconds 28
}
Write-Output "ALL_DONE"
