#ifndef SIGO_SIGNAL_ENGINE
#define SIGO_SIGNAL_ENGINE
class CSignalEngine
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int m_fast,m_slow,m_rsi,m_atr,m_cf,m_cs,m_tf_fast,m_tf_slow;
   int m_lookback;
   double m_zone,m_min_atr,m_max_atr;
   bool Value(const int handle,const int shift,double &value)
   {
      double b[1];
      if(handle==INVALID_HANDLE || CopyBuffer(handle,0,shift,1,b)!=1) return false;
      value=b[0];
      return MathIsValidNumber(value) && value!=EMPTY_VALUE;
   }
public:
   CSignalEngine(void)
   {
      m_fast=m_slow=m_rsi=m_atr=m_cf=m_cs=m_tf_fast=m_tf_slow=INVALID_HANDLE;
   }
   bool Init(string symbol,ENUM_TIMEFRAMES tf,ENUM_TIMEFRAMES confirm,ENUM_TIMEFRAMES trend,
             int fast,int slow,int rsi,int atr,int lookback,double zone,double min_atr,double max_atr)
   {
      m_symbol=symbol; m_tf=tf; m_lookback=lookback; m_zone=zone;
      m_min_atr=min_atr; m_max_atr=max_atr;
      m_fast=iMA(symbol,tf,fast,0,MODE_EMA,PRICE_CLOSE);
      m_slow=iMA(symbol,tf,slow,0,MODE_EMA,PRICE_CLOSE);
      m_rsi=iRSI(symbol,tf,rsi,PRICE_CLOSE); m_atr=iATR(symbol,tf,atr);
      m_cf=iMA(symbol,confirm,fast,0,MODE_EMA,PRICE_CLOSE);
      m_cs=iMA(symbol,confirm,slow,0,MODE_EMA,PRICE_CLOSE);
      m_tf_fast=iMA(symbol,trend,fast,0,MODE_EMA,PRICE_CLOSE);
      m_tf_slow=iMA(symbol,trend,slow,0,MODE_EMA,PRICE_CLOSE);
      return m_fast!=INVALID_HANDLE && m_slow!=INVALID_HANDLE && m_rsi!=INVALID_HANDLE &&
             m_atr!=INVALID_HANDLE && m_cf!=INVALID_HANDLE && m_cs!=INVALID_HANDLE &&
             m_tf_fast!=INVALID_HANDLE && m_tf_slow!=INVALID_HANDLE;
   }
   void Release(void)
   {
      if(m_fast!=INVALID_HANDLE) IndicatorRelease(m_fast);
      if(m_slow!=INVALID_HANDLE) IndicatorRelease(m_slow);
      if(m_rsi!=INVALID_HANDLE) IndicatorRelease(m_rsi);
      if(m_atr!=INVALID_HANDLE) IndicatorRelease(m_atr);
      if(m_cf!=INVALID_HANDLE) IndicatorRelease(m_cf);
      if(m_cs!=INVALID_HANDLE) IndicatorRelease(m_cs);
      if(m_tf_fast!=INVALID_HANDLE) IndicatorRelease(m_tf_fast);
      if(m_tf_slow!=INVALID_HANDLE) IndicatorRelease(m_tf_slow);
   }
   // Closed bars only. Zones exclude the signal candle and its predecessor.
   int Evaluate(double &atr,string &trend,string &reason)
   {
      double f,s,r,cf,cs,tf,ts;
      trend="Waiting";
      if(!Value(m_fast,1,f)||!Value(m_slow,1,s)||!Value(m_rsi,1,r)||!Value(m_atr,1,atr)||
         !Value(m_cf,1,cf)||!Value(m_cs,1,cs)||!Value(m_tf_fast,1,tf)||!Value(m_tf_slow,1,ts))
      { reason="Indicators warming up / data unavailable"; return 0; }
      trend=(tf>ts ? "Bullish" : (tf<ts ? "Bearish" : "Neutral"));
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(atr<=0 || atr/point<m_min_atr || (m_max_atr>0 && atr/point>m_max_atr))
      { reason="ATR outside configured range"; return 0; }
      MqlRates bars[]; ArraySetAsSeries(bars,true);
      int need=m_lookback+2;
      if(CopyRates(m_symbol,m_tf,1,need,bars)!=need)
      { reason="Insufficient candle history"; return 0; }
      double support=bars[2].low,resistance=bars[2].high;
      for(int i=2;i<need;i++) { support=MathMin(support,bars[i].low); resistance=MathMax(resistance,bars[i].high); }
      bool bull=bars[0].close>bars[0].open && bars[0].close>bars[1].close;
      bool bear=bars[0].close<bars[0].open && bars[0].close<bars[1].close;
      // Pullback bounce from a zone; require room to the opposing zone.
      bool buy_zone=bars[0].low<=support+m_zone*atr && bars[0].close>support && resistance-bars[0].close>=atr;
      bool sell_zone=bars[0].high>=resistance-m_zone*atr && bars[0].close<resistance && bars[0].close-support>=atr;
      if(tf>ts && cf>cs && f>s && bars[0].close>f && r>=50 && r<=70 && bull && buy_zone)
      { reason="BUY: EMA alignment, RSI 50–70, support bounce, bullish candle"; return 1; }
      if(tf<ts && cf<cs && f<s && bars[0].close<f && r>=30 && r<=50 && bear && sell_zone)
      { reason="SELL: EMA alignment, RSI 30–50, resistance rejection, bearish candle"; return -1; }
      reason=StringFormat("No alignment: RSI %.1f; zone BUY=%s SELL=%s",r,buy_zone?"yes":"no",sell_zone?"yes":"no");
      return 0;
   }
   string CurrentTrend(void)
   {
      double fast,slow;
      if(!Value(m_tf_fast,1,fast) || !Value(m_tf_slow,1,slow)) return "Waiting";
      return fast>slow ? "Bullish":(fast<slow ? "Bearish":"Neutral");
   }
   bool ATR(double &value) { return Value(m_atr,1,value) && value>0; }
};
#endif
