//+------------------------------------------------------------------+
//|                                        SupertrendRoseBot.mq5     |
//|                                  Copyright 2023, GOAT TRADING    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, GOAT TRADING"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Enums
enum LotModeEnum { FIXED_LOT, AUTO_RISK };

//--- Input Parameters
input bool Bot_Active = true;            // Bot Active (True=On, False=Off & Close Trades)

input group "--- Supertrend Parameters ---"
input int InpATRPeriod = 10;             // ATR Period
input double InpMultiplier = 3.0;        // ATR Multiplier
input bool InpChangeATR = true;          // Change ATR Calculation Method ?

input group "--- Lot & Grid Management ---"
input LotModeEnum LotMode = AUTO_RISK;    // Mode de lot
input double Fixed_Lot = 0.01;           // Lot fixe si FIXED_LOT

input group "--- Telegram Settings ---"
input string Telegram_Token = "";        // Telegram Bot Token
input long Telegram_ChatID = 0;          // Telegram Chat ID
input int Telegram_Polling_Sec = 3;      // Intervalle de lecture (sec)

//--- Global Variables
int handle_atr = INVALID_HANDLE;
double supertrend_up = 0;
double supertrend_dn = 0;
int trend = 0; // 1 = Up, -1 = Down
datetime last_bar_time = 0;

//--- Animation & UI
string UI_PREFIX = "ROSE_UI_";
int rose_state = 0; // 0 = closed, 1-4 = opening steps
datetime last_rose_update = 0;

//--- Modifiable Globals
bool ext_Bot_Active;
long ext_Telegram_ChatID;
long last_telegram_update_id = 0;
bool is_first_polling = true;
string telegram_status = "READY";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ext_Bot_Active = Bot_Active;
   ext_Telegram_ChatID = Telegram_ChatID;

   if(Telegram_Token != "" && Telegram_Polling_Sec > 0)
   {
      // We will use the millisecond timer for both animation and telegram
      EventSetMillisecondTimer(250);
   }
   else
   {
      EventSetMillisecondTimer(250);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, UI_PREFIX);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!ext_Bot_Active)
   {
      CloseAllPositions();
      return;
   }

   HandleSupertrendLogic();
}

//+------------------------------------------------------------------+
//| Supertrend Logic & Trading                                       |
//+------------------------------------------------------------------+
double CalculateATR(int period, bool useRMA)
{
   double hi[], lo[], close[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(close, true);

   int count = period + 50;
   if(CopyHigh(_Symbol, PERIOD_M15, 0, count, hi) < count) return 0;
   if(CopyLow(_Symbol, PERIOD_M15, 0, count, lo) < count) return 0;
   if(CopyClose(_Symbol, PERIOD_M15, 0, count, close) < count) return 0;

   double tr[];
   ArrayResize(tr, count - 1);
   for(int i=0; i<count-1; i++)
   {
      double hl = hi[i] - lo[i];
      double hc = MathAbs(hi[i] - close[i+1]);
      double lc = MathAbs(lo[i] - close[i+1]);
      tr[i] = MathMax(hl, MathMax(hc, lc));
   }

   if(!useRMA) // SMA
   {
      double sum = 0;
      for(int i=1; i<=period; i++) sum += tr[i];
      return sum / period;
   }
   else // RMA
   {
      double alpha = 1.0 / period;
      double val = 0;
      double sum = 0;
      int start_idx = count - 2;
      int end_idx = start_idx - period + 1;
      for(int i=start_idx; i>=end_idx; i--) sum += tr[i];
      val = sum / period;
      for(int i=end_idx-1; i>=1; i--) val = alpha * tr[i] + (1 - alpha) * val;
      return val;
   }
}

void HandleSupertrendLogic()
{
   double hi[], lo[], close[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(close, true);

   if(CopyHigh(_Symbol, PERIOD_M15, 0, 3, hi) < 3) return;
   if(CopyLow(_Symbol, PERIOD_M15, 0, 3, lo) < 3) return;
   if(CopyClose(_Symbol, PERIOD_M15, 0, 3, close) < 3) return;

   static double st_up = 0, st_dn = 0;
   static int st_trend = 1;
   static datetime last_calc_time = 0;

   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M15, SERIES_LASTBAR_DATE);

   if(current_bar_time != last_calc_time)
   {
      double atr_val = CalculateATR(InpATRPeriod, InpChangeATR);
      if(atr_val <= 0) return;

      double src1 = (hi[1] + lo[1]) / 2.0;
      double up1 = src1 - (InpMultiplier * atr_val);
      double dn1 = src1 + (InpMultiplier * atr_val);

      double prev_up = (st_up == 0) ? up1 : st_up;
      double prev_dn = (st_dn == 0) ? dn1 : st_dn;

      st_up = (close[2] > prev_up) ? MathMax(up1, prev_up) : up1;
      st_dn = (close[2] < prev_dn) ? MathMin(dn1, prev_dn) : dn1;

      int prev_trend = st_trend;
      st_trend = (prev_trend == -1 && close[1] > st_dn) ? 1 : (prev_trend == 1 && close[1] < st_up) ? -1 : prev_trend;

      if(st_trend != prev_trend)
      {
         ExecuteSAR(st_trend);
      }
      else if(PositionsTotal() == 0)
      {
         ExecuteSAR(st_trend);
      }

      trend = st_trend;
      last_calc_time = current_bar_time;
   }
}

void ExecuteSAR(int new_trend)
{
   CloseAllPositions();

   double lot = CalculateLot();
   int grid = GetGridCount();

   for(int i=0; i<grid; i++)
   {
      if(new_trend == 1)
         trade.Buy(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0, "GOAT TRADING");
      else if(new_trend == -1)
         trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0, "GOAT TRADING");
   }
}

double CalculateLot()
{
   if(LotMode == FIXED_LOT) return Fixed_Lot;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lot = 0.01;

   if(equity < 25)               lot = 0.01;
   else if(equity < 40)          lot = 0.01;
   else if(equity < 70)          lot = 0.02;
   else if(equity < 120)         lot = 0.02;
   else if(equity < 200)         lot = 0.03;
   else if(equity < 400)         lot = 0.10;
   else if(equity < 700)         lot = 0.12;
   else if(equity < 1200)        lot = 0.20;
   else if(equity < 10000)       lot = 0.50;
   else if(equity < 100000)      lot = 5.00;
   else if(equity < 250000)      lot = 8.00;
   else if(equity < 500000)      lot = 12.00;
   else if(equity < 1000000)     lot = 20.00;
   else if(equity < 5000000)     lot = 30.00;
   else if(equity < 10000000)    lot = 40.00;
   else if(equity < 25000000)    lot = 60.00;
   else if(equity < 50000000)    lot = 80.00;
   else if(equity < 100000000)   lot = 100.00;
   else if(equity < 300000000)   lot = 120.00;
   else                          lot = 150.00;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

int GetGridCount()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < 1000) return 1;
   if(balance < 5000) return 2;
   if(balance < 13000) return 3;
   if(balance < 50000) return 5;
   if(balance < 150000) return 10;
   if(balance < 350000) return 15;
   if(balance < 750000) return 20;
   return 30;
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Telegram Polling (every N seconds)
   static long last_poll_ms = 0;
   long current_ms = GetTickCount64();

   if(Telegram_Token != "" && Telegram_Polling_Sec > 0)
   {
      if(current_ms - last_poll_ms >= (long)Telegram_Polling_Sec * 1000)
      {
         FetchTelegramUpdates();
         last_poll_ms = current_ms;
      }
   }

   // Millisecond timer logic for Rose Animation & Dashboard (every 250ms)
   AnimateRose();
   UpdateDashboard();
}

//--- Placeholders for next steps
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            trade.PositionClose(ticket);
      }
   }
}
void SendTelegramMessage(string message)
{
   if(Telegram_Token == "" || ext_Telegram_ChatID == 0) return;
   string url = "https://api.telegram.org/bot" + Telegram_Token + "/sendMessage";
   StringReplace(message, " ", "%20");
   StringReplace(message, "\n", "%0A");
   string payload = "chat_id=" + IntegerToString(ext_Telegram_ChatID) + "&text=" + message;
   char data[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   int len = StringToCharArray(payload, data);
   if(len > 0) ArrayResize(data, len - 1);
   WebRequest("POST", url, headers, 5000, data, result, headers);
}

void FetchTelegramUpdates()
{
   if(Telegram_Token == "") return;
   string url = "https://api.telegram.org/bot" + Telegram_Token + "/getUpdates?offset=" + IntegerToString(last_telegram_update_id + 1) + "&limit=10&timeout=2";
   char data[], result[];
   string headers;
   int res = WebRequest("GET", url, NULL, 5000, data, result, headers);
   if(res == 200)
   {
      telegram_status = "CONNECTED";
      string response = CharArrayToString(result);
      int updatePos = StringFind(response, "\"update_id\"");
      while(updatePos != -1)
      {
         string updateIdStr = StringExtract(response, "\"update_id\"", updatePos);
         if(updateIdStr != "")
         {
            last_telegram_update_id = StringToInteger(updateIdStr);
            string chatIdStr = StringExtract(response, "\"id\"", updatePos);
            if(chatIdStr != "") ext_Telegram_ChatID = StringToInteger(chatIdStr);
            string text = StringExtract(response, "\"text\"", updatePos);
            if(!is_first_polling && text != "") ProcessTelegramCommand(text);
         }
         updatePos = StringFind(response, "\"update_id\"", updatePos + 10);
      }
      is_first_polling = false;
   }
   else telegram_status = "ERR " + IntegerToString(res);
}

string StringExtract(string source, string key, int startPos = 0)
{
   int pos = StringFind(source, key, startPos);
   if(pos == -1) return "";
   int start = pos + StringLen(key);
   while(start < StringLen(source) && (StringSubstr(source, start, 1) == ":" || StringSubstr(source, start, 1) == " " || StringSubstr(source, start, 1) == "\"")) start++;
   int firstQuote = StringFind(source, "\"", pos + StringLen(key));
   int firstComma = StringFind(source, ",", pos + StringLen(key));
   int end = (firstQuote != -1 && (firstComma == -1 || firstQuote < firstComma)) ? StringFind(source, "\"", start) : StringFind(source, ",", start);
   if(end == -1) end = StringFind(source, "}", start);
   if(end == -1) end = StringLen(source);
   return StringSubstr(source, start, end - start);
}
void AnimateRose()
{
   bool hasPositions = (PositionsTotal() > 0);

   if(hasPositions)
   {
      // Blooming: 0 -> 4
      if(rose_state < 4) rose_state++;
   }
   else
   {
      // Closing: 4 -> 0
      if(rose_state > 0) rose_state--;
   }
}

void CreateLabel(string name, string text, int x, int y, color clr, ENUM_BASE_CORNER corner, int fontSize=9, int anchor=ANCHOR_LEFT_UPPER)
{
   string objName = UI_PREFIX + name;
   if(ObjectFind(0, objName) < 0)
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);

   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, objName, OBJPROP_FONT, "Courier New");
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, anchor);
}

void UpdateDashboard()
{
   //--- Rose Animation
   string rose[6];
   if(rose_state == 0) {
      rose[0]="      @      "; rose[1]="     /\\      "; rose[2]="    |  |     "; rose[3]="     \\/      "; rose[4]="      |      "; rose[5]="    \\ | /    ";
   } else if(rose_state == 1) {
      rose[0]="     _@_     "; rose[1]="    /   \\    "; rose[2]="   |     |   "; rose[3]="    \\___/    "; rose[4]="      |      "; rose[5]="    \\ | /    ";
   } else if(rose_state == 2) {
      rose[0]="    __@__    "; rose[1]="   /     \\   "; rose[2]="  |       |  "; rose[3]="   \\_____/   "; rose[4]="      |      "; rose[5]="   \\_ | _/   ";
   } else if(rose_state == 3) {
      rose[0]="   ___@___   "; rose[1]="  /       \\  "; rose[2]=" |         | "; rose[3]="  \\_______/  "; rose[4]="      |      "; rose[5]="  \\__ | __/  ";
   } else {
      rose[0]="  ____@____  "; rose[1]=" /         \\ "; rose[2]="|  BLOOMING |"; rose[3]=" \\_________/ "; rose[4]="      |      "; rose[5]=" \\___ | ___/ ";
   }

   color roseColor = (rose_state == 4) ? clrCrimson : clrLightPink;
   int xRose = 50, yRose = 50;
   for(int i=0; i<6; i++)
      CreateLabel("Rose"+IntegerToString(i), rose[i], xRose, yRose + i*15, roseColor, CORNER_LEFT_UPPER, 12);

   //--- Grand Art Dashboard (Right Side)
   int xDash = 20, yDash = 20;
   int step = 25;
   color headClr = clrGold;
   color textClr = clrWhite;

   CreateLabel("Dash0", "╔════════════════════════════════════╗", xDash, yDash, headClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("Dash1", "║         SUPERTREND MASTERPIECE     ║", xDash, yDash + step*1, headClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("Dash2", "╠════════════════════════════════════╣", xDash, yDash + step*2, headClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);

   string trendStr = (trend == 1) ? "BULLISH" : (trend == -1 ? "BEARISH" : "WAITING");
   color trendClr = (trend == 1) ? clrLime : (trend == -1 ? clrRed : clrGray);

   CreateLabel("Dash3", "║  TREND: " + trendStr, xDash, yDash + step*3, trendClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("Dash4", "║  EQUITY: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), xDash, yDash + step*4, textClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("Dash5", "║  PROFIT: " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2), xDash, yDash + step*5, (AccountInfoDouble(ACCOUNT_PROFIT)>=0?clrLime:clrRed), CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("Dash6", "║  TRADES: " + IntegerToString(PositionsTotal()), xDash, yDash + step*6, textClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);

   CreateLabel("Dash7", "╚════════════════════════════════════╝", xDash, yDash + step*7, headClr, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);

   CreateLabel("Branding", "GOAT TRADING", xDash, yDash + step*8 + 10, clrDimGray, CORNER_RIGHT_UPPER, 8, ANCHOR_RIGHT_UPPER);

   ChartRedraw();
}
void ProcessTelegramCommand(string text)
{
   StringToUpper(text);
   StringReplace(text, "/", "");
   bool handled = false;
   string reply = "Command not recognized.";

   if(text == "HELP" || text == "AIDE")
   {
      reply = "SUPERTREND BOT COMMANDS:\nON/OFF - Bot state\nCLOSE - Close all\nSTATUS - Current status";
      handled = true;
   }
   else if(text == "ON" || text == "ACTIF TRUE")
   {
      ext_Bot_Active = true;
      reply = "Bot ACTIVATED.";
      handled = true;
   }
   else if(text == "OFF" || text == "ACTIF FALSE")
   {
      ext_Bot_Active = false;
      CloseAllPositions();
      reply = "Bot DEACTIVATED and positions closed.";
      handled = true;
   }
   else if(text == "CLOSE" || text == "FERMER")
   {
      CloseAllPositions();
      reply = "All positions closed.";
      handled = true;
   }
   else if(text == "STATUS")
   {
      reply = "Trend: " + ((trend==1)?"Bullish":"Bearish") + "\nActive: " + (ext_Bot_Active?"Yes":"No") + "\nPositions: " + IntegerToString(PositionsTotal());
      handled = true;
   }

   if(handled) SendTelegramMessage(reply);
}
