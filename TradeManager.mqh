#ifndef SIGO_TRADE_MANAGER
#define SIGO_TRADE_MANAGER
#include <Trade/Trade.mqh>
#include "RiskManager.mqh"
class CTradeManager
{
private:
   CTrade m_trade;
   string m_symbol,m_key;
   long m_magic;
   ulong m_deviation;
   bool m_hedge,m_persist;
   datetime m_last;
   ulong m_partial_attempts[];
   bool Own(void)
   { return PositionGetString(POSITION_SYMBOL)==m_symbol && PositionGetInteger(POSITION_MAGIC)==m_magic; }
   bool Result(string action)
   {
      uint code=m_trade.ResultRetcode();
      bool ok=(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL);
      PrintFormat("SIGO %s: retcode=%u %s deal=%I64u order=%I64u",action,code,
                  m_trade.ResultRetcodeDescription(),m_trade.ResultDeal(),m_trade.ResultOrder());
      return ok;
   }
   string Marker(ulong identifier) { return m_key+StringFormat("p%I64u",identifier); }
   bool PartialDone(ulong identifier)
   {
      for(int i=0;i<ArraySize(m_partial_attempts);i++) if(m_partial_attempts[i]==identifier) return true;
      if(m_persist && GlobalVariableCheck(Marker(identifier))) return true;
      if(!HistorySelectByPosition(identifier)) return true; // fail closed
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong t=HistoryDealGetTicket(i);
         long entry=HistoryDealGetInteger(t,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) return true;
      }
      return false;
   }
   bool Partial(ulong ticket,double volume)
   {
      if(!PositionSelectByTicket(ticket) || !Own() || volume>=PositionGetDouble(POSITION_VOLUME)) return false;
      ENUM_POSITION_TYPE side=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      MqlTick tick; if(!SymbolInfoTick(m_symbol,tick)) return false;
      // Explicit position ticket closes hedging volume or reduces the sole netting position.
      MqlTradeRequest req={}; MqlTradeResult res={}; MqlTradeCheckResult check={};
      req.action=TRADE_ACTION_DEAL; req.position=ticket; req.symbol=m_symbol;
      req.magic=m_magic; req.volume=volume; req.deviation=m_deviation; req.comment="SIGO partial";
      req.type=side==POSITION_TYPE_BUY ? ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      req.price=side==POSITION_TYPE_BUY ? tick.bid:tick.ask;
      req.type_filling=Filling();
      if(!OrderCheck(req,check)) { PrintFormat("SIGO partial check: %u %s",check.retcode,check.comment); return false; }
      bool sent=OrderSend(req,res);
      PrintFormat("SIGO partial: %u %s",res.retcode,res.comment);
      return sent && (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL);
   }
public:
   ENUM_ORDER_TYPE_FILLING Filling(void)
   {
      long modes=SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);
      if((modes&SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
      if((modes&SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
      if(SymbolInfoInteger(m_symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET) return ORDER_FILLING_RETURN;
      return ORDER_FILLING_FOK; // OrderCheck rejects unsupported broker specifications.
   }
   void Init(string symbol,long magic,ulong deviation)
   {
      m_symbol=symbol; m_magic=magic; m_deviation=deviation; m_last=0; ArrayResize(m_partial_attempts,0);
      m_hedge=(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      m_persist=!(bool)MQLInfoInteger(MQL_TESTER);
      m_key=SIGOStatePrefix(magic);
      m_trade.SetExpertMagicNumber(magic); m_trade.SetDeviationInPoints(deviation);
      m_trade.SetTypeFillingBySymbol(symbol); m_trade.SetAsyncMode(false);
      if(m_persist && GlobalVariableCheck(m_key+"last")) m_last=(datetime)GlobalVariableGet(m_key+"last");
      // Recover last entry from broker history as well as terminal state.
      if(HistorySelect(0,TimeCurrent()))
         for(int i=HistoryDealsTotal()-1;i>=0;i--)
         {
            ulong t=HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(t,DEAL_MAGIC)==magic && HistoryDealGetString(t,DEAL_SYMBOL)==symbol &&
               HistoryDealGetInteger(t,DEAL_ENTRY)==DEAL_ENTRY_IN)
            { m_last=(datetime)MathMax((double)m_last,(double)HistoryDealGetInteger(t,DEAL_TIME)); break; }
         }
   }
   int Count(void)
   {
      int count=0;
      for(int i=PositionsTotal()-1;i>=0;i--) if(PositionGetTicket(i)>0 && Own()) count++;
      return count;
   }
   bool CanEnter(int max_symbol,int max_account,int interval,string &reason)
   {
      if(TimeCurrent()-m_last<interval) { reason="Entry cooldown"; return false; }
      int symbol_count=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==m_symbol) symbol_count++;
      if(PositionsTotal()>=max_account || symbol_count>=max_symbol) { reason="Position cap reached"; return false; }
      if(!m_hedge && PositionSelect(m_symbol)) { reason="Netting symbol already has a position; no merging"; return false; }
      for(int i=OrdersTotal()-1;i>=0;i--)
         if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==m_symbol)
         { reason="Outstanding symbol order"; return false; }
      return true;
   }
   double Price(double value,int direction)
   {
      double tick=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick<=0) return 0;
      double units=value/tick;
      return NormalizeDouble((direction<0 ? MathFloor(units):MathCeil(units))*tick,
                             (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS));
   }
   bool Open(int side,double lots,double entry,double sl,double tp,string &reason)
   {
      MqlTradeRequest req={}; MqlTradeResult res={}; MqlTradeCheckResult check={};
      req.action=TRADE_ACTION_DEAL; req.symbol=m_symbol; req.magic=m_magic;
      req.volume=lots; req.type=side>0 ? ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      req.price=entry; req.sl=sl; req.tp=tp; req.deviation=m_deviation;
      req.type_filling=Filling(); req.comment="SIGO entry";
      ResetLastError();
      if(!OrderCheck(req,check))
      { reason=StringFormat("OrderCheck rejected: %u %s error=%d",check.retcode,check.comment,GetLastError()); return false; }
      // Reserve the interval before submission, including ambiguous transport failures.
      m_last=TimeCurrent();
      if(m_persist)
      {
         if(GlobalVariableSet(m_key+"last",(double)m_last)==0) { reason="Cannot persist submission cooldown"; return false; }
         GlobalVariablesFlush();
      }
      bool sent=OrderSend(req,res);
      reason=StringFormat("OrderSend: %u %s; deal=%I64u order=%I64u price=%.*f",res.retcode,res.comment,
                          res.deal,res.order,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS),res.price);
      Print("SIGO ",reason);
      return sent && (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL);
   }
   void CloseUnprotected(void)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong t=PositionGetTicket(i); if(t==0 || !Own()) continue;
         if(PositionGetDouble(POSITION_SL)>0 && PositionGetDouble(POSITION_TP)>0) continue;
         PrintFormat("SIGO: owned position %I64u lacks SL/TP; requesting protective closure",t);
         m_trade.PositionClose(t,m_deviation); Result("unprotected position close");
      }
   }
   void CloseOwned(void)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong t=PositionGetTicket(i); if(t==0 || !Own()) continue;
         m_trade.PositionClose(t,m_deviation); Result("emergency close");
      }
   }
   void Manage(double atr,bool trailing,double trail_atr,bool breakeven,double be_atr,double be_offset,
               bool partial,double partial_atr,double partial_pct)
   {
      MqlTick tick; if(atr<=0 || !SymbolInfoTick(m_symbol,tick)) return;
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      double min_distance=(MathMax(SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                   SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL))+1)*point;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong t=PositionGetTicket(i); if(t==0 || !Own()) continue;
         ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP),volume=PositionGetDouble(POSITION_VOLUME);
         double price=buy ? tick.bid:tick.ask,profit=(buy?1:-1)*(price-open),next=sl;
         if(breakeven && profit>=be_atr*atr)
         {
            double be=Price(open+(buy?1:-1)*be_offset*point,buy?-1:1);
            if(sl==0 || (buy ? be>next:be<next)) next=be;
         }
         if(trailing && profit>=trail_atr*atr)
         {
            double tr=Price(price+(buy?-1:1)*trail_atr*atr,buy?-1:1);
            if(next==0 || (buy ? tr>next:tr<next)) next=tr;
         }
         if(next>0 && (sl==0 || MathAbs(next-sl)>=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE)) &&
            (buy ? price-next>min_distance:next-price>min_distance) &&
            (tp==0 || MathAbs(tp-price)>min_distance))
         { m_trade.PositionModify(t,next,tp); Result("stop modification"); }
         if(partial && profit>=partial_atr*atr && !PartialDone(id))
         {
            double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP),minlot=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
            if(step<=0) continue;
            double closevol=NormalizeDouble(MathFloor(volume*partial_pct/100/step)*step,8);
            if(closevol>=minlot && volume-closevol>=minlot)
            {
               // Reserve before sending: ambiguous responses must never cause duplicate reductions.
               if(m_persist)
               {
                  if(GlobalVariableSet(Marker(id),1)==0) { Print("SIGO: cannot persist partial reservation"); continue; }
                  GlobalVariablesFlush();
               }
               int n=ArraySize(m_partial_attempts); ArrayResize(m_partial_attempts,n+1); m_partial_attempts[n]=id;
               Partial(t,closevol);
            }
         }
      }
   }
   bool LossPause(int limit,int minutes,string &reason)
   {
      if(limit<=0) return false;
      if(!HistorySelect(0,TimeCurrent())) { reason="Cannot read history for loss pause"; return true; }
      int losses=0; datetime last_close=0;
      // Count completed position lifecycles, combining entries, partial exits, fees and swaps.
      ulong ids[];
      for(int i=HistoryDealsTotal()-1;i>=0;i--)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=m_magic || HistoryDealGetString(deal,DEAL_SYMBOL)!=m_symbol) continue;
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
         ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         bool seen=false,active=false;
         for(int j=0;j<ArraySize(ids);j++) if(ids[j]==id) seen=true;
         if(seen) continue;
         int n=ArraySize(ids); ArrayResize(ids,n+1); ids[n]=id;
         for(int j=PositionsTotal()-1;j>=0;j--)
            if(PositionGetTicket(j)>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) active=true;
         if(active) continue;
         double pnl=0;
         for(int j=0;j<HistoryDealsTotal();j++)
         {
            ulong h=HistoryDealGetTicket(j);
            if((ulong)HistoryDealGetInteger(h,DEAL_POSITION_ID)==id)
               pnl+=HistoryDealGetDouble(h,DEAL_PROFIT)+HistoryDealGetDouble(h,DEAL_COMMISSION)+
                    HistoryDealGetDouble(h,DEAL_SWAP)+HistoryDealGetDouble(h,DEAL_FEE);
         }
         if(last_close==0) last_close=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         if(pnl>=0) break;
         losses++;
         if(losses>=limit)
         {
            if(TimeCurrent()<last_close+minutes*60) { reason="Pause after consecutive losing positions"; return true; }
            break;
         }
      }
      return false;
   }
};
#endif
