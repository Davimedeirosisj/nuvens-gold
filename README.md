# Nuvens Gold Breakout MT5

Clean-room implementation inspired by the observed behavior of a protected XAUUSD breakout EA. It is not the original commercial EA and does not contain decompiled or copied source.

## Operational model

- XAUUSD breakout using pending Buy Stop and Sell Stop orders.
- ATR volatility gate: no new pending orders when ATR is below `MinATR`.
- M30 signal structure with an optional H4 EMA trend filter.
- ATR-based entry buffer, stop loss and take profit.
- Risk-based position sizing (`RiskPerSignal`).
- Breakeven and ATR trailing management.
- Daily-loss and high-water-mark drawdown blocks.
- Spread and Friday controls.

## Important

This EA is a new, independent implementation based on behavioral observations. The exact formulas and internal code of the commercial EX5 could not be recovered. Backtest and forward-test it on demo before any funded account.

The included `.ex5` was compiled with MetaTrader 5 build 6264. The source `.mq5` is included so the binary can be rebuilt.

## Documentation

See [docs/OPERACIONAL.md](docs/OPERACIONAL.md) for the complete operating model, entry and exit rules, ATR logic, risk sizing, drawdown protections, and parameter reference.
