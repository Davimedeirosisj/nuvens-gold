# Nuvens Gold Breakout MT5 — Documento Operacional

## 1. Visão geral

O Nuvens Gold Breakout MT5 é uma Expert Advisor para MetaTrader 5 criada em implementação independente (clean-room), inspirada no comportamento observado de uma EA comercial protegida. Ela não contém código decompilado ou copiado do Gold Reaper.

O modelo procura rompimentos de máximas e mínimas recentes no XAUUSD. Quando a volatilidade está suficiente, coloca uma ordem pendente acima do mercado e outra abaixo, desde que o filtro direcional permita cada lado.

O timeframe padrão do sinal é M30 e o filtro direcional usa a média exponencial do H4.

## 2. Fluxo operacional

Em cada novo candle do timeframe de sinal, a EA:

1. Atualiza o controle diário e o maior saldo/equity registrado.
2. Verifica limite diário, drawdown total, spread e horário de sexta-feira.
3. Calcula o ATR do timeframe de sinal.
4. Se o ATR estiver abaixo de `MinATR`, cancela as pendentes da EA e não abre novas ordens.
5. Procura a máxima e a mínima dos últimos `BreakoutLookback` candles fechados.
6. Adiciona o buffer `EntryATRBuffer` multiplicado pelo ATR.
7. Coloca `Buy Stop` acima da máxima e `Sell Stop` abaixo da mínima.
8. Calcula o lote pelo risco monetário e pela distância até o stop.
9. Administra posições abertas com breakeven e trailing baseado em ATR.

As ordens pendentes antigas da mesma EA são removidas e recalculadas a cada novo candle. A validade padrão de uma ordem pendente é de 24 horas.

## 3. Condição de volatilidade

O ATR é usado como filtro mínimo de atividade:

```text
Se ATR < MinATR:
    cancelar pendentes
    não abrir novas ordens
```

Isso evita operar quando o ouro está com amplitude muito pequena. O valor de `MinATR` depende da quantidade de casas decimais e do contrato oferecido pela corretora; deve ser calibrado no símbolo do usuário.

## 4. Entradas

### Compra

```text
máxima = maior máxima dos últimos BreakoutLookback candles fechados
entrada = máxima + EntryATRBuffer × ATR
```

Uma `Buy Stop` só é enviada quando o preço de entrada fica acima do ask atual e o filtro H4 permite compras.

### Venda

```text
mínima = menor mínima dos últimos BreakoutLookback candles fechados
entrada = mínima − EntryATRBuffer × ATR
```

Uma `Sell Stop` só é enviada quando o preço de entrada fica abaixo do bid atual e o filtro H4 permite vendas.

O filtro de tendência compara o fechamento do último candle H4 com uma EMA. Compras são permitidas quando o fechamento está acima ou igual à EMA; vendas, quando está abaixo ou igual à EMA.

## 5. Stop loss e take profit

Para uma compra:

```text
SL = entrada − SL_ATR × ATR
TP = entrada + TP_ATR × ATR
```

Para uma venda:

```text
SL = entrada + SL_ATR × ATR
TP = entrada − TP_ATR × ATR
```

Com os valores padrão, o alvo nominal é aproximadamente 1,33 vezes a distância do stop (`2,00 / 1,50`). O trailing pode alterar a relação efetiva entre risco e retorno.

## 6. Dimensionamento por risco

O lote é estimado assim:

```text
risco monetário = equity ou saldo × RiskPerSignal / 100
valor do stop   = distância do stop / tick size × tick value
 lote           = risco monetário / valor do stop
```

O resultado é ajustado ao lote mínimo, máximo e passo de volume da corretora.

O risco é por sinal. Se várias ordens forem acionadas simultaneamente, o risco agregado pode ser superior ao risco de uma única operação. Por isso, os limites diário e total continuam necessários.

## 7. Gerenciamento das posições

### Breakeven

Quando o preço avança `BreakEvenAtR` vezes o risco inicial, o stop pode ser deslocado para o preço de entrada, acrescido de `BreakEvenOffsetATR × ATR`.

### Trailing ATR

Com `UseSwingTrailing=true`, o stop acompanha o preço usando uma distância de `TrailATR × ATR`:

```text
compra: novo SL = bid − TrailATR × ATR
venda:  novo SL = ask + TrailATR × ATR
```

O stop só avança em direção ao lucro. Ele nunca é ampliado para aumentar o risco da posição.

## 8. Proteções de mesa proprietária

### Limite diário

No início de cada novo dia, a EA registra o equity de referência. Se o equity cair abaixo de:

```text
equity inicial do dia × (1 − MaxDailyLoss / 100)
```

a EA bloqueia novas ordens.

### Drawdown total

A EA mantém um high-water mark do equity. Se o equity cair abaixo de:

```text
maior equity registrado × (1 − MaxTotalDrawdown / 100)
```

a EA bloqueia novas ordens.

Esses controles são internos à EA. A regra da mesa proprietária pode usar equity flutuante, saldo inicial do dia, horário próprio e outras regras; sempre deve ser conferida separadamente.

## 9. Filtros de execução

- `MaxSpreadPoints` impede novas entradas quando o spread ultrapassa o limite.
- `FridayStopHour` bloqueia novas entradas a partir do horário definido na sexta-feira.
- `PendingExpiryHours` define a validade das ordens pendentes.
- `MagicNumber` separa as operações desta EA das demais estratégias.
- O símbolo é obtido do gráfico em que a EA está instalada; ela não força XAUUSD internamente.

## 10. Parâmetros

| Parâmetro | Padrão | Função |
|---|---:|---|
| `SignalTF` | M30 | Timeframe principal dos sinais |
| `BreakoutLookback` | 20 | Quantidade de candles para máxima/mínima |
| `ATRPeriod` | 14 | Período do ATR |
| `MinATR` | 2.0 | ATR mínimo para permitir operações |
| `EntryATRBuffer` | 0.10 | Distância extra da entrada em ATR |
| `SL_ATR` | 1.50 | Distância do stop em ATR |
| `TP_ATR` | 2.00 | Distância do alvo em ATR |
| `UseHigherTFTrend` | true | Liga o filtro direcional superior |
| `HigherTF` | H4 | Timeframe do filtro de tendência |
| `TrendMAPeriod` | 50 | Período da EMA superior |
| `RiskPerSignal` | 0.25 | Risco percentual por sinal |
| `MaxDailyLoss` | 4.0 | Bloqueio de perda diária em percentual |
| `MaxTotalDrawdown` | 8.0 | Bloqueio de drawdown total em percentual |
| `InitialBalanceReference` | 0.0 | Reservado para referência manual futura |
| `UseEquityForRisk` | true | Usa equity em vez de saldo no cálculo de lote |
| `MagicNumber` | 26001501 | Identificador das operações |
| `MaxSpreadPoints` | 500 | Spread máximo permitido |
| `UseBreakEven` | true | Ativa breakeven |
| `BreakEvenAtR` | 1.0 | Múltiplo de risco para ativar breakeven |
| `BreakEvenOffsetATR` | 0.05 | Folga do breakeven em ATR |
| `UseSwingTrailing` | true | Ativa trailing baseado em ATR |
| `TrailATR` | 1.0 | Distância do trailing em ATR |
| `PendingExpiryHours` | 24 | Validade da ordem pendente |
| `CancelOppositeOnEntry` | false | Reservado para controle futuro de ordem oposta |
| `UseNewsPause` | false | Reservado para integração futura com calendário |
| `NewsPauseMinutes` | 60 | Janela futura de pausa de notícias |
| `FridayStopHour` | 20 | Hora de bloqueio na sexta-feira |

## 11. Instalação

1. Copie `NuvensGold_Breakout.ex5` para `MQL5/Experts/NuvensGold/`.
2. Ou abra `NuvensGold_Breakout.mq5` no MetaEditor e compile.
3. Reinicie o navegador do MetaTrader ou atualize a árvore Navigator.
4. Anexe a EA ao gráfico do ativo desejado.
5. Confira o tamanho do contrato, tick value, spread e horário do servidor.
6. Faça backtest e forward test em conta demo.

## 12. Limitações e uso responsável

Esta EA é uma reconstrução comportamental independente. Ela não reproduz fórmulas internas desconhecidas do EX5 comercial. Os parâmetros padrão não constituem recomendação financeira e não garantem aprovação em FTMO, The5ers ou qualquer outra mesa.

Antes de usar capital real, testar com:

- spread variável e comissão real;
- atraso de execução;
- diferentes anos e períodos fora da amostra;
- gaps e notícias;
- regras específicas da mesa;
- risco menor que o limite máximo permitido.
