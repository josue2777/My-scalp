//+------------------------------------------------------------------+
//|                                                AsianRangeBot.mq5 |
//|                                  Copyright 2023, User            |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, User"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input group "--- Paramètres de Session Asiatique ---"
input int      StartHour   = 1;      // Heure de début (H)
input int      StartMinute = 45;     // Minute de début (M)
input int      EndHour     = 2;      // Heure de fin (H)
input int      EndMinute   = 15;     // Minute de fin (M)

input group "--- Gestion des Risques & TP/SL ---"
input double   TargetProfitUSD = 18.0; // TP en $ pour 0.01 lot
input double   StopLossUSD     = 14.0; // SL en $ pour 0.01 lot
input double   RiskPercent     = 1.0;  // Risque en % du capital
input int      MinTradesPerZone = 1;   // Nombre minimum de trades par zone
input int      MaxTradesPerZone = 1;   // Nombre maximum de trades par zone

//--- Global variables
CTrade trade;
double zoneHigh = 0;
double zoneLow = 0;
bool   zoneActive = false;
int    tradesOpenedThisZone = 0;
datetime lastZoneDate = 0;
datetime lastCheckedBar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "ASIAN_ZONE_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   // Reset zone at the start of a new day or before session
   datetime currentDate = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
   if(currentDate > lastZoneDate)
   {
      zoneActive = false;
      zoneHigh = 0;
      zoneLow = 0;
      tradesOpenedThisZone = 0;
      lastCheckedBar = 0;
      ObjectsDeleteAll(0, "ASIAN_ZONE_");
      lastZoneDate = currentDate;
   }

   // Identify range after session end
   if(!zoneActive && tradesOpenedThisZone == 0 && (dt.hour > EndHour || (dt.hour == EndHour && dt.min >= EndMinute)))
   {
      IdentifyRange(currentDate);
   }

   // Breakout detection
   if(zoneActive && tradesOpenedThisZone < MaxTradesPerZone)
   {
      // Check if we should wait for current trades to close
      if(PositionsTotal() == 0)
      {
         CheckBreakout();
      }
   }
}

//+------------------------------------------------------------------+
//| Identify Asian Session Range                                     |
//+------------------------------------------------------------------+
void IdentifyRange(datetime dayStart)
{
   datetime start = dayStart + StartHour * 3600 + StartMinute * 60;
   datetime end = dayStart + EndHour * 3600 + EndMinute * 60;

   int startBar = iBarShift(_Symbol, PERIOD_M1, start);
   int endBar = iBarShift(_Symbol, PERIOD_M1, end);

   if(startBar < 0 || endBar < 0) return;

   int count = startBar - endBar + 1;
   if(count <= 0) return;

   double highs[], lows[];
   if(CopyHigh(_Symbol, PERIOD_M1, endBar, count, highs) <= 0) return;
   if(CopyLow(_Symbol, PERIOD_M1, endBar, count, lows) <= 0) return;

   zoneHigh = highs[ArrayMaximum(highs)];
   zoneLow = lows[ArrayMinimum(lows)];
   zoneActive = true;

   DrawZone();
}

//+------------------------------------------------------------------+
//| Draw Visual Zone                                                 |
//+------------------------------------------------------------------+
void DrawZone()
{
   ObjectCreate(0, "ASIAN_ZONE_HIGH", OBJ_HLINE, 0, 0, zoneHigh);
   ObjectSetInteger(0, "ASIAN_ZONE_HIGH", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, "ASIAN_ZONE_HIGH", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "ASIAN_ZONE_HIGH", OBJPROP_WIDTH, 2);

   ObjectCreate(0, "ASIAN_ZONE_LOW", OBJ_HLINE, 0, 0, zoneLow);
   ObjectSetInteger(0, "ASIAN_ZONE_LOW", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "ASIAN_ZONE_LOW", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "ASIAN_ZONE_LOW", OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Breakout Detection Logic                                         |
//+------------------------------------------------------------------+
void CheckBreakout()
{
   datetime time[];
   if(CopyTime(_Symbol, PERIOD_M15, 1, 1, time) <= 0) return;

   if(time[0] <= lastCheckedBar) return;

   double close[];
   if(CopyClose(_Symbol, PERIOD_M15, 1, 1, close) <= 0) return;

   lastCheckedBar = time[0];

   if(close[0] > zoneHigh)
   {
      ExecuteTrade(ORDER_TYPE_BUY);
   }
   else if(close[0] < zoneLow)
   {
      ExecuteTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Execute Trade with Calculated Lot and TP/SL                      |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);

   // Lot calculation: 1% risk based on $14 per 0.01 lot ratio
   // So RiskAmount / 1400.0 = Lot (since 0.01 / 14 = 1 / 1400)
   double lot = (riskAmount / StopLossUSD) * 0.01;

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Calculate TP and SL distances in price points
   // TP = 18$ for 0.01 lot, SL = 14$ for 0.01 lot
   double tpDist = (TargetProfitUSD * tickSize) / (tickValue * 0.01);
   double slDist = (StopLossUSD * tickSize) / (tickValue * 0.01);

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   double tpPrice = (type == ORDER_TYPE_BUY) ? price + tpDist : price - tpDist;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   slPrice = NormalizeDouble(slPrice, digits);
   tpPrice = NormalizeDouble(tpPrice, digits);

   // Open trades (Min to Max)
   int tradesToOpen = MinTradesPerZone;
   if(tradesToOpen < 1) tradesToOpen = 1;

   for(int i=0; i<tradesToOpen && tradesOpenedThisZone < MaxTradesPerZone; i++)
   {
      if(trade.PositionOpen(_Symbol, type, lot, price, slPrice, tpPrice))
      {
         tradesOpenedThisZone++;
      }
      else
      {
         Print("Error opening trade: ", trade.ResultRetcodeDescription());
      }
   }

   if(tradesOpenedThisZone >= MaxTradesPerZone)
   {
      zoneActive = false; // Zone is annulled after max trades
      ObjectsSetInteger(0, "ASIAN_ZONE_HIGH", OBJPROP_COLOR, clrGray);
      ObjectsSetInteger(0, "ASIAN_ZONE_LOW", OBJPROP_COLOR, clrGray);
   }
}
