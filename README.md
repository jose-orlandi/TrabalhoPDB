# Do artigo ao banco de dados: estruturas do PDB citadas na literatura

Trabalho da disciplina FCM 2026 (prof. Thomas Nogueira Vilches).
Ricardo de Paiva Caetano, Pedro Yuji Yashima, José Victor Orlandi.

Pipeline em R que pega os artigos mais recentes de duas revistas, acha os códigos PDB citados no texto,
busca as informações de cada estrutura no RCSB PDB e guarda tudo num banco PostgreSQL.

O PDB diz quais estruturas existem, mas não quais estão sendo estudadas. As citações nos artigos mostram isso:
que proteínas, organismos e métodos a comunidade está usando agora, e quanto ela reaproveita estrutura que já
existe. Como a seleção sempre pega os artigos mais novos, cada rodada é uma foto atualizada do campo.

## Como funciona

```
Europe PMC ──00──> dados/artigos_selecionados.csv
                         │
PMC (AWS) ───01──> pdfs/ (fora do git)
                         │
             ──02──> saida/mencoes_pdb.csv
                         │
RCSB PDB ────03──> saida/estruturas.csv + saida/entidades.csv + saida/codigos_nao_encontrados.csv
                         │
             ──04──> PostgreSQL, schema pdb
```

| Script | O que faz | Tempo (10 artigos por revista) |
|---|---|---|
| `R/00_selecionar_artigos.R` | escolhe os artigos mais recentes de cada revista na Europe PMC | 1 a 3 min |
| `R/01_baixar_pdfs.R` | baixa os PDFs do PubMed Central | ~2 min (só baixa o que falta) |
| `R/02_extrair_pdb.R` | lê os PDFs e acha os códigos PDB citados | segundos |
| `R/03_scraping_pdb.R` | busca cada código no RCSB (estrutura e proteínas) | ~3 s por código novo |
| `R/04_banco_sql.R` | monta o banco a partir dos csv | segundos |

## Estrutura do repositório

```
R/                    scripts do pipeline, na ordem (00 a 04)
sql/
  01_criar_tabelas.sql  tabelas do banco
  02_consultas.sql      consultas de exemplo
dados/
  artigos_selecionados.csv
saida/
  mencoes_pdb.csv               qual artigo cita qual código
  estruturas.csv                uma linha por estrutura
  entidades.csv                 uma linha por proteína de cada estrutura
  codigos_nao_encontrados.csv   códigos que não existem no RCSB
.Renviron.exemplo     modelo da configuração do banco
```

## Divisão

| Etapa | Quem |
|---|---|
| 1–2. Seleção dos artigos, download dos PDFs e extração dos códigos | Ricardo |
| 3. Web scraping no PDB | Ricardo |
| 4. Banco SQL | Pedro |
| 5. Tratamento e integração das tabelas no tidyverse | Pedro |
| Gráficos, relatório e apresentação | José Victor |

## Como rodar

### 1. Pacotes do R

```r
install.packages(c("tidyverse", "jsonlite", "pdftools", "rvest", "DBI", "RPostgres"))
```

No Linux alguns pacotes compilam e precisam de bibliotecas do sistema. No Ubuntu/Mint:

```bash
sudo apt install libcurl4-openssl-dev libxml2-dev libssl-dev libpoppler-cpp-dev libpq-dev \
  libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype-dev libtiff-dev libwebp-dev
```

Se o pacote `fs` reclamar do `uv.h`, instalar com `Sys.setenv(USE_BUNDLED_LIBUV = 1)` antes do `install.packages`.

### 2. PostgreSQL (só pro script 04)

```bash
sudo apt install postgresql
sudo -u postgres psql -c "\password postgres"   # define a senha do usuário postgres
sudo -u postgres createdb pdb_pipeline
cp .Renviron.exemplo .Renviron                  # e colocar a senha no .Renviron
```

O `.Renviron` fica na pasta do projeto e fora do git. O R lê ele quando abre, então tem que abrir o R na pasta
do projeto.

### 3. Rodar

Da pasta do projeto, na ordem:

```r
source("R/00_selecionar_artigos.R")
source("R/01_baixar_pdfs.R")
source("R/02_extrair_pdb.R")
source("R/03_scraping_pdb.R")
source("R/04_banco_sql.R")
```

Pra mudar quantos artigos entram, trocar `n_por_revista` no começo do script 00. O scraping é a parte demorada:
com 50 artigos por revista são uns 600 códigos, perto de 30 minutos.

## As etapas

### 00. Seleção dos artigos

Duas revistas, pra comparar o lado experimental com o computacional:

- **IUCrJ**: experimental, quase sempre deposita estrutura nova
- **PLoS Computational Biology**: computacional, normalmente reaproveita estruturas que já existem

Busca na API da Europe PMC por `JOURNAL + OPEN_ACCESS:y + ACCESSION_TYPE:pdb`, do mais novo pro mais antigo
(na mesma data, o de PMID mais novo primeiro). Pra cada artigo, pergunta à API de anotações da Europe PMC quantos
códigos PDB diferentes ela achou no texto, e fica com os 10 primeiros de cada revista que tenham pelo menos 3.
Quando a API não responde, tenta de novo até 3 vezes.

Não tira nada à mão: artigo de RNA, DNA ou mineral entra também, e na análise dá pra separar pela `classificacao`
da estrutura ou pelas entidades (estrutura sem proteína não tem linha em `entidades.csv`). Como a busca sempre pega
os mais recentes, a lista muda cada vez que o script roda.

### 01. Download dos PDFs

O site do PMC barra download automático, então os PDFs vêm do bucket aberto do PubMed Central na AWS
(`pmc-oa-opendata.s3.amazonaws.com`). O script lista os arquivos do artigo, fica só com o PDF principal (sem o
material suplementar) e baixa a versão mais recente pra `pdfs/`, com 2 s entre um download e outro. PDF que já
está na pasta não é baixado de novo. A pasta `pdfs/` fica fora do git.

### 02. Extração dos códigos

- regex: 1 dígito de 1 a 9 mais 3 caracteres, sem diferenciar maiúscula, exigindo pelo menos uma letra (senão pega ano)
- só conta se tiver "PDB", "entry", "accession" etc. na mesma linha ou até 6 linhas acima
- na IUCrJ o bloco "PDB references: ... Supporting information" do resumo conta inteiro
- tira ordinal (2nd, 3rd) e unidade (10mJ, 100ms)

Sobra algum lixo (tipo `20AD`, do equipamento "LC-20AD"), que cai no scraping quando o RCSB não acha o código.

### 03. Scraping no RCSB PDB

Pra cada código em `saida/mencoes_pdb.csv`, o script entra em `https://www.rcsb.org/structure/<codigo>` e pega
pelo `id` do elemento. A página já vem pronta no HTML, então dá pra usar `read_html()` direto, sem `chromote`.

`estruturas.csv`, uma linha por estrutura:

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

`entidades.csv`, uma linha por proteína da estrutura (cada tabela `#table_macromolecule-protein-entityId-N` da
mesma página). Uma estrutura da spike com um anticorpo, por exemplo, vira 3 linhas. Serve pra juntar estruturas
diferentes da mesma proteína pelo UniProt e ver quais proteínas aparecem em mais artigos.

| Coluna | De onde vem |
|---|---|
| `entidade` | número da entidade na estrutura (o `N` do id da tabela) |
| `molecula` | coluna "Molecule" |
| `organismo` | coluna "Organism" (pode ser diferente do organismo da estrutura, ex.: anticorpo sintético) |
| `uniprot` | link pro uniprot.org; NA quando não tem (anticorpo, construção sintética), separado por `;` se tiver mais de um |
| `gene` | "Gene Names:" nos detalhes |
| `ec` | "EC:" nos detalhes, classe da enzima; NA se não for enzima |

Coleta responsável: 2 s entre uma página e outra, e o script só busca o que ainda não está em `estruturas.csv` nem
em `codigos_nao_encontrados.csv`. Código que dá 404 ou que existe mas ainda não foi liberado (cai em
`/structure/unreleased/`, com a página sem título) vai pra `codigos_nao_encontrados.csv` e não é buscado de novo.

### 04. Banco SQL

PostgreSQL, no schema `pdb`, seguindo o padrão da aula: `ref_` pra tabela de referência, `tab_` pra tabela de
dados, id com `GENERATED ALWAYS AS IDENTITY` e chave estrangeira com `ALTER TABLE`. As tabelas estão em
`sql/01_criar_tabelas.sql`. O `R/04_banco_sql.R` apaga o schema, cria de novo e carrega os csv com `dbWriteTable`,
usando o `trocar_id()` da aula pra trocar o código pelo id da tabela de referência.

```
ref_revista ──< tab_artigo ──< tab_mencao >── tab_estrutura ──< tab_entidade ──< tab_entidade_uniprot >── ref_uniprot
```

| Tabela | O que guarda |
|---|---|
| `ref_revista` | as revistas |
| `tab_artigo` | os artigos, ligados à revista |
| `tab_mencao` | qual artigo cita qual estrutura, quantas vezes e o contexto |
| `tab_estrutura` | uma linha por código PDB citado, com os campos do scraping |
| `tab_entidade` | as proteínas de cada estrutura |
| `ref_uniprot` | os códigos UniProt |
| `tab_entidade_uniprot` | liga entidade e UniProt (proteína quimérica tem mais de um, anticorpo não tem nenhum) |

A coluna `encontrada` de `tab_estrutura` faz o papel de fila de coleta: `TRUE` achou no RCSB, `FALSE` deu 404 ou
não foi liberada, `NULL` ainda não foi buscada.

`sql/02_consultas.sql` tem consultas prontas (dá pra rodar no DBeaver, no pgAdmin ou com `dbGetQuery`): estruturas
e método por revista, proteínas citadas em mais artigos, estrutura depositada pelo próprio artigo ou reaproveitada,
idade da estrutura quando foi citada e a fila de coleta.

## Resultados da última rodada (18/11/2026)

20 artigos (IUCrJ de mar a set/2026, PLoS de jul a out/2026).

- **Códigos:** 123 únicos → 120 estruturas e 3 não encontrados (`20AD`, `600S`, `18NZ`). 3 códigos aparecem em mais
  de um artigo (`7BH3`, `9TO1`, `9TO5`).
- **Comparando com a Europe PMC:** 114 códigos em comum, 12 que só a gente achou (parte é lixo que cai no scraping)
  e 23 que a gente perdeu (código em figura ou em linha de tabela longe do cabeçalho; 11 deles num artigo só).
- **Métodos:** 83 de raio X, 33 de crio-ME e 3 de cristalografia de elétrons. Resolução média de 1,8 a 2,2 Å no
  raio X e de 3,0 a 3,6 Å na crio-ME.
- **Proteínas:** 199 entidades, 185 com UniProt, 102 proteínas diferentes. 2 aparecem em mais de um artigo
  (beta-lactamase CTX-M-15 e integrina alfa-M), e várias aparecem em muitas estruturas do mesmo artigo (11 da CTX-M-15,
  10 da L-asparaginase 2, 7 da spike do SARS-CoV-2).
- **IUCrJ vs PLoS:** a IUCrJ cita estruturas com 5,7 anos em média e depositou 30 das 89 que cita; a PLoS cita
  estruturas com 15,3 anos em média e não depositou nenhuma.

## Cuidados e limitações

- **A seleção muda a cada rodada.** `artigos_selecionados.csv` e `mencoes_pdb.csv` são refeitos toda vez, mas
  `estruturas.csv`, `entidades.csv` e `codigos_nao_encontrados.csv` acumulam as seleções antigas (pra não buscar de
  novo). Pra analisar só a seleção atual, partir de `mencoes_pdb.csv` (no banco, de `tab_mencao`).
- **DOI em caixa diferente.** O DOI do artigo vem em minúsculo e o do PDB em maiúsculo; pra comparar, usar
  `tolower()` no R ou `LOWER()` no SQL.
- **`n_cadeias` conta só as cadeias proteicas únicas**, não o total de cadeias.
- **Estrutura não liberada com título.** O `5WH0` cai em `/structure/unreleased/` mas a página tem título, então
  passa no scraping sem os outros campos. No banco ele fica com `encontrada = FALSE`.
- **Erro de digitação no artigo.** O pipeline pega o código como está escrito: o `9YRD` (uma estrutura de RNA) aparece
  num artigo sobre a CTX-M-15, provavelmente no lugar do `9RYD`.
- **A Europe PMC muda com o tempo.** A contagem de códigos por artigo vem da mineração de texto dela, que é
  atualizada; a mesma busca pode dar uma seleção um pouco diferente depois.
