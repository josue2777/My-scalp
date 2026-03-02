//+------------------------------------------------------------------+
//|                                                GoatTrading.mq5   |
//|                                  Copyright 2023, GOAT TRADING    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, GOAT TRADING"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

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
input string Telegram_Token = "8233885509:AAG73gHOq-yWIkeHWDPhKhq2Rw9lCyj2GjE"; // Telegram Bot Token
input long Telegram_ChatID = 7505313544; // Telegram Chat ID
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

//--- Global Variables
bool ordersExecuted = false;
int lastBuyCount = 0;
int lastSellCount = 0;
long last_telegram_update_id = 0;

//--- Modifiable Global States (initialized from inputs)
bool ext_Bot_Active;
double ext_Global_TP_Buy, ext_Global_SL_Buy;
double ext_Global_TP_Sell, ext_Global_SL_Sell;

//+------------------------------------------------------------------+
//| Send a message to Telegram                                       |
//+------------------------------------------------------------------+
void SendTelegramMessage(string message)
{
   if(Telegram_Token == "" || Telegram_ChatID == 0) return;

   string url = "https://api.telegram.org/bot" + Telegram_Token + "/sendMessage";
   string payload = "chat_id=" + IntegerToString(Telegram_ChatID) + "&text=" + message;
   char data[], result[];
   string headers;

   StringToCharArray(payload, data);

   int res = WebRequest("POST", url, NULL, 5000, data, result, headers);

   if(res == -1)
      Print("WebRequest Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Fetch new messages from Telegram                                 |
//+------------------------------------------------------------------+
void FetchTelegramUpdates()
{
   if(Telegram_Token == "") return;

   string url = "https://api.telegram.org/bot" + Telegram_Token + "/getUpdates?offset=" + IntegerToString(last_telegram_update_id + 1);
   char data[], result[];
   string headers;

   int res = WebRequest("GET", url, NULL, 5000, data, result, headers);

   if(res == 200)
   {
      string response = CharArrayToString(result);

      // Look for multiple messages in response
      int msgPos = StringFind(response, "\"text\"");
      while(msgPos != -1)
      {
         string updateIdStr = StringExtract(response, "\"update_id\"");
         if(updateIdStr != "") last_telegram_update_id = StringToInteger(updateIdStr);

         string text = StringExtract(response, "\"text\"");
         if(text != "") ProcessTelegramCommand(text);

         // Move to next message if any (simplified)
         response = StringSubstr(response, msgPos + 6);
         msgPos = StringFind(response, "\"text\"");
      }
   }
}

//+------------------------------------------------------------------+
//| Simple string parsing helper                                     |
//+------------------------------------------------------------------+
string StringExtract(string source, string key)
{
   int pos = StringFind(source, key);
   if(pos == -1) return "";

   int start = pos + StringLen(key);
   // Skip colon and quotes
   while(start < StringLen(source) && (StringSubstr(source, start, 1) == ":" || StringSubstr(source, start, 1) == " " || StringSubstr(source, start, 1) == "\""))
      start++;

   int end = start;
   // If it's a string value, find closing quote
   if(StringFind(source, "\"", pos + StringLen(key)) != -1 && StringFind(source, "\"", pos + StringLen(key)) < StringFind(source, ",", pos + StringLen(key)))
   {
      end = StringFind(source, "\"", start);
   }
   else // numeric value
   {
      end = StringFind(source, ",", start);
      int endBracket = StringFind(source, "}", start);
      if(end == -1 || (endBracket != -1 && endBracket < end)) end = endBracket;
   }

   if(end == -1) return "";

   string val = StringSubstr(source, start, end - start);
   return val;
}

//+------------------------------------------------------------------+
//| Parse and execute Telegram commands                              |
//+------------------------------------------------------------------+
void ProcessTelegramCommand(string text)
{
   StringReplace(text, "+", " "); // Decode spaces if needed
   StringToUpper(text);

   bool handled = false;
   string reply = "Command not recognized.";

   // Commands: TP BUY [val], TP SELL [val], SL BUY [val], SL SELL [val], CLOSE, ACTIF [true/false]
   if(StringFind(text, "TP BUY") != -1)
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
   else if(StringFind(text, "FERMER") != -1 || StringFind(text, "CLOSE") != -1)
   {
      CloseAllPositions();
      reply = "All positions closed.";
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
      reply = "Bot deactivated and trades closed.";
      handled = true;
   }

   if(handled)
      SendTelegramMessage(reply);
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
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double volume = PositionGetDouble(POSITION_VOLUME);
            double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = volume;
            request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = price;
            request.deviation = 10;
            request.comment = "CLOSE ALL (GOAT)";
            request.type_filling = ORDER_FILLING_IOC;

            if(!OrderSend(request, result))
               Print("CloseAll FAILED for ticket ", ticket, ". Error: ", GetLastError());
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

            if(Use_MultiLevel_TP)
            {
               if(buyCount <= Trades_Level1 && Trades_Level1 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? TP_Level1 : (TP_Level1 > 0 ? openPrice + TP_Level1 * point * pipAdjust : 0);
               else if(buyCount <= (Trades_Level1 + Trades_Level2) && Trades_Level2 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? TP_Level2 : (TP_Level2 > 0 ? openPrice + TP_Level2 * point * pipAdjust : 0);
               else if(buyCount <= (Trades_Level1 + Trades_Level2 + Trades_Level3) && Trades_Level3 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? TP_Level3 : (TP_Level3 > 0 ? openPrice + TP_Level3 * point * pipAdjust : 0);
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

            if(Use_MultiLevel_TP)
            {
               if(sellCount <= Trades_Level1 && Trades_Level1 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? TP_Level1 : (TP_Level1 > 0 ? openPrice - TP_Level1 * point * pipAdjust : 0);
               else if(sellCount <= (Trades_Level1 + Trades_Level2) && Trades_Level2 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? TP_Level2 : (TP_Level2 > 0 ? openPrice - TP_Level2 * point * pipAdjust : 0);
               else if(sellCount <= (Trades_Level1 + Trades_Level2 + Trades_Level3) && Trades_Level3 > 0)
                  newTP = (TP_SL_Mode == PRICE_LEVEL) ? TP_Level3 : (TP_Level3 > 0 ? openPrice - TP_Level3 * point * pipAdjust : 0);
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
//| Open a single order                                              |
//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   double lot = CalculateLot();
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipAdjust = (digits == 3 || digits == 5) ? 10.0 : 1.0;

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = type;
   request.price = price;
   request.deviation = 10;
   request.comment = "GOAT TRADING";
   request.type_filling = ORDER_FILLING_IOC;

   double sl = 0, tp = 0;
   if(type == ORDER_TYPE_BUY)
   {
      if(TP_SL_Mode == PRICE_LEVEL)
      {
         sl = ext_Global_SL_Buy;
         tp = ext_Global_TP_Buy;
      }
      else
      {
         if(ext_Global_SL_Buy > 0) sl = price - ext_Global_SL_Buy * point * pipAdjust;
         if(ext_Global_TP_Buy > 0) tp = price + ext_Global_TP_Buy * point * pipAdjust;
      }
   }
   else
   {
      if(TP_SL_Mode == PRICE_LEVEL)
      {
         sl = ext_Global_SL_Sell;
         tp = ext_Global_TP_Sell;
      }
      else
      {
         if(ext_Global_SL_Sell > 0) sl = price + ext_Global_SL_Sell * point * pipAdjust;
         if(ext_Global_TP_Sell > 0) tp = price - ext_Global_TP_Sell * point * pipAdjust;
      }
   }

   request.sl = NormalizeDouble(sl, digits);
   request.tp = NormalizeDouble(tp, digits);

   if(!OrderSend(request, result))
      Print("OrderSend FAILED. Error: ", GetLastError());
   else
      Print("Trade successful. Ticket: ", result.deal);
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
//| Update the dashboard on chart                                    |
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

   string lotStr = (LotMode == FIXED_LOT) ? "FIXED_LOT" : "AUTO_RISK";

   string dashboard = "--- GOAT TRADING DASHBOARD ---\n";
   dashboard += "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   dashboard += "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   dashboard += "Profit: " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "\n";
   dashboard += "Total BUY: " + IntegerToString(totalBuy) + "\n";
   dashboard += "Total SELL: " + IntegerToString(totalSell) + "\n";
   dashboard += "Lot Mode: " + lotStr;

   Comment(dashboard);

   lastBuyCount = totalBuy;
   lastSellCount = totalSell;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize modifiable globals from inputs
   ext_Bot_Active = Bot_Active;
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
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   FetchTelegramUpdates();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!ext_Bot_Active)
   {
      if(PositionsTotal() > 0) CloseAllPositions();
      Comment("GOAT TRADING: EA DISABLED - TRADES CLOSED");
      return;
   }

   UpdateDashboard();
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
