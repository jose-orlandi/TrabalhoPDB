library(tidyverse)
library(DBI)

# a senha fica no .Renviron da pasta do projeto (fora do git), ver .Renviron.exemplo
con <- dbConnect(RPostgres::Postgres(),
                 dbname = Sys.getenv("PG_DB", "pdb_pipeline"),
                 host = Sys.getenv("PG_HOST", "localhost"),
                 port = as.integer(Sys.getenv("PG_PORT", "5432")),
                 user = Sys.getenv("PG_USER", "postgres"),
                 password = Sys.getenv("PG_PASSWORD"))

#? cria as tabelas (apaga o schema pdb e monta de novo)

comandos <- read_file("sql/01_criar_tabelas.sql") %>%
  str_split(";") %>%
  pluck(1)

# tira os pedacos que so tem comentario
comandos <- comandos[str_trim(str_remove_all(comandos, "--[^\n]*")) != ""]
walk(comandos, ~ dbExecute(con, .x))

# troca a coluna X pelo id Z da tabela tabY (a mesma funcao da aula de SQL)
trocar_id <- function(con, df, X, Z, tabY){

  tab <- dbGetQuery(
    con, paste0("SELECT ", X, ",", Z, " FROM ", tabY, ";")
  )

  df_novo <- df %>%
    left_join(tab, by = X) %>%
    select(-all_of(X))

  return(df_novo)
}

escreve <- function(df, tabela) {
  dbWriteTable(con, name = Id(schema = "pdb", table = tabela), value = df,
               row.names = FALSE, append = TRUE)
}

artigos <- read.csv("dados/artigos_selecionados.csv")
mencoes <- read.csv("saida/mencoes_pdb.csv")
estruturas <- read.csv("saida/estruturas.csv", colClasses = c(data_deposito = "Date"))
# o 03 so cria esse arquivo se algum codigo deu 404
nao_achou <- tibble(codigo_pdb = character())
if (file.exists("saida/codigos_nao_encontrados.csv")) nao_achou <- read.csv("saida/codigos_nao_encontrados.csv")
entidades <- read.csv("saida/entidades.csv", colClasses = "character")

#? revistas e artigos

artigos %>%
  distinct(nome_revista = revista) %>%
  escreve("ref_revista")

artigos %>%
  select(nome_revista = revista, pmcid, doi, data_publicacao, titulo) %>%
  mutate(data_publicacao = as.Date(data_publicacao)) %>%
  trocar_id(con, ., "nome_revista", "id_revista", "pdb.ref_revista") %>%
  rename(revista_id = id_revista) %>%
  escreve("tab_artigo")

#? estruturas: todo codigo citado entra, achado ou nao

tab_estrutura <- tibble(codigo_pdb = unique(c(estruturas$codigo_pdb, nao_achou$codigo_pdb, mencoes$codigo_pdb))) %>%
  left_join(estruturas, by = "codigo_pdb") %>%
  mutate(
    # nao liberada com titulo (tipo o 5WH0) passa no scraping mas vem sem metodo nem data
    encontrada = case_when(
      codigo_pdb %in% nao_achou$codigo_pdb ~ FALSE,
      codigo_pdb %in% estruturas$codigo_pdb & is.na(metodo) ~ FALSE,
      codigo_pdb %in% estruturas$codigo_pdb ~ TRUE,
      TRUE ~ NA
    )
  ) %>%
  select(codigo_pdb, encontrada, nome, classificacao, organismo, metodo, resolucao,
         data_deposito, massa_kda, n_cadeias, doi_estrutura)

escreve(tab_estrutura, "tab_estrutura")

#? mencoes: liga artigo e estrutura

mencoes %>%
  select(pmcid, codigo_pdb, n_mencoes, contexto) %>%
  trocar_id(con, ., "pmcid", "id_artigo", "pdb.tab_artigo") %>%
  trocar_id(con, ., "codigo_pdb", "id_estrutura", "pdb.tab_estrutura") %>%
  rename(artigo_id = id_artigo, estrutura_id = id_estrutura) %>%
  escreve("tab_mencao")

#? entidades (proteinas de cada estrutura)

# o rcsb escreve "&nbsp" sem ponto e virgula e cola o aviso de quimera no organismo
entidades <- entidades %>%
  mutate(
    across(c(molecula, organismo, gene), ~ str_squish(gsub("&nbsp;?", " ", .x))),
    organismo = str_trim(str_remove(organismo, "This entity is chimeric")),
    entidade = as.integer(entidade)
  )

entidades %>%
  select(codigo_pdb, entidade, molecula, organismo, gene, ec) %>%
  trocar_id(con, ., "codigo_pdb", "id_estrutura", "pdb.tab_estrutura") %>%
  rename(estrutura_id = id_estrutura) %>%
  escreve("tab_entidade")

# uniprot: uma linha por par entidade-uniprot
entidade_uniprot <- entidades %>%
  filter(!is.na(uniprot)) %>%
  separate_rows(uniprot, sep = ";") %>%
  select(codigo_pdb, entidade, uniprot)

entidade_uniprot %>%
  distinct(uniprot) %>%
  escreve("ref_uniprot")

ids_entidade <- dbGetQuery(con, "SELECT id_entidade, codigo_pdb, entidade FROM pdb.tab_entidade
                                 LEFT JOIN pdb.tab_estrutura ON estrutura_id = id_estrutura")

entidade_uniprot %>%
  left_join(ids_entidade, by = c("codigo_pdb", "entidade")) %>%
  select(id_entidade, uniprot) %>%
  trocar_id(con, ., "uniprot", "id_uniprot", "pdb.ref_uniprot") %>%
  rename(entidade_id = id_entidade, uniprot_id = id_uniprot) %>%
  escreve("tab_entidade_uniprot")

#? confere quantas linhas foram pra cada tabela

tabelas <- c("ref_revista", "tab_artigo", "tab_estrutura", "tab_mencao",
             "tab_entidade", "ref_uniprot", "tab_entidade_uniprot")

map(tabelas, ~ dbGetQuery(con, paste0("SELECT '", .x, "' AS tabela, COUNT(*) AS n FROM pdb.", .x))) %>%
  list_rbind() %>%
  print()

dbDisconnect(con)
