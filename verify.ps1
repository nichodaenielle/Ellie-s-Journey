$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$html = [IO.File]::ReadAllText((Join-Path $root 'index.html'))

function Read-FilmData($name, $opening, $closing) {
    $pattern = 'var ' + $name + '\s*=\s*(' + $opening + '.*?' + $closing + ');'
    $match = [regex]::Match($html, $pattern, 'Singleline')
    if (-not $match.Success) { throw "Missing $name data" }
    $value = ConvertFrom-Json $match.Groups[1].Value
    if ($value -is [array]) {
        foreach ($entry in $value) { Write-Output $entry }
    } else {
        Write-Output $value
    }
}

function Require-Asset($path) {
    if (-not (Test-Path (Join-Path $root $path))) {
        throw "Missing asset: $path"
    }
}

$clips = @(Read-FilmData 'CLIPS' '\[' '\]')
$scenes = @(Read-FilmData 'SCENES' '\[' '\]')
$photos = Read-FilmData 'PH' '\{' '\}'
if ((Test-Path (Join-Path $root 'film/048.mp4')) -or
    (Test-Path (Join-Path $root 'film/posters/048.jpg'))) {
    throw 'Removed clip 048 is still present'
}
$ids = @{}
foreach ($clip in $clips) {
    if ($clip.n -eq '048') { throw 'Removed clip 048 is still in the clip list' }
    if ($ids.ContainsKey($clip.n)) { throw "Duplicate clip: $($clip.n)" }
    $ids[$clip.n] = $true
    Require-Asset "film/$($clip.n).mp4"
    Require-Asset "film/posters/$($clip.n).jpg"
}

$used = @{}
$slideCount = 0
$lastDate = ''
foreach ($scene in $scenes) {
    foreach ($item in $scene.items) {
        if ($item.c) {
            if (-not $ids.ContainsKey($item.c)) { throw "Unknown scene clip: $($item.c)" }
            if ($used.ContainsKey($item.c)) { throw "Repeated scene clip: $($item.c)" }
            $used[$item.c] = $true
            $date = $item.d
        } else {
            $slideCount++
            $date = $item.p.d
            Require-Asset "film/photos/bg/$($item.p.imgs[0][0]).jpg"
            foreach ($image in $item.p.imgs) {
                if ($image[0] -eq 'P031') { throw 'Removed collage P031 is still in a scene' }
                Require-Asset "film/photos/$($image[0]).jpg"
                Require-Asset "film/photos/th/$($image[0]).jpg"
            }
        }
        if ($date -and $lastDate -and $date -lt $lastDate) {
            throw "Out-of-order scene item: $date follows $lastDate"
        }
        if ($date) { $lastDate = $date }
    }
}
foreach ($id in $ids.Keys) {
    if (-not $used.ContainsKey($id)) { throw "Clip absent from scenes: $id" }
}
Require-Asset "film/photos/$($photos.pro.imgs[0][0]).jpg"
Require-Asset "film/photos/bg/$($photos.pro.imgs[0][0]).jpg"

$playlist = [regex]::Match($html, 'var MUSIC\s*=\s*(\[.*?\]);', 'Singleline')
if (-not $playlist.Success) { throw 'Missing music playlist' }
foreach ($song in (ConvertFrom-Json $playlist.Groups[1].Value)) {
    Require-Asset $song
}

$limit = 25MB
Get-ChildItem (Join-Path $root 'film') -File -Recurse |
    Where-Object { $_.Length -gt $limit } |
    ForEach-Object { throw "Cloudflare asset exceeds 25 MiB: $($_.FullName)" }

Write-Host "OK: $($clips.Count) clips, $slideCount scene slides, $(@($scenes).Count) scenes, all referenced assets present and under 25 MiB."
