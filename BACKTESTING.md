# Backtesting and validation

**No MT5 compilation, backtest or demo run has been performed for this source release. There are no performance results.** Source inspection on Linux cannot validate MQL5 compilation, broker execution or strategy profitability.

## Compile and establish a baseline

1. Follow README installation; compile `SIGO_Scalper.mq5` in current MT5 MetaEditor with F7. Require zero errors and investigate warnings. Record terminal build and compiler output.
2. In MT5 press Ctrl+R, select this Expert Advisor and the **exact broker symbol**, timeframe M1, and **Every tick based on real ticks** where available. Download enough M1/M5/M15 history plus a warmup period before the measured period. The signal engine skips incomplete buffers.
3. Set `EnableAutomatedTrading=true`, explicit dates, account currency, actual account type/leverage, spread/cost inputs, and initial deposit. Use the broker's tick data and contract specifications. Confirm Tester Journal initialization succeeded and actual entries/exits occurred. A zero-trade run validates neither trade execution nor profitability; investigate spread, minimum risk, signal rarity, trading permissions, history and session clocks.
4. Save the `.set` inputs, report, Journal, symbol specification snapshot and date ranges. Separate failed/rejected orders from executed trades. Check that attached stops appear on every accepted entry. Do not change signals merely to manufacture trades.

## Costs and sensitivity

The risk model's `EstimatedRoundTurnCostPerLot` is a sizing reserve; it **does not inject commission into the tester**. Configure actual commissions in supported tester/broker account settings, or account for verified costs separately in analysis. Report whether tick spread is variable and whether commissions, swaps and fees are actually charged. Do not add spread twice to broker P/L. Apply the same currency conventions throughout.

Run sensitivity variants with wider observed spreads, higher commissions, more restrictive deviation, larger slippage reserves and execution delays using tester settings supported by your terminal. An input reserve changes sizing, not fill simulation. If the tester cannot model actual slippage/latency, label that limitation and perform controlled demo forward tests. Test stop gaps around session opens; fills can breach a nominal loss budget.

## Required functional scenarios

Record expected and observed outcomes; these are instructions, **not reported passing tests**.

| Scenario | Expected behavior |
|---|---|
| Trading disabled / terminal Algo Trading disabled | No new entry; existing management may attempt requests, which terminal permissions can reject |
| Bullish and bearish qualifying historical bars | BUY and SELL use aligned closed-bar indicators and native broker deals with SL/TP |
| Missing history / invalid symbol | No entry; warmup reason or initialization failure |
| Symbol suffix/prefix | Attach to exact broker chart name; properties and calculations use that symbol |
| Excess spread / closed session / stale quote | No new entry; management is not session-gated |
| Deposits 5, 10, 20, 50, 100, 500 | Respect equity budget, min/step/max volume and margin; skip minimum lots that are unsafe |
| Different leverage, contract sizes, deposit currencies | Broker profit/margin calculations determine affordability; no forced 0.01 lots |
| Existing position without SL / any pending order | New entry blocked account-wide |
| Other account positions with SL | Their current-to-stop risk and estimated costs reduce remaining risk budget |
| Per-symbol or account cap / cooldown | No additional entry |
| Consecutive losing completed positions | Aggregate partial exits/entry fees per lifecycle; pause until configured time expires |
| 3% daily equity loss, then recovery | New entries remain blocked for the observed server day; owned emergency closures requested if enabled |
| Next observed server day | Daily baseline/halt rolls over; overall halt stays latched |
| 6% peak-equity drawdown | Overall halt persists across restart; no automatic reset |
| Emergency closure rejected / market closed | Retcode logged; later events attempt owned closure again |
| Trailing/break-even / freeze zone | Only favorable valid stops requested; broker retcodes checked |
| Partial exit at minimum lot | Skip unless both close and remainder meet minimum; no repeated partial per lifecycle |
| Partial fill / insufficient margin / invalid stops / requote / timeout | Log broker result; no naked fallback, immediate resend, top-up or martingale |
| Hedging account | Individual ticket management and multiple entries only within caps |
| Netting account | No adding to existing symbol position; partial exit reduces owned sole position |
| Restart with open trades | Same account/symbol/magic discovers positions; history/global state recover cooldown and partial status; current bar skipped |
| Duplicate SIGO chart in one terminal | Second controller initialization blocked while lease is valid |

Use a demo terminal for restart, terminal-global, duplicate-chart and mobile checks; Strategy Tester uses isolated state and does not establish live-state persistence. To verify restart recovery, record state using F3, stop/restart MT5 without deleting its data, compare unchanged baselines/halts, and confirm no duplicate entry or second partial exit. Simulate missing connectivity only on demo. Never disable protective assertions or expose a live account to create test cases.

## Measure outcomes

Export completed position lifecycles, not just raw deals (partial exits make deal counts misleading). Include all commissions, fees and swaps. Report at least:

- Net profit and test span, executed position count and rejected/skipped order counts.
- Win rate = profitable completed positions / completed positions; disclose breakeven treatment.
- Profit factor = gross positive net position P/L / absolute gross negative net position P/L; undefined if there are no losses.
- Maximum equity drawdown in currency and percent, including floating losses. Also distinguish tester drawdown from this EA's observed-peak protection metric.
- Maximum consecutive losing completed positions, average win/loss, expectancy per position.
- Average realized R = mean(net position P/L / original estimated monetary risk). Capture original entry/stop/volume and costs from tester execution/history and sizing logs; a later trailed stop is not original risk. Keep it separate from configured price reward:risk (default 1.5). If original risk cannot be reconstructed, mark realized R unavailable.
- Margin level, worst spread/slippage and exposure time where data permits; deposit currency and broker specs.

## Out-of-sample and walk-forward

Split history chronologically before optimization: for example 60% development, 20% validation and 20% untouched final test. Cover varied volatility and sessions. Optimize a small predeclared parameter set on development data only. Freeze it before validation and final evaluation. Do not select the final test period after viewing its returns.

For walk-forward evaluation, choose fixed rolling windows (for example six months training then one month forward), re-fit only on each training window and concatenate its immediately following forward month. Include costs and rejected trades in each fold. Inspect sensitivity around chosen parameters rather than only the best point. Preserve all failed and unprofitable runs.

After historical acceptance, demo forward-test on the intended broker with actual sessions and account specifications. Verify orders, stops, mobile visibility and restart behavior, then compare realized costs to assumptions. No backtest or demo result guarantees future performance, and small accounts may be unable to place any risk-compliant trade.
