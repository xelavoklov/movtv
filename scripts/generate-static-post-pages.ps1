[CmdletBinding()]
param(
  [string]$SiteDir = (Split-Path -Parent $PSScriptRoot),
  [string]$BaseUrl = "https://xelavoklov.ru"
)

$ErrorActionPreference = "Stop"

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

function Get-OgImage($post) {
  $media = Resolve-MediaItems $post
  foreach ($m in $media) {
    if ($m -match "\.(jpg|jpeg|png|gif|webp)$") {
      return Resolve-MediaUrl $m
    }
  }
  return "/favicon.ico"
}

function Render-MediaHtml($post) {
  $media = Resolve-MediaItems $post
  if (-not $media -or $media.Count -eq 0) { return "" }

  $chunks = New-Object System.Collections.Generic.List[string]
  foreach ($item in $media) {
    $url = Resolve-MediaUrl $item
    if (-not $url) { continue }

    $safeName = Escape-Html $item
    if ($item -match "\.(jpg|jpeg|png|gif|webp)$") {
      $chunks.Add('<img src="' + $url + '" alt="' + $safeName + '" loading="lazy" />')
    } elseif ($item -match "\.(mp4|webm|ogg)$") {
      $chunks.Add('<video controls preload="metadata" src="' + $url + '"></video>')
    } elseif ($item -match "\.(mp3|wav|m4a|oga)$") {
      $chunks.Add('<div class="media-audio"><audio controls preload="metadata" src="' + $url + '"></audio><span>' + $safeName + '</span></div>')
    } else {
      $chunks.Add('<a class="media-file" href="' + $url + '" target="_blank" rel="noopener noreferrer">' + $safeName + '</a>')
    }
  }

  if ($chunks.Count -eq 0) { return "" }
  return '<div class="media">' + ($chunks -join "`n") + '</div>'
}

function Build-PostHtml($post, [string]$baseUrl) {
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
  $title = "Post #$id | xelavoklov.ru"
  $description = Escape-Html $short
  $canonical = "$baseUrl/posts/$id/"
  $ogImagePath = Get-OgImage $post
  $ogImageAbs = if ($ogImagePath.StartsWith("http")) { $ogImagePath } else { "$baseUrl$ogImagePath" }
  $mediaHtml = Render-MediaHtml $post

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
  "headline": "Post #$id",
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
  <title>$title</title>
  <meta name="description" content="$description">
  <link rel="canonical" href="$canonical">
  <meta property="og:type" content="article">
  <meta property="og:title" content="$title">
  <meta property="og:description" content="$description">
  <meta property="og:url" content="$canonical">
  <meta property="og:image" content="$ogImageAbs">
  <meta property="og:site_name" content="xelavoklov.ru">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="$title">
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
      $mediaHtml
    </article>
  </main>
</body>
</html>
"@
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

foreach ($post in $messages) {
  if (-not ($post.PSObject.Properties.Name -contains "id")) { continue }
  $id = [string]$post.id
  $dir = Join-Path $postsRoot $id
  if (-not (Test-Path $dir)) {
    New-Item -Path $dir -ItemType Directory | Out-Null
  }

  $html = Build-PostHtml -post $post -baseUrl $BaseUrl
  $outFile = Join-Path $dir "index.html"
  Set-Content -Path $outFile -Value $html -Encoding UTF8
}

$postsById = $messages | Where-Object { $_.id -ne $null } | Sort-Object -Property { [int]$_.id } -Descending
$archiveLinks = New-Object System.Collections.Generic.List[string]
foreach ($post in $postsById) {
  $id = [string]$post.id
  $text = Get-TextString $post.text
  $short = if ($text.Length -gt 120) { (Escape-Html ($text.Substring(0,117) + "...")) } else { Escape-Html $text }
  $dateLabel = ""
  if ($post.PSObject.Properties.Name -contains "date") {
    try { $dateLabel = ([DateTime]::Parse([string]$post.date)).ToString("yyyy-MM-dd") } catch { $dateLabel = [string]$post.date }
  }
  $safeDate = Escape-Html $dateLabel
  $archiveItem = '<li><a href="/posts/' + $id + '/">Post #' + $id + '</a> <span>' + $safeDate + '</span><div>' + $short + '</div></li>'
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
  <meta property="og:image" content="$BaseUrl/favicon.ico">
  <link rel="icon" href="/favicon.ico" type="image/x-icon">
  <style>
    body { margin: 0; font-family: Helvetica, Arial, sans-serif; background: #f4f6f8; color: #111; }
    .page { max-width: 900px; margin: 0 auto; padding: 20px; }
    h1 { margin-top: 0; }
    a { color: #2267c5; }
    ul { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
    li { background: #fff; border: 1px solid #e5e7eb; border-radius: 10px; padding: 10px 12px; }
    li span { color: #687285; font-size: 12px; margin-left: 6px; }
    li div { margin-top: 6px; color: #222; font-size: 14px; line-height: 1.35; }
    @media (prefers-color-scheme: dark) {
      body { background: #0f1217; color: #eceff4; }
      li { background: #1a1f28; border-color: #2b3342; }
      li div, li span { color: #c7d0de; }
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
  $lastmod = ""
  if ($post.PSObject.Properties.Name -contains "date") {
    try {
      $lastmod = ([DateTime]::Parse([string]$post.date)).ToString("yyyy-MM-dd")
    } catch {
      $lastmod = ""
    }
  }
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
Write-Output "Archive page: $postsRoot/index.html"
Write-Output "Sitemap: $(Join-Path $SiteDir 'sitemap.xml')"
Write-Output "Robots: $(Join-Path $SiteDir 'robots.txt')"
