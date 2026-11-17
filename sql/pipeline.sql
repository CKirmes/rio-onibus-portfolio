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

--CALENDARIO ESPECIAL
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.calendario_especial` AS
SELECT * FROM UNNEST([
  STRUCT(DATE '2026-10-04' AS data, 'eleicao' AS tipo_especial,
         'Eleicoes gerais - 1o turno' AS motivo, 'Volume 1,81x a mediana de domingo; fonte sem marcacao' AS evidencia),
  (DATE '2026-10-25', 'eleicao',  'Eleicoes gerais - 2o turno',          'Volume 1,83x; fonte sem marcacao'),
  (DATE '2026-11-08', 'prova',    'Provavel 1o dia do ENEM 2026 (a confirmar)', 'Volume 1,26x; fonte sem marcacao'),
  (DATE '2022-12-09', 'futebol',  'Copa 2022: Brasil x Croacia',          'Volume 0,74x da mediana de dia util'),
  (DATE '2023-02-18', 'carnaval', 'Carnaval 2023',                        'Volume 0,60x'),
  (DATE '2023-02-19', 'carnaval', 'Carnaval 2023',                        'Volume 0,65x'),
  (DATE '2023-02-20', 'carnaval', 'Carnaval 2023 (fonte: Dia Util)',      'Volume 0,41x'),
  (DATE '2023-02-21', 'carnaval', 'Carnaval 2023 (fonte: Dia Util)',      'Volume 0,36x'),
  (DATE '2023-02-22', 'carnaval', 'Quarta de Cinzas 2023',                'Volume 0,59x'),
  (DATE '2026-06-29', 'anomalia', 'Greve de onibus + jogo do Brasil',     'Volume 0,30x; greve noticiada'),
  (DATE '2026-06-30', 'anomalia', 'Greve de onibus (provavel continuacao)', 'Volume 0,39x'),
  (DATE '2026-07-01', 'anomalia', 'Greve de onibus (provavel continuacao)', 'Volume 0,50x'),
  (DATE '2023-06-22', 'anomalia', 'Queda sem causa identificada',         'Volume 0,68x'),
  (DATE '2024-04-28', 'anomalia', 'Queda sem causa identificada',         'Volume 0,63x')
]);


-- BASE M.L
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.ml_base`
CLUSTER BY servico AS
WITH params AS (
  SELECT DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 4 DAY) AS ultimo_completo
),
diario AS (
  SELECT f.servico, f.data, SUM(f.viagens) AS viagens, SUM(f.km_apurado) AS km
  FROM `portfolio-onibus.ouro.fato_servico_dia` f, params p
  WHERE f.data <= p.ultimo_completo
  GROUP BY f.servico, f.data
),
calendario_hist AS (
  SELECT f.data, ANY_VALUE(f.tipo_dia) AS tipo_dia
  FROM `portfolio-onibus.ouro.fato_servico_dia` f, params p
  WHERE f.data <= p.ultimo_completo
  GROUP BY f.data
),
verao AS (
  SELECT LOWER(tipo_dia) LIKE '%ver%o%' AS ativo
  FROM calendario_hist
  WHERE EXTRACT(DAYOFWEEK FROM data) IN (1, 7)
  ORDER BY data DESC
  LIMIT 1
),
calendario_futuro AS (
  SELECT
    d AS data,
    CASE
      WHEN STRPOS(fe.tipo_dia_previsto, ' - ') > 0 THEN fe.tipo_dia_previsto
      WHEN fe.tipo_dia_previsto IS NOT NULL       THEN fe.tipo_dia_previsto || IF(v.ativo, ' - Verão', '')
      WHEN EXTRACT(DAYOFWEEK FROM d) = 1          THEN 'Domingo' || IF(v.ativo, ' - Verão', '')
      WHEN EXTRACT(DAYOFWEEK FROM d) = 7          THEN 'Sabado'  || IF(v.ativo, ' - Verão', '')
      ELSE 'Dia Útil'
    END AS tipo_dia
  FROM params p
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE_ADD(p.ultimo_completo, INTERVAL 1 DAY),
                                        DATE_ADD(p.ultimo_completo, INTERVAL 7 DAY))) AS d
  CROSS JOIN verao v
  LEFT JOIN `portfolio-onibus.ouro.feriados` fe ON fe.data = d
),
calendario AS (
  SELECT data, tipo_dia FROM calendario_hist
  UNION ALL
  SELECT data, tipo_dia FROM calendario_futuro
),
limites AS (
  SELECT d.servico, MIN(d.data) AS ini,
    IF(MAX(d.data) >= DATE_SUB(p.ultimo_completo, INTERVAL 27 DAY),
       DATE_ADD(p.ultimo_completo, INTERVAL 7 DAY),
       MAX(d.data)) AS fim
  FROM diario d, params p
  GROUP BY d.servico, p.ultimo_completo
),
grade AS (
  SELECT l.servico, dt AS data
  FROM limites l, UNNEST(GENERATE_DATE_ARRAY(l.ini, l.fim)) AS dt
)
SELECT
  g.servico, g.data, c.tipo_dia,
  EXTRACT(DAYOFWEEK FROM g.data) AS dia_semana,
  EXTRACT(MONTH FROM g.data)     AS mes,
  EXTRACT(DAY FROM g.data)       AS dia_mes,
  g.data > p.ultimo_completo     AS eh_futuro,
  IF(g.data > p.ultimo_completo, NULL, COALESCE(d.viagens, 0)) AS viagens,
  IF(g.data > p.ultimo_completo, NULL, COALESCE(d.km, 0))      AS km
FROM grade g
CROSS JOIN params p
LEFT JOIN diario d USING (servico, data)
LEFT JOIN calendario c USING (data);

--FERIADOS
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.feriados` AS
SELECT * FROM UNNEST([
  STRUCT(DATE '2026-11-20' AS data, 'Consciencia Negra' AS nome, 'Domingo' AS tipo_dia_previsto),
  (DATE '2026-12-24', 'Vespera de Natal',     'Sabado - Véspera de Natal'),
  (DATE '2026-12-25', 'Natal',                'Domingo'),
  (DATE '2026-12-31', 'Vespera de Ano Novo',  'Sabado - Reveillon'),
  (DATE '2027-01-01', 'Confraternizacao',     'Domingo - Reveillon'),
  (DATE '2027-01-20', 'Sao Sebastiao',        'Domingo'),
  (DATE '2027-02-08', 'Carnaval',             'Domingo'),
  (DATE '2027-02-09', 'Carnaval',             'Domingo'),
  (DATE '2027-02-10', 'Quarta de Cinzas',     'Sabado'),
  (DATE '2027-03-26', 'Sexta-feira Santa',    'Domingo'),
  (DATE '2027-04-21', 'Tiradentes',           'Domingo'),
  (DATE '2027-04-23', 'Sao Jorge',            'Domingo'),
  (DATE '2027-05-01', 'Dia do Trabalho',      'Domingo'),
  (DATE '2027-05-27', 'Corpus Christi',       'Domingo'),
  (DATE '2027-09-07', 'Independencia',        'Domingo'),
  (DATE '2027-10-12', 'N. Sra. Aparecida',    'Domingo'),
  (DATE '2027-11-02', 'Finados',              'Domingo'),
  (DATE '2027-11-15', 'Proclamacao da Republica', 'Domingo'),
  (DATE '2027-11-20', 'Consciencia Negra',    'Domingo'),
  (DATE '2027-12-24', 'Vespera de Natal',     'Sabado - Véspera de Natal'),
  (DATE '2027-12-25', 'Natal',                'Domingo'),
  (DATE '2027-12-31', 'Vespera de Ano Novo',  'Sabado - Reveillon')
]);

ASSERT (SELECT COUNT(DISTINCT data) FROM `portfolio-onibus.ouro.ml_base` WHERE eh_futuro) = 7
  AS 'Nao foram geradas as 7 datas futuras';

-- ML FEAT
CREATE OR REPLACE TABLE `portfolio-onibus.ouro.ml_features`
CLUSTER BY servico AS
WITH base AS (
  SELECT
    b.*,
    REPLACE(TRIM(SPLIT(b.tipo_dia, ' - ')[OFFSET(0)]), 'Sabado', 'Sábado') AS tipo_base,
    IF(STRPOS(b.tipo_dia, ' - ') > 0,
       LOWER(TRIM(SUBSTR(b.tipo_dia, STRPOS(b.tipo_dia, ' - ') + 3))), NULL) AS evento,
    c.tipo_especial
  FROM `portfolio-onibus.ouro.ml_base` b
  LEFT JOIN `portfolio-onibus.ouro.calendario_especial` c USING (data)
),
classificado AS (
  SELECT *,
    CASE
      WHEN evento IS NULL OR REGEXP_CONTAINS(evento, r'^ver[aã]o$')          THEN 'nenhum'
      WHEN REGEXP_CONTAINS(evento, r'r[eé]veillon|natal|fim de ano')         THEN 'festas_fim_de_ano'
      WHEN REGEXP_CONTAINS(evento, r'rock in rio|madonna|lady gaga|shakira') THEN 'show'
      WHEN REGEXP_CONTAINS(evento, r'enem|cnu')                              THEN 'prova'
      WHEN REGEXP_CONTAINS(evento, r'copa')                                  THEN 'futebol'
      WHEN REGEXP_CONTAINS(evento, r'elei')                                  THEN 'eleicao'
      WHEN REGEXP_CONTAINS(evento, r'parada|marcha')                         THEN 'evento_de_rua'
      ELSE 'operacao_atipica'
    END AS categoria_evento
  FROM base
),
operacional AS (
  SELECT *,
    COALESCE(tipo_especial,
             IF(categoria_evento IN ('eleicao', 'prova', 'festas_fim_de_ano'),
                categoria_evento, tipo_base)
    ) AS tipo_operacional
  FROM classificado
),
lags AS (
  SELECT *,
    LAG(viagens, 7)  OVER w AS lag_7,
    LAG(viagens, 14) OVER w AS lag_14,
    LAG(viagens, 21) OVER w AS lag_21,
    LAG(viagens, 28) OVER w AS lag_28,
    AVG(viagens)    OVER (PARTITION BY servico ORDER BY data ROWS BETWEEN 34 PRECEDING AND 7 PRECEDING) AS media_28d,
    STDDEV(viagens) OVER (PARTITION BY servico ORDER BY data ROWS BETWEEN 34 PRECEDING AND 7 PRECEDING) AS desvio_28d,
    MAX(viagens)    OVER (PARTITION BY servico ORDER BY data ROWS BETWEEN 34 PRECEDING AND 7 PRECEDING) AS max_28d,
    LAST_VALUE(viagens) OVER (PARTITION BY servico, tipo_operacional ORDER BY UNIX_DATE(data)
                              RANGE BETWEEN UNBOUNDED PRECEDING AND 7 PRECEDING) AS ultimo_mesmo_tipo,
    AVG(viagens)        OVER (PARTITION BY servico, tipo_operacional ORDER BY UNIX_DATE(data)
                              RANGE BETWEEN 63 PRECEDING AND 7 PRECEDING)       AS media_mesmo_tipo_8sem
  FROM operacional
  WINDOW w AS (PARTITION BY servico ORDER BY data)
)
SELECT *,
  (lag_7 + lag_14 + lag_21 + lag_28) / 4                   AS media_4_mesmo_dia,
  max_28d > 0                                               AS linha_ativa,
  (tipo_base = 'Domingo' AND dia_semana != 1)               AS eh_feriado,
  COALESCE(REGEXP_CONTAINS(evento, r'ver[aã]o'), FALSE)     AS eh_verao,
  COALESCE(tipo_especial = 'anomalia', FALSE)               AS eh_anomalia
FROM lags
WHERE lag_28 IS NOT NULL;
