# SIGO SCALPER settings

All price distances labeled **points** use `SYMBOL_POINT`, not pips or dollars. Broker gold and index point sizes differ. Monetary costs are in the account's deposit currency. These are configurable starting values, not validated presets. Inputs appear in the MT5 EA properties and Strategy Tester.

| Input | Default | Meaning |
|---|---:|---|
| EnableAutomatedTrading | false | Enables new entries; existing owned positions still receive management and emergency protection |
| TradingSymbol | empty | Uses chart symbol; a nonempty exact broker name must match chart |
| MagicNumber | 26052901 | Positive ownership/state identifier; keep stable across restarts |
| TradingDirection | SIGO_BOTH | `SIGO_BOTH`, `SIGO_BUY`, `SIGO_SELL` |
| MaximumTradesPerSymbol | 3 | Cap on all positions on this symbol, including external positions; netting stays at one |
| MaximumAccountPositions | 3 | All account positions, including manual/other strategies |
| MinimumEntryIntervalSeconds | 60 | Cooldown from last submission attempt or recovered fill |
| MaximumSpreadPoints | 50 | Blocks new entries above this ask-minus-bid spread |
| MaximumDeviationPoints | 10 | Requested entry/close deviation; broker execution mode may override it |
| MaximumQuoteAgeSeconds | 10 | Reject older/invalid entry quotes |
| StrategyTimeframe | PERIOD_M1 | Signal candle and new-bar entry gate |
| ConfirmationTimeframe | PERIOD_M5 | Confirmation EMA alignment on closed bar |
| TrendTimeframe | PERIOD_M15 | Overall trend EMA alignment on closed bar |
| FastEMAPeriod | 20 | Fast EMA on all three frames |
| SlowEMAPeriod | 50 | Slow EMA, must exceed fast period |
| RSIPeriod | 14 | Execution RSI; BUY 50–70, SELL 30–50, change signal module for different thresholds |
| ATRPeriod | 14 | Execution ATR for volatility, stops and management |
| ZoneLookbackBars | 20 | Older bars for min-low support and max-high resistance |
| ZoneToleranceATR | 0.5 | Maximum distance from zone for bounce/rejection |
| MinimumATRPoints | 10 | Minimum allowed ATR |
| MaximumATRPoints | 0 | Upper ATR limit; zero disables upper filter |
| StopLossATRMultiplier | 1.5 | Initial ATR stop distance, expanded if broker stops require it |
| TakeProfitRiskMultiplier | 1.5 | TP distance / actual entry-to-SL distance after rounding |
| RiskPercent | 0.5 | Maximum estimated equity risk of a new trade |
| MaximumDailyEquityLossPercent | 3 | Daily equity loss halt; resets at next observed broker day |
| MaximumOverallDrawdownPercent | 6 | Observed equity-peak drawdown halt; manual review/reset required |
| MaximumTotalOpenRiskPercent | 2 | Account-wide estimated risk ceiling; missing stops/pending orders block entries |
| EstimatedRoundTurnCostPerLot | 10 | Estimated commission/fees per round-trip lot in account currency; obtain actual broker schedule |
| StopSlippageAllowancePoints | 20 | Additional adverse stop execution assumption; requested entry deviation also included in sizing |
| FreeMarginReservePercent | 20 | Portion of free margin unavailable to this new order |
| EmergencyCloseOwnedPositions | true | Requests owned-symbol/magic closure on either equity breach |
| ConsecutiveLossLimit | 3 | Completed losing positions before pause; zero disables |
| LossPauseMinutes | 60 | Pause measured from latest completed losing position |
| EnableTrailingStop | false | Enables trailing after profit reaches its ATR distance |
| TrailingStopATR | 1 | Trailing activation and distance, based on latest closed-bar ATR |
| EnableBreakEven | true | Enables favorable entry-based stop adjustment |
| BreakEvenActivationATR | 1 | Favorable price distance required to activate |
| BreakEvenOffsetPoints | 0 | Favorable offset from entry; zero excludes costs |
| EnablePartialProfit | false | One partial reduction per position, if minimum/remainder allow |
| PartialProfitActivationATR | 1.5 | Favorable price distance required |
| PartialClosePercent | 50 | Requested percent of then-current volume, rounded down |
| EnableSessionFilter | true | Restricts entries, never protection/management |
| SessionStartHour | 7 | Inclusive broker server hour, 0–23 |
| SessionEndHour | 20 | Exclusive hour; equal start/end = all day; supports overnight |
| ShowDashboard | true | Dark chart dashboard; no external UI/service |

Account percentages must be positive and at most 100; per-trade risk cannot exceed aggregate risk. Margin reserve is 0–less than 100; partial percent is greater than 0 and less than 100. Invalid inputs cause initialization failure, with a log message. These validation boundaries are not recommendations to increase risk.

Stops are rounded outward to tick size. Stop modifications also respect stop/freeze distance and never deliberately loosen an existing stop. ATR-based management thresholds move as volatility changes. RSI bounds, the candle rule, opposing-zone room of one ATR, and zone construction are independent logic in `SignalEngine.mqh`; they are not all exposed as inputs. No economic-news filter, portfolio correlation model, multi-symbol scanner, or hosted mobile service is included.

Daily dashboard realized P/L sums today's account BUY/SELL deal profit, swaps, commissions and fees. Separate broker balance-charge transactions are not included. Equity protection still observes their effect on equity. Dashboard figures use account scope except the explicitly labeled owned-position count and symbol spread/trend.
