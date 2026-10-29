# SIGO SCALPER

Native MetaTrader 5 Expert Advisor for configurable EMA/RSI/ATR scalping. It sends real broker orders through MT5 when enabled. This is an independently designed strategy inspired by visible automation features, not AXIOM's private algorithm. No reference video was supplied with this project. Profitability and suitability for small balances are unproven.

**Status:** source implementation. MetaEditor and MT5 are unavailable in the Linux development environment, so this code has **not been compiled, run in MT5, or backtested**. Static source checks are not a substitute. Complete compilation, Strategy Tester checks, and demo validation before considering a live account. Automated entries default to **off**.

## Architecture

- `SIGO_Scalper.mq5`: inputs, lifecycle, broker/session/spread checks, single-controller lease, closed-bar scheduling.
- `SignalEngine.mqh`: EMA 20/50 on execution/confirmation/trend frames, RSI 14, ATR 14, historical support/resistance, candle confirmation.
- `RiskManager.mqh`: account-equity sizing, account-wide stop exposure, margin reserve, persisted daily and peak-equity protection.
- `TradeManager.mqh`: native requests with attached SL/TP, `OrderCheck`, retcode logs, cooldown recovery, trailing/break-even/partial exits and losing-streak pause.
- `Dashboard.mqh`: optional dark chart panel with white text and #E91E63 accents.

Signals use only completed bars. Default BUY requires bullish EMA alignment on M1/M5/M15, M1 close above its fast EMA, RSI 50–70, a bullish candle closing above its predecessor, a bounce within 0.5 ATR of historical support, and at least one ATR of space to resistance. SELL mirrors those rules with RSI 30–50. Zones use 20 older candles, excluding the signal bar and its predecessor. No martingale, grid, or entries triggered by losing positions. Default SL is 1.5 ATR (expanded for broker stop restrictions); TP is 1.5 times the final price risk. Signals can be rare; the EA does not force trades.

## Windows installation and compilation

1. Install your broker's **MetaTrader 5 desktop** on Windows or a compatible Windows VPS. Sign in to a **demo** account. MT4 is incompatible.
2. In MT5 choose **File → Open Data Folder**. Open `MQL5\Experts`, create `SIGO_SCALPER`, and copy `SIGO_Scalper.mq5` plus all four `.mqh` files into that folder. Preserve the filenames and keep the headers beside the EA.
3. Press **F4** in MT5 to open MetaEditor. In its Navigator open `Experts\SIGO_SCALPER\SIGO_Scalper.mq5`.
4. Press **F7** to compile. Require **zero errors**, review all warnings, and confirm `SIGO_Scalper.ex5` is created. The standard `Trade\Trade.mqh` library ships with MT5; no DLL, Python bridge, API key, or paid dependency is required.
5. Return to MT5, refresh Navigator → Expert Advisors. First use **Ctrl+R** to open Strategy Tester and follow [BACKTESTING.md](BACKTESTING.md). Set `EnableAutomatedTrading=true` in tester inputs to test entries.
6. For demo forward testing, select the exact broker symbol in Market Watch, open its chart, then drag the EA onto it. Start with M1 and the documented defaults. Set `TradingSymbol` blank to use that chart, or enter its exact matching name.
7. In EA properties enable **Allow Algo Trading** and set `EnableAutomatedTrading=true` after checking all risk/cost inputs. Enable MT5's toolbar **Algo Trading** button and terminal Expert Advisor permissions. Keep DLL imports disabled; none are needed.
8. Inspect **Experts** and **Journal** for initialization, signal reasons, sizing, broker rejections, fills and protection events. Verify every filled position has SL and TP. The EA will not retry with naked orders if attached stops are rejected. It also requests closure of an owned position found without SL or TP on subsequent events, independent of indicator readiness.
9. Keep desktop MT5 running and connected, or use a compatible VPS. Trailing, break-even, partial exits and equity protection require the EA to be running; accepted broker SL/TP normally remain when it is offline, subject to broker execution conditions.

## Instruments and accounts

Use the actual chart symbol: `XAUUSD`, `XAUUSDm`, `pro.XAUUSD`, or your broker's equivalent. The EA uses symbol properties instead of assuming a forex contract or pip size. NAS100, US30, EURUSD and GBPUSD can be selected by attaching to those charts, but **spread, volatility, cost and session settings must be calibrated separately**. This is one symbol per instance; it does not scan Market Watch. Chart and configured symbol must match to use the correct tick events.

Hedging accounts permit multiple independently managed owned positions up to configured caps. Netting/exchange accounts permit only one position per symbol; the EA refuses additional entries on that symbol rather than merging risk. Do not trade the same symbol manually or through another EA while SIGO controls it: netting merges deal ownership, and magic numbers cannot isolate shared positions.

Run only one SIGO controller per account. A 15-second renewable terminal-global lease blocks concurrent SIGO instances within the same terminal. It cannot coordinate other terminals, other EAs or manual trading. Restart after an abnormal exit may require waiting 15 seconds. Other account positions count toward the account cap and open-risk budget; any position without a stop, or any pending order anywhere on the account, blocks new entries conservatively. Emergency liquidation affects only positions matching this symbol and magic number, so it cannot guarantee account protection from other activity.

## Small-account sizing and protection

Risk defaults to 0.5% of equity, with a 2% cap on estimated aggregate open risk. `OrderCalcProfit` values stop loss in account currency using the broker's contract/tick/currency rules. Estimated commission/fees per round-turn lot and an adverse slippage allowance are included. Spread is already included through the entry side and stop price; it is not charged twice. Margin is calculated separately using `OrderCalcMargin` and the final request is checked with `OrderCheck`. Lots are rounded down to broker steps and never forced up to the minimum.

For equities of 5, 10, 20, 50, 100 and 500 account-currency units, a 0.5% budget is respectively 0.025, 0.05, 0.10, 0.25, 0.50 and 2.50. These are budgets, **not promises of tradable lot sizes**. If the minimum volume exceeds the budget or free-margin reserve, the EA logs the reason and skips. A $5 or $10 standard gold account may never qualify. Leverage reduces margin, not stop-loss risk. Commissions, swaps, gaps, price changes and slippage can exceed estimates; stops do not guarantee maximum loss. Market-execution brokers may ignore requested deviation.

Daily loss is measured from equity at the first EA observation of each broker-server day (or startup on its first day); it includes floating and realized changes across the account. At 3% by default, the daily halt latches until the next observed server day, even if equity recovers. Overall 6% drawdown is measured from the highest equity observed while running and latches until a deliberate manual reset. By default either breach also requests closure of owned positions, retrying on subsequent events if rejected. Deposits and withdrawals are not cash-flow-adjusted and can affect these limits. No offline monitoring or exact midnight reconstruction is claimed.

Live state is stored in MT5 terminal global variables keyed by a fixed-length hash of server, login and magic: day, daily baseline/halt, equity peak/halt, entry cooldown, partial-exit markers. Broker history supplements entry and partial recovery. Preserve the same magic and terminal data directory across restarts. A risk-state write failure blocks new entries. Terminal globals are local and can expire after four weeks without access; moving to another terminal/VPS does not transfer them. Strategy Tester runs use isolated in-memory state and do not reuse live halts. To reset a live overall halt, stop the EA, review the cause, and use **F3** to remove only that strategy's `SIGO.<identity-hash>.` state before restarting; this resets protection baselines, not losses. Never reset halts automatically.

Entries are attempted once per new execution candle; restart skips the current candle. Submission attempts reserve the cooldown even if the response is ambiguous. Outstanding account orders block entries. There is no blind resend after rejection. Broker outcomes and history remain authoritative; a timeout does not prove no fill. Partial fills retain their accepted broker stops and are not topped up. Unexpected external edits to positions require operator review.

Break-even is a price-level feature; zero offset does **not** cover commissions, swaps or exit slippage. Partial exits round down and require both the closed and remaining volume to meet broker minimums. The partial reservation is persisted before submission, so a rejected or ambiguous partial request is not automatically repeated for that position. An existing exit deal suppresses further partial reductions for that position. Disabling automated entries does not disable protective management of existing owned positions. Remove the EA to stop that management, understanding the consequence.

## Mobile monitoring

Install **MetaTrader 5** on Android, select the same broker/server, and sign in to the same trading account. The Trade tab shows balance, equity, free margin, margin level, open BUY/SELL positions and floating P/L; History shows completed trades. Availability and layout depend on broker/app version. Mobile can perform supported manual actions. **The EA runs on desktop MT5/VPS, never inside MT5 mobile.** Investor access may permit monitoring only. No extra integration or secret in this repository is required.

See [SETTINGS.md](SETTINGS.md) for every input and [BACKTESTING.md](BACKTESTING.md) for acceptance scenarios and performance validation. This project contains no fabricated results and makes no return guarantee.
