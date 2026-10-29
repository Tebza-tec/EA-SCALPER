#property strict
#property version "1.00"
#property description "SIGO SCALPER: closed-bar EMA/RSI/ATR zone scalping with account risk limits."
#include "RiskManager.mqh"
#include "TradeManager.mqh"
#include "SignalEngine.mqh"
#include "Dashboard.mqh"

enum ENUM_SIGO_DIRECTION { SIGO_BOTH=0, SIGO_BUY=1, SIGO_SELL=2 };
input group "Execution"
input bool EnableAutomatedTrading=false;
input string TradingSymbol=""; // Empty = chart symbol; otherwise exact broker symbol
input long MagicNumber=26052901;
input ENUM_SIGO_DIRECTION TradingDirection=SIGO_BOTH;
input int MaximumTradesPerSymbol=3;
input int MaximumAccountPositions=3;
input int MinimumEntryIntervalSeconds=60;
input double MaximumSpreadPoints=50;
input ulong MaximumDeviationPoints=10;
input int MaximumQuoteAgeSeconds=10;
input group "Strategy"
input ENUM_TIMEFRAMES StrategyTimeframe=PERIOD_M1;
input ENUM_TIMEFRAMES ConfirmationTimeframe=PERIOD_M5;
input ENUM_TIMEFRAMES TrendTimeframe=PERIOD_M15;
input int FastEMAPeriod=20;
input int SlowEMAPeriod=50;
input int RSIPeriod=14;
input int ATRPeriod=14;
input int ZoneLookbackBars=20;
input double ZoneToleranceATR=0.5;
input double MinimumATRPoints=10;
input double MaximumATRPoints=0; // Zero disables upper filter
input double StopLossATRMultiplier=1.5;
input double TakeProfitRiskMultiplier=1.5;
input group "Account risk"
input double RiskPercent=0.5;
input double MaximumDailyEquityLossPercent=3;
input double MaximumOverallDrawdownPercent=6;
input double MaximumTotalOpenRiskPercent=2;
input double EstimatedRoundTurnCostPerLot=10; // Account currency; calibrate to broker
input double StopSlippageAllowancePoints=20;
input double FreeMarginReservePercent=20;
input bool EmergencyCloseOwnedPositions=true;
input int ConsecutiveLossLimit=3;
input int LossPauseMinutes=60;
input group "Management"
input bool EnableTrailingStop=false;
input double TrailingStopATR=1;
input bool EnableBreakEven=true;
input double BreakEvenActivationATR=1;
input double BreakEvenOffsetPoints=0;
input bool EnablePartialProfit=false;
input double PartialProfitActivationATR=1.5;
input double PartialClosePercent=50;
input group "Session (broker server clock)"
input bool EnableSessionFilter=true;
input int SessionStartHour=7;
input int SessionEndHour=20; // Equal hours = 24 hours; supports overnight sessions
input bool ShowDashboard=true;

CRiskManager Risk;
CTradeManager Trades;
CSignalEngine Signals;
CDashboard Dashboard;
string SymbolName,Status="Starting",Trend="Waiting",LeaseKey;
datetime LastBar=0;
double LeaseValue=0;
bool HaveLease=false,Tester=false;

void Report(string message)
{
   if(Status!=message) Print("SIGO: ",message);
   Status=message;
}
bool SessionOpen(void)
{
   if(!EnableSessionFilter || SessionStartHour==SessionEndHour) return true;
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   if(SessionStartHour<SessionEndHour) return d.hour>=SessionStartHour && d.hour<SessionEndHour;
   return d.hour>=SessionStartHour || d.hour<SessionEndHour;
}
bool Lease(void)
{
   if(Tester) return true;
   double now=(double)TimeLocal();
   if(!GlobalVariableCheck(LeaseKey)) GlobalVariableTemp(LeaseKey);
   double old=GlobalVariableGet(LeaseKey);
   if(HaveLease && old!=LeaseValue) { HaveLease=false; return false; }
   if(!HaveLease && old>now) return false;
   double next=now+15;
   if(!GlobalVariableSetOnCondition(LeaseKey,next,old)) return false;
   LeaseValue=next; HaveLease=true; return true;
}
bool Permissions(string &reason)
{
   if(!EnableAutomatedTrading) { reason="Automated entries disabled"; return false; }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   { reason="Connection / Algo Trading / account permission unavailable"; return false; }
   return true;
}
bool ValidateInputs(void)
{
   return MagicNumber>0 && RiskPercent>0 && RiskPercent<=MaximumTotalOpenRiskPercent &&
      MaximumTotalOpenRiskPercent>0 && MaximumTotalOpenRiskPercent<=100 &&
      MaximumDailyEquityLossPercent>0 && MaximumDailyEquityLossPercent<=100 &&
      MaximumOverallDrawdownPercent>0 && MaximumOverallDrawdownPercent<=100 &&
      MaximumTradesPerSymbol>0 && MaximumAccountPositions>0 && MinimumEntryIntervalSeconds>=1 &&
      MaximumSpreadPoints>0 && MaximumQuoteAgeSeconds>0 && FastEMAPeriod>0 && SlowEMAPeriod>FastEMAPeriod &&
      RSIPeriod>1 && ATRPeriod>1 && ZoneLookbackBars>=2 && ZoneToleranceATR>=0 &&
      MinimumATRPoints>=0 && (MaximumATRPoints==0 || MaximumATRPoints>=MinimumATRPoints) &&
      StopLossATRMultiplier>0 && TakeProfitRiskMultiplier>0 && EstimatedRoundTurnCostPerLot>=0 &&
      StopSlippageAllowancePoints>=0 && FreeMarginReservePercent>=0 && FreeMarginReservePercent<100 &&
      ConsecutiveLossLimit>=0 && LossPauseMinutes>0 && TrailingStopATR>0 && BreakEvenActivationATR>0 &&
      BreakEvenOffsetPoints>=0 && PartialProfitActivationATR>0 && PartialClosePercent>0 && PartialClosePercent<100 &&
      SessionStartHour>=0 && SessionStartHour<=23 && SessionEndHour>=0 && SessionEndHour<=23;
}
int OnInit(void)
{
   if(!ValidateInputs()) { Print("SIGO: invalid input parameters"); return INIT_PARAMETERS_INCORRECT; }
   SymbolName=TradingSymbol=="" ? _Symbol:TradingSymbol;
   if(SymbolName!=_Symbol)
   { Print("SIGO: attach EA to the exact configured symbol chart so OnTick uses its quotes"); return INIT_PARAMETERS_INCORRECT; }
   if(!SymbolSelect(SymbolName,true) || SymbolInfoDouble(SymbolName,SYMBOL_TRADE_TICK_SIZE)<=0)
   { Print("SIGO: symbol unavailable / invalid tick size"); return INIT_FAILED; }
   Tester=(bool)MQLInfoInteger(MQL_TESTER);
   LeaseKey=StringFormat("SIGO.control.%I64d",AccountInfoInteger(ACCOUNT_LOGIN));
   if(!Lease()) { Print("SIGO: another controller is active for this account in this terminal"); return INIT_FAILED; }
   if(AccountInfoDouble(ACCOUNT_EQUITY)<=0) { Print("SIGO: wait for positive account equity before initialization"); return INIT_FAILED; }
   if(!Risk.Init(SymbolName,MagicNumber,MaximumDailyEquityLossPercent,MaximumOverallDrawdownPercent,
             MaximumTotalOpenRiskPercent,EstimatedRoundTurnCostPerLot,StopSlippageAllowancePoints+(double)MaximumDeviationPoints,FreeMarginReservePercent)) return INIT_FAILED;
   Trades.Init(SymbolName,MagicNumber,MaximumDeviationPoints);
   if(!Signals.Init(SymbolName,StrategyTimeframe,ConfirmationTimeframe,TrendTimeframe,FastEMAPeriod,
                    SlowEMAPeriod,RSIPeriod,ATRPeriod,ZoneLookbackBars,ZoneToleranceATR,MinimumATRPoints,MaximumATRPoints))
   { Print("SIGO: indicator handle creation failed"); return INIT_FAILED; }
   Dashboard.Init(ShowDashboard);
   // Do not enter on the current, possibly already processed bar after restart.
   LastBar=iTime(SymbolName,StrategyTimeframe,0);
   if(!EventSetTimer(1)) return INIT_FAILED;
   Print("SIGO: initialized. No profitability claim; use demo / Strategy Tester first.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer(); Signals.Release(); Dashboard.Destroy();
   if(HaveLease && !Tester) GlobalVariableSetOnCondition(LeaseKey,0,LeaseValue);
}
void ProtectionAndManagement(void)
{
   Trades.CloseUnprotected();
   Risk.Update();
   if(Risk.Breached())
   {
      Report("Equity protection active: new entries blocked");
      if(EmergencyCloseOwnedPositions) Trades.CloseOwned();
      return;
   }
   double atr;
   if(Signals.ATR(atr)) Trades.Manage(atr,EnableTrailingStop,TrailingStopATR,EnableBreakEven,
      BreakEvenActivationATR,BreakEvenOffsetPoints,EnablePartialProfit,PartialProfitActivationATR,PartialClosePercent);
}
void OnTimer(void)
{
   if(!Lease()) { Report("Account controller lease lost"); return; }
   ProtectionAndManagement();
   MqlTick tick; double spread=0;
   if(SymbolInfoTick(SymbolName,tick)) spread=(tick.ask-tick.bid)/SymbolInfoDouble(SymbolName,SYMBOL_POINT);
   Trend=Signals.CurrentTrend();
   Dashboard.Draw(Status,SymbolName,Trend,SessionOpen()?"Open":"Closed",spread,RiskPercent,
                  Risk.Drawdown(),Risk.DailyRealized(),Trades.Count());
}
void OnTick(void)
{
   if(!Lease()) { Report("Account controller lease unavailable"); return; }
   ProtectionAndManagement();
   datetime bar=iTime(SymbolName,StrategyTimeframe,0);
   if(bar<=0 || bar==LastBar) return;
   LastBar=bar; // At most one submission attempt per candle, including rejected requests.
   string reason;
   if(!Permissions(reason) || !Risk.Allowed(reason)) { Report(reason); return; }
   if(!SessionOpen()) { Report("Outside configured session"); return; }
   if(!Trades.CanEnter(MaximumTradesPerSymbol,MaximumAccountPositions,MinimumEntryIntervalSeconds,reason) ||
      Trades.LossPause(ConsecutiveLossLimit,LossPauseMinutes,reason)) { Report(reason); return; }
   MqlTick tick;
   if(!SymbolInfoTick(SymbolName,tick) || tick.bid<=0 || tick.ask<=tick.bid || tick.time<=0 ||
      TimeCurrent()-tick.time>MaximumQuoteAgeSeconds) { Report("Invalid or stale quote"); return; }
   double point=SymbolInfoDouble(SymbolName,SYMBOL_POINT);
   if((tick.ask-tick.bid)/point>MaximumSpreadPoints) { Report("Spread exceeds limit"); return; }
   double atr=0; int side=Signals.Evaluate(atr,Trend,reason);
   if(side==0) { Report(reason); return; }
   Print("SIGO signal: ",reason);
   if((side>0 && TradingDirection==SIGO_SELL)||(side<0 && TradingDirection==SIGO_BUY))
   { Report("Signal blocked by direction setting"); return; }
   long mode=SymbolInfoInteger(SymbolName,SYMBOL_TRADE_MODE);
   long order_mode=SymbolInfoInteger(SymbolName,SYMBOL_ORDER_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      (side>0 && mode==SYMBOL_TRADE_MODE_SHORTONLY)||(side<0 && mode==SYMBOL_TRADE_MODE_LONGONLY)||
      (order_mode&SYMBOL_ORDER_MARKET)==0 || (order_mode&SYMBOL_ORDER_SL)==0 || (order_mode&SYMBOL_ORDER_TP)==0)
   { Report("Broker symbol does not permit requested market order with SL/TP"); return; }
   double entry=side>0 ? tick.ask:tick.bid;
   double min_stop=(SymbolInfoInteger(SymbolName,SYMBOL_TRADE_STOPS_LEVEL)+1)*point;
   double distance=MathMax(StopLossATRMultiplier*atr,min_stop+(tick.ask-tick.bid));
   double sl=Trades.Price(entry-side*distance,side>0?-1:1);
   double actual_distance=MathAbs(entry-sl);
   double tp=Trades.Price(entry+side*MathMax(actual_distance*TakeProfitRiskMultiplier,min_stop),side>0?1:-1);
   if(sl<=0 || tp<=0) { Report("Invalid stop / target price"); return; }
   ENUM_ORDER_TYPE type=side>0 ? ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double lots=Risk.Size(type,entry,sl,RiskPercent,reason);
   Print("SIGO sizing: ",reason);
   if(lots<=0) { Report(reason); return; }
   // No unprotected fallback if a broker rejects attached stops.
   Trades.Open(side,lots,entry,sl,tp,reason); Report(reason);
}
