//+------------------------------------------------------------------+
//|                                                GoatTrading.mq5   |
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
enum TPSLModeEnum { PRICE_LEVEL, PIPS };

//--- Input Parameters
input bool Bot_Active = true;            // Bot Active (True=On, False=Off & Close Trades)

input group "--- Gestion des lots ---"
input LotModeEnum LotMode = AUTO_RISK;    // Mode de lot
input double Risk_Percent = 2.0;         // % du capital risqué (si applicable)
input double Fixed_Lot = 0.01;           // Lot fixe si FIXED_LOT

input group "--- Ouverture des ordres ---"
input int Buy_Count = 5;                 // Nombre de BUY à ouvrir
input int Sell_Count = 0;                // Nombre de SELL à ouvrir
input bool Execute_Orders = true;        // Activer l'ouverture automatique
input bool Only_If_No_Open_Trades = false; // Bloquer si un trade est ouvert

input group "--- Telegram Settings ---"
input string Telegram_Token = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw"; // Telegram Bot Token
input long Telegram_ChatID = 0;          // Telegram Chat ID
input int Telegram_Polling_Sec = 3;      // Intervalle de lecture (sec)

input group "--- TP / SL Global ---"
input TPSLModeEnum TP_SL_Mode = PRICE_LEVEL; // Mode TP/SL (Prix ou Pips)
input double Global_TP_Buy = 71311.0;    // Global TP BUY
input double Global_SL_Buy = 69520.0;    // Global SL BUY
input double Global_TP_Sell = 0.0;       // Global TP SELL
input double Global_SL_Sell = 0.0;       // Global SL SELL

input group "--- TP Multi-niveaux ---"
input bool Use_MultiLevel_TP = true;     // Utiliser TP multi-niveaux
input double TP_Level1 = 0.0;            // TP Niveau 1
input int Trades_Level1 = 0;             // Nombre de trades Niveau 1
input double TP_Level2 = 0.0;            // TP Niveau 2
input int Trades_Level2 = 0;             // Nombre de trades Niveau 2
input double TP_Level3 = 0.0;            // TP Niveau 3
input int Trades_Level3 = 0;             // Nombre de trades Niveau 3

input group "--- Indicators & Alerts ---"
input string Custom_Indicator_Name = "lucky-reversal"; // Nom de l'indicateur
input int Indicator_Buy_Buffer = 0;      // Index buffer d'achat
input int Indicator_Sell_Buffer = 1;     // Index buffer de vente
input bool Enable_MTF_Alerts = true;     // Alertes automatiques M15-H1

input group "--- Advanced Market Structure (SMC) ---"
input int Internal_Lookback = 4;         // Lookback Structure Interne
input int Swing_Lookback = 50;           // Lookback Structure Swing
input bool Show_SMC_Labels = true;       // Afficher labels SMC sur graphique

//--- Global Variables
bool ordersExecuted = false;
int lastBuyCount = 0;
int lastSellCount = 0;
long last_telegram_update_id = 0;
bool is_first_polling = true;
string telegram_status = "READY";

//--- Alert synchronization
datetime last_alert_m15 = 0;
datetime last_alert_m30 = 0;
datetime last_alert_h1 = 0;
int handle_m15 = INVALID_HANDLE;
int handle_m30 = INVALID_HANDLE;
int handle_h1 = INVALID_HANDLE;
int handle_atr = INVALID_HANDLE;

//--- Dashboard Animation
int current_eye_state = 0;
datetime last_eye_change = 0;
string UI_PREFIX = "GOAT_UI_";

//--- Cat Movement & Animation
int catOffsetX = 0;
int catOffsetY = 0;
datetime lastCatMove = 0;
int tailState = 0;

//--- SMC Structures
struct SMC_Structure {
   double price;
   datetime time;
   string type; // "BOS" or "CHoCH"
   bool bull;
};

struct FVG_Data {
   double top;
   double bottom;
   bool bull;
   datetime time;
};

//--- SMC Global Variables
int internal_trend = 0; // 1=Bull, -1=Bear
int swing_trend = 0;    // 1=Bull, -1=Bear
SMC_Structure last_internal_ms;
SMC_Structure last_swing_ms;

//--- SMC Helpers
double GetPivotHigh(const double &hi[], int index, int left, int right, int total)
{
   if(index < right || index + left >= total) return 0;
   double val = hi[index];
   for(int i=1; i<=left; i++) if(hi[index+i] > val) return 0;
   for(int i=1; i<=right; i++) if(hi[index-i] > val) return 0;
   return val;
}

double GetPivotLow(const double &lo[], int index, int left, int right, int total)
{
   if(index < right || index + left >= total) return 0;
   double val = lo[index];
   for(int i=1; i<=left; i++) if(lo[index+i] < val) return 0;
   for(int i=1; i<=right; i++) if(lo[index-i] < val) return 0;
   return val;
}

void UpdateSMC()
{
   int iLen = Internal_Lookback;
   int sLen = Swing_Lookback;

   double hi[], lo[], cl[];
   datetime tm[];
   int copied = CopyHigh(_Symbol, _Period, 0, 1000, hi);
   if(copied < 1000) return;
   CopyLow(_Symbol, _Period, 0, 1000, lo);
   CopyClose(_Symbol, _Period, 0, 1000, cl);
   CopyTime(_Symbol, _Period, 0, 1000, tm);

   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(cl, true);
   ArraySetAsSeries(tm, true);

   double price = cl[1]; // Use last closed bar

   //--- Internal Structure
   double iH = 0, iL = 0;
   for(int i=iLen; i<500; i++) {
      double val = GetPivotHigh(hi, i, iLen, iLen, 1000);
      if(val > 0) { iH = val; break; }
   }
   for(int i=iLen; i<500; i++) {
      double val = GetPivotLow(lo, i, iLen, iLen, 1000);
      if(val > 0) { iL = val; break; }
   }

   if(iH > 0 && price > iH) {
      last_internal_ms.type = (internal_trend < 0) ? "CHoCH" : "BOS";
      last_internal_ms.bull = true;
      last_internal_ms.price = iH;
      last_internal_ms.time = tm[0];
      internal_trend = 1;
   }
   else if(iL > 0 && price < iL) {
      last_internal_ms.type = (internal_trend > 0) ? "CHoCH" : "BOS";
      last_internal_ms.bull = false;
      last_internal_ms.price = iL;
      last_internal_ms.time = tm[0];
      internal_trend = -1;
   }

   //--- Swing Structure
   double sH = 0, sL = 0;
   for(int i=sLen; i<1000; i++) {
      double val = GetPivotHigh(hi, i, sLen, sLen, 1000);
      if(val > 0) { sH = val; break; }
   }
   for(int i=sLen; i<1000; i++) {
      double val = GetPivotLow(lo, i, sLen, sLen, 1000);
      if(val > 0) { sL = val; break; }
   }

   if(sH > 0 && price > sH) {
      last_swing_ms.type = (swing_trend < 0) ? "CHoCH" : "BOS";
      last_swing_ms.bull = true;
      last_swing_ms.price = sH;
      last_swing_ms.time = tm[0];
      swing_trend = 1;
   }
   else if(sL > 0 && price < sL) {
      last_swing_ms.type = (swing_trend > 0) ? "CHoCH" : "BOS";
      last_swing_ms.bull = false;
      last_swing_ms.price = sL;
      last_swing_ms.time = tm[0];
      swing_trend = -1;
   }
}

void GetLatestFVG(FVG_Data &fvg)
{
   fvg.time = 0;
   double hi[], lo[];
   datetime tm[];
   if(CopyHigh(_Symbol, _Period, 0, 110, hi) < 110) return;
   CopyLow(_Symbol, _Period, 0, 110, lo);
   CopyTime(_Symbol, _Period, 0, 110, tm);
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(tm, true);

   // Scan last 100 bars for the most recent FVG
   for(int i=1; i<100; i++) {
      double h2 = hi[i+2];
      double l0 = lo[i];
      double l2 = lo[i+2];
      double h0 = hi[i];

      // Bullish FVG
      if(l0 > h2) {
         fvg.bull = true;
         fvg.top = l0;
         fvg.bottom = h2;
         fvg.time = tm[i+1];
         break;
      }
      // Bearish FVG
      if(h0 < l2) {
         fvg.bull = false;
         fvg.top = l2;
         fvg.bottom = h0;
         fvg.time = tm[i+1];
         break;
      }
   }
}

string GetLiquidityInfo()
{
   if(handle_atr == INVALID_HANDLE) handle_atr = iATR(_Symbol, _Period, 14);

   double atr_buf[];
   if(CopyBuffer(handle_atr, 0, 0, 1, atr_buf) <= 0) {
      return "Indéterminée";
   }
   double tolerance = atr_buf[0] * 0.1;

   double hi[], lo[];
   if(CopyHigh(_Symbol, _Period, 0, 250, hi) < 250) return "Données insuffisantes";
   CopyLow(_Symbol, _Period, 0, 250, lo);
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);

   double lastH = 0, prevH = 0, lastL = 0, prevL = 0;

   // Simplified peak/trough detection for EQH/EQL
   for(int i=1; i<200; i++) {
      double pHigh = GetPivotHigh(hi, i, 2, 2, 250);
      if(pHigh > 0) {
         if(lastH == 0) lastH = pHigh;
         else if(prevH == 0) { prevH = pHigh; break; }
      }
   }
   for(int i=1; i<200; i++) {
      double pLow = GetPivotLow(lo, i, 2, 2, 250);
      if(pLow > 0) {
         if(lastL == 0) lastL = pLow;
         else if(prevL == 0) { prevL = pLow; break; }
      }
   }

   if(lastH > 0 && prevH > 0 && MathAbs(lastH - prevH) <= tolerance) return "EQH détecté (Résistance)";
   if(lastL > 0 && prevL > 0 && MathAbs(lastL - prevL) <= tolerance) return "EQL détecté (Support)";

   return "Aucune zone d'égalité immédiate";
}

//--- Modifiable Global States (initialized from inputs)
long ext_Telegram_ChatID;
bool ext_Bot_Active;
bool ext_Use_MultiLevel_TP;
double ext_TP_Level1, ext_TP_Level2, ext_TP_Level3;
int ext_Trades_Level1, ext_Trades_Level2, ext_Trades_Level3;
double ext_Global_TP_Buy, ext_Global_SL_Buy;
double ext_Global_TP_Sell, ext_Global_SL_Sell;
double ext_Target_Profit = 0;
double ext_Target_Loss = 0;

//+------------------------------------------------------------------+
//| Send a message to Telegram                                       |
//+------------------------------------------------------------------+
void SendTelegramMessage(string message)
{
   if(Telegram_Token == "" || ext_Telegram_ChatID == 0) return;

   string url = "https://api.telegram.org/bot" + Telegram_Token + "/sendMessage";

   // Simple URL encoding for message
   StringReplace(message, " ", "%20");
   StringReplace(message, "\n", "%0A");
   StringReplace(message, "#", "%23");
   StringReplace(message, "&", "%26");

   string payload = "chat_id=" + IntegerToString(ext_Telegram_ChatID) + "&text=" + message;
   char data[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   int len = StringToCharArray(payload, data);
   if(len > 0) ArrayResize(data, len - 1); // Remove null terminator

   int res = WebRequest("POST", url, headers, 5000, data, result, headers);

   if(res == -1)
      Print("Telegram Send Error: ", GetLastError());
   else if(res != 200)
      Print("Telegram API Error Code: ", res, " Response: ", CharArrayToString(result));
}

//+------------------------------------------------------------------+
//| Fetch new messages from Telegram                                 |
//+------------------------------------------------------------------+
void FetchTelegramUpdates()
{
   if(Telegram_Token == "") return;

   // Increase limit to 10 and add timeout
   string url = "https://api.telegram.org/bot" + Telegram_Token + "/getUpdates?offset=" + IntegerToString(last_telegram_update_id + 1) + "&limit=10&timeout=2";
   char data[], result[];
   string headers;

   int res = WebRequest("GET", url, NULL, 5000, data, result, headers);

   if(res == 200)
   {
      telegram_status = "CONNECTED";
      string response = CharArrayToString(result);

      // Look for multiple messages in response by searching for "update_id"
      int updatePos = StringFind(response, "\"update_id\"");
      while(updatePos != -1)
      {
         string updateIdStr = StringExtract(response, "\"update_id\"", updatePos);
         if(updateIdStr != "")
         {
            last_telegram_update_id = StringToInteger(updateIdStr);

            // Extract Chat ID dynamically if not set or if we want to ensure we reply to the right person
            int chatPos = StringFind(response, "\"chat\"", updatePos);
            if(chatPos != -1)
            {
               string chatIdStr = StringExtract(response, "\"id\"", chatPos);
               if(chatIdStr != "")
               {
                  long cid = StringToInteger(chatIdStr);
                  if(ext_Telegram_ChatID == 0)
                  {
                     ext_Telegram_ChatID = cid;
                     Print("Telegram Chat ID detected: ", ext_Telegram_ChatID);
                     SendTelegramMessage("Bonjour Monsieur, je suis maintenant connecté à votre compte. Comment puis-je vous aider aujourd'hui ?");
                  }
                  else
                  {
                     ext_Telegram_ChatID = cid; // Update to latest sender
                  }
               }
            }

            // Extract the text for this specific update_id block
            string text = StringExtract(response, "\"text\"", updatePos);

            if(!is_first_polling)
            {
               if(text != "") ProcessTelegramCommand(text);
            }
         }

         // Search for the next "update_id" starting after the current one
         updatePos = StringFind(response, "\"update_id\"", updatePos + 10);
      }
      is_first_polling = false;
   }
   else
   {
      telegram_status = "ERR " + IntegerToString(res);
      if(res == -1)
      {
         int err = GetLastError();
         Print("Telegram WebRequest Error: ", err);
         if(err == 4014) telegram_status = "ERR: URL NOT ALLOWED";
      }
   }
}

//+------------------------------------------------------------------+
//| Simple string parsing helper with start position                 |
//+------------------------------------------------------------------+
string StringExtract(string source, string key, int startPos = 0)
{
   int pos = StringFind(source, key, startPos);
   if(pos == -1) return "";

   int start = pos + StringLen(key);
   // Skip colon, spaces and quotes
   while(start < StringLen(source) && (StringSubstr(source, start, 1) == ":" || StringSubstr(source, start, 1) == " " || StringSubstr(source, start, 1) == "\""))
      start++;

   int end = start;
   // If it's a string value (surrounded by quotes), find closing quote
   // We look for the first quote after the key within a reasonable distance
   int firstQuote = StringFind(source, "\"", pos + StringLen(key));
   int firstComma = StringFind(source, ",", pos + StringLen(key));

   if(firstQuote != -1 && (firstComma == -1 || firstQuote < firstComma))
   {
      end = StringFind(source, "\"", start);
   }
   else // numeric value or unquoted
   {
      end = StringFind(source, ",", start);
      int endBracket = StringFind(source, "}", start);
      if(end == -1 || (endBracket != -1 && endBracket < end)) end = endBracket;
   }

   if(end == -1) end = StringLen(source);

   string val = StringSubstr(source, start, end - start);
   return val;
}

//+------------------------------------------------------------------+
//| Parse and execute Telegram commands                              |
//+------------------------------------------------------------------+
void ProcessTelegramCommand(string text)
{
   StringReplace(text, "+", " "); // Decode spaces if needed
   StringReplace(text, "LVL", "LEVEL");
   StringReplace(text, "/", "");  // Support /command format
   StringReplace(text, "_", " "); // Support BotFather menu commands (e.g. /tp_buy -> TP BUY)
   StringToUpper(text);

   // Remove 'COMMANDN' numbering if present (e.g. COMMAND1 BUY -> BUY)
   if(StringFind(text, "COMMAND") == 0)
   {
      int spacePos = StringFind(text, " ");
      if(spacePos != -1)
      {
         text = StringSubstr(text, spacePos + 1);
         StringTrimLeft(text);
      }
   }

   bool handled = false;
   string reply = "Command not recognized. Use HELP for a list of commands.";

   if(text == "HELP" || text == "AIDE")
   {
      reply = "GOAT TRADING COMMANDS:\n" +
              "BUY [count] - Open BUY trades\n" +
              "SELL [count] - Open SELL trades\n" +
              "CLOSE - Close all trades\n" +
              "CLOSE 3 - Close last 3 trades\n" +
              "CLOSE PROFIT [val] - Target Profit\n" +
              "CLOSE LOSS [val] - Target Loss\n" +
              "TP/SL BUY [val] - Set BUY TP/SL\n" +
              "TP/SL SELL [val] - Set SELL TP/SL\n" +
              "TP LEVEL [1/2/3] [val] - Set Multi-TP levels\n" +
              "COUNT LEVEL [1/2/3] [num] - Set trades per TP level\n" +
              "MULTI TP [ON/OFF] - Toggle Multi-TP mode\n" +
              "ON/OFF - Toggle Bot Active\n" +
              "ANALYSE - Market Technical Analysis\n" +
              "CAPTURE - Get Chart Screenshot\n" +
              "MYID - Get your Chat ID";
      handled = true;
   }
   else if(text == "MYID")
   {
      reply = "Your Chat ID is: " + IntegerToString(ext_Telegram_ChatID);
      handled = true;
   }
   else if(text == "ANALYSE" || text == "ANALYSIS")
   {
      reply = GetMarketAnalysis();
      handled = true;
   }
   else if(text == "CAPTURE" || text == "PHOTO" || text == "SCREENSHOT")
   {
      SendChartScreenshot();
      return; // Handled separately
   }
   // Commands: TP BUY [val], TP SELL [val], SL BUY [val], SL SELL [val], CLOSE, ACTIF [true/false]
   else if(StringFind(text, "MULTI TP ON") != -1)
   {
      ext_Use_MultiLevel_TP = true;
      reply = "Multi-Level TP mode ACTIVATED.";
      handled = true;
   }
   else if(StringFind(text, "MULTI TP OFF") != -1)
   {
      ext_Use_MultiLevel_TP = false;
      reply = "Multi-Level TP mode DEACTIVATED. Using Global TP.";
      handled = true;
   }
   else if(StringFind(text, "TP LEVEL 1") != -1)
   {
      ext_TP_Level1 = StringToDouble(StringSubstr(text, StringFind(text, "LEVEL 1") + 8));
      reply = "Take Profit Level 1 updated to " + DoubleToString(ext_TP_Level1, 5);
      handled = true;
   }
   else if(StringFind(text, "TP LEVEL 2") != -1)
   {
      ext_TP_Level2 = StringToDouble(StringSubstr(text, StringFind(text, "LEVEL 2") + 8));
      reply = "Take Profit Level 2 updated to " + DoubleToString(ext_TP_Level2, 5);
      handled = true;
   }
   else if(StringFind(text, "TP LEVEL 3") != -1)
   {
      ext_TP_Level3 = StringToDouble(StringSubstr(text, StringFind(text, "LEVEL 3") + 8));
      reply = "Take Profit Level 3 updated to " + DoubleToString(ext_TP_Level3, 5);
      handled = true;
   }
   else if(StringFind(text, "COUNT LEVEL 1") != -1)
   {
      ext_Trades_Level1 = (int)StringToInteger(StringSubstr(text, StringFind(text, "LEVEL 1") + 8));
      reply = "Trade Count for Level 1 updated to " + IntegerToString(ext_Trades_Level1);
      handled = true;
   }
   else if(StringFind(text, "COUNT LEVEL 2") != -1)
   {
      ext_Trades_Level2 = (int)StringToInteger(StringSubstr(text, StringFind(text, "LEVEL 2") + 8));
      reply = "Trade Count for Level 2 updated to " + IntegerToString(ext_Trades_Level2);
      handled = true;
   }
   else if(StringFind(text, "COUNT LEVEL 3") != -1)
   {
      ext_Trades_Level3 = (int)StringToInteger(StringSubstr(text, StringFind(text, "LEVEL 3") + 8));
      reply = "Trade Count for Level 3 updated to " + IntegerToString(ext_Trades_Level3);
      handled = true;
   }
   else if(StringFind(text, "TP BUY") != -1)
   {
      ext_Global_TP_Buy = StringToDouble(StringSubstr(text, StringFind(text, "BUY") + 4));
      reply = "Global TP BUY updated to " + DoubleToString(ext_Global_TP_Buy, 5);
      handled = true;
   }
   else if(StringFind(text, "SL BUY") != -1)
   {
      ext_Global_SL_Buy = StringToDouble(StringSubstr(text, StringFind(text, "BUY") + 4));
      reply = "Global SL BUY updated to " + DoubleToString(ext_Global_SL_Buy, 5);
      handled = true;
   }
   else if(StringFind(text, "TP SELL") != -1)
   {
      ext_Global_TP_Sell = StringToDouble(StringSubstr(text, StringFind(text, "SELL") + 5));
      reply = "Global TP SELL updated to " + DoubleToString(ext_Global_TP_Sell, 5);
      handled = true;
   }
   else if(StringFind(text, "SL SELL") != -1)
   {
      ext_Global_SL_Sell = StringToDouble(StringSubstr(text, StringFind(text, "SELL") + 5));
      reply = "Global SL SELL updated to " + DoubleToString(ext_Global_SL_Sell, 5);
      handled = true;
   }
   else if(StringFind(text, "CLOSE PROFIT") != -1)
   {
      ext_Target_Profit = StringToDouble(StringSubstr(text, StringFind(text, "PROFIT") + 7));
      reply = "Target Profit set to $" + DoubleToString(ext_Target_Profit, 2);
      handled = true;
   }
   else if(StringFind(text, "CLOSE LOSS") != -1)
   {
      ext_Target_Loss = MathAbs(StringToDouble(StringSubstr(text, StringFind(text, "LOSS") + 5)));
      reply = "Target Loss set to -$" + DoubleToString(ext_Target_Loss, 2);
      handled = true;
   }
   else if(StringFind(text, "FERMER") != -1 || StringFind(text, "CLOSE") != -1)
   {
      int count = (int)StringToInteger(StringSubstr(text, StringFind(text, " ") + 1));
      if(count > 0)
      {
         for(int i=0; i<count && PositionsTotal()>0; i++)
         {
            ulong ticket = PositionGetTicket(0);
            if(PositionSelectByTicket(ticket)) trade.PositionClose(ticket);
         }
         reply = "Closed " + IntegerToString(count) + " positions.";
      }
      else
      {
         CloseAllPositions();
         reply = "All positions closed.";
      }
      handled = true;
   }
   else if(StringFind(text, "ACTIF TRUE") != -1 || StringFind(text, "ON") != -1)
   {
      ext_Bot_Active = true;
      reply = "Bot activated.";
      handled = true;
   }
   else if(StringFind(text, "ACTIF FALSE") != -1 || StringFind(text, "OFF") != -1)
   {
      ext_Bot_Active = false;
      CloseAllPositions();
      reply = "Bot deactivated and trades closed.";
      handled = true;
   }
   else if(StringFind(text, "BUY") != -1 || StringFind(text, "ACHAT") != -1)
   {
      int count = (int)StringToInteger(StringSubstr(text, StringFind(text, " ") + 1));
      if(count <= 0) count = (Buy_Count > 0) ? Buy_Count : 1;

      if(!ext_Bot_Active) reply = "Error: Bot is DISABLED.";
      else if(Only_If_No_Open_Trades && (lastBuyCount + lastSellCount) > 0) reply = "Error: Active trades exist.";
      else
      {
         int ok = 0;
         for(int i=0; i<count; i++) if(OpenOrder(ORDER_TYPE_BUY)) ok++;
         reply = "BUY Request: " + IntegerToString(ok) + "/" + IntegerToString(count) + " success.";
         if(ok < count) reply += " Error: " + trade.ResultRetcodeDescription();
      }
      handled = true;
   }
   else if(StringFind(text, "SELL") != -1 || StringFind(text, "VENTE") != -1)
   {
      int count = (int)StringToInteger(StringSubstr(text, StringFind(text, " ") + 1));
      if(count <= 0) count = (Sell_Count > 0) ? Sell_Count : 1;

      if(!ext_Bot_Active) reply = "Error: Bot is DISABLED.";
      else if(Only_If_No_Open_Trades && (lastBuyCount + lastSellCount) > 0) reply = "Error: Active trades exist.";
      else
      {
         int ok = 0;
         for(int i=0; i<count; i++) if(OpenOrder(ORDER_TYPE_SELL)) ok++;
         reply = "SELL Request: " + IntegerToString(ok) + "/" + IntegerToString(count) + " success.";
         if(ok < count) reply += " Error: " + trade.ResultRetcodeDescription();
      }
      handled = true;
   }

   if(handled)
      SendTelegramMessage(reply);
}

//+------------------------------------------------------------------+
//| Enhanced Market Analysis with Structure and Courteous Tone       |
//+------------------------------------------------------------------+
string GetMarketAnalysis()
{
   UpdateSMC();
   FVG_Data latest_fvg;
   GetLatestFVG(latest_fvg);
   string liquidity = GetLiquidityInfo();

   // Greetings
   string greeting = "Bonjour Monsieur. C'est un plaisir de vous servir. Voici mon analyse SMC détaillée pour " + _Symbol + " :\n\n";

   double rsi[], ma50[], ma200[];
   int rsiHandle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   int ma50Handle = iMA(_Symbol, _Period, 50, 0, MODE_SMA, PRICE_CLOSE);
   int ma200Handle = iMA(_Symbol, _Period, 200, 0, MODE_SMA, PRICE_CLOSE);

   if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) <= 0 ||
      CopyBuffer(ma50Handle, 0, 0, 1, ma50) <= 0 ||
      CopyBuffer(ma200Handle, 0, 0, 1, ma200) <= 0)
   {
      IndicatorRelease(rsiHandle); IndicatorRelease(ma50Handle); IndicatorRelease(ma200Handle);
      return "Pardonnez-moi Monsieur, mais mes indicateurs ne sont pas encore prêts. Veuillez patienter un instant.";
   }

   IndicatorRelease(rsiHandle); IndicatorRelease(ma50Handle); IndicatorRelease(ma200Handle);

   //--- Market Structure (Fractals Based)
   double fractHigh[], fractLow[];
   datetime times[];
   int fractHandle = iFractals(_Symbol, _Period);
   CopyBuffer(fractHandle, 0, 0, 100, fractHigh);
   CopyBuffer(fractHandle, 1, 0, 100, fractLow);
   CopyTime(_Symbol, _Period, 0, 100, times);
   IndicatorRelease(fractHandle);

   double lastH = 0, lastL = 0, prevH = 0, prevL = 0;
   datetime lastHTime = 0, lastLTime = 0, prevHTime = 0, prevLTime = 0;

   for(int i=2; i<100; i++) {
      if(fractHigh[i] != 0 && fractHigh[i] != EMPTY_VALUE) {
         if(lastH == 0) { lastH = fractHigh[i]; lastHTime = times[i]; }
         else if(prevH == 0) { prevH = fractHigh[i]; prevHTime = times[i]; }
      }
      if(fractLow[i] != 0 && fractLow[i] != EMPTY_VALUE) {
         if(lastL == 0) { lastL = fractLow[i]; lastLTime = times[i]; }
         else if(prevL == 0) { prevL = fractLow[i]; prevLTime = times[i]; }
      }
      if(lastH != 0 && prevH != 0 && lastL != 0 && prevL != 0) break;
   }

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string structure = "NEUTRE";
   if(price > lastH) structure = "BOS HAUSSIER (Break of Structure)";
   else if(price < lastL) structure = "BOS BAISSIER (Break of Structure)";
   else if(lastH < prevH && lastL < prevL) structure = "TENDANCE BAISSIÈRE ÉTABLIE";
   else if(lastH > prevH && lastL > prevL) structure = "TENDANCE HAUSSIÈRE ÉTABLIE";

   //--- M30 Strong Movement Detection
   double m30High[], m30Low[];
   CopyHigh(_Symbol, PERIOD_M30, 0, 5, m30High);
   CopyLow(_Symbol, PERIOD_M30, 0, 5, m30Low);
   double avgRange = 0;
   for(int i=0; i<5; i++) avgRange += (m30High[i] - m30Low[i]);
   avgRange /= 5;

   double currentM30Range = (m30High[0] - m30Low[0]);
   string movement = "STABLE";
   if(currentM30Range > avgRange * 1.8) movement = "FORT MOUVEMENT DÉTECTÉ";

   //--- Final Trend Synthesis
   string finalTrend = (ma50[0] > ma200[0] && price > lastL) ? "HAUSSIÈRE" : "BAISSIÈRE";
   if(ma50[0] < ma200[0] && price < lastH) finalTrend = "BAISSIÈRE";

   string rsiText = DoubleToString(rsi[0], 1);
   if(rsi[0] > 70) rsiText += " (SURACHETÉ)";
   else if(rsi[0] < 30) rsiText += " (SURVENDU)";

   // FVG Info
   string fvg_str = "Aucun récent";
   if(latest_fvg.time > 0) {
      fvg_str = (latest_fvg.bull ? "HAUSSIER" : "BAISSIER") + " à " + DoubleToString(latest_fvg.bottom, _Digits);
   }

   string analysis = greeting +
                     "📈 STRUCTURE SWING : " + (swing_trend > 0 ? "BULLISH" : "BEARISH") + " (" + last_swing_ms.type + ")\n" +
                     "🔍 STRUCTURE INTERNE : " + (internal_trend > 0 ? "BULLISH" : "BEARISH") + " (" + last_internal_ms.type + ")\n" +
                     "🕯️ FAIR VALUE GAP : " + fvg_str + "\n" +
                     "💧 LIQUIDITÉ : " + liquidity + "\n" +
                     "📊 TENDANCE GÉNÉRALE : " + finalTrend + "\n" +
                     "⚡ MOUVEMENT M30 : " + movement + "\n" +
                     "🕒 RSI(14) : " + rsiText + "\n" +
                     "📉 TRENDLINE : " + (finalTrend == "HAUSSIÈRE" ? "Support ascendant" : "Résistance descendante") + " dessiné sur votre graphique.\n\n" +
                     "J'espère que cela vous aidera dans vos décisions, Monsieur. Je reste à votre entière disposition.";

   //--- Physical Drawing on Chart
   ObjectsDeleteAll(0, "GOAT_STRUCT_");
   if(lastH > 0) {
      ObjectCreate(0, "GOAT_STRUCT_H", OBJ_HLINE, 0, 0, lastH);
      ObjectSetInteger(0, "GOAT_STRUCT_H", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, "GOAT_STRUCT_H", OBJPROP_STYLE, STYLE_DOT);
   }
   if(lastL > 0) {
      ObjectCreate(0, "GOAT_STRUCT_L", OBJ_HLINE, 0, 0, lastL);
      ObjectSetInteger(0, "GOAT_STRUCT_L", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, "GOAT_STRUCT_L", OBJPROP_STYLE, STYLE_DOT);
   }

   // SMC Labels
   if(Show_SMC_Labels) {
      if(last_internal_ms.time > 0) {
         string name = "GOAT_STRUCT_INT_" + TimeToString(last_internal_ms.time, TIME_DATE|TIME_MINUTES);
         if(ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_TEXT, 0, last_internal_ms.time, last_internal_ms.price);
            ObjectSetString(0, name, OBJPROP_TEXT, "  i" + last_internal_ms.type);
            ObjectSetInteger(0, name, OBJPROP_COLOR, last_internal_ms.bull ? clrLime : clrRed);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
         }
      }
      if(last_swing_ms.time > 0) {
         string name = "GOAT_STRUCT_SWG_" + TimeToString(last_swing_ms.time, TIME_DATE|TIME_MINUTES);
         if(ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_TEXT, 0, last_swing_ms.time, last_swing_ms.price);
            ObjectSetString(0, name, OBJPROP_TEXT, "  " + last_swing_ms.type);
            ObjectSetInteger(0, name, OBJPROP_COLOR, last_swing_ms.bull ? clrLime : clrRed);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
            ObjectSetInteger(0, name, OBJPROP_FONT, "Arial Bold");
         }
      }
   }

   // Trendline based on actual fractal times
   // Trendline based on actual fractal times
   if(lastH > 0 && prevH > 0 && lastL > 0 && prevL > 0) {
      datetime t1 = (finalTrend == "HAUSSIÈRE") ? prevLTime : prevHTime;
      double p1 = (finalTrend == "HAUSSIÈRE") ? prevL : prevH;
      datetime t2 = (finalTrend == "HAUSSIÈRE") ? lastLTime : lastHTime;
      double p2 = (finalTrend == "HAUSSIÈRE") ? lastL : lastH;

      ObjectCreate(0, "GOAT_STRUCT_TL", OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, "GOAT_STRUCT_TL", OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, "GOAT_STRUCT_TL", OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, "GOAT_STRUCT_TL", OBJPROP_RAY_RIGHT, true);
   }

   return analysis;
}

//+------------------------------------------------------------------+
//| Send a screenshot of the current chart to Telegram               |
//+------------------------------------------------------------------+
void SendChartScreenshot()
{
   if(ext_Telegram_ChatID == 0) return;
   string filename = "GoatChart_" + _Symbol + ".png";
   if(!ChartScreenShot(0, filename, 1200, 800, ALIGN_RIGHT))
   {
      SendTelegramMessage("Error: Could not take screenshot.");
      return;
   }

   int handle = FileOpen(filename, FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      SendTelegramMessage("Error: Could not open screenshot file.");
      return;
   }

   int fileSize = (int)FileSize(handle);
   uchar photoData[];
   ArrayResize(photoData, fileSize);
   FileReadArray(handle, photoData);
   FileClose(handle);

   if(Telegram_Token == "" || ext_Telegram_ChatID == 0) return;

   string url = "https://api.telegram.org/bot" + Telegram_Token + "/sendPhoto";
   string boundary = "-------GoatBoundary" + IntegerToString((int)TimeCurrent());
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";

   string part1 = "--" + boundary + "\r\n" +
                  "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n" +
                  IntegerToString(ext_Telegram_ChatID) + "\r\n" +
                  "--" + boundary + "\r\n" +
                  "Content-Disposition: form-data; name=\"photo\"; filename=\"" + filename + "\"\r\n" +
                  "Content-Type: image/png\r\n\r\n";
   string part2 = "\r\n--" + boundary + "--\r\n";

   uchar part1Data[], part2Data[], fullData[];
   StringToCharArray(part1, part1Data, 0, StringLen(part1));
   StringToCharArray(part2, part2Data, 0, StringLen(part2));

   int totalSize = ArraySize(part1Data) + ArraySize(photoData) + ArraySize(part2Data);
   ArrayResize(fullData, totalSize);

   int offset = 0;
   ArrayCopy(fullData, part1Data, offset, 0, ArraySize(part1Data)); offset += ArraySize(part1Data);
   ArrayCopy(fullData, photoData, offset, 0, ArraySize(photoData)); offset += ArraySize(photoData);
   ArrayCopy(fullData, part2Data, offset, 0, ArraySize(part2Data));

   char result[];
   string resultHeaders;
   int res = WebRequest("POST", url, headers, 10000, fullData, result, resultHeaders);

   if(res == 200) Print("Screenshot sent successfully.");
   else Print("SendPhoto failed. Code: ", res, " Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Check for profit/loss targets set via Telegram                   |
//+------------------------------------------------------------------+
void CheckTargets()
{
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);

   if(ext_Target_Profit > 0 && profit >= ext_Target_Profit)
   {
      CloseAllPositions();
      SendTelegramMessage("Target Profit reached ($" + DoubleToString(profit, 2) + "). All positions closed.");
      ext_Target_Profit = 0;
   }

   if(ext_Target_Loss > 0 && profit <= -ext_Target_Loss)
   {
      CloseAllPositions();
      SendTelegramMessage("Target Loss reached (-$" + DoubleToString(MathAbs(profit), 2) + "). All positions closed.");
      ext_Target_Loss = 0;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on capital brackets                     |
//+------------------------------------------------------------------+
double CalculateLot()
{
   if(LotMode == FIXED_LOT) return Fixed_Lot;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lot = 0.01;

   if(balance >= 2 && balance <= 1000) lot = 0.01;
   else if(balance > 1000 && balance <= 5000) lot = 0.03;
   else if(balance > 5000 && balance <= 13000) lot = 0.05;
   else if(balance > 13000 && balance <= 50000) lot = 0.10;
   else if(balance > 50000 && balance <= 150000) lot = 0.50;
   else if(balance > 150000 && balance <= 350000) lot = 1.00;
   else if(balance > 350000 && balance <= 750000) lot = 3.00;
   else if(balance > 750000) lot = 3.00;

   // Respect broker constraints
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;

   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Close all open positions for the current symbol                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            trade.SetExpertMagicNumber(0); // Optional: filter by magic if needed
            if(!trade.PositionClose(ticket))
               Print("CloseAll FAILED for ticket ", ticket, ". Error: ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify an existing position's TP/SL                             |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   if(!OrderSend(request, result))
   {
      uint errorCode = GetLastError();
      if(errorCode != 0 && errorCode != 10025) // 10025 is no changes
         Print("ModifyPosition FAILED for ticket ", ticket, ". Error: ", errorCode);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Manage TP and SL for all open positions                          |
//+------------------------------------------------------------------+
void ManageTP_SL()
{
   int buyCount = 0;
   int sellCount = 0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipAdjust = (digits == 3 || digits == 5) ? 10.0 : 1.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double newTP = 0;
         double newSL = 0;

         if(type == POSITION_TYPE_BUY)
         {
            buyCount++;
            newSL = (TP_SL_Mode == PRICE_LEVEL) ? ext_Global_SL_Buy : (ext_Global_SL_Buy > 0 ? openPrice - ext_Global_SL_Buy * point * pipAdjust : 0);

            if(ext_Use_MultiLevel_TP)
            {
               if(buyCount <= ext_Trades_Level1 && ext_Trades_Level1 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_TP_Level1 : (ext_TP_Level1 > 0 ? openPrice + ext_TP_Level1 * point * pipAdjust : 0);
               else if(buyCount <= (ext_Trades_Level1 + ext_Trades_Level2) && ext_Trades_Level2 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_TP_Level2 : (ext_TP_Level2 > 0 ? openPrice + ext_TP_Level2 * point * pipAdjust : 0);
               else if(buyCount <= (ext_Trades_Level1 + ext_Trades_Level2 + ext_Trades_Level3) && ext_Trades_Level3 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_TP_Level3 : (ext_TP_Level3 > 0 ? openPrice + ext_TP_Level3 * point * pipAdjust : 0);
               else
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_Global_TP_Buy : (ext_Global_TP_Buy > 0 ? openPrice + ext_Global_TP_Buy * point * pipAdjust : 0);
            }
            else
            {
               newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_Global_TP_Buy : (ext_Global_TP_Buy > 0 ? openPrice + ext_Global_TP_Buy * point * pipAdjust : 0);
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            sellCount++;
            newSL = (TP_SL_Mode == PRICE_LEVEL) ? ext_Global_SL_Sell : (ext_Global_SL_Sell > 0 ? openPrice + ext_Global_SL_Sell * point * pipAdjust : 0);

            if(ext_Use_MultiLevel_TP)
            {
               if(sellCount <= ext_Trades_Level1 && ext_Trades_Level1 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_TP_Level1 : (ext_TP_Level1 > 0 ? openPrice - ext_TP_Level1 * point * pipAdjust : 0);
               else if(sellCount <= (ext_Trades_Level1 + ext_Trades_Level2) && ext_Trades_Level2 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_TP_Level2 : (ext_TP_Level2 > 0 ? openPrice - ext_TP_Level2 * point * pipAdjust : 0);
               else if(sellCount <= (ext_Trades_Level1 + ext_Trades_Level2 + ext_Trades_Level3) && ext_Trades_Level3 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_TP_Level3 : (ext_TP_Level3 > 0 ? openPrice - ext_TP_Level3 * point * pipAdjust : 0);
               else
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_Global_TP_Sell : (ext_Global_TP_Sell > 0 ? openPrice - ext_Global_TP_Sell * point * pipAdjust : 0);
            }
            else
            {
               newTP = (TP_SL_Mode == PRICE_LEVEL) ? ext_Global_TP_Sell : (ext_Global_TP_Sell > 0 ? openPrice - ext_Global_TP_Sell * point * pipAdjust : 0);
            }
         }

         newSL = NormalizeDouble(newSL, digits);
         newTP = NormalizeDouble(newTP, digits);

         if(MathAbs(currentSL - newSL) > point / 2.0 || MathAbs(currentTP - newTP) > point / 2.0)
         {
            ModifyPosition(ticket, newSL, newTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open a single order with enhanced compatibility                  |
//+------------------------------------------------------------------+
bool OpenOrder(ENUM_ORDER_TYPE type)
{
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return false;

   double lot = CalculateLot();
   double price = (type == ORDER_TYPE_BUY) ? last_tick.ask : last_tick.bid;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   trade.SetExpertMagicNumber(0);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol); // Auto-detect filling (IOC, FOK, etc.)

   // For some brokers, we must open with 0 SL/TP first (Market Execution)
   // trade.mqh handles this if we use its methods
   bool success = false;
   if(type == ORDER_TYPE_BUY)
      success = trade.Buy(lot, _Symbol, price, 0, 0, "GOAT TRADING");
   else
      success = trade.Sell(lot, _Symbol, price, 0, 0, "GOAT TRADING");

   if(!success)
   {
      Print("Trade Error: ", trade.ResultRetcodeDescription());
      return false;
   }

   // After opening, ManageTP_SL() will apply the correct targets in the next tick
   return true;
}

//+------------------------------------------------------------------+
//| Open multiple orders as defined in inputs                        |
//+------------------------------------------------------------------+
void OpenMultipleOrders()
{
   for(int i = 0; i < Buy_Count; i++)
   {
      OpenOrder(ORDER_TYPE_BUY);
   }
   for(int i = 0; i < Sell_Count; i++)
   {
      OpenOrder(ORDER_TYPE_SELL);
   }
   ordersExecuted = true;
}

//+------------------------------------------------------------------+
//| Helper to create UI Labels                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Update the dashboard on chart (Graphical UI)                     |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int totalBuy = 0;
   int totalSell = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) totalBuy++;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) totalSell++;
         }
      }
   }
   lastBuyCount = totalBuy;
   lastSellCount = totalSell;

   //--- Handle Cat Movement every 2 minutes
   if(TimeCurrent() - lastCatMove > 120)
   {
      lastCatMove = TimeCurrent();
      int move = (int)(MathRand() % 4);
      if(move == 0) { catOffsetX = 0; catOffsetY = 0; } // Reset
      else if(move == 1) { catOffsetX = 30; } // Shift
      else if(move == 2) { catOffsetY = 20; } // Down
      else if(move == 3) { catOffsetY = -20; } // Up
   }

   color catColor = clrGold;
   color textColor = clrWhite;
   color statusColor = ext_Bot_Active ? clrLime : clrRed;
   string statusText = ext_Bot_Active ? "ACTIVE" : "SLEEPING";

   //--- Draw Egyptian Cat (Left Upper Corner, Side View)
   string c[13];
   string tail = (TimeLocal() % 2 == 0) ? "~~ " : " ~ ";
   string eyes = "o   o";
   if(!ext_Bot_Active) {
      eyes = "-   -";
      string z = (TimeLocal() % 2 == 0) ? "z" : "Z";
      c[0] = "         |\\____/|               ";
      c[1] = "         /      \\               ";
      c[2] = "        (  " + eyes + "  )              ";
      c[3] = "         (   " + z + "    )              ";
      c[4] = "  _______/        \\_____________ ";
      c[5] = " /                              \\";
      c[6] = "|   GOAT EGYPTIAN MAINE COON     |";
      c[7] = "|      [STATUS: SLEEPING]        |";
      c[8] = " \\______________________________/ ";
      c[9] = "   (m__m)             (m__m) " + tail;
      c[10]= "   \\____/             \\____/     ";
      c[11]= "                                 ";
      c[12]= "                                 ";
   } else {
      int state = (int)((TimeLocal() / 30) % 4);
      if(state == 0) eyes = "u   u";
      else if(state == 1) eyes = "<   <";
      else if(state == 2) eyes = "o   o";
      else if(state == 3) eyes = ">   >";

      c[0] = "         |\\____/|               ";
      c[1] = "         /      \\               ";
      c[2] = "        (  " + eyes + "  )              ";
      c[3] = "         (   ^    )              ";
      c[4] = "  _______/        \\_____________ ";
      c[5] = " /                              \\";
      c[6] = "|   GOAT EGYPTIAN MAINE COON     |";
      c[7] = "|      [STATUS:  ACTIVE ]        |";
      c[8] = " \\______________________________/ ";
      c[9] = "   (m__m)             (m__m) " + tail;
      c[10]= "   \\____/             \\____/     ";
      c[11]= "                                 ";
      c[12]= "                                 ";
   }

   int xCat = 30 + catOffsetX;
   int yCat = 30 + catOffsetY;
   int cSpacing = 16;

   for(int i=0; i<11; i++)
      CreateLabel("CatLine"+IntegerToString(i), c[i], xCat, yCat + i*cSpacing, catColor, CORNER_LEFT_UPPER, 11, ANCHOR_LEFT_UPPER);

   //--- Draw Info (Right Upper Corner) - Scaled down
   int xInfo = 20;
   int yInfo = 20;
   int spacing = 24;
   CreateLabel("Title", "== GOAT TRADING ==", xInfo, yInfo, clrAqua, CORNER_RIGHT_UPPER, 18, ANCHOR_RIGHT_UPPER);
   CreateLabel("Status", "STATUS: " + statusText, xInfo, yInfo + spacing, statusColor, CORNER_RIGHT_UPPER, 14, ANCHOR_RIGHT_UPPER);
   CreateLabel("Balance", "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), xInfo, yInfo + spacing*2, textColor, CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);
   CreateLabel("Equity", "Equity:  " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), xInfo, yInfo + spacing*3, textColor, CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);
   CreateLabel("Profit", "Profit:  " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2), xInfo, yInfo + spacing*4, (AccountInfoDouble(ACCOUNT_PROFIT)>=0?clrLime:clrRed), CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);
   CreateLabel("Trades", "BUY["+IntegerToString(totalBuy)+"] SELL["+IntegerToString(totalSell)+"]", xInfo, yInfo + spacing*5, textColor, CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);
   CreateLabel("Lotting", "Lotting: " + ((LotMode==FIXED_LOT)?"FIXED":"AUTO"), xInfo, yInfo + spacing*6, textColor, CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);

   color telColor = (telegram_status == "CONNECTED") ? clrDeepSkyBlue : clrOrangeRed;
   CreateLabel("Telegram", "TELEGRAM: " + telegram_status, xInfo, yInfo + spacing*7, telColor, CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Cleanup UI Objects                                               |
//+------------------------------------------------------------------+
void CleanupUI()
{
   ObjectsDeleteAll(0, UI_PREFIX);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ext_Telegram_ChatID = Telegram_ChatID;

   // Initialize Indicator Handles
   handle_m15 = iCustom(_Symbol, PERIOD_M15, Custom_Indicator_Name);
   handle_m30 = iCustom(_Symbol, PERIOD_M30, Custom_Indicator_Name);
   handle_h1 = iCustom(_Symbol, PERIOD_H1, Custom_Indicator_Name);
   handle_atr = iATR(_Symbol, _Period, 14);

   // Initialize modifiable globals from inputs
   ext_Bot_Active = Bot_Active;
   ext_Use_MultiLevel_TP = Use_MultiLevel_TP;
   ext_TP_Level1 = TP_Level1; ext_Trades_Level1 = Trades_Level1;
   ext_TP_Level2 = TP_Level2; ext_Trades_Level2 = Trades_Level2;
   ext_TP_Level3 = TP_Level3; ext_Trades_Level3 = Trades_Level3;
   ext_Global_TP_Buy = Global_TP_Buy;
   ext_Global_SL_Buy = Global_SL_Buy;
   ext_Global_TP_Sell = Global_TP_Sell;
   ext_Global_SL_Sell = Global_SL_Sell;

   if(Telegram_Token != "" && Telegram_Polling_Sec > 0)
      EventSetTimer(Telegram_Polling_Sec);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   CleanupUI();
   IndicatorRelease(handle_m15);
   IndicatorRelease(handle_m30);
   IndicatorRelease(handle_h1);
   IndicatorRelease(handle_atr);
}

//+------------------------------------------------------------------+
//| Helper to check a single timeframe for alerts                    |
//+------------------------------------------------------------------+
void CheckSingleTFAlert(ENUM_TIMEFRAMES tf, int handle, datetime &lastAlertTime)
{
   if(handle == INVALID_HANDLE) return;

   double buy[], sell[];
   // Check BUY
   if(CopyBuffer(handle, Indicator_Buy_Buffer, 1, 1, buy) > 0 && buy[0] != 0 && buy[0] != EMPTY_VALUE)
   {
      datetime barTime = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
      if(barTime > lastAlertTime)
      {
         lastAlertTime = barTime;
         string msg = "🚨 SIGNAL D'ACHAT DÉTECTÉ (" + EnumToString(tf) + ")\n" +
                      "Indicateur: " + Custom_Indicator_Name + "\n" +
                      "Bonjour Monsieur, une opportunité se présente sur " + _Symbol + ".";
         SendTelegramMessage(msg);
      }
   }

   // Check SELL
   if(CopyBuffer(handle, Indicator_Sell_Buffer, 1, 1, sell) > 0 && sell[0] != 0 && sell[0] != EMPTY_VALUE)
   {
      datetime barTime = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
      if(barTime > lastAlertTime)
      {
         lastAlertTime = barTime;
         string msg = "🚨 SIGNAL DE VENTE DÉTECTÉ (" + EnumToString(tf) + ")\n" +
                      "Indicateur: " + Custom_Indicator_Name + "\n" +
                      "Bonjour Monsieur, le marché semble vouloir descendre sur " + _Symbol + ".";
         SendTelegramMessage(msg);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for automatic signals from lucky-reversal across timeframes|
//+------------------------------------------------------------------+
void CheckMTFAlerts()
{
   if(!Enable_MTF_Alerts) return;

   CheckSingleTFAlert(PERIOD_M15, handle_m15, last_alert_m15);
   CheckSingleTFAlert(PERIOD_M30, handle_m30, last_alert_m30);
   CheckSingleTFAlert(PERIOD_H1, handle_h1, last_alert_h1);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   FetchTelegramUpdates();
   CheckMTFAlerts();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDashboard();
   CheckTargets();

   if(!ext_Bot_Active)
   {
      if(PositionsTotal() > 0) CloseAllPositions();
      return;
   }

   ManageTP_SL();

   if(Execute_Orders)
   {
      if(!ordersExecuted)
      {
         bool canOpen = true;
         if(Only_If_No_Open_Trades && (lastBuyCount + lastSellCount) > 0)
         {
            canOpen = false;
         }

         if(canOpen)
         {
            OpenMultipleOrders();
         }
      }
   }
   else
   {
      ordersExecuted = false; // Réinitialise si désactivé
   }
}
