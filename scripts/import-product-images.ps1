[CmdletBinding()]
param(
    [string]$SourceDirectory = 'Z:\ZAP ZAP\futuraim_site_completo\produtos',
    [string]$DestinationDirectory = (Join-Path $PSScriptRoot '..\home\produtos\catalogo-futuraim'),
    [string]$PublicBaseUrl = 'https://raw.githubusercontent.com/copyeprintlaranjeiras-droid/copy-e-print-assets/main/home/produtos/catalogo-futuraim'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Slug {
    param([Parameter(Mandatory)][string]$Text)

    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = [Text.StringBuilder]::new()
    foreach ($character in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }

    $slug = $builder.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 55) { $slug = $slug.Substring(0, 55).TrimEnd('-') }
    return $slug
}

function Get-ImageExtension {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $header = [byte[]]::new(12)
        $read = $stream.Read($header, 0, $header.Length)
    }
    finally {
        $stream.Dispose()
    }

    if ($read -ge 12 -and [Text.Encoding]::ASCII.GetString($header, 0, 4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($header, 8, 4) -eq 'WEBP') { return '.webp' }
    if ($read -ge 8 -and $header[0] -eq 0x89 -and $header[1] -eq 0x50 -and $header[2] -eq 0x4E -and $header[3] -eq 0x47) { return '.png' }
    if ($read -ge 3 -and $header[0] -eq 0xFF -and $header[1] -eq 0xD8 -and $header[2] -eq 0xFF) { return '.jpg' }
    return $null
}

function Get-Category {
    param([Parameter(Mandatory)][string]$Name)

    switch -Regex ($Name) {
        'calendario|agenda|planner|caderno|apostila' { return 'calendarios-e-agendas' }
        'adesivo|rotulo|etiqueta|lacre|pastilha|transfer|decalque' { return 'adesivos-e-rotulos' }
        'banner|backdrop|wind-banner|placa|totem|faixa|display|lona|cavalete|bandeira' { return 'banners-e-sinalizacao' }
        'camisa|camiseta|agasalho|bermuda|calca|bone|abada|cropped|rash|colete|avental|uniforme|vestido' { return 'vestuario' }
        'embalagem|sacola|caixa|cartucho|barca|cinta|porta-talher|forminha|pipoca|delivery|envoltorio|saco-' { return 'embalagens' }
        'caneca|copo|garrafa|squeeze|chaveiro|caneta|ecobag|almofada|capa-|capinha|guarda-chuva|mochila|taca|balde|azulejo|abridor|baralho|brinde' { return 'personalizados-e-brindes' }
        'folder|folheto|panfleto|flyer' { return 'folders-e-folhetos' }
        'cartao|postal|tag-|cracha|credencial|convite|papel|receituario|prontuario|ficha|envelope|carimbo|bloco|certificado|ingresso|marcador' { return 'cartoes-e-papelaria' }
        'festa|evento|topo-de-bolo|lembrancinha|convite' { return 'festas-e-eventos' }
        default { return 'diversos' }
    }
}

$source = [IO.Path]::GetFullPath($SourceDirectory)
$destination = [IO.Path]::GetFullPath($DestinationDirectory)
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Pasta de origem não encontrada: $source"
}

[IO.Directory]::CreateDirectory($destination) | Out-Null
$records = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[string]]::new()

foreach ($file in Get-ChildItem -LiteralPath $source -File | Sort-Object Name) {
    $extension = Get-ImageExtension -Path $file.FullName
    if (-not $extension) {
        $skipped.Add($file.Name)
        continue
    }

    $sequence = if ($file.BaseName -match '^(\d{5})') { $Matches[1] } else { '{0:D5}' -f ($records.Count + 1) }
    $description = $file.BaseName -replace '^\d{5}_\d+x\d+(?:-\d+)?-', ''
    $description = $description -replace '_\d+(?:_\d+)?$', ''
    $category = Get-Category -Name $description.ToLowerInvariant()
    $slug = ConvertTo-Slug -Text $description
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "produto-$sequence" }

    $targetName = "$sequence-$slug$extension"
    $categoryDirectory = Join-Path $destination $category
    [IO.Directory]::CreateDirectory($categoryDirectory) | Out-Null
    $targetPath = Join-Path $categoryDirectory $targetName
    Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force

    $relativePath = "$category/$targetName"
    $records.Add([pscustomobject][ordered]@{
        sequence        = $sequence
        category        = $category
        product_hint    = ($description -replace '-', ' ')
        source_filename = $file.Name
        file_name       = $targetName
        relative_path   = $relativePath
        public_url      = "$($PublicBaseUrl.TrimEnd('/'))/$relativePath"
        bytes           = $file.Length
        sha256          = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

$manifestJson = Join-Path $destination 'manifest.json'
$manifestCsv = Join-Path $destination 'manifest.csv'
$records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestJson -Encoding utf8
$records | Export-Csv -LiteralPath $manifestCsv -NoTypeInformation -Encoding utf8

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source       = $source
    destination  = $destination
    imported     = $records.Count
    skipped      = $skipped.Count
    categories   = @($records | Group-Object category | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; count = $_.Count }
    })
    skipped_files = @($skipped)
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'import-summary.json') -Encoding utf8

$summary
