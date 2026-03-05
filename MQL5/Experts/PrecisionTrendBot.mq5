//+------------------------------------------------------------------+
//|                                           PrecisionTrendBot.mq5  |
//|                                  Copyright 2024, GOAT TRADING    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, GOAT TRADING"
#property link      "https://www.mql5.com"
#property version   "1.30"
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

input group "--- Scalping de Conservation ---"
input bool Use_Trailing = true;          // Enable Trailing Stop
input int Trailing_Start = 50;           // Trailing Start (Points)
input int Trailing_Stop = 30;            // Trailing distance (Points)
input int Trailing_Step = 10;            // Trailing step (Points)

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

//--- Rose Animation Variables
int roseFrame = 0;
long lastRoseUpdate = 0;
string roseFrames[] = {
   "       .       ",
   "      ( )      ",
   "     ( @ )     ",
   "    (  @  )    ",
   "   (   @   )   ",
   "  (  @_@_@  )  ",
   " ( @@@@@@@@@ ) ",
   " {@@@@@@@@@@@} ",
   "  [@@@@@@@@@]  ",
   "   \\@@@@@@@/   ",
   "    \\@@@@@/    ",
   "     \\@@@/     ",
   "      \\@/      ",
   "       V       "
};

//--- Linear Regression Variables
struct LR_Result {
   double slope;
   double average;
   double intercept;
   double stdDev;
   double pearsonR;
};

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
   double price_arr[];
   ArraySetAsSeries(price_arr, true);
   if(CopyClose(_Symbol, PERIOD_M15, 0, lookback + shift, price_arr) < period + shift) return 0;

   switch(type)
   {
      case SMA: return iSMA_Iterative(price_arr, period, shift);
      case EMA: return iEMA_Iterative(price_arr, period, shift);
      case WMA: return iWMA_Iterative(price_arr, period, shift);
      case Hull: return iHullMA_Iterative(price_arr, period, shift);
      case VWMA: return iVWMA_M15(period, shift);
      case SMMA: return iSMMA_Iterative(price_arr, period, shift);
      case TEMA: return iTEMA_Iterative(price_arr, period, shift);
      case T3: return iT3_Iterative(price_arr, period, shift, t3_vfac);
      default: return iSMA_Iterative(price_arr, period, shift);
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

void iT3_GD_Array(const double &in_data[], double &out_data[], int p, double factor)
{
   double alpha = 2.0 / (p + 1.0);
   int n = ArraySize(in_data);
   ArrayResize(out_data, n);
   double e1[]; ArrayResize(e1, n);
   double last = in_data[n-1];
   for(int i=n-1; i>=0; i--) { e1[i] = alpha * in_data[i] + (1.0 - alpha) * last; last = e1[i]; }
   last = e1[n-1];
   for(int i=n-1; i>=0; i--) {
      double e2 = alpha * e1[i] + (1.0 - alpha) * last;
      out_data[i] = e1[i] * (1.0 + factor) - e2 * factor;
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
   double c_p[];
   long v_p[];
   if(CopyClose(_Symbol, PERIOD_M15, s, p, c_p) < p || CopyTickVolume(_Symbol, PERIOD_M15, s, p, v_p) < p) return 0;
   double spv = 0, sv = 0;
   for(int i=0; i<p; i++) { spv += c_p[i] * (double)v_p[i]; sv += (double)v_p[i]; }
   return (sv != 0) ? spv / sv : 0;
}

//+------------------------------------------------------------------+
//| Linear Regression Logic (Pine Translation)                       |
//+------------------------------------------------------------------+
LR_Result CalculateLR(int length, int shift)
{
   LR_Result res = {0,0,0,0,0};
   double src_p[];
   ArraySetAsSeries(src_p, true);
   if(CopyClose(_Symbol, PERIOD_M15, shift, length, src_p) < length) return res;

   double sumX = 0, sumY = 0, sumXSqr = 0, sumXY = 0;
   for(int i=0; i<length; i++)
   {
      double val = src_p[i];
      double per = i + 1.0;
      sumX += per; sumY += val;
      sumXSqr += per * per;
      sumXY += val * per;
   }
   res.slope = (length * sumXY - sumX * sumY) / (length * sumXSqr - sumX * sumX);
   res.average = sumY / length;
   res.intercept = res.average - res.slope * sumX / length + res.slope;

   double stdDevAcc = 0, dsxx = 0, dsyy = 0, dsxy = 0;
   double daY = res.intercept + res.slope * (length - 1) / 2.0;
   double valLR = res.intercept;
   for(int j=0; j<length; j++)
   {
      double price = src_p[j];
      double dxt = price - res.average;
      double dyt = valLR - daY;
      stdDevAcc += MathPow(price - valLR, 2);
      dsxx += dxt * dxt;
      dsyy += dyt * dyt;
      dsxy += dxt * dyt;
      valLR += res.slope;
   }
   res.stdDev = MathSqrt(stdDevAcc / (length <= 1 ? 1 : length - 1));
   res.pearsonR = (dsxx == 0 || dsyy == 0) ? 0 : dsxy / MathSqrt(dsxx * dsyy);

   return res;
}

//+------------------------------------------------------------------+
//| Core Trade Management                                            |
//+------------------------------------------------------------------+
bool OpenOrder(ENUM_ORDER_TYPE type)
{
   MqlTick tick_p;
   if(!SymbolInfoTick(_Symbol, tick_p)) return false;
   double lot = CalculateLot();
   double price = (type == ORDER_TYPE_BUY) ? tick_p.ask : tick_p.bid;
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
   else if(balance > 750000) lot = (balance / 750000.0) * 3.0;

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

   EventSetMillisecondTimer(250);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, UI_PREFIX); IndicatorRelease(handle_ema200); }

void OnTimer()
{
   static int telCounter = 0;
   telCounter++;
   if(telCounter >= 4 * Telegram_Polling_Sec)
   {
      FetchTelegramUpdates();
      telCounter = 0;
   }
   UpdateDashboard();
}

int GetPrecisionSignal()
{
   double p0 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, 0, T3_Factor);
   double p1 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, 1, T3_Factor);
   double ps = CalculateMA(Primary_MA_Algo, Primary_MA_Period, Trend_Smoothness, T3_Factor);
   double ps1 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, Trend_Smoothness + 1, T3_Factor);
   double s0 = CalculateMA(Secondary_MA_Algo, Secondary_MA_Period, 0, T3_Factor);

   double ema200_arr[]; CopyBuffer(handle_ema200, 0, 0, 1, ema200_arr);
   double price_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool cBull = p0 >= ps, cBear = p0 < ps, pBull = p1 >= ps1, pBear = p1 < ps1;

   if(cBull && pBear && s0 > p0 && (!Use_EMA_Filter || price_bid > ema200_arr[0])) return 1;
   if(cBear && pBull && s0 < p0 && (!Use_EMA_Filter || price_bid < ema200_arr[0])) return -1;

   return 0;
}

void OnTick()
{
   if(!ext_Bot_Active) { if(PositionsTotal() > 0) CloseAllPositions(); return; }
   CheckTargets();
   if(Use_Trailing) ApplyTrailingStop();

   int signal = GetPrecisionSignal();

   if(signal == 1)
   {
      if(PositionCount(POSITION_TYPE_SELL) > 0) {
         ClosePositions(POSITION_TYPE_SELL);
         SendTelegramMessage("🔄 Reversing to BUY");
      }
      if(PositionCount(POSITION_TYPE_BUY) == 0) OpenOrder(ORDER_TYPE_BUY);
   }
   else if(signal == -1)
   {
      if(PositionCount(POSITION_TYPE_BUY) > 0) {
         ClosePositions(POSITION_TYPE_BUY);
         SendTelegramMessage("🔄 Reversing to SELL");
      }
      if(PositionCount(POSITION_TYPE_SELL) == 0) OpenOrder(ORDER_TYPE_SELL);
   }

   if(PositionCount(POSITION_TYPE_BUY) == 0 && PositionCount(POSITION_TYPE_SELL) == 0)
   {
      double p0 = CalculateMA(Primary_MA_Algo, Primary_MA_Period, 0, T3_Factor);
      double ps = CalculateMA(Primary_MA_Algo, Primary_MA_Period, Trend_Smoothness, T3_Factor);
      if(p0 >= ps) OpenOrder(ORDER_TYPE_BUY);
      else OpenOrder(ORDER_TYPE_SELL);
   }
}

void ApplyTrailingStop()
{
   double point_p = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         double curSL = PositionGetDouble(POSITION_SL);
         double openP = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid_p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask_p = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            if(bid_p - openP > Trailing_Start * point_p)
            {
               double newSL = NormalizeDouble(bid_p - Trailing_Stop * point_p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
               if(newSL > curSL + Trailing_Step * point_p || curSL == 0)
                  trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
            }
         }
         else
         {
            if(openP - ask_p > Trailing_Start * point_p)
            {
               double newSL = NormalizeDouble(ask_p + Trailing_Stop * point_p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
               if(newSL < curSL - Trailing_Step * point_p || curSL == 0)
                  trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
            }
         }
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
   int total = b + s;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   LR_Result lr = CalculateLR(100, 0);

   int x = 20, y = 20, h = 20;
   color headClr = clrGold;
   color textClr = clrWhite;

   CreateLabel("Box", "╔══════════════════════════════════╗", x, y, headClr, CORNER_RIGHT_UPPER, 10);
   CreateLabel("Title", "║   P R E S T I G E   T E R M I N A L  ║", x, y+h, headClr, CORNER_RIGHT_UPPER, 10);
   CreateLabel("Sep1", "╠══════════════════════════════════╣", x, y+h*2, headClr, CORNER_RIGHT_UPPER, 10);

   int row = y + h*3;
   DrawArtRow("ASSET     ", _Symbol, x+15, row, textClr); row+=h;
   DrawArtRow("CAPITAL   ", DoubleToString(balance, 2), x+15, row, textClr); row+=h;
   DrawArtRow("EQUITY    ", DoubleToString(equity, 2), x+15, row, textClr); row+=h;
   DrawArtRow("P/L LIVE  ", DoubleToString(profit, 2), x+15, row, (profit>=0?clrLime:clrRed)); row+=h;
   DrawArtRow("CORREL. R ", DoubleToString(lr.pearsonR, 4), x+15, row, headClr); row+=h;
   DrawArtRow("ACTIVE B/S", IntegerToString(b)+" / "+IntegerToString(s), x+15, row, textClr); row+=h;

   CreateLabel("Box_End", "╚══════════════════════════════════╝", x, row, headClr, CORNER_RIGHT_UPPER, 10);

   long now = GetTickCount();
   if(now - lastRoseUpdate >= 200)
   {
      lastRoseUpdate = now;
      if(total > 0 && roseFrame < ArraySize(roseFrames)-1) roseFrame++;
      if(total == 0 && roseFrame > 0) roseFrame--;
   }

   color roseColor = (total > 0) ? clrCrimson : clrSlateGray;
   string roseText = roseFrames[roseFrame];

   CreateLabel("Rose_F", roseText, 40, 300, roseColor, CORNER_LEFT_UPPER, 45);
   CreateLabel("Rose_S", "  |  ", 55, 365, clrForestGreen, CORNER_LEFT_UPPER, 25);
   CreateLabel("Rose_L1", " /|\\ ", 55, 390, clrForestGreen, CORNER_LEFT_UPPER, 20);
   CreateLabel("Rose_L2", "  |  ", 55, 415, clrForestGreen, CORNER_LEFT_UPPER, 20);
   CreateLabel("Rose_M", (total > 0 ? "V I T A L I T Y" : "S I L E N C E"), 40, 460, roseColor, CORNER_LEFT_UPPER, 10);

   ChartRedraw();
}

void DrawArtRow(string label, string val, int x, int y, color valClr)
{
   CreateLabel("L_"+label, "║ " + label + " |", x + 150, y, clrLightGray, CORNER_RIGHT_UPPER, 10);
   CreateLabel("V_"+label, val + " ║", x, y, valClr, CORNER_RIGHT_UPPER, 10);
}

void CreateLabel(string name, string txt, int x, int y, color clr, ENUM_BASE_CORNER corner, int fontSize = 9)
{
   string n = UI_PREFIX + name;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, (corner == CORNER_RIGHT_UPPER || corner == CORNER_RIGHT_LOWER) ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   }
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, n, OBJPROP_FONT, "Courier New");
}

void CheckTargets()
{
   double p_val = AccountInfoDouble(ACCOUNT_PROFIT);
   if(ext_Target_Profit > 0 && p_val >= ext_Target_Profit) { CloseAllPositions(); ext_Target_Profit = 0; }
   if(ext_Target_Loss > 0 && p_val <= -ext_Target_Loss) { CloseAllPositions(); ext_Target_Loss = 0; }
}
