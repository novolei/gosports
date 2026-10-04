Set-Location "G:\NewGDP\go-sports"
& .\tools\gemini_icon.ps1 -PromptFile "art_src\gemini\prompts\gag_sardine.txt" -OutFile "art_src\gemini\raw\gag_sardine_v1.png" -ReferenceImages @("art_src\brand\ball_render.png") -AspectRatio 1:1 -ImageSize 1K
Write-Output "ALL_DONE"
