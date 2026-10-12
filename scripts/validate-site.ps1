[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$message) {
    $failures.Add($message)
}

function Get-PortableRelativePath([string]$basePath, [string]$targetPath) {
    $normalizedBase = [IO.Path]::GetFullPath($basePath).TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    $normalizedTarget = [IO.Path]::GetFullPath($targetPath)
    $baseUri = [Uri]::new($normalizedBase)
    $targetUri = [Uri]::new($normalizedTarget)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('\', '/')
}

$requiredFiles = @(
    '.nojekyll',
    'README.md',
    'index.html',
    'style.css',
    'app.js',
    'data.js',
    'assets/brand-mark.svg',
    'assets/package-architecture.svg',
    'templates/document.html',
    'templates/card.example.js',
    'docs/case-study.html',
    'docs/overview.html',
    'docs/architecture.html',
    'docs/android-setup.html',
    'docs/modules.html',
    'docs/verification.html',
    'docs/contributing.html',
    'scripts/new-document.ps1'
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        Add-Failure "Missing required file: $relativePath"
    }
}

$forbiddenNames = @(
    'google-services.json',
    'GoogleService-Info.plist',
    'keystore.properties',
    'signing.properties'
)

foreach ($name in $forbiddenNames) {
    $found = Get-ChildItem -LiteralPath $root -Recurse -Force -File -Filter $name -ErrorAction SilentlyContinue
    if ($found) {
        Add-Failure "Forbidden file included: $name"
    }
}

$forbiddenExtensions = @('.apk', '.aab', '.keystore', '.jks')
Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\.git\*" -and $_.Extension -in $forbiddenExtensions } |
    ForEach-Object { Add-Failure "Forbidden build/signing artifact: $($_.FullName)" }

$htmlFiles = Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.html' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\.git\*" -and $_.FullName -notlike "*\.superpowers\*" }

foreach ($html in $htmlFiles) {
    $content = Get-Content -LiteralPath $html.FullName -Raw
    $relative = Get-PortableRelativePath $root $html.FullName

    if ($content -notmatch '<html\s+lang="ko"') {
        Add-Failure "${relative}: missing lang=ko"
    }
    if ($content -notmatch '<meta\s+name="viewport"') {
        Add-Failure "${relative}: missing viewport metadata"
    }
    if ($content -notmatch '<title>[^<]+</title>') {
        Add-Failure "${relative}: missing document title"
    }
    if ($content -match 'C:\\Users\\|file://') {
        Add-Failure "${relative}: contains an absolute local path"
    }

    $attributeMatches = [regex]::Matches($content, '(?:href|src)="([^"]+)"')
    foreach ($match in $attributeMatches) {
        $url = $match.Groups[1].Value
        if ($url -match '^(?:https?:|mailto:|#|data:|javascript:)') {
            continue
        }

        $pathOnly = ($url -split '[?#]')[0]
        if ([string]::IsNullOrWhiteSpace($pathOnly)) {
            continue
        }

        $resolved = [IO.Path]::GetFullPath((Join-Path $html.DirectoryName $pathOnly))
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-Failure "${relative}: broken local reference $url"
        }
    }
}

$dataPath = Join-Path $root 'data.js'
if (Test-Path -LiteralPath $dataPath) {
    $dataContent = Get-Content -LiteralPath $dataPath -Raw
    $urls = [regex]::Matches($dataContent, 'url:\s*["'']([^"'']+)["'']') |
        ForEach-Object { $_.Groups[1].Value }

    $duplicates = $urls | Group-Object | Where-Object Count -gt 1
    foreach ($duplicate in $duplicates) {
        Add-Failure "Duplicate card URL: $($duplicate.Name)"
    }

    foreach ($url in $urls) {
        if ($url -match '^https?://') {
            continue
        }
        $pathOnly = ($url -split '[?#]')[0]
        if (-not (Test-Path -LiteralPath (Join-Path $root $pathOnly))) {
            Add-Failure "data.js references missing document: $url"
        }
    }

    foreach ($section in @('case-study', 'start', 'architecture', 'sdk', 'verification', 'operations')) {
        if ($dataContent -notmatch ('id:\s*["'']' + [regex]::Escape($section) + '["'']')) {
            Add-Failure "data.js missing section: $section"
        }
    }
}

$textFiles = Get-ChildItem -LiteralPath $root -Recurse -Force -File -Include '*.html', '*.js', '*.css', '*.md', '*.svg', '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\.git\*" -and $_.FullName -notlike "*\.superpowers\*" }

foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match '(?i)(api[_-]?key|client[_-]?secret|private[_-]?key)\s*[:=]\s*["''][A-Za-z0-9_\-]{16,}') {
        Add-Failure "Possible secret in $(Get-PortableRelativePath $root $file.FullName)"
    }
}

$node = Get-Command node -ErrorAction SilentlyContinue
$appPath = Join-Path $root 'app.js'
if ($node -and (Test-Path -LiteralPath $appPath)) {
    $testScript = @'
const assert = require('node:assert/strict');
const utils = require(process.argv[1]);
const cards = [
  { title: 'Core package', desc: 'SDK neutral', tags: ['UPM'], project: 'mobile', pinned: false },
  { title: 'Firebase adapter', desc: 'Analytics', tags: ['SDK'], project: 'mobile', pinned: true }
];
assert.equal(utils.matchesCard(cards[0], 'neutral', 'all', 'architecture'), true);
assert.equal(utils.matchesCard(cards[0], 'missing', 'all', 'architecture'), false);
assert.equal(utils.matchesCard(cards[0], '', 'mobile', 'architecture'), true);
assert.equal(utils.matchesCard(cards[0], '', 'other', 'architecture'), false);
assert.deepEqual(utils.sortCards(cards).map(card => card.title), ['Firebase adapter', 'Core package']);
console.log('JavaScript behavior checks passed');
'@
    $nodeOutput = & $node.Source -e $testScript $appPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "JavaScript behavior checks failed: $($nodeOutput -join ' ')"
    } else {
        Write-Output ($nodeOutput -join [Environment]::NewLine)
    }
} elseif (-not $node) {
    Add-Failure 'Node.js is unavailable; JavaScript behavior checks could not run'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Site validation failed with $($failures.Count) issue(s)."
}

Write-Output "Site validation passed: $($requiredFiles.Count) required files, $($htmlFiles.Count) HTML files."
