# GOAT TRADING - Expert Advisor for MetaTrader 5

## 1. Description
GOAT TRADING is a high-performance scalping Expert Advisor (EA) designed for automated batch execution with advanced position management. It features automatic lot sizing based on account capital, multi-level Take Profit (TP) management, and a real-time information dashboard.

## 2. Key Features
- **Automatic Lot Sizing**: Adjusts trade volume dynamically based on account balance brackets ($2 to $750,000+).
- **Batch Execution**: Opens a predefined number of BUY and SELL orders simultaneously with a single toggle.
- **Multi-Level Take Profit**: Assigns different TP levels to specific groups of positions (up to 3 levels).
- **Flexible TP/SL Modes**: Support for both absolute price levels and pips.
- **Scalping Optimized**: Uses `ORDER_FILLING_IOC` for fast execution and minimal slippage on volatile brokers.
- **Real-Time Dashboard**: Displays Balance, Equity, Profit, and current trade counts directly on the chart.
- **Trade Comments**: All trades are tagged with "GOAT TRADING" for easy identification.

## 3. Configuration Parameters

### A. Lot Management
- **Lot Mode**: Choose between `FIXED_LOT` or `AUTO_RISK` (bracket-based).
- **Fixed Lot**: The volume used if Fixed Lot mode is active.

### B. Order Execution
- **Buy Count**: Number of BUY orders to open.
- **Sell Count**: Number of SELL orders to open.
- **Execute Orders**: Toggle to `true` to trigger the opening of orders. Once trades are opened, the EA prevents multiple executions on the same "activation".

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

---
*Developed by Jules - Software Engineer.*
