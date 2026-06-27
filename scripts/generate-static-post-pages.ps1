[CmdletBinding()]
param(
  [string]$SiteDir = (Split-Path -Parent $PSScriptRoot),
  [string]$BaseUrl = "https://xelavoklov.ru"
)

$ErrorActionPreference = "Stop"

$PreviewWidth = 1200
$PreviewHeight = 630

try {
  Add-Type -AssemblyName System.Drawing
} catch {
  throw "System.Drawing is required to generate preview images."
}

function Escape-Html([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return "" }
  $s = $s -replace "&", "&amp;"
  $s = $s -replace "<", "&lt;"
  $s = $s -replace ">", "&gt;"
  $s = $s -replace '"', "&quot;"
  return $s
}

function Get-TextString($textValue) {
  if ($null -eq $textValue) { return "" }
  if ($textValue -is [string]) { return $textValue }
  if ($textValue -is [System.Collections.IEnumerable] -and -not ($textValue -is [string])) {
    $parts = @()
    foreach ($t in $textValue) {
      if ($t -is [string]) {
        $parts += $t
      } elseif ($null -ne $t -and $t.PSObject.Properties.Name -contains "text") {
        $parts += [string]$t.text
      }
    }
    return ($parts -join "")
  }
  return [string]$textValue
}

function Resolve-MediaItems($post) {
  $items = New-Object System.Collections.Generic.List[string]

  $addItem = {
    param($value)
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return }
    $v = [string]$value
    if ($v -match "^Photo unavailable$" -or $v -match "^Video file$" -or $v -match "^\(File not included\)") { return }
    $items.Add($v)
  }

  if ($post.PSObject.Properties.Name -contains "photo") {
    & $addItem $post.photo
  }

  foreach ($field in @("media", "file_name", "real_media_path")) {
    if ($post.PSObject.Properties.Name -contains $field) {
      $value = $post.$field
      if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        foreach ($entry in $value) { & $addItem $entry }
      } else {
        & $addItem $value
      }
    }
  }

  return $items.ToArray() | Select-Object -Unique
}

function Resolve-MediaUrl([string]$item) {
  if ([string]::IsNullOrWhiteSpace($item)) { return $null }
  if ($item -match "^https?://") { return $item }

  $path = $item.TrimStart('/')
  if ($path.StartsWith("media/")) { return "/$path" }
  if ($path.StartsWith("photos/") -or $path.StartsWith("videos/") -or $path.StartsWith("audio/") -or $path.StartsWith("files/") -or $path.StartsWith("comics/") -or $path.StartsWith("person/")) {
    return "/media/$path"
  }

  if ($path -match "\.(jpg|jpeg|png|gif|webp)$") { return "/media/photos/$path" }
  if ($path -match "\.(mp4|webm|ogg)$") { return "/media/videos/$path" }
  if ($path -match "\.(mp3|wav|m4a|oga)$") { return "/media/audio/$path" }
  return "/media/files/$path"
}

function Resolve-MediaFilePath([string]$item, [string]$siteDir) {
  if ([string]::IsNullOrWhiteSpace($item)) { return $null }
  if ($item -match "^https?://") { return $null }

  $raw = $item.TrimStart('/')
  $normalized = $raw -replace "\\", "/"

  $candidates = @()
  if ($normalized.StartsWith("media/")) {
    $candidates += (Join-Path $siteDir $normalized)
  } elseif ($normalized.StartsWith("photos/") -or $normalized.StartsWith("videos/") -or $normalized.StartsWith("audio/") -or $normalized.StartsWith("files/") -or $normalized.StartsWith("comics/") -or $normalized.StartsWith("person/")) {
    $candidates += (Join-Path (Join-Path $siteDir "media") $normalized)
  } else {
    if ($normalized -match "\.(jpg|jpeg|png|gif|webp)$") {
      $candidates += (Join-Path (Join-Path $siteDir "media/photos") $normalized)
      $candidates += (Join-Path (Join-Path $siteDir "media/comics") $normalized)
    } elseif ($normalized -match "\.(mp4|webm|ogg)$") {
      $candidates += (Join-Path (Join-Path $siteDir "media/videos") $normalized)
    } elseif ($normalized -match "\.(mp3|wav|m4a|oga)$") {
      $candidates += (Join-Path (Join-Path $siteDir "media/audio") $normalized)
    } else {
      $candidates += (Join-Path (Join-Path $siteDir "media/files") $normalized)
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }
  return $null
}

function Get-PrimaryMediaKind($post) {
  $media = Resolve-MediaItems $post
  foreach ($m in $media) {
    if ($m -match "\.(jpg|jpeg|png|gif|webp)$") { return "image" }
  }
  foreach ($m in $media) {
    if ($m -match "\.(mp4|webm|ogg)$") { return "video" }
  }
  foreach ($m in $media) {
    if ($m -match "\.(mp3|wav|m4a|oga)$") { return "audio" }
  }
  if ($media.Count -gt 0) { return "document" }
  return "text"
}

function Get-PrimaryImageFilePath($post, [string]$siteDir) {
  $media = Resolve-MediaItems $post
  foreach ($m in $media) {
    if ($m -match "\.(jpg|jpeg|png|gif|webp)$") {
      $file = Resolve-MediaFilePath -item $m -siteDir $siteDir
      if ($file) { return $file }
    }
  }
  return $null
}

function Get-PostTitle($post) {
  $id = [string]$post.id
  $text = (Get-TextString $post.text).Trim()
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    $firstLine = ($text -split "`r?`n")[0].Trim()
    if ($firstLine.Length -gt 72) {
      $firstLine = $firstLine.Substring(0, 69) + "..."
    }
    return $firstLine
  }

  $kind = Get-PrimaryMediaKind $post
  switch ($kind) {
    "video" { return "Video post #$id" }
    "audio" { return "Audio post #$id" }
    "document" { return "Document post #$id" }
    "image" { return "Image post #$id" }
    default { return "Post #$id" }
  }
}

function Get-WrappedLines(
  [System.Drawing.Graphics]$Graphics,
  [System.Drawing.Font]$Font,
  [string]$Text,
  [int]$MaxWidth,
  [int]$MaxLines
) {
  $result = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [pscustomobject]@{ Lines = $result; Truncated = $false }
  }

  $clean = ($Text -replace "\s+", " ").Trim()
  $words = $clean.Split(' ')
  $current = ""
  $index = 0
  $truncated = $false

  while ($index -lt $words.Length) {
    $word = $words[$index]
    $candidate = if ([string]::IsNullOrEmpty($current)) { $word } else { "$current $word" }
    $width = [Math]::Ceiling($Graphics.MeasureString($candidate, $Font).Width)

    if ($width -le $MaxWidth) {
      $current = $candidate
      $index++
      continue
    }

    if (-not [string]::IsNullOrEmpty($current)) {
      $result.Add($current)
      $current = ""
      if ($result.Count -ge $MaxLines) {
        $truncated = $index -lt $words.Length
        break
      }
      continue
    }

    # Single very long token fallback
    $fragment = ""
    foreach ($ch in $word.ToCharArray()) {
      $probe = $fragment + $ch
      $pWidth = [Math]::Ceiling($Graphics.MeasureString($probe, $Font).Width)
      if ($pWidth -le $MaxWidth) {
        $fragment = $probe
      } else {
        break
      }
    }
    if ([string]::IsNullOrEmpty($fragment)) {
      $fragment = $word.Substring(0, [Math]::Min(1, $word.Length))
    }
    $result.Add($fragment)
    $index++
    if ($result.Count -ge $MaxLines) {
      $truncated = $index -lt $words.Length
      break
    }
  }

  if (-not [string]::IsNullOrEmpty($current) -and $result.Count -lt $MaxLines) {
    $result.Add($current)
  } elseif (-not [string]::IsNullOrEmpty($current) -and $result.Count -ge $MaxLines) {
    $truncated = $true
  }

  if (-not $truncated -and ($index -lt $words.Length)) {
    $truncated = $true
  }

  return [pscustomobject]@{ Lines = $result; Truncated = $truncated }
}

function New-PostPreview(
  $post,
  [string]$siteDir,
  [string]$previewDir,
  [string]$title,
  [int]$width,
  [int]$height
) {
  $id = [string]$post.id
  $imagePath = Get-PrimaryImageFilePath -post $post -siteDir $siteDir
  $kind = Get-PrimaryMediaKind $post
  $text = (Get-TextString $post.text).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) {
    switch ($kind) {
      "video" { $text = "VIDEO" }
      "audio" { $text = "AUDIO" }
      "document" { $text = "DOCUMENT" }
      "image" { $text = "IMAGE" }
      default { $text = "POST" }
    }
  }
  $overlayText = "$title`n$text"

  $bmp = New-Object System.Drawing.Bitmap($width, $height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

  try {
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, 33, 40))
    $g.FillRectangle($bgBrush, 0, 0, $width, $height)
    $bgBrush.Dispose()

    $imageDrawn = $false
    if ($imagePath) {
      try {
        $img = [System.Drawing.Image]::FromFile($imagePath)
        try {
          # Draw unscaled, anchored to top-left. If larger than canvas, it is naturally cropped.
          $g.DrawImageUnscaled($img, 0, 0)
          $imageDrawn = $true
        } finally {
          $img.Dispose()
        }
      } catch {
        # Some source formats may not be readable by System.Drawing; fall back to template background.
        $imageDrawn = $false
      }
    }

    if (-not $imageDrawn) {
      $kindBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(55, 62, 78))
      $g.FillRectangle($kindBrush, 0, 0, $width, $height)
      $kindBrush.Dispose()

      $badgeText = switch ($kind) {
        "video" { "VIDEO" }
        "audio" { "AUDIO" }
        "document" { "DOCUMENT" }
        "image" { "IMAGE" }
        default { "TEXT" }
      }
      $badgeFont = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
      $badgeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 230, 240))
      $g.DrawString($badgeText, $badgeFont, $badgeBrush, 40, 30)
      $badgeBrush.Dispose()
      $badgeFont.Dispose()
    }

    $overlayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(118, 0, 0, 0))
    $g.FillRectangle($overlayBrush, 0, 0, $width, $height)
    $overlayBrush.Dispose()

    $left = 42
    $top = 44
    $boxWidth = $width - 84
    $boxHeight = $height - 88

    $font = New-Object System.Drawing.Font("Segoe UI", 38, [System.Drawing.FontStyle]::Bold)
    $lineHeight = [Math]::Ceiling($g.MeasureString("Ag", $font).Height * 0.96)
    $maxLines = [Math]::Max(1, [Math]::Floor($boxHeight / $lineHeight))

    $wrapped = Get-WrappedLines -Graphics $g -Font $font -Text $overlayText -MaxWidth $boxWidth -MaxLines $maxLines
    $lines = $wrapped.Lines

    for ($i = 0; $i -lt $lines.Count; $i++) {
      $alpha = 238
      if ($wrapped.Truncated -and $i -eq ($lines.Count - 1)) {
        # Per requirement: last visible line is semi-transparent when text overflows.
        $alpha = 130
      }

      $lineBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 255, 255, 255))
      $g.DrawString($lines[$i], $font, $lineBrush, $left, $top + ($i * $lineHeight))
      $lineBrush.Dispose()
    }

    $font.Dispose()

    $outPath = Join-Path $previewDir ($id + ".jpg")
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
  }
  finally {
    $g.Dispose()
    $bmp.Dispose()
  }

  return "/previews/$id.jpg"
}

function Build-PostHtml(
  $post,
  [string]$baseUrl,
  [string]$postTitle,
  [string]$ogImagePath
) {
  $id = [string]$post.id
  $text = Get-TextString $post.text
  $textPlain = $text
  $textHtml = Escape-Html $textPlain -replace "`r?`n", "<br>"
  $dateString = ""
  if ($post.PSObject.Properties.Name -contains "date") {
    try {
      $dt = [DateTime]::Parse([string]$post.date)
      $dateString = $dt.ToString("yyyy-MM-dd HH:mm")
    } catch {
      $dateString = [string]$post.date
    }
  }

  $short = if ($textPlain.Length -gt 160) { $textPlain.Substring(0, 157) + "..." } else { $textPlain }
  $title = Escape-Html $postTitle
  $description = Escape-Html $short
  $canonical = "$baseUrl/posts/$id/"
  $ogImageAbs = if ($ogImagePath.StartsWith("http")) { $ogImagePath } else { "$baseUrl$ogImagePath" }

  $author = "xelavoklovlive"
  if ($post.PSObject.Properties.Name -contains "from") {
    $author = [string]$post.from
  }

  $articleDate = ""
  if ($post.PSObject.Properties.Name -contains "date") {
    try {
      $articleDate = ([DateTime]::Parse([string]$post.date)).ToString("s") + "Z"
    } catch {
      $articleDate = ""
    }
  }

  $jsonLd = @"
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "$title",
  "author": {
    "@type": "Person",
    "name": "$(Escape-Html $author)"
  },
  "mainEntityOfPage": "$canonical",
  "datePublished": "$articleDate",
  "description": "$description",
  "image": ["$ogImageAbs"]
}
"@

  return @"
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>$title | xelavoklov.ru</title>
  <meta name="description" content="$description">
  <link rel="canonical" href="$canonical">
  <meta property="og:type" content="article">
  <meta property="og:title" content="$title | xelavoklov.ru">
  <meta property="og:description" content="$description">
  <meta property="og:url" content="$canonical">
  <meta property="og:image" content="$ogImageAbs">
  <meta property="og:site_name" content="xelavoklov.ru">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="$title | xelavoklov.ru">
  <meta name="twitter:description" content="$description">
  <meta name="twitter:image" content="$ogImageAbs">
  <link rel="icon" href="/favicon.ico" type="image/x-icon">
  <style>
    body { margin: 0; font-family: Helvetica, Arial, sans-serif; background: #f4f6f8; color: #111; }
    .page { max-width: 820px; margin: 0 auto; padding: 20px; }
    .nav { margin-bottom: 14px; font-size: 14px; }
    .nav a { color: #2267c5; text-decoration: none; }
    .post { background: #fff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 14px; box-shadow: 0 1px 2px rgba(0,0,0,.06); }
    .meta { color: #687285; font-size: 12px; margin-bottom: 8px; display: flex; gap: 8px; }
    .bubble { white-space: pre-wrap; font-size: 16px; line-height: 1.45; }
    .media { margin-top: 12px; display: grid; gap: 10px; }
    .media img, .media video { width: 100%; border-radius: 10px; display: block; }
    .media-file { color: #2267c5; text-decoration: none; }
    .media-audio { display: grid; gap: 6px; }
    @media (prefers-color-scheme: dark) {
      body { background: #0f1217; color: #eceff4; }
      .post { background: #1a1f28; border-color: #2b3342; }
      .meta { color: #9ba8c0; }
      .nav a, .media-file { color: #7db0ff; }
    }
  </style>
  <script type="application/ld+json">$jsonLd</script>
</head>
<body>
  <main class="page">
    <nav class="nav"><a href="/">Back to Home</a> · <a href="/posts/">Posts Archive</a></nav>
    <article class="post">
      <div class="meta"><span>Post #$id</span><span>$dateString</span></div>
      <div class="bubble">$textHtml</div>
    </article>
  </main>
</body>
</html>
"@
}

function Get-ValidLastmod($post) {
  if (-not ($post.PSObject.Properties.Name -contains "date")) { return "" }
  try {
    $d = [DateTime]::Parse([string]$post.date)
    if ($d.Year -lt 2000) { return "" }
    return $d.ToString("yyyy-MM-dd")
  } catch {
    return ""
  }
}

$channelPath = Join-Path $SiteDir "channel.json"
if (-not (Test-Path $channelPath)) {
  throw "channel.json not found in $SiteDir"
}

$raw = Get-Content -Path $channelPath -Raw -Encoding UTF8
$parsed = $raw | ConvertFrom-Json
$messages = @()
if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed.PSObject.Properties.Name -contains "messages")) {
  $messages = @($parsed)
} else {
  $messages = @($parsed.messages)
}

if ($messages.Count -eq 0) {
  throw "No messages found in channel.json"
}

$postsRoot = Join-Path $SiteDir "posts"
if (-not (Test-Path $postsRoot)) {
  New-Item -Path $postsRoot -ItemType Directory | Out-Null
}

$previewsRoot = Join-Path $SiteDir "previews"
if (-not (Test-Path $previewsRoot)) {
  New-Item -Path $previewsRoot -ItemType Directory | Out-Null
}

Get-ChildItem -Path $previewsRoot -Filter "*.jpg" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$titleMap = @{}

foreach ($post in $messages) {
  if (-not ($post.PSObject.Properties.Name -contains "id")) { continue }
  $id = [string]$post.id
  $title = Get-PostTitle $post
  $titleMap[$id] = $title

  $previewRelPath = New-PostPreview -post $post -siteDir $SiteDir -previewDir $previewsRoot -title $title -width $PreviewWidth -height $PreviewHeight

  $dir = Join-Path $postsRoot $id
  if (-not (Test-Path $dir)) {
    New-Item -Path $dir -ItemType Directory | Out-Null
  }

  $html = Build-PostHtml -post $post -baseUrl $BaseUrl -postTitle $title -ogImagePath $previewRelPath
  $outFile = Join-Path $dir "index.html"
  Set-Content -Path $outFile -Value $html -Encoding UTF8
}

$postsById = $messages | Where-Object { $_.id -ne $null } | Sort-Object -Property { [int]$_.id } -Descending
$archiveLinks = New-Object System.Collections.Generic.List[string]
foreach ($post in $postsById) {
  $id = [string]$post.id
  $title = if ($titleMap.ContainsKey($id)) { $titleMap[$id] } else { "Post #$id" }
  $dateLabel = Get-ValidLastmod $post
  $safeDate = Escape-Html $dateLabel
  $safeTitle = Escape-Html $title
  $archiveItem = '<li><a href="/posts/' + $id + '/">' + $safeTitle + '</a> <span>' + $safeDate + '</span></li>'
  $archiveLinks.Add($archiveItem)
}

$archiveHtml = @"
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Posts Archive | xelavoklov.ru</title>
  <meta name="description" content="Archive of xelavoklovlive posts with permanent links.">
  <link rel="canonical" href="$BaseUrl/posts/">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Posts Archive | xelavoklov.ru">
  <meta property="og:description" content="Archive of xelavoklovlive posts with permanent links.">
  <meta property="og:url" content="$BaseUrl/posts/">
  <meta property="og:image" content="$BaseUrl/previews/2.jpg">
  <link rel="icon" href="/favicon.ico" type="image/x-icon">
  <style>
    body { margin: 0; font-family: Helvetica, Arial, sans-serif; background: #f4f6f8; color: #111; }
    .page { max-width: 900px; margin: 0 auto; padding: 20px; }
    h1 { margin-top: 0; }
    a { color: #2267c5; }
    ul { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
    li { background: #fff; border: 1px solid #e5e7eb; border-radius: 10px; padding: 10px 12px; }
    li span { color: #687285; font-size: 12px; margin-left: 6px; }
    @media (prefers-color-scheme: dark) {
      body { background: #0f1217; color: #eceff4; }
      li { background: #1a1f28; border-color: #2b3342; }
      li span { color: #c7d0de; }
      a { color: #7db0ff; }
    }
  </style>
</head>
<body>
  <main class="page">
    <p><a href="/">Back to Home</a></p>
    <h1>Posts Archive</h1>
    <ul>
      $($archiveLinks -join "`n")
    </ul>
  </main>
</body>
</html>
"@

Set-Content -Path (Join-Path $postsRoot "index.html") -Value $archiveHtml -Encoding UTF8

$sitemapEntries = New-Object System.Collections.Generic.List[string]
$sitemapEntries.Add("<url><loc>$BaseUrl/</loc></url>")
$sitemapEntries.Add("<url><loc>$BaseUrl/posts/</loc></url>")
foreach ($post in $postsById) {
  $id = [string]$post.id
  $lastmod = Get-ValidLastmod $post
  if ($lastmod) {
    $sitemapEntries.Add("<url><loc>$BaseUrl/posts/$id/</loc><lastmod>$lastmod</lastmod></url>")
  } else {
    $sitemapEntries.Add("<url><loc>$BaseUrl/posts/$id/</loc></url>")
  }
}

$sitemap = @"
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$($sitemapEntries -join "`n")
</urlset>
"@
Set-Content -Path (Join-Path $SiteDir "sitemap.xml") -Value $sitemap -Encoding UTF8

$robots = @"
User-agent: *
Allow: /

Sitemap: $BaseUrl/sitemap.xml
"@
Set-Content -Path (Join-Path $SiteDir "robots.txt") -Value $robots -Encoding UTF8

Write-Output "Generated post pages: $($postsById.Count)"
Write-Output "Generated previews: $($postsById.Count)"
Write-Output "Archive page: $postsRoot/index.html"
Write-Output "Sitemap: $(Join-Path $SiteDir 'sitemap.xml')"
Write-Output "Robots: $(Join-Path $SiteDir 'robots.txt')"
