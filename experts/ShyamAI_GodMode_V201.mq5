//+------------------------------------------------------------------+
//|                                ShyamAI_Pro_MA_Cross_v2.mq5        |
//|                                     Professional Edition         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Shyam AI Ltd."
#property link      "https://www.shyam.ai"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

input group "--- Strategy Parameters ---"
input int      InpFastMAPeriod   = 10;
input int      InpSlowMAPeriod   = 30;
input ENUM_MA_METHOD InpMAMethod = MODE_EMA;
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE;

input group "--- Risk Management ---"
input double   InpRiskPercent    = 1.5;
input double   InpRiskRewardRatio = 2.0;
input int      InpStopLossPoints = 50;
input int      InpTrailingStop   = 25;
input double   InpMaxDailyDD     = 3.0;
input ulong    InpMagicNumber    = 123456;
input int      InpDeviation      = 10;

CTrade         trade;
int            fastMAHandle, slowMAHandle;
datetime       lastBarTime;
double         initialDailyEquity;
datetime       lastResetDate;

int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviation);
   
   fastMAHandle = iMA(_Symbol, _Period, InpFastMAPeriod, 0, InpMAMethod, InpMAPrice);
   slowMAHandle = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, InpMAMethod, InpMAPrice);
   
   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE) return(INIT_FAILED);
   
   initialDailyEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastResetDate = TimeCurrent();
   return(INIT_SUCCEEDED);
}

void OnTick() {
   if(IsDailyDrawdownExceeded()) return;
   ManageTrailingStop();
   
   if(!IsNewBar()) return;

   // Check if position exists
   if(PositionSelectByMagic(InpMagicNumber)) return;

   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, true); ArraySetAsSeries(slowMA, true);
   
   if(CopyBuffer(fastMAHandle, 0, 1, 2, fastMA) < 2 || CopyBuffer(slowMAHandle, 0, 1, 2, slowMA) < 2) return;

   if(fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0]) ExecuteTrade(ORDER_TYPE_BUY);
   else if(fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0]) ExecuteTrade(ORDER_TYPE_SELL);
}

//--- Helper: Position Check
bool PositionSelectByMagic(ulong magic) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetInteger(POSITION_MAGIC) == (long)magic && PositionGetString(POSITION_SYMBOL) == _Symbol) return true;
      }
   }
   return false;
}

//--- Helper: Execute Trade with Normalization
void ExecuteTrade(ENUM_ORDER_TYPE type) {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPoints = InpStopLossPoints * _Point;
   double tpPoints = slPoints * InpRiskRewardRatio;
   
   double sl = (type == ORDER_TYPE_BUY) ? (price - slPoints) : (price + slPoints);
   double tp = (type == ORDER_TYPE_BUY) ? (price + tpPoints) : (price - tpPoints);
   
   double lot = CalculateLotSize(InpStopLossPoints);
   
   if(type == ORDER_TYPE_BUY) trade.Buy(lot, _Symbol, price, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "ShyamAI Buy");
   else trade.Sell(lot, _Symbol, price, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "ShyamAI Sell");
}

double CalculateLotSize(int slPoints) {
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot = NormalizeDouble(riskAmount / (slPoints * tickValue), 2);
   return MathFloor(lot / lotStep) * lotStep;
}

bool IsDailyDrawdownExceeded() {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(((initialDailyEquity - currentEquity) / initialDailyEquity) * 100.0 >= InpMaxDailyDD) return true;
   return false;
}

bool IsNewBar() {
   datetime currentBar = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(currentBar != lastBarTime) { lastBarTime = currentBar; return true; }
   return false;
}
