#ifndef SIGO_DASHBOARD
#define SIGO_DASHBOARD
class CDashboard
{
private:
   string m_prefix;
   bool m_enabled;
public:
   void Init(bool enabled) { m_enabled=enabled; m_prefix="SIGO_UI_"; }
   void Destroy(void) { if(m_prefix!="") ObjectsDeleteAll(0,m_prefix); }
   void Draw(string status,string symbol,string trend,string session,double spread,double risk,
             double dd,double daily,int owned)
   {
      if(!m_enabled) return;
      string bg=m_prefix+"BG";
      if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,12); ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,20);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,560); ObjectSetInteger(0,bg,OBJPROP_YSIZE,290);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'20,20,26'); ObjectSetInteger(0,bg,OBJPROP_COLOR,C'233,30,99');
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      string lines[12];
      lines[0]="SIGO SCALPER | "+symbol;
      lines[1]="Status: "+StringSubstr(status,0,70);
      lines[2]=StringFormat("Balance: %.2f | Equity: %.2f %s",AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),AccountInfoString(ACCOUNT_CURRENCY));
      lines[3]=StringFormat("Floating P/L (account): %.2f",AccountInfoDouble(ACCOUNT_PROFIT));
      lines[4]=StringFormat("Daily realized P/L (account): %.2f",daily);
      lines[5]=StringFormat("Open trades: %d owned | %d account",owned,PositionsTotal());
      lines[6]=StringFormat("Spread: %.1f points",spread);
      lines[7]="Trend: "+trend;
      lines[8]="Session: "+session+" (broker time)";
      lines[9]=StringFormat("Risk per entry: %.2f%%",risk);
      lines[10]=StringFormat("Equity peak drawdown: %.2f%%",dd);
      lines[11]="Native MT5 orders | Monitor via the same account on mobile";
      for(int i=0;i<12;i++)
      {
         string name=m_prefix+IntegerToString(i);
         if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_XDISTANCE,25); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,30+i*22);
         ObjectSetInteger(0,name,OBJPROP_COLOR,i==0?C'233,30,99':clrWhite);
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE,i==0?12:10);
         ObjectSetString(0,name,OBJPROP_FONT,"Consolas"); ObjectSetString(0,name,OBJPROP_TEXT,lines[i]);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      }
      ChartRedraw();
   }
};
#endif
