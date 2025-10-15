# JKK Retracements EA – Concept Review

## Identified Trading Concept
- The expert adviser submits **paired pending limit orders every new H1 bar**: one BUY LIMIT below the current Bid (Bid − 10 points) and one SELL LIMIT above the current Ask (Ask + 10 points). Both orders are created with zero stop-loss and take-profit values and share the same lifetime (`LifetimePendingOrders`).
- The system therefore attempts to capture **short-term mean-reversion / retracement moves** around the hourly open, expecting price to dip and reverse upward (triggering the buy limit) or rise and reverse downward (triggering the sell limit).
- There is no technical indicator filter; trade direction is unconditional aside from the `TradeBUY` / `TradeSELL` switches and spread / time filters.
- Position sizing is primarily fixed-lot, with optional auto-lot (percentage of balance/equity) and a step increase once a configured number of positions is already open.
- Loss containment is delegated to a **virtual equity drop check** (pauses and closes all positions if equity falls below 60% of balance) and an optional **hedging module** that opens an opposite-market order when floating P/L drawdown exceeds a pip threshold. The hedge can trail to break-even and has its own SL/TP.
- A manual control panel allows quick closing of positions or pausing the EA.

## Coherence Assessment
- The high-level idea of fading hourly extensions with symmetric limit orders is coherent as a **mean-reversion grid / retracement** approach, but the current implementation lacks several elements required for risk consistency.
- Because the limits are placed at a fixed distance (10 points) without volatility adaptation, the strategy can struggle during high-volatility periods; the hedging logic tries to compensate yet is loosely coupled to actual price movement (it references account P/L instead of chart-based drawdown).
- Risk control is weak: default trades have **no hard SL/TP**, relying on equity drop or manual intervention. That makes the concept vulnerable to runaway trends and gaps, especially if hedging is disabled or misconfigured.
- The hedging trigger uses `CalculateTotalProfit()` (cash P/L) divided by `pointValue`, which conflates monetary drawdown with pip distance and is sensitive to lot size changes. It might misrepresent actual drawdown and may not activate when expected.
- Order lifetime management is coherent, but the EA can accumulate many open trades because a new pair of pending orders is placed every hour regardless of existing exposure (until `MaxOpenOrders` is reached). This behavior is consistent with grid strategies but increases risk concentration.

## Recommendations Before Further Development
1. **Clarify the risk model**:
   - Decide on explicit per-trade or per-grid stop-loss logic. Consider using the existing `VirtualStopLoss` input or chart-based SL to limit catastrophic losses.
   - Revisit the equity drop threshold (60%). Provide a configurable percentage input and optionally support daily loss limits.
2. **Improve hedge trigger accuracy**:
   - Instead of P/L-derived pips, compute floating drawdown using averaged entry price or the worst open position price. This will align hedging with actual price movement.
   - Consider tracking hedge tickets per symbol/direction instead of a single global `hedgeTicket` to avoid conflicts in multi-position scenarios.
3. **Volatility adaptation**:
   - Scale the limit order distance with ATR or recent range so the retracement entry remains proportionate to market conditions.
   - Allow different distances for buy and sell sides to accommodate asymmetric behavior.
4. **Order management enhancements**:
   - Add optional take-profit targets (e.g., opposite side of the range) and a trailing or partial-close mechanism.
   - Ensure pending orders are cancelled when price action invalidates the setup (e.g., when the next hour begins and the order was not triggered).
5. **Code robustness**:
   - Validate that `HasTradeThisHour` correctly recognizes pending orders; otherwise, consider storing the last order hour explicitly.
   - Introduce structured logging and error handling (e.g., retries on trade context busy).
6. **Testing and Monitoring**:
   - Back-test across varying volatility regimes to assess whether the fixed-distance grid maintains profitability.
   - Add metrics to the info panel (max DD, hedge status) to monitor risk while live trading.

These steps will help solidify the EA's core retracement concept and provide a safer foundation for subsequent feature development.

## Trading-Session Time Conversion

- **Session gating hinges on an accurate GMT timestamp.** `IsTradingTime()` converts the broker's clock to GMT and then checks the hard-coded London/New York windows.【F:JKK_Retracements.mq4†L174-L178】【F:JKK_Retracements.mq4†L303-L374】
- The EA now supports three offset sources:
  1. **Manual local offset (default path).** `GMTOffset` specifies the workstation/VPS offset from GMT in hours. When this input is left at `0`, the code automatically estimates the local offset from `TimeLocal() - TimeGMT()` and logs the detected value.【F:JKK_Retracements.mq4†L318-L352】
  2. **Manual broker offset.** Enable `UseBrokerServerOffset` and fill `BrokerServerOffset` with the broker's GMT difference. If left at `0`, the EA falls back to the measured `TimeCurrent() - TimeGMT()` offset and reports it.【F:JKK_Retracements.mq4†L354-L375】
  3. **Explicit configuration.** Supplying either offset input overrides the auto-detection logic for precise DST handling.
- With these fallbacks the GMT conversion aligns even when the inputs remain at their defaults, allowing `ManageOrders()` to execute during the intended London/New York hours while still prompting the trader to set explicit offsets for long-term accuracy.【F:JKK_Retracements.mq4†L332-L375】【F:JKK_Retracements.mq4†L540-L576】
