//+------------------------------------------------------------------+
//|                                           PrecisionTrendBot.mq5  |
//|                                  Copyright 2024, GOAT TRADING    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, GOAT TRADING"
#property link      "https://www.mql5.com"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Enums
enum LotModeEnum { FIXED_LOT, AUTO_RISK };
enum TPSLModeEnum { PRICE_LEVEL, PIPS };
enum MA_Type { SMA=1, EMA=2, WMA=3, Hull=4, VWMA=5, SMMA=6, TEMA=7, T3=8 };

//--- Input Parameters
input bool Bot_Active = true;            // Bot Active (True=On, False=Off & Close Trades)

input group "--- Gestion des lots ---"
input LotModeEnum LotMode = AUTO_RISK;    // Mode de lot
input double Risk_Percent = 2.0;         // % du capital risqué
input double Fixed_Lot = 0.01;           // Lot fixe si FIXED_LOT

input group "--- Ouverture des ordres ---"
input int Buy_Count = 1;                 // Nombre de BUY à ouvrir
input int Sell_Count = 1;                // Nombre de SELL à ouvrir
input bool Execute_Orders = true;        // Activer l'ouverture automatique

input group "--- Telegram Settings ---"
input string Telegram_Token = "";        // Telegram Bot Token
input long Telegram_ChatID = 0;          // Telegram Chat ID
input int Telegram_Polling_Sec = 3;      // Intervalle de lecture (sec)

input group "--- TP / SL Global ---"
input TPSLModeEnum TP_SL_Mode = PRICE_LEVEL;
input double Global_TP_Buy = 0.0;
input double Global_SL_Buy = 0.0;
input double Global_TP_Sell = 0.0;
input double Global_SL_Sell = 0.0;

input group "--- Precision Trend Settings ---"
input int Primary_MA_Period = 20;        // Primary MA Period
input MA_Type Primary_MA_Algo = SMA;     // Primary MA Type
input int Secondary_MA_Period = 50;      // Secondary MA Period
input MA_Type Secondary_MA_Algo = SMA;   // Secondary MA Type
input double T3_Factor = 0.7;            // Tilson T3 Volume Factor
input bool Use_EMA_Filter = true;        // Enable 200 EMA Trend Filter
input int Filter_EMA_Period = 200;       // Filter EMA Period
input int Trend_Smoothness = 4;          // Trend Shift detection bars

//--- Global Variables
int lastBuyCount = 0;
int lastSellCount = 0;
long last_telegram_update_id = 0;
bool is_first_polling = true;
string telegram_status = "READY";
datetime last_signal_time = 0;
string UI_PREFIX = "PTB_UI_";

//--- Indicator handles
int handle_ema200 = INVALID_HANDLE;

//--- Modifiable Global States
long ext_Telegram_ChatID;
bool ext_Bot_Active;
double ext_Global_TP_Buy, ext_Global_SL_Buy;
double ext_Global_TP_Sell, ext_Global_SL_Sell;
double ext_Target_Profit = 0;
double ext_Target_Loss = 0;

//+------------------------------------------------------------------+
//| Moving Average Calculation Logic (Pine Script Translation)       |
//+------------------------------------------------------------------+
double CalculateMA(MA_Type type, int period, int shift, double t3_vfac = 0.7)
{
   int lookback = period * 5 + 100;
   double price[];
   ArraySetAsSeries(price, true);
   if(CopyClose(_Symbol, PERIOD_M15, 0, lookback + shift, price) < period + shift) return 0;

   switch(type)
   {
      case SMA: return iSMA_Iterative(price, period, shift);
      case EMA: return iEMA_Iterative(price, period, shift);
      case WMA: return iWMA_Iterative(price, period, shift);
      case Hull: return iHullMA_Iterative(price, period, shift);
      case VWMA: return iVWMA_M15(period, shift);
      case SMMA: return iSMMA_Iterative(price, period, shift);
      case TEMA: return iTEMA_Iterative(price, period, shift);
      case T3: return iT3_Iterative(price, period, shift, t3_vfac);
      default: return iSMA_Iterative(price, period, shift);
   }
}

double iSMA_Iterative(const double &src[], int p, int s)
{
   double sum = 0;
   for(int i=0; i<p; i++) sum += src[s+i];
   return sum / p;
}

double iWMA_Iterative(const double &src[], int p, int s)
{
   double sum = 0, wsum = 0;
   for(int i=0; i<p; i++) { double w = p - i; sum += src[s+i] * w; wsum += w; }
   return sum / wsum;
}

double iEMA_Iterative(const double &src[], int p, int s)
{
   double alpha = 2.0 / (p + 1.0);
   double res = src[ArraySize(src)-1];
   for(int i=ArraySize(src)-2; i>=s; i--) res = alpha * src[i] + (1.0 - alpha) * res;
   return res;
}

double iSMMA_Iterative(const double &src[], int p, int s)
{
   double res = 0;
   int size = ArraySize(src);
   for(int i=size-p; i<size; i++) res += src[i];
   res /= p;
   for(int i=size-p-1; i>=s; i--) res = (res * (p-1) + src[i]) / p;
   return res;
}

double iHullMA_Iterative(const double &src[], int p, int s)
{
   int half = p / 2;
   int sqr = (int)MathRound(MathSqrt(p));
   double diff[]; ArrayResize(diff, ArraySize(src));
   for(int i=0; i<ArraySize(src) - p; i++)
   {
      double wma_half = iWMA_Iterative(src, half, i);
      double wma_full = iWMA_Iterative(src, p, i);
      diff[i] = 2.0 * wma_half - wma_full;
   }
   return iWMA_Iterative(diff, sqr, s);
}

double iTEMA_Iterative(const double &src[], int p, int s)
{
   double alpha = 2.0 / (p + 1.0);
   int n = ArraySize(src);
   double e1[], e2[], e3[];
   ArrayResize(e1, n); ArrayResize(e2, n); ArrayResize(e3, n);

   double last = src[n-1];
   for(int i=n-1; i>=0; i--) { e1[i] = alpha * src[i] + (1.0 - alpha) * last; last = e1[i]; }
   last = e1[n-1];
   for(int i=n-1; i>=0; i--) { e2[i] = alpha * e1[i] + (1.0 - alpha) * last; last = e2[i]; }
   last = e2[n-1];
   for(int i=n-1; i>=0; i--) { e3[i] = alpha * e2[i] + (1.0 - alpha) * last; last = e3[i]; }

   return 3.0 * (e1[s] - e2[s]) + e3[s];
}

void iT3_GD_Array(const double &input[], double &output[], int p, double factor)
{
   double alpha = 2.0 / (p + 1.0);
   int n = ArraySize(input);
   double e1[]; ArrayResize(e1, n);
   double last = input[n-1];
   for(int i=n-1; i>=0; i--) { e1[i] = alpha * input[i] + (1.0 - alpha) * last; last = e1[i]; }
   last = e1[n-1];
   for(int i=n-1; i>=0; i--) {
      double e2 = alpha * e1[i] + (1.0 - alpha) * last;
      output[i] = e1[i] * (1.0 + factor) - e2 * factor;
      last = e2;
   }
}

double iT3_Iterative(const double &src[], int p, int s, double factor)
{
   int n = ArraySize(src);
   double o1[], o2[], o3[];
   ArrayResize(o1, n); ArrayResize(o2, n); ArrayResize(o3, n);
   iT3_GD_Array(src, o1, p, factor);
   iT3_GD_Array(o1, o2, p, factor);
   iT3_GD_Array(o2, o3, p, factor);
   return o3[s];
}

double iVWMA_M15(int p, int s)
{
   double c[], v[];
   if(CopyClose(_Symbol, PERIOD_M15, s, p, c) < p || CopyTickVolume(_Symbol, PERIOD_M15, s, p, v) < p) return 0;
   double spv = 0, sv = 0;
   for(int i=0; i<p; i++) { spv += c[i] * v[i]; sv += v[i]; }
   return (sv != 0) ? spv / sv : 0;
}

//+------------------------------------------------------------------+
//| Core Trade Management                                            |
//+------------------------------------------------------------------+
bool OpenOrder(ENUM_ORDER_TYPE type)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   double lot = CalculateLot();
   double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   double sl = (type == ORDER_TYPE_BUY) ? ext_Global_SL_Buy : ext_Global_SL_Sell;
   double tp = (type == ORDER_TYPE_BUY) ? ext_Global_TP_Buy : ext_Global_TP_Sell;
   trade.SetTypeFillingBySymbol(_Symbol);
   return (type == ORDER_TYPE_BUY) ? trade.Buy(lot, _Symbol, price, sl, tp, "PRECISION SAR") : trade.Sell(lot, _Symbol, price, sl, tp, "PRECISION SAR");
}

void ClosePositions(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_TYPE) == type)
         trade.PositionClose(t);
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(t);
   }
}

double CalculateLot()
{
   if(LotMode == FIXED_LOT) return Fixed_Lot;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lot = 0.01;

   if(balance >= 2 && balance <= 1000) lot = 0.01;
   else if(balance > 1000 && balance <= 5000) lot = 0.1;
   else if(balance > 5000 && balance <= 13000) lot = 0.2;
   else if(balance > 13000 && balance <= 50000) lot = 0.3;
   else if(balance > 50000 && balance <= 150000) lot = 0.50;
   else if(balance > 150000 && balance <= 350000) lot = 1.00;
   else if(balance > 350000 && balance <= 750000) lot = 3.00;
   else if(balance > 750000) lot = 3.00;

   // Respect broker constraints
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Telegram Helpers                                                 |
//+------------------------------------------------------------------+
void SendTelegramMessage(string msg)
{
   if(Telegram_Token == "" || ext_Telegram_ChatID == 0) return;
   string url = "https://api.telegram.org/bot" + Telegram_Token + "/sendMessage";
   StringReplace(msg, " ", "%20"); StringReplace(msg, "\n", "%0A");
   string payload = "chat_id=" + IntegerToString(ext_Telegram_ChatID) + "&text=" + msg;
   char data[], res[]; string head = "Content-Type: application/x-www-form-urlencoded\r\n";
   int len = StringToCharArray(payload, data); if(len > 0) ArrayResize(data, len - 1);
   WebRequest("POST", url, head, 5000, data, res, head);
}

void FetchTelegramUpdates()
{
   if(Telegram_Token == "") return;
   string url = "https://api.telegram.org/bot" + Telegram_Token + "/getUpdates?offset=" + IntegerToString(last_telegram_update_id + 1) + "&limit=10&timeout=2";
   char data[], res[]; string head;
   if(WebRequest("GET", url, NULL, 5000, data, res, head) == 200)
   {
      telegram_status = "CONNECTED";
      string resp = CharArrayToString(res);
      int pos = StringFind(resp, "\"update_id\"");
      while(pos != -1)
      {
         last_telegram_update_id = StringToInteger(StringExtract(resp, "\"update_id\"", pos));
         long cid = StringToInteger(StringExtract(resp, "\"id\"", StringFind(resp, "\"chat\"", pos)));
         if(ext_Telegram_ChatID == 0) ext_Telegram_ChatID = cid;
         string txt = StringExtract(resp, "\"text\"", pos);
         if(!is_first_polling && txt != "") ProcessTelegramCommand(txt);
         pos = StringFind(resp, "\"update_id\"", pos + 10);
      }
      is_first_polling = false;
   }
}

string StringExtract(string src, string key, int start = 0)
{
   int p = StringFind(src, key, start); if(p == -1) return "";
   int s = p + StringLen(key);
   while(s < StringLen(src) && (StringSubstr(src, s, 1) == ":" || StringSubstr(src, s, 1) == " " || StringSubstr(src, s, 1) == "\"")) s++;
   int e = s;
   if(StringFind(src, "\"", p + StringLen(key)) != -1) e = StringFind(src, "\"", s);
   else { e = StringFind(src, ",", s); if(e == -1 || StringFind(src, "}", s) < e) e = StringFind(src, "}", s); }
   return (e == -1) ? StringSubstr(src, s) : StringSubstr(src, s, e - s);
}

void ProcessTelegramCommand(string text)
{
   StringToUpper(text);
   if(text == "HELP") SendTelegramMessage("Commands: ON, OFF, CLOSE, ANALYSE");
   else if(text == "ON") { ext_Bot_Active = true; SendTelegramMessage("Bot ON"); }
   else if(text == "OFF") { ext_Bot_Active = false; CloseAllPositions(); SendTelegramMessage("Bot OFF & Closed"); }
   else if(text == "CLOSE") { CloseAllPositions(); SendTelegramMessage("All Closed"); }
   else if(text == "ANALYSE") SendTelegramMessage(GetMarketAnalysis());
}

string GetMarketAnalysis()
{
   double p = CalculateMA(Primary_MA_Algo, Primary_MA_Period, 0, T3_Factor);
   double s = CalculateMA(Secondary_MA_Algo, Secondary_MA_Period, 0, T3_Factor);
   return "Symbol: " + _Symbol + "\nPrimary MA: " + DoubleToString(p, 5) + "\nSecondary MA: " + DoubleToString(s, 5);
}

//+------------------------------------------------------------------+
//| Expert Events                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   ext_Telegram_ChatID = Telegram_ChatID; ext_Bot_Active = Bot_Active;
   ext_Global_TP_Buy = Global_TP_Buy; ext_Global_SL_Buy = Global_SL_Buy;
   ext_Global_TP_Sell = Global_TP_Sell; ext_Global_SL_Sell = Global_SL_Sell;
   handle_ema200 = iMA(_Symbol, PERIOD_M15, Filter_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   EventSetTimer(Telegram_Polling_Sec);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, UI_PREFIX); IndicatorRelease(handle_ema200); }

void OnTimer() { FetchTelegramUpdates(); UpdateDashboard(); }

int GetPrecisionSignal()
{
   double p0 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, 0, T3_Factor);
   double p1 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, 1, T3_Factor);
   double ps = CalculateMA(Primary_MA_Algo, Primary_MA_Period, Trend_Smoothness, T3_Factor);
   double ps1 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, Trend_Smoothness + 1, T3_Factor);
   double s0 = CalculateMA(Secondary_MA_Algo, Secondary_MA_Period, 0, T3_Factor);

   double ema200[];
   if(CopyBuffer(handle_ema200, 0, 0, 1, ema200) <= 0) return 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool cBull = p0 >= ps, cBear = p0 < ps, pBull = p1 >= ps1, pBear = p1 < ps1;

   if(cBull && pBear && s0 > p0 && (!Use_EMA_Filter || price > ema200[0])) return 1;
   if(cBear && pBull && s0 < p0 && (!Use_EMA_Filter || price < ema200[0])) return -1;

   return 0;
}

void OnTick()
{
   if(!ext_Bot_Active) { if(PositionsTotal() > 0) CloseAllPositions(); return; }
   CheckTargets();

   int signal = GetPrecisionSignal();
   datetime current_bar = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M15, SERIES_LASTBAR_DATE);

   if(current_bar > last_signal_time)
   {
      if(signal == 1)
      {
         ClosePositions(POSITION_TYPE_SELL);
         if(PositionCount(POSITION_TYPE_BUY) == 0) OpenOrder(ORDER_TYPE_BUY);
         last_signal_time = current_bar;
         SendTelegramMessage("🚀 Precision Buy on M15");
      }
      else if(signal == -1)
      {
         ClosePositions(POSITION_TYPE_BUY);
         if(PositionCount(POSITION_TYPE_SELL) == 0) OpenOrder(ORDER_TYPE_SELL);
         last_signal_time = current_bar;
         SendTelegramMessage("🔻 Precision Sell on M15");
      }
   }
}

int PositionCount(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_TYPE) == type) count++;
   return count;
}

void UpdateDashboard()
{
   int b = PositionCount(POSITION_TYPE_BUY), s = PositionCount(POSITION_TYPE_SELL);
   CreateLabel("T", "PRECISION TREND SAR", 10, 10, clrAqua, CORNER_RIGHT_UPPER);
   CreateLabel("S", "Trades: B["+IntegerToString(b)+"] S["+IntegerToString(s)+"]", 10, 30, clrWhite, CORNER_RIGHT_UPPER);
   CreateLabel("P", "Profit: " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2), 10, 50, (AccountInfoDouble(ACCOUNT_PROFIT)>=0?clrLime:clrRed), CORNER_RIGHT_UPPER);
}

void CreateLabel(string name, string txt, int x, int y, color clr, ENUM_BASE_CORNER corner)
{
   string n = UI_PREFIX + name; if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, n, OBJPROP_TEXT, txt); ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y); ObjectSetInteger(0, n, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 10);
}

void CheckTargets()
{
   double p = AccountInfoDouble(ACCOUNT_PROFIT);
   if(ext_Target_Profit > 0 && p >= ext_Target_Profit) { CloseAllPositions(); ext_Target_Profit = 0; }
   if(ext_Target_Loss > 0 && p <= -ext_Target_Loss) { CloseAllPositions(); ext_Target_Loss = 0; }
}
