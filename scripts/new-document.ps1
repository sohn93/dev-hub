[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Slug,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Title
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $root 'templates/document.html'
$docsDirectory = Join-Path $root 'docs'
$destination = Join-Path $docsDirectory "$Slug.html"

if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Document template not found: $templatePath"
}

if (Test-Path -LiteralPath $destination) {
    throw "Document already exists: $destination"
}

$content = Get-Content -LiteralPath $templatePath -Raw
$content = $content.Replace('{{TITLE}}', $Title)
$content = $content.Replace('{{SLUG}}', $Slug)
$content = $content.Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd'))

if ($PSCmdlet.ShouldProcess($destination, 'Create document from template')) {
    if (-not (Test-Path -LiteralPath $docsDirectory)) {
        New-Item -ItemType Directory -Path $docsDirectory | Out-Null
    }
    [IO.File]::WriteAllText($destination, $content, [Text.UTF8Encoding]::new($false))
    Write-Output $destination
}
