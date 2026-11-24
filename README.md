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


