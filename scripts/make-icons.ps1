# make-icons.ps1 - draw the two plugin icons (1024x1024 PNG) with System.Drawing.
# Flat geometric shapes in white on a coloured rounded tile, with no text, so they read at
# small sizes and on light and dark backgrounds.
#   plugins/idea-forge/.claude-plugin/icon.png    orange tile, white anvil with a spark above it
#   plugins/code-handoff/.claude-plugin/icon.png  blue tile, two panels with arrows passing between them
# Usage (from the repo root): powershell -NoProfile -File scripts/make-icons.ps1
# Re-running overwrites both files.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$size = 1024

function New-Canvas {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  return @($bmp, $g)
}
function New-RoundedRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}
function Draw-Tile($g, [System.Drawing.Color]$color) {
  $tile = New-RoundedRect 32 32 960 960 200
  $brush = New-Object System.Drawing.SolidBrush($color)
  $g.FillPath($brush, $tile)
  $brush.Dispose(); $tile.Dispose()
}
function Points($coords) {
  $pts = @()
  for ($i = 0; $i -lt $coords.Count; $i += 2) { $pts += New-Object System.Drawing.PointF([float]$coords[$i], [float]$coords[$i + 1]) }
  return [System.Drawing.PointF[]]$pts
}
# A four-point star (spark) centred at cx, cy.
function Star-Points([float]$cx, [float]$cy, [float]$outer, [float]$inner) {
  $c = @()
  for ($k = 0; $k -lt 8; $k++) {
    $angle = [Math]::PI / 4 * $k - [Math]::PI / 2
    $r = $inner
    if ($k % 2 -eq 0) { $r = $outer }
    $c += $cx + $r * [Math]::Cos($angle)
    $c += $cy + $r * [Math]::Sin($angle)
  }
  return (Points $c)
}
function Save-Png($bmp, $rel) {
  $path = Join-Path $root $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Host "wrote $rel"
}

$white = [System.Drawing.Color]::White

# --- idea-forge: anvil and spark ---
$c = New-Canvas; $bmp = $c[0]; $g = $c[1]
Draw-Tile $g ([System.Drawing.Color]::FromArgb(255, 217, 72, 15))     # #D9480F
$w = New-Object System.Drawing.SolidBrush($white)
$anvil = Points @(
  150, 470,   330, 440,   850, 440,   850, 540,   720, 565,
  680, 660,   790, 720,   790, 800,   290, 800,   290, 720,
  400, 660,   370, 565,   320, 545,   230, 505
)
$g.FillPolygon($w, $anvil)
$g.FillPolygon($w, (Star-Points 560 250 150 38))
$g.FillPolygon($w, (Star-Points 775 300 70 18))
$g.FillPolygon($w, (Star-Points 360 300 55 14))
Save-Png $bmp 'plugins\idea-forge\.claude-plugin\icon.png'
$w.Dispose(); $g.Dispose(); $bmp.Dispose()

# --- code-handoff: two panels, arrows passing between them ---
$c = New-Canvas; $bmp = $c[0]; $g = $c[1]
Draw-Tile $g ([System.Drawing.Color]::FromArgb(255, 25, 113, 194))    # #1971C2
$pen = New-Object System.Drawing.Pen($white, 44)
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$left = New-RoundedRect 150 250 230 524 48
$right = New-RoundedRect 644 250 230 524 48
$g.DrawPath($pen, $left)
$g.DrawPath($pen, $right)
$w = New-Object System.Drawing.SolidBrush($white)
# Each arrow gets a tile-coloured outline first, so it reads as passing over the panel edges.
$gap = New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(255, 25, 113, 194)), 40)
$gap.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$arrowRight = Points @(270, 392,  640, 392,  640, 330,  770, 424,  640, 518,  640, 456,  270, 456)   # top, pointing right
$arrowLeft = Points @(754, 568,  384, 568,  384, 506,  254, 600,  384, 694,  384, 632,  754, 632)    # bottom, pointing left
foreach ($arrow in @($arrowRight, $arrowLeft)) {
  $g.DrawPolygon($gap, $arrow)
  $g.FillPolygon($w, $arrow)
}
Save-Png $bmp 'plugins\code-handoff\.claude-plugin\icon.png'
$gap.Dispose(); $pen.Dispose(); $w.Dispose(); $left.Dispose(); $right.Dispose(); $g.Dispose(); $bmp.Dispose()
