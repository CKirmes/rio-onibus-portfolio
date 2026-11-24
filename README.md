Ônibus do Rio: quantas viagens a rede vai fazer nas próximas duas semanas

Painel de gestão da rede municipal de ônibus do Rio de Janeiro, com previsão de viagens por linha para os próximos 14 dias. Tudo roda sozinho, todo dia, e sem custo.

Painel Executivo

Por que fiz esse projeto

Eu queria três coisas:

um tema com bastante dado público, que não fosse base pronta de curso;
uma previsão que desse para conferir depois, dia a dia;
um painel para quem decide, não para o público geral.

Os dados de viagens dos ônibus municipais, que a Prefeitura do Rio publica no BigQuery (data.rio), atendiam tudo isso.

O que o painel responde:
São três páginas, cada uma com uma pergunta.

1. Painel Executivo: como a rede está indo? Média diária da última semana com dados completos (viagens, km, frota e velocidade), comparada com os mesmos dias da semana anterior. Tem a projeção de fechamento do mês e um aviso quando algum consórcio roda abaixo do que o modelo esperava.

2. Previsão e Alertas: o que vem pela frente e onde agir? Viagens previstas por consórcio para os próximos dias, a agenda de feriados e eventos, e as linhas que mais ficaram abaixo do esperado. Um clique no consórcio filtra as linhas dele.

3. Confiança no Modelo: Quanto o modelo errou no teste com dados do passado, onde ele acerta, onde erra e como está se saindo agora, em produção.


Todo dia:

O GitHub Actions roda o pipeline.sql no BigQuery. Ele recria as tabelas tratadas e faz testes de qualidade. Se algum teste falha, o processo para e nada errado chega no painel.
Se deu tudo certo, o próprio Actions chama o Databricks pela API.
O Databricks lê os dados, treina o modelo de novo, gera a previsão dos próximos 14 dias e grava de volta no BigQuery.
O Power BI lê as tabelas finais.
Se a fonte atrasar ou vier com problema, o pipeline avisa.


É um modelo LightGBM único para todas as linhas. Ele prevê quantas viagens cada linha vai fazer em cada dia.


O que deu trabalho:

A parte difícil não foi o modelo. Foi o dado real.

A fonte atrasa e às vezes deixa buracos. Os dados chegam com alguns dias de atraso, e nem sempre completos. Em novembro de 2026, os dias 14, 15 e 16 ficaram com cerca de 5% das viagens enquanto os dias seguintes já estavam completos. Se eu tratasse isso como dado real, o painel mostraria uma queda de 42% que não existiu. Criei uma regra que compara cada dia com a mediana do mesmo tipo de dia nas semanas anteriores. Dia muito abaixo disso é marcado como falha da fonte: sai das comparações, não entra no treino e aparece no painel como "sem dados da fonte".

Prever além do atraso. Como a fonte atrasa, o modelo usa apenas informações de pelo menos 14 dias antes do dia previsto. Assim a previsão continua chegando a dias que ainda estão no futuro, e não só aos que já passaram.

Feriados vêm marcados como domingo. A fonte trata todo feriado como "Domingo" e algumas vésperas como "Sábado". Montei uma tabela própria de feriados e um calendário de eventos para o modelo saber o que é feriado de verdade, o que é ENEM, eleição, show ou jogo.

O BigQuery gratuito tem limites. Por isso o pipeline recria as tabelas inteiras todo dia.


Tecnologias
SQL (BigQuery): camadas prata e ouro, funções de janela e testes de qualidade com ASSERT
Python (Databricks): pandas, LightGBM e MLflow para registrar cada treino
GitHub Actions: agendamento diário e chamada ao Databricks pela API
Power BI: DAX, modelo em estrela e projeto salvo em PBIP (dá para versionar no Git)

------------------------------------


A management dashboard for Rio de Janeiro's municipal bus network, with a trip forecast for each route over the next 14 days. Everything runs on its own, every day, at no cost.

Executive Dashboard

Why I built this

I wanted three things:

a topic with plenty of public data, not a ready-made course dataset;
a forecast I could check later, day by day;
a dashboard for decision-makers, not for the general public.

The municipal bus trip data that Rio's city government publishes on BigQuery (data.rio) checked every box.

What the dashboard answers

Three pages, each with one question.

1. Executive Dashboard: how is the network doing? Daily average for the last week with complete data (trips, km, fleet and speed), compared with the same days of the previous week. It shows the projected month-end total and a warning when an operator runs below what the model expected.

2. Forecast and Alerts: what's coming and where should we act? Forecast trips per operator for the coming days, a calendar of holidays and events, and the routes that fell furthest below expectations. Clicking an operator filters its routes.

3. Model Confidence How much the model missed when tested on past data, where it gets things right, where it gets them wrong, and how it's doing now in production.

Forecast and Alerts	Model Confidence
Forecast and Alerts	Model Confidence
Every day
GitHub Actions runs pipeline.sql on BigQuery. It rebuilds the clean tables and runs data quality tests. If any test fails, the process stops and nothing wrong reaches the dashboard.
If everything passes, Actions itself calls Databricks through the API.
Databricks reads the data, retrains the model, generates the forecast for the next 14 days and writes it back to BigQuery.
Power BI reads the final tables.

If the source is late or comes in with a problem, the pipeline lets me know.

The model

A single LightGBM model for all routes. It predicts how many trips each route will run on each day.

What took the most work

The hard part wasn't the model. It was real-world data.

The source runs late and sometimes leaves gaps. Data arrives a few days late, and not always complete. In November 2026, the 14th, 15th and 16th had only about 5% of their trips while the following days were already complete. Had I treated that as real data, the dashboard would have shown a 42% drop that never happened. I wrote a rule that compares each day with the median for the same type of day in previous weeks. A day far below that is flagged as a source failure: it's left out of comparisons, isn't used for training, and shows up on the dashboard as "no data from the source".

Forecasting past the delay. Because the source runs late, the model only uses information from at least 14 days before the day being predicted. That way the forecast keeps reaching days that are still in the future, not just days that have already passed.

Holidays come in labeled as Sunday. The source treats every holiday as "Sunday" and some holiday eves as "Saturday". I built my own holiday table and an events calendar so the model knows what's actually a holiday, and what's a national exam day (ENEM), an election, a concert or a football match.

Free BigQuery has limits. That's why the pipeline rebuilds the tables from scratch every day.

Tech stack
SQL (BigQuery): silver and gold layers, window functions and data quality tests with ASSERT
Python (Databricks): pandas, LightGBM, and MLflow to log every training run
GitHub Actions: daily scheduling and the call to Databricks through the API
Power BI: DAX, star schema, and the project saved as PBIP (so it can be versioned in Git)
