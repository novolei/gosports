<#
.SYNOPSIS
  Icon / art step for Go Sports: ask Gemini (Vertex AI, local gcloud login - no API key) for one image, optionally conditioned on
  reference images (the style anchor). The raw PNG plus a .prompt.txt sidecar (prompt + references) is the source of truth:
  generation is not reproducible and every call costs money, so post-processing (tools/key_icon.py) always starts from the raw file.

.NOTES
  Adapted from G:\NewGDP\hard-north\tools\gemini_concept.ps1 (same auth and pitfalls as the gemini-image-gen skill):
    - Expect: 100-continue must be off, or Google answers HTTP 417.
    - A Google "Sorry..." HTML page is an anti-abuse block on this egress: do NOT retry repeatedly or bypass.
    - HTTP 429 = too fast: wait 25-30 s and retry ONCE.
    - gemini-3-pro-image is served from the GLOBAL endpoint only.
    - The model cannot output a real alpha channel: ask for a flat chroma-green background and key it out afterwards.

.EXAMPLE
  & tools\gemini_icon.ps1 -PromptFile art_src\gemini\prompts\bonk.txt -OutFile art_src\gemini\raw\bonk_v1.png -AspectRatio 1:1 -ImageSize 1K
#>
param(
  [string]$Prompt = "",
  [string]$PromptFile = "",
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string[]]$ReferenceImages = @(),
  [string]$AspectRatio = "1:1",
  [string]$ImageSize = "1K",
  [string]$Project  = "clauderl",
  [string]$Location = "global",
  [string]$Model    = "gemini-3-pro-image"
)

$ErrorActionPreference = "Stop"
[System.Net.ServicePointManager]::Expect100Continue = $false
[System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]::Tls12

if ($PromptFile) { $Prompt = [IO.File]::ReadAllText((Resolve-Path $PromptFile).Path, [Text.Encoding]::UTF8) }
if (-not $Prompt) { throw "Give -Prompt or -PromptFile." }

function Get-GcloudPath {
  $c = Get-Command gcloud -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $fallback = "C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
  if (Test-Path $fallback) { return $fallback }
  throw "gcloud not found on PATH and not at the default install location."
}

$parts = @()
foreach ($ref in $ReferenceImages) {
  $full = (Resolve-Path $ref).Path
  $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
  $mime = switch ($ext) { ".jpg" { "image/jpeg" } ".jpeg" { "image/jpeg" } ".webp" { "image/webp" } default { "image/png" } }
  $parts += @{ inlineData = @{ mimeType = $mime; data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($full)) } }
}
$parts += @{ text = $Prompt }

$generation = @{ responseModalities = @("TEXT", "IMAGE") }
$imageConfig = @{}
if ($AspectRatio) { $imageConfig["aspectRatio"] = $AspectRatio }
if ($ImageSize)   { $imageConfig["imageSize"] = $ImageSize }
if ($imageConfig.Count -gt 0) { $generation["imageConfig"] = $imageConfig }
$payload = @{ contents = @(@{ role = "user"; parts = $parts }); generationConfig = $generation } | ConvertTo-Json -Depth 10 -Compress

$token = & (Get-GcloudPath) auth print-access-token 2>$null
if (-not $token) { throw "gcloud auth print-access-token returned nothing. Run: gcloud auth login" }
$apiHost = if ($Location -eq "global") { "aiplatform.googleapis.com" } else { "$Location-aiplatform.googleapis.com" }
$url = "https://$apiHost/v1/projects/$Project/locations/$Location/publishers/google/models/${Model}:generateContent"
try {
  $resp = Invoke-WebRequest -Uri $url -Method Post -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json" -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 300 -UseBasicParsing
} catch {
  $m = ($_.Exception.Message -replace '\s+', ' ')
  $body = ""
  try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $body = $sr.ReadToEnd() } catch {}
  if ($m -match "We're sorry|automated queries" -or $body -match "automated queries") { throw "Anti-abuse block on this egress. Do not retry repeatedly or bypass; wait or change egress." }
  if ($m -match "417") { throw "HTTP 417 - Expect: 100-continue was not suppressed." }
  if ($m -match "429") { throw "HTTP 429 - too fast. Wait 25-30 s and retry ONCE." }
  throw "$m  $($body.Substring(0, [Math]::Min(600, $body.Length)))"
}

$j = $resp.Content | ConvertFrom-Json
$inline = $null
$notes = @()
foreach ($p in $j.candidates[0].content.parts) {
  $names = $p.PSObject.Properties.Name
  if ($names -contains "inlineData") { $inline = $p.inlineData }
  elseif ($names -contains "text") { $notes += $p.text }
}
if (-not $inline) { throw "No image in the response (finishReason=$($j.candidates[0].finishReason)). Text: $($notes -join ' ')" }

$bytes = [Convert]::FromBase64String($inline.data)
$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[IO.File]::WriteAllBytes($OutFile, $bytes)
$sidecar = [IO.Path]::ChangeExtension($OutFile, ".prompt.txt")
$record = @("model: $Model", "location: $Location", "aspect: $AspectRatio", "size: $ImageSize", "references:") + ($ReferenceImages | ForEach-Object { "  $_" }) + @("prompt:", $Prompt, "model notes:", ($notes -join "`n"))
[IO.File]::WriteAllText($sidecar, ($record -join "`n"), [Text.UTF8Encoding]::new($false))
$magic = ($bytes[0..3] | ForEach-Object { $_.ToString("X2") }) -join " "
Write-Output "GEMINI_IMAGE_OK $OutFile $($bytes.Length) bytes magic=$magic mime=$($inline.mimeType)"
