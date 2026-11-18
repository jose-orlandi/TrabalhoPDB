library(tidyverse)
library(jsonlite)

# busca na europe pmc os artigos de acesso aberto mais recentes que citam codigo pdb
# toda vez que roda pega os mais novos, entao a lista muda com o tempo
api_busca <- "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
api_anotacoes <- "https://www.ebi.ac.uk/europepmc/annotations_api/annotationsByArticleIds"

revistas <- c("IUCrJ", "PLoS Comput Biol")
n_por_revista <- 10
min_codigos <- 3

# a api as vezes devolve vazio, tenta de novo antes de desistir
le_json <- function(url, ...) {
  for (tentativa in 1:3) {
    res <- tryCatch(suppressWarnings(fromJSON(url, ...)), error = function(e) NULL)
    if (!is.null(res)) return(res)
    message("Europe PMC nao respondeu, tentando de novo")
    Sys.sleep(5)
  }
  stop("Europe PMC nao respondeu: ", url)
}

# uma pagina da busca, do mais novo pro mais antigo
busca_pagina <- function(revista, cursor) {
  # revista <- revistas[1]; cursor <- "*"
  consulta <- sprintf('JOURNAL:"%s" AND OPEN_ACCESS:y AND ACCESSION_TYPE:pdb', revista)
  url <- paste0(api_busca, "?query=", URLencode(consulta, reserved = TRUE),
                "&format=json&pageSize=100&resultType=core",
                "&sort=", URLencode("FIRST_PDATE_D desc", reserved = TRUE),
                "&cursorMark=", URLencode(cursor, reserved = TRUE))
  res <- le_json(url)

  artigos <- res$resultList$result
  artigos <- tibble(revista = revista,
                    pmcid = artigos$pmcid,
                    pmid = as.numeric(artigos$pmid),
                    doi = artigos$doi,
                    data_publicacao = artigos$firstPublicationDate,
                    titulo = artigos$title) %>%
    filter(!is.na(pmcid)) %>%
    arrange(desc(data_publicacao), desc(pmid))

  list(artigos = artigos, proximo = res$nextCursorMark)
}

# quantos codigos pdb diferentes a europe pmc achou no texto
conta_codigos <- function(pmc) {
  # pmc <- "PMC12573926"
  Sys.sleep(0.5)
  url <- paste0(api_anotacoes, "?articleIds=PMC:", pmc, "&type=Accession%20Numbers&format=JSON")
  anotacoes <- le_json(url, simplifyVector = FALSE)[[1]]$annotations
  codigos <- map_chr(keep(anotacoes, ~ identical(.x$subType, "PDBe")), "exact")
  n_distinct(toupper(codigos))
}

# vai descendo a lista ate achar os 10 artigos de cada revista
seleciona_revista <- function(revista) {
  escolhidos <- tibble()
  cursor <- "*"

  while (nrow(escolhidos) < n_por_revista) {
    pagina <- busca_pagina(revista, cursor)
    if (nrow(pagina$artigos) == 0) break

    for (i in 1:nrow(pagina$artigos)) {
      artigo <- pagina$artigos[i, ]
      artigo$n_codigos <- conta_codigos(artigo$pmcid)
      if (artigo$n_codigos < min_codigos) next

      message(revista, ": ", artigo$pmcid, " (", artigo$n_codigos, " codigos)")
      escolhidos <- bind_rows(escolhidos, artigo)
      if (nrow(escolhidos) == n_por_revista) break
    }
    cursor <- pagina$proximo
  }
  escolhidos
}

artigos <- map(revistas, seleciona_revista) %>%
  list_rbind() %>%
  mutate(id = row_number(),
         url_pdf = paste0("https://europepmc.org/articles/", pmcid, "?pdf=render"))

dir.create("dados", showWarnings = FALSE)
artigos %>%
  select(id, revista, pmcid, doi, data_publicacao, titulo, url_pdf) %>%
  write_csv("dados/artigos_selecionados.csv")

artigos %>%
  select(id, revista, data_publicacao, n_codigos, titulo) %>%
  print(n = Inf)
