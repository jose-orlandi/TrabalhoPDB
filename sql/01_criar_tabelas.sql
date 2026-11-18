-- banco do pipeline: revistas, artigos, mencoes, estruturas e as proteinas de cada estrutura
-- o banco sai inteiro dos csv, entao o script 04 apaga o schema e monta de novo toda vez

DROP SCHEMA IF EXISTS pdb CASCADE;

CREATE SCHEMA pdb;

CREATE TABLE pdb.ref_revista
(
 id_revista INT GENERATED ALWAYS AS IDENTITY,
 nome_revista VARCHAR NOT NULL,
 UNIQUE (nome_revista),
 CONSTRAINT pk_revista PRIMARY KEY (id_revista)
);

CREATE TABLE pdb.tab_artigo
(
 id_artigo INT GENERATED ALWAYS AS IDENTITY,
 revista_id INT NOT NULL,
 pmcid VARCHAR(20) NOT NULL,
 doi VARCHAR,
 data_publicacao DATE,
 titulo TEXT,
 UNIQUE (pmcid),
 CONSTRAINT pk_artigo PRIMARY KEY (id_artigo)
);

-- encontrada: TRUE achou no RCSB, FALSE deu 404 ou nao foi liberada, NULL ainda nao foi buscada (fila)
CREATE TABLE pdb.tab_estrutura
(
 id_estrutura INT GENERATED ALWAYS AS IDENTITY,
 codigo_pdb CHAR(4) NOT NULL,
 encontrada BOOLEAN,
 nome TEXT,
 classificacao VARCHAR,
 organismo VARCHAR,
 metodo VARCHAR,
 resolucao NUMERIC,
 data_deposito DATE,
 massa_kda NUMERIC,
 n_cadeias INT,
 doi_estrutura VARCHAR,
 UNIQUE (codigo_pdb),
 CONSTRAINT pk_estrutura PRIMARY KEY (id_estrutura)
);

-- quais estruturas cada artigo cita
CREATE TABLE pdb.tab_mencao
(
 id_mencao INT GENERATED ALWAYS AS IDENTITY,
 artigo_id INT NOT NULL,
 estrutura_id INT NOT NULL,
 n_mencoes INT NOT NULL,
 contexto TEXT,
 UNIQUE (artigo_id, estrutura_id),
 CONSTRAINT pk_mencao PRIMARY KEY (id_mencao)
);

-- uma linha por proteina da estrutura
CREATE TABLE pdb.tab_entidade
(
 id_entidade INT GENERATED ALWAYS AS IDENTITY,
 estrutura_id INT NOT NULL,
 entidade INT NOT NULL,
 molecula VARCHAR,
 organismo VARCHAR,
 gene VARCHAR,
 ec VARCHAR,
 UNIQUE (estrutura_id, entidade),
 CONSTRAINT pk_entidade PRIMARY KEY (id_entidade)
);

CREATE TABLE pdb.ref_uniprot
(
 id_uniprot INT GENERATED ALWAYS AS IDENTITY,
 uniprot VARCHAR(20) NOT NULL,
 UNIQUE (uniprot),
 CONSTRAINT pk_uniprot PRIMARY KEY (id_uniprot)
);

-- tabela de ligacao: proteina quimerica tem mais de um uniprot, anticorpo nao tem nenhum
CREATE TABLE pdb.tab_entidade_uniprot
(
 entidade_id INT NOT NULL,
 uniprot_id INT NOT NULL,
 CONSTRAINT pk_entidade_uniprot PRIMARY KEY (entidade_id, uniprot_id)
);

ALTER TABLE pdb.tab_artigo ADD FOREIGN KEY (revista_id) REFERENCES pdb.ref_revista (id_revista);
ALTER TABLE pdb.tab_mencao ADD FOREIGN KEY (artigo_id) REFERENCES pdb.tab_artigo (id_artigo);
ALTER TABLE pdb.tab_mencao ADD FOREIGN KEY (estrutura_id) REFERENCES pdb.tab_estrutura (id_estrutura);
ALTER TABLE pdb.tab_entidade ADD FOREIGN KEY (estrutura_id) REFERENCES pdb.tab_estrutura (id_estrutura);
ALTER TABLE pdb.tab_entidade_uniprot ADD FOREIGN KEY (entidade_id) REFERENCES pdb.tab_entidade (id_entidade);
ALTER TABLE pdb.tab_entidade_uniprot ADD FOREIGN KEY (uniprot_id) REFERENCES pdb.ref_uniprot (id_uniprot);
