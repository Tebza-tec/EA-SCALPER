#ifndef SIGO_RISK_MANAGER
#define SIGO_RISK_MANAGER
string SIGOStatePrefix(long magic)
{
   string identity=AccountInfoString(ACCOUNT_SERVER)+StringFormat("|%I64d|%I64d",AccountInfoInteger(ACCOUNT_LOGIN),magic);
   uint a=2166136261,b=5381;
   for(int i=0;i<StringLen(identity);i++)
   {
      uint c=(uint)StringGetCharacter(identity,i);
      a=(a^c)*16777619; b=b*33+c;
   }
   // Fixed-length key keeps all ticket markers below MT5's 63-character limit.
   return StringFormat("SIGO.%08X%08X.",a,b);
}
class CRiskManager
{
private:
   string m_symbol,m_key;
   long m_magic;
   double m_daily_limit,m_drawdown_limit,m_total_risk,m_cost,m_slip,m_reserve;
   double m_day_equity,m_peak;
   int m_day;
   bool m_latched,m_daily_latched,m_persist,m_storage;
   int DayCode(datetime when)
   { MqlDateTime d; TimeToStruct(when,d); return d.year*10000+d.mon*100+d.day; }
   bool Save(void)
   {
      if(!m_persist) return true;
      bool ok=true;
      if(GlobalVariableSet(m_key+"day",m_day)==0) ok=false;
      if(GlobalVariableSet(m_key+"base",m_day_equity)==0) ok=false;
      if(GlobalVariableSet(m_key+"dailyhalt",m_daily_latched?1:0)==0) ok=false;
      if(GlobalVariableSet(m_key+"peak",m_peak)==0) ok=false;
      if(GlobalVariableSet(m_key+"halt",m_latched?1:0)==0) ok=false;
      GlobalVariablesFlush();
      if(!ok) Print("SIGO: risk state persistence failed; entries blocked");
      return ok;
   }
public:
   bool Init(string symbol,long magic,double daily,double drawdown,double total,double cost,double slip,double reserve)
   {
      m_symbol=symbol; m_magic=magic; m_daily_limit=daily; m_drawdown_limit=drawdown;
      m_total_risk=total; m_cost=cost; m_slip=slip; m_reserve=reserve;
      m_persist=!(bool)MQLInfoInteger(MQL_TESTER);
      m_key=SIGOStatePrefix(magic);
      m_day=DayCode(TimeCurrent()); m_day_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_peak=m_day_equity; m_latched=false; m_daily_latched=false;
      if(m_persist && GlobalVariableCheck(m_key+"peak"))
      {
         m_peak=GlobalVariableGet(m_key+"peak"); m_latched=GlobalVariableGet(m_key+"halt")>0;
         if((int)GlobalVariableGet(m_key+"day")==m_day)
            { m_day_equity=GlobalVariableGet(m_key+"base"); m_daily_latched=GlobalVariableGet(m_key+"dailyhalt")>0; }
      }
      m_storage=Save(); return m_storage;
   }
   void Update(void)
   {
      double equity=AccountInfoDouble(ACCOUNT_EQUITY); bool changed=false;
      int today=DayCode(TimeCurrent());
      if(today!=m_day) { m_day=today; m_day_equity=equity; m_daily_latched=false; changed=true; }
      if(DailyLoss()>=m_daily_limit && !m_daily_latched) { m_daily_latched=true; changed=true; }
      if(equity>m_peak) { m_peak=equity; changed=true; }
      if(m_peak>0 && 100*(m_peak-equity)/m_peak>=m_drawdown_limit && !m_latched)
      { m_latched=true; changed=true; Print("SIGO: overall equity protection latched"); }
      if(changed && !Save()) m_storage=false;
   }
   double Drawdown(void)
   { return m_peak>0 ? MathMax(0,100*(m_peak-AccountInfoDouble(ACCOUNT_EQUITY))/m_peak):0; }
   double DailyLoss(void)
   { return m_day_equity>0 ? MathMax(0,100*(m_day_equity-AccountInfoDouble(ACCOUNT_EQUITY))/m_day_equity):0; }
   bool Breached(void) { return m_latched || m_daily_latched || DailyLoss()>=m_daily_limit; }
   bool Allowed(string &reason)
   {
      if(!m_storage) { reason="Risk state storage unavailable; restart after fixing terminal storage"; return false; }
      if(AccountInfoDouble(ACCOUNT_EQUITY)<=0) { reason="Non-positive equity"; return false; }
      if(m_latched) { reason="Overall drawdown halt latched; manual review required"; return false; }
      if(m_daily_latched || DailyLoss()>=m_daily_limit) { reason="Daily equity loss limit"; return false; }
      return true;
   }
   // Account-wide exposure, including manual positions. Missing stops block new risk.
   double OpenRisk(string &reason)
   {
      double total=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         if(PositionGetTicket(i)==0) { reason="Cannot read account position"; return -1; }
         string sym=PositionGetString(POSITION_SYMBOL);
         double stop=PositionGetDouble(POSITION_SL),vol=PositionGetDouble(POSITION_VOLUME);
         ENUM_ORDER_TYPE type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? ORDER_TYPE_BUY:ORDER_TYPE_SELL;
         MqlTick tick;
         if(stop<=0 || !SymbolInfoTick(sym,tick)) { reason="Account position has no stop / quote"; return -1; }
         double current=type==ORDER_TYPE_BUY ? tick.bid:tick.ask,pnl;
         if(!OrderCalcProfit(type,sym,vol,current,stop+(type==ORDER_TYPE_BUY?-1:1)*m_slip*SymbolInfoDouble(sym,SYMBOL_POINT),pnl)) { reason="Cannot value open position risk"; return -1; }
         total+=MathMax(0,-pnl)+m_cost*vol;
      }
      // Pending orders can fill asynchronously; do not assume they carry no risk.
      if(OrdersTotal()>0) { reason="Account has pending orders; reserved risk unknown"; return -1; }
      return total;
   }
   double Size(ENUM_ORDER_TYPE type,double entry,double stop,double risk_pct,string &reason)
   {
      if(!Allowed(reason)) return 0;
      double equity=AccountInfoDouble(ACCOUNT_EQUITY),used=OpenRisk(reason);
      if(used<0) return 0;
      double budget=MathMin(equity*risk_pct/100,equity*m_total_risk/100-used);
      if(budget<=0) { reason="Total open risk budget exhausted"; return 0; }
      double minlot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN),step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      double maxlot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX),pnl;
      if(minlot<=0 || step<=0 || maxlot<minlot) { reason="Invalid broker volume specifications"; return 0; }
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      double stressed_stop=stop+(type==ORDER_TYPE_BUY ? -1:1)*m_slip*point;
      if(!OrderCalcProfit(type,m_symbol,minlot,entry,stressed_stop,pnl) || pnl>=0)
      { reason="Cannot calculate stop loss in account currency"; return 0; }
      double loss_per_lot=(-pnl/minlot)+m_cost;
      double lots=MathFloor((MathMin(maxlot,budget/loss_per_lot)+1e-12)/step)*step;
      lots=NormalizeDouble(lots,8);
      if(lots<minlot || lots*loss_per_lot>budget+1e-8)
      { reason=StringFormat("Minimum lot %.8f risks %.2f; budget %.2f",minlot,minlot*loss_per_lot,budget); return 0; }
      // Respect directional symbol volume limit, including other strategies.
      double limit=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_LIMIT),directional=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==m_symbol &&
            ((type==ORDER_TYPE_BUY && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)||
             (type==ORDER_TYPE_SELL && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)))
            directional+=PositionGetDouble(POSITION_VOLUME);
      if(limit>0) lots=MathMin(lots,MathFloor(MathMax(0,limit-directional)/step)*step);
      double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*(1-m_reserve/100),margin=0;
      // Linear margin estimate is followed by OrderCheck on the exact request.
      if(!OrderCalcMargin(type,m_symbol,lots,entry,margin)) { reason="Margin calculation failed"; return 0; }
      if(margin>free && margin>0) lots=MathFloor((lots*free/margin)/step)*step;
      lots=NormalizeDouble(lots,8);
      if(lots<minlot || !OrderCalcMargin(type,m_symbol,lots,entry,margin) || margin>free)
      { reason="Minimum lot unaffordable with margin reserve"; return 0; }
      reason=StringFormat("Risk budget %.2f; estimated loss %.2f; lots %.8f",budget,lots*loss_per_lot,lots);
      return lots;
   }
   double DailyRealized(void)
   {
      MqlDateTime d; TimeToStruct(TimeCurrent(),d); d.hour=0; d.min=0; d.sec=0;
      if(!HistorySelect(StructToTime(d),TimeCurrent())) return 0;
      double pnl=0;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong ticket=HistoryDealGetTicket(i);
         ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
         if(type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL)
            pnl+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+
                 HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE);
      }
      return pnl;
   }
};
#endif
