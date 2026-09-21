# Imagens de produtos

As coleções antigas continuam nas pastas já existentes. O acervo completo exportado da FuturaIM fica em `catalogo-futuraim`, separado por tipo de produto.

Arquivos de controle:

- `catalogo-futuraim/manifest.json`: fonte principal para automações.
- `catalogo-futuraim/manifest.csv`: versão fácil de revisar no Excel.
- `catalogo-futuraim/import-summary.json`: total importado e contagem por categoria.
- `catalogo-futuraim/product-image-map.csv`: criado pelo sincronizador depois de consultar os produtos da loja.

## Atualizar o acervo no GitHub

Na raiz do projeto, execute:

```powershell
.\scripts\import-product-images.ps1
```

O processo identifica o formato real de cada imagem, corrige extensões truncadas, padroniza os nomes e atualiza os manifestos.

## Preparar a troca das imagens da loja

O token nunca deve ser salvo no repositório:

```powershell
$env:IMPRIMASTORE_API_TOKEN = 'cole-o-token-somente-nesta-janela'
.\scripts\sync-imprimastore-product-images.ps1 -StoreBaseUrl 'https://www.copyeprint.com.br' -Prepare
```

Isso consulta todos os produtos, sugere uma imagem para cada um e cria `product-image-map.csv` para revisão.

Importante: a API pública da ImprimaStore documenta a leitura de produtos, mas não oferece uma operação para alterar `img_principal`. O único upload de imagem documentado é a prévia de um item de pedido (`PUT /pedidos/item/previa/{ftp}`). Por segurança, o script não tenta inventar um endpoint de edição de produto. O arquivo de mapeamento deixa a troca em massa pronta para uma futura rota oficial ou importação administrativa.

Para prévias de itens de pedido, preencha `item_ftp`, marque `review_status` como `approved` e execute explicitamente:

```powershell
.\scripts\sync-imprimastore-product-images.ps1 `
  -StoreBaseUrl 'https://www.copyeprint.com.br' `
  -UploadItemPreviews `
  -ApprovedMapPath '.\home\produtos\catalogo-futuraim\product-image-map.csv'
```
