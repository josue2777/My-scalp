//+------------------------------------------------------------------+
//|                                                ScalpingRobot.mq5 |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

input group "=== Trading Inputs ==="
input double   RiskPercent = 5; //Risk as % of Trading Capital
input int      Tppoints = 200; //Take profit (10 points = 1 pip)
input int      Slpoints = 200; //Stoploss points (10 points = 1 pip)
input int      TslTriggerPoints = 15; //Points in profit before Trailing SL is activated (10 points = 1 pip)
input int      TslPoints = 10; //Trailing Stop loss (10 points = 1 pip)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; //Time frame to run
input int InpMagic = 123; //Expert advisor identification
input string TradeComment = "Scalping Robot";
input string ExpirationDate = "2026.03.14"; // Default changed to requested date

input group "=== Telegram Settings ==="
input string TelegramToken = ""; // API key Botfather !!!LEAVE EMPTY IN CODE - INSERT IN INPUTS!!!
input string TelegramChatID = ""; // Telegram group/channel chat ID !!!LEAVE EMPTY IN CODE - INSERT IN INPUTS!!!

enum StartHour { S_Inactive=0, S_0100=1, S_0200=2, S_0300=3, S_0400=4, S_0500=5, S_0600=6, S_0700=7, S_0800=8, S_0900=9, S_1000=10, S_1100=11, S_1200=12, S_1300=13, S_1400=14, S_1500=15, S_1600=16, S_1700=17, S_1800=18, S_1900=19, S_2000=20, S_2100=21, S_2200=22, S_2300=23 };
input StartHour SHInput = 8; //Start Hour

enum EndHour { E_Inactive=0, E_0100=1, E_0200=2, E_0300=3, E_0400=4, E_0500=5, E_0600=6, E_0700=7, E_0800=8, E_0900=9, E_1000=10, E_1100=11, E_1200=12, E_1300=13, E_1400=14, E_1500=15, E_1600=16, E_1700=17, E_1800=18, E_1900=19, E_2000=20, E_2100=21, E_2200=22, E_2300=23 };
input EndHour EHInput = 21; //End Hour

int SHchoice, EHChoice;
int BarsN = 5;
int ExpirationBars = 100;
int OrderDistPoints = 100;

struct TradeTracking
  {
   ulong             ticket;
   bool              notified;
  };

TradeTracking trackedPositions[];
TradeTracking trackedOrders[];

string UI_PREFIX = "GOAT_UI_";

//+------------------------------------------------------------------+
//| Check if the EA has expired                                      |
//+------------------------------------------------------------------+
bool IsExpired()
{
   return (TimeCurrent() >= StringToTime(ExpirationDate));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(IsExpired())
   {
      Alert("❌ License expired (March 14, 2026)");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   string startMsg = "🤖 *Trading Bot Started*\n\n";
   startMsg += "Symbol: " + _Symbol + "\n";
   startMsg += "Timeframe: " + EnumToString(Timeframe) + "\n";
   startMsg += "Magic: " + IntegerToString(InpMagic) + "\n";
   startMsg += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
   startMsg += "TP: " + IntegerToString(Tppoints) + " | SL: " + IntegerToString(Slpoints) + "\n";
   startMsg += "Trading Hours: " + IntegerToString(SHInput) + ":00 - " + IntegerToString(EHInput) + ":00";

   SendTelegramMessage(startMsg);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   CleanupUI();

   string msg = "⚠️ *Bot Stopped*\n\n";
   msg += "Reason: ";

   switch(reason)
     {
      case REASON_PROGRAM:
         msg += "Program terminated";
         break;
      case REASON_REMOVE:
         msg += "EA removed from chart";
         break;
      case REASON_RECOMPILE:
         msg += "EA recompiled";
         break;
      case REASON_CHARTCHANGE:
         msg += "Symbol/timeframe changed";
         break;
      case REASON_CHARTCLOSE:
         msg += "Chart closed";
         break;
      case REASON_PARAMETERS:
         msg += "Parameters changed";
         break;
      case REASON_ACCOUNT:
         msg += "Account changed";
         break;
      case REASON_TEMPLATE:
         msg += "Template loaded";
         break;
      case REASON_INITFAILED:
         msg += "Initialization failed";
         break;
      case REASON_CLOSE:
         msg += "Terminal closed";
         break;
      default:
         msg += "Unknown (" + IntegerToString(reason) + ")";
     }

   SendTelegramMessage(msg);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(IsExpired())
   {
      CloseAllOrders(); // Close pending orders
      // Close active positions
      for(int i = PositionsTotal()-1; i>=0; i--)
      {
         if(pos.SelectByIndex(i))
         {
            if(pos.Magic()==InpMagic && pos.Symbol()==_Symbol)
               trade.PositionClose(pos.Ticket());
         }
      }
      UpdateDashboard();
      Alert("❌ License expired during operation. Stopping...");
      ExpertRemove();
      return;
   }

   TrailStop();
   CheckTradeEvents();
   UpdateDashboard();

   if(!IsNewBar())
      return;

   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   int Hournow = time.hour;

   SHchoice = SHInput;
   EHChoice = EHInput;

   if(Hournow < SHchoice)
     {
      CloseAllOrders();
      return;
     }
   if(Hournow >= EHChoice && EHChoice != 0)
     {
      CloseAllOrders();
      return;
     }

   int BuyTotal=0;
   int SellTotal=0;

   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      pos.SelectByIndex(i);
      if(pos.PositionType()==POSITION_TYPE_BUY && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
         BuyTotal++;
      if(pos.PositionType()==POSITION_TYPE_SELL && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
         SellTotal++;
     }

   for(int i = OrdersTotal()-1; i>=0; i--)
     {
      ord.SelectByIndex(i);
      if(ord.OrderType()==ORDER_TYPE_BUY_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
         BuyTotal++;
      if(ord.OrderType()==ORDER_TYPE_SELL_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
         SellTotal++;
     }

   if(BuyTotal <= 0)
     {
      double high = findHigh();
      if(high > 0)
         SendBuyOrder(high);
     }
   if(SellTotal <= 0)
     {
      double low = findLow();
      if(low > 0)
         SendSellOrder(low);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckTradeEvents()
  {
   CheckNewPositions();
   CheckClosedPositions();
   CheckNewOrders();
   CheckDeletedOrders();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckNewPositions()
  {
   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         if(pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
           {
            ulong ticket = pos.Ticket();

            if(!IsPositionTracked(ticket))
              {
               AddTrackedPosition(ticket);

               string msg = "✅ *Trade Opened*\n\n";
               msg += "Symbol: " + pos.Symbol() + "\n";
               msg += "Type: " + (pos.PositionType()==POSITION_TYPE_BUY ? "BUY 🟢" : "SELL 🔴") + "\n";
               msg += "Entry: " + DoubleToString(pos.PriceOpen(), _Digits) + "\n";
               msg += "Lots: " + DoubleToString(pos.Volume(), 2) + "\n";
               msg += "SL: " + DoubleToString(pos.StopLoss(), _Digits) + "\n";
               msg += "TP: " + DoubleToString(pos.TakeProfit(), _Digits) + "\n";
               msg += "Ticket: " + IntegerToString(ticket);

               SendTelegramMessage(msg);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckClosedPositions()
  {
   for(int i = ArraySize(trackedPositions)-1; i>=0; i--)
     {
      bool found = false;

      for(int j = PositionsTotal()-1; j>=0; j--)
        {
         if(pos.SelectByIndex(j))
           {
            if(pos.Ticket() == trackedPositions[i].ticket)
              {
               found = true;
               break;
              }
           }
        }

      if(!found)
        {
         ulong ticket = trackedPositions[i].ticket;

         if(HistorySelectByPosition(ticket))
           {
            for(int h = HistoryDealsTotal()-1; h>=0; h--)
              {
               ulong dealTicket = HistoryDealGetTicket(h);

               if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
                 {
                  double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                  double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

                  string msg = (profit >= 0 ? "💰 *Trade Closed - Profit*\n\n" : "❌ *Trade Closed - Loss*\n\n");
                  msg += "Ticket: " + IntegerToString(ticket) + "\n";
                  msg += "Exit: " + DoubleToString(price, _Digits) + "\n";
                  msg += "Lots: " + DoubleToString(volume, 2) + "\n";
                  msg += "P/L: " + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
                  msg += "Reason: " + GetDealReasonText(reason);

                  SendTelegramMessage(msg);
                  break;
                 }
              }
           }

         RemoveTrackedPosition(i);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckNewOrders()
  {
   for(int i = OrdersTotal()-1; i>=0; i--)
     {
      if(ord.SelectByIndex(i))
        {
         if(ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
           {
            ulong ticket = ord.Ticket();

            if(!IsOrderTracked(ticket))
              {
               AddTrackedOrder(ticket);

               string msg = "📝 *New Pending Order*\n\n";
               msg += "Symbol: " + ord.Symbol() + "\n";
               msg += "Type: " + GetOrderTypeText(ord.OrderType()) + "\n";
               msg += "Entry: " + DoubleToString(ord.PriceOpen(), _Digits) + "\n";
               msg += "Lots: " + DoubleToString(ord.VolumeInitial(), 2) + "\n";
               msg += "SL: " + DoubleToString(ord.StopLoss(), _Digits) + "\n";
               msg += "TP: " + DoubleToString(ord.TakeProfit(), _Digits) + "\n";
               msg += "Expiry: " + TimeToString(ord.TimeExpiration()) + "\n";
               msg += "Ticket: " + IntegerToString(ticket);

               SendTelegramMessage(msg);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckDeletedOrders()
  {
   for(int i = ArraySize(trackedOrders)-1; i>=0; i--)
     {
      bool found = false;

      for(int j = OrdersTotal()-1; j>=0; j--)
        {
         if(ord.SelectByIndex(j))
           {
            if(ord.Ticket() == trackedOrders[i].ticket)
              {
               found = true;
               break;
              }
           }
        }

      if(!found)
        {
         ulong ticket = trackedOrders[i].ticket;

         string msg = "🗑️ *Order Deleted*\n\n";
         msg += "Ticket: " + IntegerToString(ticket) + "\n";

         if(HistoryOrderSelect(ticket))
           {
            ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
            msg += "Reason: " + GetOrderStateText(state);
           }
         else
           {
            msg += "Reason: Order not found in history";
           }

         SendTelegramMessage(msg);
         RemoveTrackedOrder(i);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetOrderTypeText(ENUM_ORDER_TYPE type)
  {
   switch(type)
     {
      case ORDER_TYPE_BUY_STOP:
         return "BUY STOP 🟢🔼";
      case ORDER_TYPE_SELL_STOP:
         return "SELL STOP 🔴🔽";
      case ORDER_TYPE_BUY_LIMIT:
         return "BUY LIMIT 🟢🔽";
      case ORDER_TYPE_SELL_LIMIT:
         return "SELL LIMIT 🔴🔼";
      default:
         return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetDealReasonText(ENUM_DEAL_REASON reason)
  {
   switch(reason)
     {
      case DEAL_REASON_SL:
         return "Stop Loss";
      case DEAL_REASON_TP:
         return "Take Profit";
      case DEAL_REASON_SO:
         return "Stop Out";
      case DEAL_REASON_EXPERT:
         return "EA Closed";
      default:
         return "Manual/Other";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetOrderStateText(ENUM_ORDER_STATE state)
  {
   switch(state)
     {
      case ORDER_STATE_CANCELED:
         return "Canceled";
      case ORDER_STATE_EXPIRED:
         return "Expired";
      case ORDER_STATE_FILLED:
         return "Filled";
      case ORDER_STATE_REJECTED:
         return "Rejected";
      default:
         return "Unknown";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPositionTracked(ulong ticket)
  {
   for(int i=0; i<ArraySize(trackedPositions); i++)
     {
      if(trackedPositions[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsOrderTracked(ulong ticket)
  {
   for(int i=0; i<ArraySize(trackedOrders); i++)
     {
      if(trackedOrders[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddTrackedPosition(ulong ticket)
  {
   int size = ArraySize(trackedPositions);
   ArrayResize(trackedPositions, size+1);
   trackedPositions[size].ticket = ticket;
   trackedPositions[size].notified = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddTrackedOrder(ulong ticket)
  {
   int size = ArraySize(trackedOrders);
   ArrayResize(trackedOrders, size+1);
   trackedOrders[size].ticket = ticket;
   trackedOrders[size].notified = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RemoveTrackedPosition(int index)
  {
   int size = ArraySize(trackedPositions);
   if(index < 0 || index >= size)
      return;

   for(int i=index; i<size-1; i++)
     {
      trackedPositions[i] = trackedPositions[i+1];
     }
   ArrayResize(trackedPositions, size-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RemoveTrackedOrder(int index)
  {
   int size = ArraySize(trackedOrders);
   if(index < 0 || index >= size)
      return;

   for(int i=index; i<size-1; i++)
     {
      trackedOrders[i] = trackedOrders[i+1];
     }
   ArrayResize(trackedOrders, size-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendTelegramMessage(string text)
  {
   if(TelegramToken == "" || TelegramChatID == "")
     {
      Print("Telegram not configured!");
      return;
     }

   string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";

   string postData = "chat_id=" + TelegramChatID + "&text=" + text + "&parse_mode=Markdown";

   char data[];
   char result[];
   string headers;

   ArrayResize(data, StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8)-1);

   int res = WebRequest("POST", url, NULL, NULL, 5000, data, 0, result, headers);

   if(res == -1)
     {
      Print("WebRequest error: ", GetLastError());
      Print("Enable URL in MT5: Tools -> Options -> Expert Advisors -> Allow WebRequest for URL: https://api.telegram.org");
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double findHigh()
  {
   double highestHigh = 0;
   for(int i = 0; i < 200; i++)
     {
      double high = iHigh(_Symbol, Timeframe, i);
      if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*2+1, i-BarsN) == i)
        {
         if(high > highestHigh)
           {
            return high;
           }
        }
      highestHigh = MathMax(high, highestHigh);
     }
   return -1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double findLow()
  {
   double lowestLow = DBL_MAX;
   for(int i = 0; i < 200; i++)
     {
      double low = iLow(_Symbol, Timeframe, i);
      if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i)
        {
         if(low > lowestLow)
           {
            return low;
           }
        }
      lowestLow = MathMin(low, lowestLow);
     }
   return -1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, Timeframe, 0);
   if(previousTime != currentTime)
     {
      previousTime = currentTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendBuyOrder(double entry)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask > entry - OrderDistPoints * _Point)
      return;

   double tp = entry + Tppoints * _Point;
   double sl = entry - Slpoints * _Point;
   double lots = 0.01;

   if(RiskPercent > 0)
      lots = calcLots(entry-sl);

   datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);

   trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendSellOrder(double entry)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid < entry + OrderDistPoints * _Point)
      return;

   double tp = entry - Tppoints * _Point;
   double sl = entry + Slpoints * _Point;
   double lots = 0.01;

   if(RiskPercent > 0)
      lots = calcLots(sl - entry);

   datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);

   trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double calcLots(double slPoints)
  {
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;

   double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double loststep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minvolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxvolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double volumelimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   double moneyPerLotstep = slPoints / ticksize * tickvalue * loststep;
   double lots = MathFloor(risk / moneyPerLotstep) * loststep;

   if(volumelimit != 0)
      lots = MathMin(lots, volumelimit);
   if(maxvolume != 0)
      lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   if(minvolume != 0)
      lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   lots = NormalizeDouble(lots, 2);

   return lots;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   int deletedCount = 0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ord.SelectByIndex(i);
      ulong ticket = ord.Ticket();
      if(ord.Symbol() == _Symbol && ord.Magic() == InpMagic)
        {
         if(trade.OrderDelete(ticket))
            deletedCount++;
        }
     }

   if(deletedCount > 0)
     {
      string msg = "🕒 *Trading Hours Ended*\n\n";
      msg += "Orders Deleted: " + IntegerToString(deletedCount);
      SendTelegramMessage(msg);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TrailStop()
  {
   double sl = 0;
   double tp = 0;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         ulong ticket = pos.Ticket();
         double oldSL = pos.StopLoss();

         if(pos.Magic()==InpMagic && pos.Symbol()==_Symbol)
           {
            if(pos.PositionType()==POSITION_TYPE_BUY)
              {
               if(bid-pos.PriceOpen()>TslTriggerPoints*_Point)
                 {
                  tp=pos.TakeProfit();
                  sl=bid-(TslPoints*_Point);

                  if(sl > pos.StopLoss() && sl!=0)
                    {
                     if(trade.PositionModify(ticket, sl, tp))
                       {
                        string msg = "🔄 *Trailing Stop Activated*\n\n";
                        msg += "Ticket: " + IntegerToString(ticket) + "\n";
                        msg += "New SL: " + DoubleToString(sl, _Digits);
                        SendTelegramMessage(msg);
                       }
                    }
                 }
              }
            else
               if(pos.PositionType()==POSITION_TYPE_SELL)
                 {
                  if(ask+(TslTriggerPoints*_Point)<pos.PriceOpen())
                    {
                     tp = pos.TakeProfit();
                     sl = ask + (TslPoints * _Point);
                     if(sl<pos.StopLoss() && sl!=0)
                       {
                        if(trade.PositionModify(ticket,sl,tp))
                          {
                           string msg = "🔄 *Trailing Stop Activated*\n\n";
                           msg += "Ticket: " + IntegerToString(ticket) + "\n";
                           msg += "New SL: " + DoubleToString(sl, _Digits);
                           SendTelegramMessage(msg);
                          }
                       }
                    }
                 }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Dashboard Helpers                                                |
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

void CreateRect(string name, int x, int y, int width, int height, color clr, ENUM_BASE_CORNER corner, int border=1)
{
   string objName = UI_PREFIX + name;
   if(ObjectFind(0, objName) < 0)
      ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, border);
}

void CleanupUI()
{
   ObjectsDeleteAll(0, UI_PREFIX);
}

void UpdateDashboard()
{
   int totalBuy = 0;
   int totalSell = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == InpMagic && pos.Symbol() == _Symbol)
      {
         if(pos.PositionType() == POSITION_TYPE_BUY) totalBuy++;
         else totalSell++;
      }
   }

   string statusText = "ACTIVE";
   color statusColor = clrLime;
   if(IsExpired())
   {
      statusText = "EXPIRED";
      statusColor = clrRed;
   }

   //--- Draw Magnificent Data Table (Right Upper Corner)
   int xTable = 20;
   int yTable = 20;
   int width = 280;
   int rowHeight = 22;
   int rows = 9;
   int headerHeight = 30;

   // Calculate Today's Profit
   double dailyProfit = 0;
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
         dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }

   double floatingProfit = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == InpMagic && pos.Symbol() == _Symbol)
         floatingProfit += pos.Profit();
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = (balance > 0) ? (MathAbs(floatingProfit) / balance) * 100.0 : 0;
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Background & Header
   CreateRect("TableBG", xTable, yTable, width, headerHeight + (rows * rowHeight) + 10, C'30,30,30', CORNER_RIGHT_UPPER);
   CreateRect("TableHeader", xTable, yTable, width, headerHeight, clrGold, CORNER_RIGHT_UPPER);
   CreateLabel("TableTitle", "SCALPING ROBOT SYSTEMS", xTable + 140, yTable + 5, clrBlack, CORNER_RIGHT_UPPER, 12, ANCHOR_RIGHT_UPPER);

   // Data Rows
   int curY = yTable + headerHeight + 5;
   int xCol1 = xTable + 260;
   int xCol2 = xTable + 20;

   CreateLabel("L_Status", "STATUS:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Status", statusText, xCol2, curY, statusColor, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_Balance", "BALANCE:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Balance", DoubleToString(balance, 2) + " $", xCol2, curY, clrGold, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_Equity", "EQUITY:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Equity", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + " $", xCol2, curY, clrGold, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_DProfit", "TODAY PROFIT:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_DProfit", DoubleToString(dailyProfit, 2) + " $", xCol2, curY, (dailyProfit >= 0 ? clrLime : clrRed), CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_FProfit", "FLOATING P/L:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_FProfit", DoubleToString(floatingProfit, 2) + " $", xCol2, curY, (floatingProfit >= 0 ? clrLime : clrRed), CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_Drawdown", "DRAWDOWN:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Drawdown", DoubleToString(drawdown, 2) + " %", xCol2, curY, (drawdown > 5 ? clrOrange : clrGold), CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_Positions", "POSITIONS:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Positions", "B:" + IntegerToString(totalBuy) + " S:" + IntegerToString(totalSell), xCol2, curY, clrAqua, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_Risk", "RISK:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Risk", DoubleToString(RiskPercent, 1) + " %", xCol2, curY, clrGold, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   curY += rowHeight;

   CreateLabel("L_Spread", "SPREAD:", xCol1, curY, clrWhite, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);
   CreateLabel("V_Spread", DoubleToString(spread, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), xCol2, curY, clrGold, CORNER_RIGHT_UPPER, 10, ANCHOR_RIGHT_UPPER);

   ChartRedraw();
}
