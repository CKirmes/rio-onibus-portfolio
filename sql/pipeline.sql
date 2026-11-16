-- PRATA: limpeza, padronização e deduplicação
CREATE OR REPLACE VIEW `portfolio-onibus.prata.viagem` AS
SELECT
  data, tipo_dia,
  CASE WHEN modo IS NULL OR TRIM(modo) IN ('', 'null') THEN 'Ônibus' ELSE modo END AS modo,
  sistema, consorcio, servico, vista, sentido,
  route_id, trip_id, shape_id, id_veiculo, id_viagem,
  datetime_partida, datetime_chegada,
  EXTRACT(HOUR FROM datetime_partida) AS hora_partida,
  tempo_viagem, distancia_planejada
FROM `datario.transporte_rodoviario_municipal.viagem_onibus`
WHERE tempo_viagem > 0
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_viagem ORDER BY datetime_chegada DESC) = 1;

-- OURO: fato linha x dia
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.fato_servico_dia`
CLUSTER BY consorcio, servico AS
SELECT
  data, tipo_dia, modo, sistema, consorcio, servico, vista,
  COUNT(*)                                          AS viagens,
  ROUND(SUM(distancia_planejada), 1)                AS km_apurado,
  ROUND(SUM(tempo_viagem) / 60, 1)                  AS horas_em_viagem,
  ROUND(SAFE_DIVIDE(SUM(distancia_planejada), SUM(tempo_viagem) / 60), 1) AS velocidade_media_kmh,
  APPROX_QUANTILES(tempo_viagem, 100)[OFFSET(50)]   AS tempo_mediano_min,
  APPROX_QUANTILES(tempo_viagem, 100)[OFFSET(90)]   AS tempo_p90_min,
  COUNT(DISTINCT id_veiculo)                        AS veiculos,
  CURRENT_TIMESTAMP()                               AS _atualizado_em
FROM `portfolio-onibus.prata.viagem`
WHERE data >= '2022-06-01'
GROUP BY data, tipo_dia, modo, sistema, consorcio, servico, vista;

-- QUALIDADE: o pipeline falha se algo estiver errado
ASSERT (SELECT MAX(data) FROM `portfolio-onibus.ouro.fato_servico_dia`)
       >= DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 3 DAY)
  AS 'Ouro desatualizado: a fonte nao trouxe os ultimos dias';

ASSERT (SELECT COUNT(*) FROM `portfolio-onibus.ouro.fato_servico_dia` WHERE modo IS NULL) = 0
  AS 'Existem linhas com modo nulo na ouro';


-- BASE M.L
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.ml_base`
CLUSTER BY servico AS
WITH diario AS (
  SELECT servico, data, SUM(viagens) AS viagens, SUM(km_apurado) AS km
  FROM `portfolio-onibus.ouro.fato_servico_dia`
  GROUP BY servico, data
),
calendario AS (
  SELECT data, ANY_VALUE(tipo_dia) AS tipo_dia
  FROM `portfolio-onibus.ouro.fato_servico_dia`
  GROUP BY data
),
limites AS (
  SELECT servico, MIN(data) AS ini, MAX(data) AS fim
  FROM diario
  GROUP BY servico
),
grade AS (
  SELECT l.servico, d AS data
  FROM limites l, UNNEST(GENERATE_DATE_ARRAY(l.ini, l.fim)) AS d
)
SELECT
  g.servico, g.data, c.tipo_dia,
  EXTRACT(DAYOFWEEK FROM g.data) AS dia_semana,
  EXTRACT(MONTH FROM g.data)     AS mes,
  EXTRACT(DAY FROM g.data)       AS dia_mes,
  COALESCE(d.viagens, 0)         AS viagens,
  COALESCE(d.km, 0)              AS km
FROM grade g
LEFT JOIN diario d USING (servico, data)
LEFT JOIN calendario c USING (data);


-- ML FEAT
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.ml_features`
CLUSTER BY servico AS
WITH base AS (
  SELECT
    *,
    REPLACE(TRIM(SPLIT(tipo_dia, ' - ')[OFFSET(0)]), 'Sabado', 'Sábado') AS tipo_base,
    IF(STRPOS(tipo_dia, ' - ') > 0,
       LOWER(TRIM(SUBSTR(tipo_dia, STRPOS(tipo_dia, ' - ') + 3))), NULL) AS evento
  FROM `portfolio-onibus.ouro.ml_base`
),
lags AS (
  SELECT
    *,
    LAG(viagens, 7)  OVER w AS lag_7,
    LAG(viagens, 14) OVER w AS lag_14,
    LAG(viagens, 21) OVER w AS lag_21,
    LAG(viagens, 28) OVER w AS lag_28,
    AVG(viagens)    OVER (PARTITION BY servico ORDER BY data ROWS BETWEEN 34 PRECEDING AND 7 PRECEDING) AS media_28d,
    STDDEV(viagens) OVER (PARTITION BY servico ORDER BY data ROWS BETWEEN 34 PRECEDING AND 7 PRECEDING) AS desvio_28d,
    MAX(viagens)    OVER (PARTITION BY servico ORDER BY data ROWS BETWEEN 34 PRECEDING AND 7 PRECEDING) AS max_28d
  FROM base
  WINDOW w AS (PARTITION BY servico ORDER BY data)
)
SELECT
  *,
  (lag_7 + lag_14 + lag_21 + lag_28) / 4 AS media_4_mesmo_dia,
  max_28d > 0                             AS linha_ativa,
  COALESCE(REGEXP_CONTAINS(evento, r'ver[aã]o'), FALSE) AS eh_verao,
  CASE
    WHEN evento IS NULL OR REGEXP_CONTAINS(evento, r'^ver[aã]o$')             THEN 'nenhum'
    WHEN REGEXP_CONTAINS(evento, r'r[eé]veillon|natal|fim de ano')            THEN 'festas_fim_de_ano'
    WHEN REGEXP_CONTAINS(evento, r'rock in rio|madonna|lady gaga|shakira')    THEN 'show'
    WHEN REGEXP_CONTAINS(evento, r'enem|cnu')                                 THEN 'prova'
    WHEN REGEXP_CONTAINS(evento, r'copa')                                     THEN 'futebol'
    WHEN REGEXP_CONTAINS(evento, r'elei')                                     THEN 'eleicao'
    WHEN REGEXP_CONTAINS(evento, r'parada|marcha')                            THEN 'evento_de_rua'
    ELSE 'operacao_atipica'
  END AS categoria_evento
FROM lags
WHERE lag_28 IS NOT NULL;
