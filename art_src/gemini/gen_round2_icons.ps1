Set-Location "G:\NewGDP\go-sports"
$jobs = @(
  @{name="act_jump";   refs=@("art_src\gemini\raw\act_block_v1.png")},
  @{name="emb_flame";  refs=@()},
  @{name="emb_trophy"; refs=@("art_src\gemini\raw\emb_flame_v1.png")},
  @{name="emb_lock";   refs=@("art_src\gemini\raw\emb_flame_v1.png")}
)
foreach ($j in $jobs) {
  $n = $j.name
  $out = "art_src\gemini\raw\${n}_v1.png"
  $refs = @($j.refs | Where-Object { Test-Path $_ })
  $ok = $false
  for ($try = 0; $try -lt 2 -and -not $ok; $try++) {
    try {
      & .\tools\gemini_icon.ps1 -PromptFile "art_src\gemini\prompts\$n.txt" -OutFile $out -ReferenceImages $refs -AspectRatio 1:1 -ImageSize 1K
      $ok = $true
    } catch {
      Write-Output "FAIL $n try $try : $($_.Exception.Message)"
      if ($_.Exception.Message -match "429") { Start-Sleep -Seconds 32 } else { break }
    }
  }
  Start-Sleep -Seconds 28
}
Write-Output "ALL_DONE"
