# GOAT TRADING - Expert Advisor for MetaTrader 5

## 1. Description
GOAT TRADING is a high-performance scalping Expert Advisor (EA) designed for automated batch execution with advanced position management. It features automatic lot sizing based on account capital, multi-level Take Profit (TP) management, and a real-time information dashboard.

## 2. Key Features
- **Automatic Lot Sizing**: Adjusts trade volume dynamically based on account balance brackets ($2 to $750,000+).
- **Batch Execution**: Opens a predefined number of BUY and SELL orders simultaneously with a single toggle.
- **Multi-Level Take Profit**: Assigns different TP levels to specific groups of positions (up to 3 levels).
- **Flexible TP/SL Modes**: Support for both absolute price levels and pips.
- **Scalping Optimized**: Uses `ORDER_FILLING_IOC` for fast execution and minimal slippage on volatile brokers.
- **Graphical Dashboard**: Displays Balance, Equity, Profit, and current trade counts in the top-right corner of the chart, featuring a cute animated Egyptian Cat (Gold color).
- **Trade Comments**: All trades are tagged with "GOAT TRADING" for easy identification.

## 3. Configuration Parameters

### A. Global Control
- **Bot Active**: Toggle to `true` to enable the EA. If set to `false`, the EA stops all operations AND closes all open positions for the current symbol.

### B. Lot Management
- **Lot Mode**: Choose between `FIXED_LOT` or `AUTO_RISK` (bracket-based).
- **Fixed Lot**: The volume used if Fixed Lot mode is active.

### B. Order Execution
- **Buy Count**: Number of BUY orders to open.
- **Sell Count**: Number of SELL orders to open.
- **Execute Orders**: Toggle to `true` to trigger the opening of orders. Once trades are opened, the EA prevents multiple executions on the same "activation".
- **Only If No Open Trades**: If set to `true`, the EA will not open new orders if there is already at least one open position on the current symbol.

### C. TP / SL Management
- **TP/SL Mode**: Choose between `PRICE_LEVEL` or `PIPS`.
- **Global TP/SL (Buy/Sell)**: Default target levels for all positions.

### D. Multi-Level TP
- **Use Multi-Level TP**: Toggle to enable/disable staggered exits.
- **TP Level 1/2/3**: The price or pip value for each level.
- **Trades Level 1/2/3**: The number of positions assigned to each TP level.

## 4. Capital Brackets (Auto Lot)
| Balance ($) | Lot Size |
|-------------|----------|
| 2 – 1,000 | 0.01 |
| 1,001 – 5,000 | 0.03 |
| 5,001 – 13,000 | 0.05 |
| 13,001 – 50,000 | 0.10 |
| 50,001 – 150,000 | 0.50 |
| 150,001 – 350,000 | 1.00 |
| 350,001 – 750,000 | 3.00 |
| > 750,000 | 3.00 |

## 5. Installation
1. Open MetaTrader 5.
2. Go to `File` > `Open Data Folder`.
3. Navigate to `MQL5/Experts/`.
4. Copy `GoatTrading.mq5` into this folder.
5. Restart MT5 or refresh the Navigator panel.
6. Drag the EA onto a chart and ensure "Algo Trading" is enabled.

## 6. Telegram Integration Guide
To control the bot via Telegram, follow these steps:

1. **Create a Bot**:
   - Message **@BotFather** on Telegram.
   - Send `/newbot` and follow instructions to get your **Bot Token**.
2. **Get your Chat ID**:
   - Message **@userinfobot** to get your personal **Chat ID**.
3. **Configure MT5**:
   - Open MT5 > `Tools` > `Options` > `Expert Advisors`.
   - Check **"Allow WebRequest for listed URL"**.
   - Add `https://api.telegram.org`.
4. **EA Settings**:
   - Paste your **Token** and **Chat ID** into the EA inputs.
   - Note: Commands sent via Telegram update the bot's *internal state*. These changes are not reflected in the input parameter UI but are active in the bot's logic.

### Supported Commands:
- `BUY` or `ACHAT`: Opens a batch of BUY orders (as defined by Buy Count).
- `SELL` or `VENTE`: Opens a batch of SELL orders (as defined by Sell Count).
- `TP BUY 72500` / `SL BUY 69000`
- `TP SELL 71000` / `SL SELL 73000`
- `CLOSE` or `FERMER`: Closes all positions for the current symbol.
- `ON` or `ACTIF TRUE`: Activates the bot.
- `OFF` or `ACTIF FALSE`: Deactivates the bot and closes all trades.

## 7. How to Use

### A. Telegram Remote Control
You can open batches of trades directly from Telegram:
- **`BUY`** or **`ACHAT`**: Opens a batch of BUY orders. The number of orders is determined by the `Buy Count` parameter in MT5.
- **`SELL`** or **`VENTE`**: Opens a batch of SELL orders. The number of orders is determined by the `Sell Count` parameter in MT5.
- **Dynamic Updates**: You can also send `TP BUY 72000` or `SL SELL 50 pips` to update targets for all current and future trades in the session.

### B. Multi-TP Mode (Partial Exits)
To use staggered profit targets:
1. Set **`Use Multi-Level TP`** to `true`.
2. Define your levels:
   - **`TP Level 1`**: The target (Price or Pips) for the first group.
   - **`Trades Level 1`**: How many trades in the batch should hit this target.
   - *Repeat for Level 2 and 3.*
3. If a trade is not covered by any level, it falls back to the **Global TP**.
*Example: If you open 5 BUYs, you can set Level 1 to 20 pips for 2 trades, and Level 2 to 50 pips for the remaining 3.*

### C. The Dashboard (Egyptian Maine Coon)
The **Gold Egyptian Cat** on the left side represents your bot's soul:
- **Body**: An elongated, elegant side-view design.
- **Awake**: Active and alert. Its eyes look around every 30 seconds, and its tail oscillates.
- **Sleeping**: Bot is deactivated (eyes closed, tail still).
- **Movement**: Every 2 minutes, the cat will elegantly shift its position on the left side of the chart.
- **Info Panel**: The data (Balance, Profit, etc.) is locked on the top-right in a large, easy-to-read format.

### D. Safety
Use **`Bot Active`** (MT5) or Telegram **`OFF`** to immediately stop all logic and close every open position on the symbol.

---
*Developed by Jules - Software Engineer.*
