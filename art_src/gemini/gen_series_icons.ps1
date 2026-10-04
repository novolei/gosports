# Series teaser icons for the promo video (table tennis / football / shuffleboard), same style anchor as the ball render.
Set-Location "G:\NewGDP\go-sports"
$ref = "art_src\brand\ball_render.png"
foreach ($n in @("series_tt", "series_fb", "series_sb")) {
  $out = "art_src\gemini\raw\${n}_v1.png"
  $ok = $false
  for ($try = 0; $try -lt 2 -and -not $ok; $try++) {
    try {
      & .\tools\gemini_icon.ps1 -PromptFile "art_src\gemini\prompts\$n.txt" -OutFile $out -ReferenceImages @($ref) -AspectRatio 1:1 -ImageSize 1K
      $ok = $true
    } catch {
      Write-Output "FAIL $n try $try : $($_.Exception.Message)"
      if ($_.Exception.Message -match "429") { Start-Sleep -Seconds 32 } else { break }
    }
  }
  Start-Sleep -Seconds 28
}
Write-Output "ALL_DONE"
