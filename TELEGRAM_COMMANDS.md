# GOAT TRADING - Telegram Commands Guide

You can control your Expert Advisor remotely by sending these commands to your bot. Commands are NOT case-sensitive and support both English and French.

## 1. Trade Execution
Open batches of orders instantly.

- **`BUY`** or **`ACHAT`**: Opens a batch of BUY orders using the default `Buy Count`.
- **`BUY 10`**: Opens exactly 10 BUY orders.
- **`SELL`** or **`VENTE`**: Opens a batch of SELL orders using the default `Sell Count`.
- **`SELL 5`**: Opens exactly 5 SELL orders.

## 2. Closing Positions
Manage your exits with precision.

- **`CLOSE`** or **`FERMER`**: Closes ALL open positions for the current symbol.
- **`CLOSE 3`**: Closes the 3 oldest positions for the symbol.
- **`CLOSE PROFIT 50`**: Sets a target. The EA will close everything when total profit reaches **$50**.
- **`CLOSE LOSS 100`**: Sets a target. The EA will close everything if total loss hits **-$100**.

## 3. Dynamic Target Updates
Update your TP/SL for all active and future trades in the current session.

- **`TP BUY [val]`**: Updates Global Take Profit for BUYs.
- **`SL BUY [val]`**: Updates Global Stop Loss for BUYs.
- **`TP SELL [val]`**: Updates Global Take Profit for SELLs.
- **`SL SELL [val]`**: Updates Global Stop Loss for SELLs.

### Multi-Level TP (Scalping Mode)
- **`MULTI TP ON`**: Activates multi-level TP management.
- **`MULTI TP OFF`**: Deactivates multi-level TP (uses Global TP).
- **`TP LEVEL 1 [val]`**: Sets the target price for the first level.
- **`COUNT LEVEL 1 [num]`**: Number of trades to close at Level 1.
- **`TP LEVEL 2 [val]`**, **`COUNT LEVEL 2 [num]`**: Configuration for Level 2.
- **`TP LEVEL 3 [val]`**, **`COUNT LEVEL 3 [num]`**: Configuration for Level 3.

## 4. Bot Status & Safety
- **`ON`** or **`ACTIF TRUE`**: Activates the bot logic. The Egyptian Cat will wake up.
- **`OFF`** or **`ACTIF FALSE`**: Deactivates the bot logic AND closes all current positions immediately. The cat will go to sleep.

## 5. Market Analysis & Visuals
- **`ANALYSE`**: Returns a technical analysis report (Trend, RSI, Price, Market Structure).
- **`CAPTURE`** or **`PHOTO`**: Sends a high-quality screenshot of the current chart with drawn Trendlines and BOS/CHoCH levels.

## 6. Support & Setup
- **`HELP`** or **`AIDE`**: Displays a summary of all commands.
- **`MYID`**: Shows your unique Telegram Chat ID for use in the bot's input parameters.

---
*Note: Telegram commands update the bot's internal state. These changes will not be visible in the MT5 Input Parameters window, but they are active in the EA's logic.*
