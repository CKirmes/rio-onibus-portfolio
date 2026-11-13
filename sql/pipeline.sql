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
