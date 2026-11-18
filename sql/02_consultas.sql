-- consultas de exemplo no banco do pipeline (schema pdb)

------------------------------------------------------------
-- artigos e estruturas citadas por revista
------------------------------------------------------------
SELECT nome_revista, COUNT(DISTINCT id_artigo) AS artigos, COUNT(DISTINCT estrutura_id) AS estruturas
FROM pdb.tab_artigo
LEFT JOIN pdb.ref_revista ON revista_id = id_revista
LEFT JOIN pdb.tab_mencao ON artigo_id = id_artigo
GROUP BY nome_revista;

------------------------------------------------------------
-- metodo experimental por revista
------------------------------------------------------------
SELECT nome_revista, metodo, COUNT(DISTINCT id_estrutura) AS estruturas, ROUND(AVG(resolucao), 2) AS resolucao_media
FROM pdb.tab_mencao
LEFT JOIN pdb.tab_artigo ON artigo_id = id_artigo
LEFT JOIN pdb.ref_revista ON revista_id = id_revista
LEFT JOIN pdb.tab_estrutura ON estrutura_id = id_estrutura
WHERE encontrada
GROUP BY nome_revista, metodo
ORDER BY nome_revista, estruturas DESC;

------------------------------------------------------------
-- proteinas (uniprot) citadas em mais artigos
------------------------------------------------------------
SELECT uniprot, MIN(molecula) AS proteina, COUNT(DISTINCT artigo_id) AS artigos, COUNT(DISTINCT tab_mencao.estrutura_id) AS estruturas
FROM pdb.tab_mencao
LEFT JOIN pdb.tab_entidade ON tab_mencao.estrutura_id = tab_entidade.estrutura_id
INNER JOIN pdb.tab_entidade_uniprot ON entidade_id = id_entidade
LEFT JOIN pdb.ref_uniprot ON uniprot_id = id_uniprot
GROUP BY uniprot
ORDER BY artigos DESC, estruturas DESC
LIMIT 15;

------------------------------------------------------------
-- estrutura depositada pelo proprio artigo ou reaproveitada
-- (o doi do artigo vem minusculo e o do pdb maiusculo, por isso o LOWER)
------------------------------------------------------------
WITH origem AS (
    SELECT nome_revista,
           CASE WHEN LOWER(doi_estrutura) = LOWER(doi) THEN 'depositada pelo artigo'
                ELSE 'reaproveitada' END AS origem
    FROM pdb.tab_mencao
    LEFT JOIN pdb.tab_artigo ON artigo_id = id_artigo
    LEFT JOIN pdb.ref_revista ON revista_id = id_revista
    LEFT JOIN pdb.tab_estrutura ON estrutura_id = id_estrutura
    WHERE encontrada
)
SELECT nome_revista, origem, COUNT(*) AS n
FROM origem
GROUP BY nome_revista, origem
ORDER BY nome_revista, origem;

------------------------------------------------------------
-- idade da estrutura quando foi citada (anos entre o deposito e o artigo)
------------------------------------------------------------
SELECT nome_revista,
       ROUND(AVG((data_publicacao - data_deposito) / 365.25), 1) AS idade_media_anos,
       MIN(data_deposito) AS deposito_mais_antigo
FROM pdb.tab_mencao
LEFT JOIN pdb.tab_artigo ON artigo_id = id_artigo
LEFT JOIN pdb.ref_revista ON revista_id = id_revista
LEFT JOIN pdb.tab_estrutura ON estrutura_id = id_estrutura
WHERE encontrada
GROUP BY nome_revista;

------------------------------------------------------------
-- fila de coleta: codigo citado que ainda nao foi buscado no RCSB
------------------------------------------------------------
SELECT codigo_pdb FROM pdb.tab_estrutura WHERE encontrada IS NULL;
