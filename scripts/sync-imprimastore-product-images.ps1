[CmdletBinding(DefaultParameterSetName = 'Prepare')]
param(
    [Parameter(Mandatory)][ValidatePattern('^https://')][string]$StoreBaseUrl,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\home\produtos\catalogo-futuraim\manifest.json'),
    [string]$MapPath = (Join-Path $PSScriptRoot '..\home\produtos\catalogo-futuraim\product-image-map.csv'),
    [Parameter(ParameterSetName = 'Prepare')][switch]$Prepare,
    [Parameter(ParameterSetName = 'Upload')][switch]$UploadItemPreviews,
    [Parameter(ParameterSetName = 'Upload', Mandatory)][string]$ApprovedMapPath,
    [int]$DelayMilliseconds = 200
)

$ErrorActionPreference = 'Stop'
$token = $env:IMPRIMASTORE_API_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Defina IMPRIMASTORE_API_TOKEN somente na sessão atual antes de executar.'
}

$apiRoot = "$($StoreBaseUrl.TrimEnd('/'))/api-v1"
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

function ConvertTo-ComparableText {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = [Text.StringBuilder]::new()
    foreach ($character in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return (($builder.ToString().ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim())
}

function Get-AllProducts {
    $all = [Collections.Generic.List[object]]::new()
    $page = 1
    do {
        $response = Invoke-RestMethod -Method Get -Uri "$apiRoot/produtos?pagina=$page" -Headers $headers
        foreach ($record in @($response.registros)) { $all.Add($record) }
        $next = $response.paginacao.proxima_pagina
        $page++
    } while ($null -ne $next -and "$next" -ne '')
    return $all
}

function Get-MatchScore {
    param([string]$ProductText, [string]$ImageText)
    $productWords = @((ConvertTo-ComparableText $ProductText) -split ' ' | Where-Object Length -ge 3 | Select-Object -Unique)
    $imageWords = @((ConvertTo-ComparableText $ImageText) -split ' ' | Where-Object Length -ge 3 | Select-Object -Unique)
    if ($productWords.Count -eq 0 -or $imageWords.Count -eq 0) { return 0 }
    $matches = @($productWords | Where-Object { $imageWords -contains $_ }).Count
    return [Math]::Round((2.0 * $matches) / ($productWords.Count + $imageWords.Count), 4)
}

if ($PSCmdlet.ParameterSetName -eq 'Prepare') {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $products = Get-AllProducts
    $map = foreach ($product in $products) {
        $productText = "$($product.titulo) $($product.url) $($product.material) $($product.formato) $($product.categoria) $($product.subcategoria)"
        $best = $manifest | ForEach-Object {
            [pscustomobject]@{ image = $_; score = Get-MatchScore -ProductText $productText -ImageText $_.product_hint }
        } | Sort-Object score -Descending | Select-Object -First 1

        [pscustomobject][ordered]@{
            product_id       = $product.id
            product_title    = $product.titulo
            product_url      = $product.url
            current_image    = $product.img_principal
            proposed_image   = $best.image.public_url
            source_file      = $best.image.relative_path
            match_score      = $best.score
            review_status    = if ($best.score -ge 0.35) { 'review' } else { 'needs-manual-match' }
            item_ftp         = ''
        }
    }
    $map | Export-Csv -LiteralPath $MapPath -NoTypeInformation -Encoding utf8
    [pscustomobject]@{ products = $products.Count; map = [IO.Path]::GetFullPath($MapPath); mode = 'preview-only' }
    return
}

# A API pública documentada não altera img_principal de produto. Este modo atende
# exclusivamente o endpoint oficial PUT /pedidos/item/previa/{ftp}.
$approved = Import-Csv -LiteralPath $ApprovedMapPath | Where-Object {
    $_.review_status -eq 'approved' -and -not [string]::IsNullOrWhiteSpace($_.item_ftp)
}
if ($approved.Count -eq 0) { throw 'Nenhuma linha aprovada com item_ftp foi encontrada.' }

$log = [Collections.Generic.List[object]]::new()
foreach ($row in $approved) {
    $image = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $ManifestPath) $row.source_file))
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) {
        $log.Add([pscustomobject]@{ ftp = $row.item_ftp; status = 'missing-file'; file = $image; message = '' })
        continue
    }

    try {
        $result = Invoke-RestMethod -Method Put -Uri "$apiRoot/pedidos/item/previa/$($row.item_ftp)" -Headers $headers -Form @{ file = Get-Item -LiteralPath $image }
        $log.Add([pscustomobject]@{ ftp = $row.item_ftp; status = 'updated'; file = $image; message = $result.sucesso })
    }
    catch {
        $log.Add([pscustomobject]@{ ftp = $row.item_ftp; status = 'error'; file = $image; message = $_.Exception.Message })
    }
    Start-Sleep -Milliseconds $DelayMilliseconds
}

$logPath = Join-Path (Split-Path -Parent $ApprovedMapPath) ("upload-log-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$log | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding utf8
$log
