# Do artigo ao banco de dados: estruturas do PDB citadas na literatura

Trabalho da disciplina FCM 2026 (prof. Thomas Nogueira Vilches).
Ricardo de Paiva Caetano, Pedro Yuji Yashima, José Victor Orlandi.

Pipeline em R que pega um conjunto de artigos, acha os códigos PDB citados no texto,
busca as informações de cada estrutura no PDB e guarda tudo num banco SQL.

## Divisão

| Etapa | Quem |
|---|---|
| 1–2. Seleção dos artigos, download dos PDFs e extração dos códigos | Ricardo |
| 3. Web scraping no PDB | Ricardo |
| 4. Banco SQL (revistas, artigos, menções, estruturas) | Pedro |
| 5. Tratamento e integração das tabelas no tidyverse | Pedro |
| Gráficos, relatório e apresentação | José Victor |

## Artigos

20 artigos de acesso aberto, os 10 mais recentes de cada revista (`n_por_revista` no script):

- **IUCrJ**: experimental, quase sempre deposita estrutura nova
- **PLoS Computational Biology**: computacional, normalmente reaproveita estruturas que já existem

Critério (`R/00_selecionar_artigos.R`): busca na Europe PMC por `JOURNAL + OPEN_ACCESS:y + ACCESSION_TYPE:pdb`,
do mais novo pro mais antigo (na mesma data, o de PMID mais novo primeiro), e fica com os 10 primeiros de cada
revista que tenham pelo menos 3 códigos PDB diferentes segundo a Europe PMC. Não tira nada à mão: artigo de RNA,
DNA ou mineral entra também, e na análise dá pra separar pela `classificacao` da estrutura e pelas `entidades`
(estrutura sem proteína não tem linha em `entidades.csv`). Como a busca sempre pega os mais recentes, a lista muda
cada vez que o script roda.
A lista está em `dados/artigos_selecionados.csv`.

## Como rodar

Rodar da pasta do projeto, na ordem:

```r
source("R/00_selecionar_artigos.R") # atualiza dados/artigos_selecionados.csv com os artigos mais recentes
source("R/01_baixar_pdfs.R")   # baixa os pdfs pra pasta pdfs/ (fica fora do git)
source("R/02_extrair_pdb.R")   # gera saida/mencoes_pdb.csv
source("R/03_scraping_pdb.R")  # gera saida/estruturas.csv, saida/entidades.csv e saida/codigos_nao_encontrados.csv
```

Pacotes: `tidyverse`, `jsonlite`, `pdftools`, `rvest`.

## Extração dos códigos

- regex `\b[1-9][a-z0-9]{3}\b` sem diferenciar maiúscula, exigindo pelo menos uma letra (senão pega ano)
- só conta se tiver "PDB", "entry", "accession" etc. na mesma linha ou até 6 linhas acima
- na IUCrJ o bloco "PDB references: ... Supporting information" do resumo conta inteiro
- tira ordinal (2nd, 3rd) e unidade (10mJ, 100ms)

Comparando com a mineração de texto da Europe PMC (seleção de 18/11/2026): 114 códigos em comum, 12 que só a gente
achou (alguns são códigos reais, outros são lixo tipo `20AD` do equipamento "LC-20AD" ou `600S` de "600 s", que caem
quando a busca no PDB não acha nada) e 23 que a gente perdeu (código em figura ou em linha de tabela longe do cabeçalho;
11 deles num artigo só, o `PMC13324649`).

## Scraping no PDB

Para cada código em `saida/mencoes_pdb.csv`, o script entra em `https://www.rcsb.org/structure/<codigo>`
e pega pelo `id` do elemento:

| Coluna | De onde vem |
|---|---|
| `nome` | `#structureTitle` |
| `classificacao` | `#header_classification` |
| `organismo` | `#header_organism` |
| `metodo` | `#exp_header_0_method` |
| `resolucao` (Å) | `#exp_header_0_diffraction_resolution` (raio X) ou `#exp_header_0_em_resolution` (crio-ME); NMR fica NA |
| `data_deposito` | texto "Deposited:" |
| `massa_kda` | `#contentStructureWeight` |
| `n_cadeias` | texto "Unique protein chains:" (cadeias proteicas **únicas**, não o total) |
| `doi_estrutura` | `#pubmedDOI`, DOI da publicação original da estrutura |

Da mesma página sai também `saida/entidades.csv`, com uma linha por proteína da estrutura (cada tabela
`#table_macromolecule-protein-entityId-N`). Uma estrutura da spike com um anticorpo, por exemplo, vira 3 linhas.
Serve pra juntar estruturas diferentes da mesma proteína e ver quais proteínas aparecem em mais artigos.

| Coluna | De onde vem |
|---|---|
| `entidade` | número da entidade na estrutura (o `N` do id da tabela) |
| `molecula` | coluna "Molecule" |
| `organismo` | coluna "Organism" (pode ser diferente do organismo da estrutura, ex.: anticorpo sintético) |
| `uniprot` | link pro uniprot.org; NA quando não tem (anticorpo, construção sintética), separado por `;` se tiver mais de um |
| `gene` | "Gene Names:" nos detalhes |
| `ec` | "EC:" nos detalhes, classe da enzima; NA se não for enzima |

Coleta responsável: 2 s entre uma página e outra, e o script só busca o que ainda não está em
`estruturas.csv` nem em `codigos_nao_encontrados.csv`. Código que dá 404 (lixo da extração, tipo `207A`)
ou que existe mas ainda não foi liberado (o `25CN` cai em `/structure/unreleased/`, com a página sem título)
vai para `codigos_nao_encontrados.csv` e não é buscado de novo.

Resultado da seleção de 18/11/2026: 123 códigos únicos → 120 estruturas e 3 não encontrados (`20AD`, `600S`, `18NZ`).
83 de raio X, 33 de crio-ME, 3 de cristalografia de elétrons e 1 sem método (`5WH0`, que não foi liberado mas tem título).
3 códigos aparecem em mais de um artigo (`7BH3`, `9TO1`, `9TO5`) e 30 estruturas foram depositadas pelo próprio artigo.
As 120 estruturas têm 199 entidades, 185 delas com UniProt, que dão 102 proteínas diferentes. 2 proteínas aparecem
em mais de um artigo (beta-lactamase CTX-M-15 `G3G192` e integrina alfa-M `P11215`) e várias aparecem em muitas
estruturas do mesmo artigo (11 da CTX-M-15, 10 da L-asparaginase 2, 7 da spike). 2 estruturas não têm entidade de
proteína (o `9YRD`, que é RNA, e o `5WH0`).

`estruturas.csv`, `entidades.csv` e `codigos_nao_encontrados.csv` não apagam nada das seleções antigas, então para
analisar só a seleção atual tem que cruzar com `mencoes_pdb.csv`.

A página do RCSB já vem pronta no HTML, então aqui dá para usar `read_html()` direto, sem `chromote`.
