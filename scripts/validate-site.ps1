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

function Test-PathInsideRoot([string]$basePath, [string]$targetPath) {
    $normalizedBase = [IO.Path]::GetFullPath($basePath).TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    $normalizedTarget = [IO.Path]::GetFullPath($targetPath)
    return $normalizedTarget.StartsWith($normalizedBase, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ExactPathCase([string]$basePath, [string]$targetPath) {
    if (-not (Test-PathInsideRoot $basePath $targetPath)) {
        return $false
    }

    $relative = Get-PortableRelativePath $basePath $targetPath
    $current = [IO.Path]::GetFullPath($basePath)
    foreach ($segment in ($relative -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }
        $match = Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ceq $segment } |
            Select-Object -First 1
        if (-not $match) {
            return $false
        }
        $current = $match.FullName
    }
    return $true
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
    $content = Get-Content -LiteralPath $html.FullName -Raw -Encoding UTF8
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
    $attributeMatches = [regex]::Matches($content, '(?:href|src)="([^"]+)"')
    foreach ($match in $attributeMatches) {
        $url = $match.Groups[1].Value
        if ($url -match '^(?:https?:|mailto:|data:|javascript:)') {
            continue
        }

        if ($url.StartsWith('/') -or $url.StartsWith('\')) {
            Add-Failure "${relative}: root-relative reference is not project-site safe: $url"
            continue
        }

        $fragment = if ($url.Contains('#')) { [Uri]::UnescapeDataString(($url -split '#', 2)[1]) } else { '' }
        $pathOnly = [Uri]::UnescapeDataString((($url -split '#', 2)[0] -split '\?', 2)[0])
        if ([string]::IsNullOrWhiteSpace($pathOnly)) {
            $resolved = $html.FullName
        } else {
            $resolved = [IO.Path]::GetFullPath((Join-Path $html.DirectoryName $pathOnly))
        }

        if (-not (Test-PathInsideRoot $root $resolved)) {
            Add-Failure "${relative}: local reference escapes the repository: $url"
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-Failure "${relative}: broken local reference $url"
            continue
        }
        if (-not (Test-ExactPathCase $root $resolved)) {
            Add-Failure "${relative}: local reference has incorrect filename casing: $url"
        }
        if ($fragment -and [IO.Path]::GetExtension($resolved) -ieq '.html') {
            $targetContent = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
            $escapedFragment = [regex]::Escape($fragment)
            if ($targetContent -notmatch ('(?:id|name)="' + $escapedFragment + '"')) {
                Add-Failure "${relative}: missing fragment target $url"
            }
        }
    }
}

$dataPath = Join-Path $root 'data.js'
if (Test-Path -LiteralPath $dataPath) {
    $dataContent = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8
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

        if ($url.StartsWith('/') -or $url.StartsWith('\')) {
            Add-Failure "data.js contains a root-relative URL that is not project-site safe: $url"
            continue
        }

        $fragment = if ($url.Contains('#')) { [Uri]::UnescapeDataString(($url -split '#', 2)[1]) } else { '' }
        $pathOnly = [Uri]::UnescapeDataString((($url -split '#', 2)[0] -split '\?', 2)[0])
        $resolved = [IO.Path]::GetFullPath((Join-Path $root $pathOnly))
        if (-not (Test-PathInsideRoot $root $resolved)) {
            Add-Failure "data.js URL escapes the repository: $url"
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-Failure "data.js references missing document: $url"
            continue
        }
        if (-not (Test-ExactPathCase $root $resolved)) {
            Add-Failure "data.js URL has incorrect filename casing: $url"
        }
        if ($fragment -and [IO.Path]::GetExtension($resolved) -ieq '.html') {
            $targetContent = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
            $escapedFragment = [regex]::Escape($fragment)
            if ($targetContent -notmatch ('(?:id|name)="' + $escapedFragment + '"')) {
                Add-Failure "data.js URL has a missing fragment target: $url"
            }
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
$privatePathPattern = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String('KD9pKSg/OltBLVpdOlxcVXNlcnNcXHxbQS1aXTovVXNlcnMvfC8oPzpVc2Vyc3xob21lKS9bXi9cc10rL3xcXFxcW15cXFxzXStcXCk=')
)

foreach ($file in $textFiles) {
    [string]$content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($content -match '(?i)(api[_-]?key|client[_-]?secret|private[_-]?key)\s*[:=]\s*["''][A-Za-z0-9_\-]{16,}') {
        Add-Failure "Possible secret in $(Get-PortableRelativePath $root $file.FullName)"
    }
    $fileUriToken = 'file:' + '//'
    if ($content -match $privatePathPattern -or
        $content.Contains($fileUriToken)) {
        Add-Failure "Possible private local path in $(Get-PortableRelativePath $root $file.FullName)"
    }
}

$node = Get-Command node -ErrorAction SilentlyContinue
$appPath = Join-Path $root 'app.js'
if ($node -and (Test-Path -LiteralPath $appPath)) {
    $testScript = @'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const utils = require(process.argv[1]);
const dataPath = process.argv[2];
const context = { window: {} };
vm.runInNewContext(fs.readFileSync(dataPath, 'utf8'), context, { filename: dataPath });
const data = context.window.DEV_HUB_DATA;
assert.ok(data && Array.isArray(data.projects) && Array.isArray(data.sections), 'real catalog must load');
assert.equal(new Set(data.projects.map(project => project.id)).size, data.projects.length, 'project IDs must be unique');
assert.equal(new Set(data.sections.map(section => section.id)).size, data.sections.length, 'section IDs must be unique');
const projectIds = new Set(data.projects.map(project => project.id));
for (const section of data.sections) {
  assert.ok(Array.isArray(section.cards), `${section.id} cards must be an array`);
  for (const card of section.cards) assert.ok(projectIds.has(card.project), `${card.title} uses an unknown project`);
}
const cards = [
  { title: 'Core package', desc: 'SDK neutral', tags: ['UPM'], project: 'mobile', pinned: false },
  { title: 'Firebase adapter', desc: 'Analytics', tags: ['SDK'], project: 'mobile', pinned: true }
];
assert.equal(utils.matchesCard(cards[0], 'neutral', 'all', 'architecture'), true);
assert.equal(utils.matchesCard(cards[0], 'missing', 'all', 'architecture'), false);
assert.equal(utils.matchesCard(cards[0], '', 'mobile', 'architecture'), true);
assert.equal(utils.matchesCard(cards[0], '', 'other', 'architecture'), false);
assert.deepEqual(utils.sortCards(cards).map(card => card.title), ['Firebase adapter', 'Core package']);
assert.equal(utils.visibleSections(data, data.projects[0].label, 'all').length > 0, true);
assert.equal(utils.visibleSections(data, 'no-result-query', 'all').length, 0);
for (const project of data.projects) {
  const expectedCount = data.sections.reduce((sum, section) => sum + section.cards.filter(card => card.project === project.id).length, 0);
  const actualCount = utils.visibleSections(data, '', project.id).reduce((sum, section) => sum + section.cards.length, 0);
  assert.equal(actualCount, expectedCount, `${project.id} filter count must match its own cards`);
}
console.log('JavaScript behavior checks passed');
'@
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $nodeOutput = & $node.Source -e $testScript $appPath $dataPath 2>&1
    $nodeExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($nodeExitCode -ne 0) {
        Add-Failure "JavaScript behavior checks failed: $($nodeOutput -join ' ')"
    } else {
        Write-Output ($nodeOutput -join [Environment]::NewLine)
    }
} elseif (-not $node) {
    Add-Failure 'Node.js is unavailable; JavaScript behavior checks could not run'
}

$architecturePath = Join-Path $root 'assets/package-architecture.svg'
if (Test-Path -LiteralPath $architecturePath) {
    $architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8
    if ($architecture -notmatch 'M206 420v-35h144v-49' -or $architecture -notmatch 'M674 420v-35H530v-49') {
        Add-Failure 'Architecture diagram must point from both SDK adapters toward Core'
    }
}

$androidSetupPath = Join-Path $root 'docs/android-setup.html'
if (Test-Path -LiteralPath $androidSetupPath) {
    $androidSetup = Get-Content -LiteralPath $androidSetupPath -Raw -Encoding UTF8
    if ($androidSetup -notmatch 'google-services\.json[\s\S]{0,800}Build Sample Scenes') {
        Add-Failure 'Firebase setup must rebuild sample scenes after adding google-services.json'
    }
}

$generatorPath = Join-Path $root 'scripts/new-document.ps1'
if (Test-Path -LiteralPath $generatorPath) {
    $generator = Get-Content -LiteralPath $generatorPath -Raw -Encoding UTF8
    if ($generator -notmatch 'Get-Content[^\r\n]+-Encoding UTF8') {
        Add-Failure 'Document generator must read the UTF-8 template explicitly'
    }
    if ($generator -notmatch 'HtmlEncode') {
        Add-Failure 'Document generator must HTML-encode titles'
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Site validation failed with $($failures.Count) issue(s)."
}

Write-Output "Site validation passed: $($requiredFiles.Count) required files, $($htmlFiles.Count) HTML files."
