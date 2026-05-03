//+------------------------------------------------------------------+
//|                                           GridEA_Autonomous.mq4 |
//|       Copyright 2018, Valentinos Galanos <sonidelav@hotmail.com> |
//|       Reconfigured by Jules - Software Engineer                  |
//+------------------------------------------------------------------+
#define ver "2.00-REVERSED"
#property copyright "Copyright 2018, Valentinos Galanos <sonidelav@hotmail.com>"
#property version   ver
#property strict


//--- Includes
#include <Arrays\ArrayObj.mqh>
#include <Object.mqh>
#include <ChartObjects\ChartObjectsLines.mqh>


//--- input parameters
input group "=== Grid Settings ==="
input int      GridGap          =   50;             // Grid Gap (Pips)
input double   LotSize          =   0.01;           // Trade Lot Volume
input int      TotalGridLines   =   7;              // Total Grid Lines Each Side
input int      MagicNumber      =   888;            // Magic Number


input group "=== Telegram Settings ==="
input string   TelegramToken    =   "";             // Telegram Bot Token
input string   TelegramChatID   =   "";             // Telegram Chat ID


//+------------------------------------------------------------------+
//| CGridLine Class                                                  |
//+------------------------------------------------------------------+
class CGridLine : public CObject
{
private:
    CChartObjectHLine   *m_chartGridLineObj;    // GRAPH HORIZONTAL LINE

    double  m_price;                            // PRICE OF GRID LINE
    string  m_name;                             // NAME OF LINE
    color   m_lineColor;                        // LINE COLOR

    ENUM_ORDER_TYPE m_direction;                // DIRECTION (OP_BUY or OP_SELL)
    bool    m_ordersExecuted;                   // MARKET EXECUTED
    bool    m_reached;                          // REACH STATE

    int     m_magic;                            // MAGIC NUMBER
    int     m_gridGap;                          // GRID GAP (PIPS)
    double  m_lotSize;                          // LOT VOLUME

    double  m_point;                            // SYMBOL POINT


public:
    CGridLine(double dPrice, string sName, color clLineColor, ENUM_ORDER_TYPE eDirection, bool bWithoutOrders, int magic, int gridGap, double lotSize);
    ~CGridLine();

    double  GetClosePrice();
    bool    HasBeenReached();
    bool    HasBeenReachedClosePrice();
    void    MarketExecutionOrders();

    double  GetPrice() { return m_price; }
    bool    IsExecuted() { return m_ordersExecuted; }
    void    SetExecuted(bool state) { m_ordersExecuted = state; }
};


CGridLine::CGridLine(double dPrice, string sName, color clLineColor, ENUM_ORDER_TYPE eDirection, bool bWithoutOrders, int magic, int gridGap, double lotSize)
{
    m_price             = dPrice;
    m_name              = sName;
    m_lineColor         = clLineColor;
    m_direction         = eDirection;
    m_ordersExecuted    = bWithoutOrders;
    m_reached           = false;
    m_magic             = magic;
    m_gridGap           = gridGap;
    m_lotSize           = lotSize;

    m_point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    if(digits == 3 || digits == 5) m_point *= 10;

    m_chartGridLineObj = new CChartObjectHLine();
    if(m_chartGridLineObj.Create(0, m_name, 0, m_price))
    {
        m_chartGridLineObj.Color(m_lineColor);
        m_chartGridLineObj.Background(true);
        m_chartGridLineObj.Description(m_name);
        m_chartGridLineObj.Selectable(false);
        m_chartGridLineObj.Hidden(false);
        m_chartGridLineObj.Width(1);
    }
}


CGridLine::~CGridLine()
{
    if(CheckPointer(m_chartGridLineObj) != POINTER_INVALID)
        delete m_chartGridLineObj;
}


double CGridLine::GetClosePrice()
{
    // Reconfigured Logic:
    // OP_SELL is used for Above lines (trigger when bid >= price, reset when bid <= price - gap)
    // OP_BUY is used for Below lines (trigger when bid <= price, reset when bid >= price + gap)
    if(m_direction == OP_SELL) return m_price - (m_gridGap * m_point);
    else return m_price + (m_gridGap * m_point);
}


bool CGridLine::HasBeenReached()
{
    if(m_reached) return false;
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    // Reconfigured Logic:
    if(m_direction == OP_SELL) { // Above
        if(bid >= m_price) { m_reached = true; return true; }
    } else { // Below (OP_BUY)
        if(bid <= m_price) { m_reached = true; return true; }
    }
    return false;
}


bool CGridLine::HasBeenReachedClosePrice()
{
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    // Reconfigured Logic:
    if(m_direction == OP_SELL) return bid <= GetClosePrice(); // Above resets below
    else return bid >= GetClosePrice(); // Below resets above
}


void CGridLine::MarketExecutionOrders()
{
    if(m_ordersExecuted) return;
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    string comment = StringFormat("GRID|%G", m_price);
    ResetLastError();

    bool isEntry = (m_name == "GridLine Entry");

    // Reconfigured logic: Open BUY at Below levels, SELL at Above levels.
    // Entry opens both to maintain initial hedge.
    if(m_direction == OP_BUY || isEntry)
    {
        double tp_buy = m_price + (m_gridGap * m_point);
        int tB = OrderSend(Symbol(), OP_BUY, m_lotSize, ask, 3, 0, tp_buy, comment, m_magic, 0, clrBlue);
        if(tB < 0) Print("Error opening BUY order: ", GetLastError());
    }

    if(m_direction == OP_SELL || isEntry)
    {
        double tp_sell = m_price - (m_gridGap * m_point);
        int tS = OrderSend(Symbol(), OP_SELL, m_lotSize, bid, 3, 0, tp_sell, comment, m_magic, 0, clrRed);
        if(tS < 0) Print("Error opening SELL order: ", GetLastError());
    }

    m_ordersExecuted = true;
}


//+------------------------------------------------------------------+
//| CGridExpert Class                                                |
//+------------------------------------------------------------------+
class CGridExpert
{
private:
    CArrayObj   *m_GridLines;
    CGridLine   *m_ReachedGridLine;
    CGridLine   *m_EntryGridLine;

    int         m_TotalGridLines;
    double      m_LotSize;
    int         m_GridGapPips;
    int         m_Magic;
    string      m_TelegramToken;
    string      m_TelegramChatID;

    string      m_Symbol;
    double      m_SymbolPoint;
    bool        m_BotEnabled;
    bool        m_StartupNotify;


protected:
    void        GenerateGridLines();
    void        Reset();
    bool        CheckRecovery();                // Returns true if orders were recovered
    void        SendTelegramMessage(string msg);

public:
    CGridExpert(int gap, double lot, int totalLines, int magic, string token, string chatID);
    ~CGridExpert();

    void    OnTimer();
    int     OnInit();
    void    OnDeinit(const int reason);
    void    OnTick();
};


CGridExpert::CGridExpert(int gap, double lot, int totalLines, int magic, string token, string chatID)
{
    m_GridLines         = new CArrayObj;
    m_GridLines.FreeMode(true);
    m_ReachedGridLine   = NULL;
    m_EntryGridLine     = NULL;
    m_TotalGridLines    = totalLines;
    m_LotSize           = lot;
    m_GridGapPips       = gap;
    m_Magic             = magic;
    m_TelegramToken     = token;
    m_TelegramChatID    = chatID;
    m_Symbol            = Symbol();
    m_SymbolPoint       = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
    int digits          = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
    if(digits == 3 || digits == 5) m_SymbolPoint *= 10;
    m_BotEnabled        = true;
    m_StartupNotify     = false;
}


CGridExpert::~CGridExpert()
{
    if(CheckPointer(m_GridLines) != POINTER_INVALID) delete m_GridLines;
    if(CheckPointer(m_EntryGridLine) != POINTER_INVALID) delete m_EntryGridLine;
}


int CGridExpert::OnInit(void)
{
    ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, 1);
    ChartSetInteger(0, CHART_SHOW_GRID, 0);

    // We try recovery FIRST. If no orders found, we generate new ones.
    if(!CheckRecovery())
    {
        GenerateGridLines();
    }

    return(INIT_SUCCEEDED);
}


void CGridExpert::OnDeinit(const int reason)
{
    // WebRequest is forbidden in OnDeinit
    Print(StringFormat("⚠️ GridEA Stopped. Reason: %d", reason));
}


void CGridExpert::OnTimer() {}


void CGridExpert::OnTick(void)
{
    if(!m_BotEnabled) return;

    if(!m_StartupNotify)
    {
        SendTelegramMessage(StringFormat("🤖 *GridEA Autonomous Online (Reconfigured)*\nSymbol: %s\nLot: %G\nGap: %d pips\nMagic: %d", m_Symbol, m_LotSize, m_GridGapPips, m_Magic));
        m_StartupNotify = true;
    }


    if(CheckPointer(m_GridLines) != POINTER_INVALID && m_GridLines.Total() > 0)
    {
        for(int i = 0; i < m_GridLines.Total(); i++)
        {
            CGridLine *gridLine = m_GridLines.At(i);
            if(CheckPointer(gridLine) == POINTER_INVALID) continue;
            if(gridLine.HasBeenReached())
            {
                gridLine.MarketExecutionOrders();
                m_ReachedGridLine = gridLine;
                SendTelegramMessage(StringFormat("📉 *Grid Line Hit (Reversal)*\nPrice: %G\nSymbol: %s", gridLine.GetPrice(), m_Symbol));
                break;
            }
        }
        if(m_ReachedGridLine != NULL && m_ReachedGridLine.HasBeenReachedClosePrice())
        {
            m_ReachedGridLine = NULL;
            Reset();
        }
    }
}


void CGridExpert::GenerateGridLines()
{
    double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
    if(CheckPointer(m_EntryGridLine) != POINTER_INVALID) delete m_EntryGridLine;
    // Entry uses OP_SELL to follow 'Above' logic (reset when bid <= price - gap)
    m_EntryGridLine = new CGridLine(bid, "GridLine Entry", clrGold, OP_SELL, false, m_Magic, m_GridGapPips, m_LotSize);
    m_EntryGridLine.MarketExecutionOrders();
    m_GridLines.Clear();
    for(int i = 1; i <= m_TotalGridLines; i++)
    {
        double offset = m_SymbolPoint * m_GridGapPips * i;
        // Reconfigured: Above is SELL (Short), Below is BUY (Long)
        m_GridLines.Add(new CGridLine(bid + offset, StringFormat("GridLine Short [%d]", i), clrOrangeRed, OP_SELL, false, m_Magic, m_GridGapPips, m_LotSize));
        m_GridLines.Add(new CGridLine(bid - offset, StringFormat("GridLine Long [%d]", i), clrDeepSkyBlue, OP_BUY, false, m_Magic, m_GridGapPips, m_LotSize));
    }
}


void CGridExpert::Reset()
{
    SendTelegramMessage("🔄 *Resetting Grid and Closing Orders*");
    int total = OrdersTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == m_Magic && OrderSymbol() == m_Symbol)
            {
                bool res = false;
                if(OrderType() <= OP_SELL) res = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrWhite);
                else res = OrderDelete(OrderTicket());

                if(!res) Print("Error processing order ", OrderTicket(), ": ", GetLastError());
            }
        }
    }
    GenerateGridLines();
}


bool CGridExpert::CheckRecovery()
{
    bool found = false;
    double latestPrice = 0;

    int total = OrdersTotal();
    for(int i = 0; i < total; i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == m_Magic && OrderSymbol() == m_Symbol)
            {
                string comment = OrderComment();
                if(StringFind(comment, "GRID|") >= 0)
                {
                    latestPrice = StringToDouble(StringSubstr(comment, 5));
                    found = true;
                }
            }
        }
    }

    if(found)
    {
        Print("[GRID EA] Recovering from price: ", latestPrice);

        // Re-generate grid centered at the recovered price to maintain consistency
        if(CheckPointer(m_EntryGridLine) != POINTER_INVALID) delete m_EntryGridLine;
        m_EntryGridLine = new CGridLine(latestPrice, "GridLine Entry", clrGold, OP_SELL, true, m_Magic, m_GridGapPips, m_LotSize);

        m_GridLines.Clear();
        for(int i = 1; i <= m_TotalGridLines; i++)
        {
            double offset = m_SymbolPoint * m_GridGapPips * i;
            // Reconfigured: Above is SELL (Short), Below is BUY (Long)
            m_GridLines.Add(new CGridLine(latestPrice + offset, StringFormat("GridLine Short [%d]", i), clrOrangeRed, OP_SELL, false, m_Magic, m_GridGapPips, m_LotSize));
            m_GridLines.Add(new CGridLine(latestPrice - offset, StringFormat("GridLine Long [%d]", i), clrDeepSkyBlue, OP_BUY, false, m_Magic, m_GridGapPips, m_LotSize));
        }

        // Mark appropriately
        for(int j = 0; j < m_GridLines.Total(); j++)
        {
            CGridLine *gl = m_GridLines.At(j);
            if(MathAbs(gl.GetPrice() - latestPrice) < (m_SymbolPoint / 10.0))
            {
                gl.SetExecuted(true);
                m_ReachedGridLine = gl;
            }
        }
    }

    return found;
}


void CGridExpert::SendTelegramMessage(string msg)
{
    if(m_TelegramToken == "" || m_TelegramChatID == "") return;
    string url = "https://api.telegram.org/bot" + m_TelegramToken + "/sendMessage";
    string params = "chat_id=" + m_TelegramChatID + "&text=" + msg + "&parse_mode=Markdown";
    char data[], res[]; string headers;
    StringToCharArray(params, data, 0, WHOLE_ARRAY, CP_UTF8);
    WebRequest("POST", url, NULL, NULL, 5000, data, ArraySize(data), res, headers);
}


//+------------------------------------------------------------------+
//| Expert Main entry points                                         |
//+------------------------------------------------------------------+
CGridExpert*    GridEA;
bool            initialized=false;
bool            timerCalled=false;


int OnInit()
{
    EventSetMillisecondTimer(500);
    if(!initialized)
    {
        initialized = true;
        GridEA = new CGridExpert(GridGap, LotSize, TotalGridLines, MagicNumber, TelegramToken, TelegramChatID);
        return GridEA.OnInit();
    }
    return(INIT_SUCCEEDED);
}


void OnDeinit(const int reason)
{
    EventKillTimer();
    if(initialized && GridEA != NULL)
    {
        GridEA.OnDeinit(reason);
        initialized = false;
        delete GridEA;
    }
}


void OnTick()
{
    if(initialized && GridEA != NULL) GridEA.OnTick();
}


void OnTimer()
{
    if(!timerCalled)
    {
        timerCalled = true;
        if(initialized && GridEA != NULL) GridEA.OnTimer();
        timerCalled = false;
    }
}