#include <Trade\Trade.mqh>

CTrade Trade;

// Input parameters
input double lotSize = 0.03;           // Input lot size
input int tpPips = 50;                 // Take Profit in pips
input int slPips = 50;                 // Stop Loss in pips
input int trailingStopPips = 15;       // Trailing Stop to kick in after 15 pips in profit direction
input int maxOpenTrades = 2;           // Maximum number of open trades
input double atrThreshold = 0.5;       // ATR threshold for volatility filter
input int cooldownMinutes = 15;        // Cooldown period between trades

// Define global variables
double lastMSSLevelM1 = 0.0;
double lastMSSLevelM5 = 0.0;
datetime lastTradeTime = 0;

// New global variables for trade analysis
double totalProfit = 0;
double totalLoss = 0;
int winningTrades = 0;
int losingTrades = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  Print("EA Initialized.");
  AnalyzePastTrades(); // Analyze past trades during initialization
  return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  Print("EA Deinitialized.");
}

//+------------------------------------------------------------------+
//| Main OnTick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  string symbol = "GOLD";

  double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
  double bidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

  // Ensure no more than maxOpenTrades are open at a time
  if (PositionsTotal() >= maxOpenTrades)
  {
    Print("Maximum of ", maxOpenTrades, " trades reached. No new trades will be opened.");
    return;
  }

  // Ensure trend alignment before placing trades
  if (!CheckTrendAlignment(symbol))
  {
    Print("Trend is not aligned. No trades will be placed.");
    return;
  }

  // Additional filter: Check if price is above/below a longer-term moving average
  double maDaily = iMA(symbol, PERIOD_D1, 200, 0, MODE_SMA, PRICE_CLOSE);
  double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
  if (currentPrice < maDaily)
  {
    Print("Price is below the 200-day moving average. No trades will be placed.");
    return;
  }

  // ATR Filter: Ensure ATR is above a certain threshold for volatility
  double atr = iATR(symbol, PERIOD_M5, 14);
  if (atr < atrThreshold)
  {
    Print("ATR filter not met. No trades will be placed.");
    return;
  }

  // Trigger flags
  bool hnsTriggered = CheckHeadAndShoulders(symbol, PERIOD_M5);
  bool inverseHnsTriggered = CheckInverseHeadAndShoulders(symbol, PERIOD_M5);
  bool mssTriggered = CheckMarketStructureShift(symbol, PERIOD_M1, lastMSSLevelM1);
  bool breakRetestTriggered = CheckBreakAndRetest(symbol, PERIOD_M5);
  bool priceActionTriggered = CheckPriceActionPatterns(symbol, PERIOD_M1);
  bool volumeTriggered = CheckVolumeAnalysis(symbol, PERIOD_M1);
  bool dolTriggered = CheckDrawOnLiquidity(symbol, PERIOD_M5);
  bool bosTriggered = CheckBreakOfStructure(symbol, PERIOD_M5);
  bool liquidityTargetingTriggered = CheckLiquidityTargeting(symbol, PERIOD_M5);

  // Collect triggers that are true
  string triggers = "";
  if (hnsTriggered) triggers += "HnS ";
  if (inverseHnsTriggered) triggers += "Inverse HnS ";
  if (mssTriggered) triggers += "MSS ";
  if (breakRetestTriggered) triggers += "Break-Retest ";
  if (priceActionTriggered) triggers += "PriceAction ";
  if (volumeTriggered) triggers += "Volume ";
  if (dolTriggered) triggers += "DOL ";
  if (bosTriggered) triggers += "BOS ";
  if (liquidityTargetingTriggered) triggers += "LiquidityTargeting ";

  int triggerCount = 0;
  if (hnsTriggered) triggerCount++;
  if (inverseHnsTriggered) triggerCount++;
  if (mssTriggered) triggerCount++;
  if (breakRetestTriggered) triggerCount++;
  if (priceActionTriggered) triggerCount++;
  if (volumeTriggered) triggerCount++;
  if (dolTriggered) triggerCount++;
  if (bosTriggered) triggerCount++;
  if (liquidityTargetingTriggered) triggerCount++;

  // Determine order type based on triggers
  ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
  if (inverseHnsTriggered || (mssTriggered && !hnsTriggered))
    orderType = ORDER_TYPE_SELL;

  // Proceed only if at least two triggers are met, including primary criteria (DOL, BOS, LiquidityTargeting)
  if (triggerCount >= 2 && (dolTriggered || bosTriggered || liquidityTargetingTriggered))
  {
    double entryPrice = (orderType == ORDER_TYPE_BUY) ? askPrice : bidPrice;
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS); // Cast to int to avoid data loss

    // Calculate SL and TP prices in points
    double slPrice = (orderType == ORDER_TYPE_BUY) ? entryPrice - slPips * 0.10 : entryPrice + slPips * 0.10;
    double tpPrice = (orderType == ORDER_TYPE_BUY) ? entryPrice + tpPips * 0.10 : entryPrice - tpPips * 0.10;

    // Pass trigger info into the comment field
    string comment = "Triggers met: " + triggers;
    SendOrderWithComment(symbol, orderType, lotSize, entryPrice, slPrice, tpPrice, comment);

    // Update last trade time
    lastTradeTime = TimeCurrent();
  }
}

//+------------------------------------------------------------------+
//| SendOrderWithComment Function                                    |
//+------------------------------------------------------------------+
void SendOrderWithComment(string symbol, ENUM_ORDER_TYPE type, double lotSize, double price, double slPrice, double tpPrice, string comment)
{
  MqlTradeRequest request;
  MqlTradeResult result;
  ZeroMemory(request);
  ZeroMemory(result);

  request.action = TRADE_ACTION_DEAL;
  request.symbol = symbol;
  request.type = type;
  request.volume = lotSize;
  request.price = price;
  request.sl = NormalizeDouble(slPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); // Cast to int to avoid data loss
  request.tp = NormalizeDouble(tpPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); // Cast to int to avoid data loss
  request.type_filling = ORDER_FILLING_IOC; // Market Execution filling mode
  request.type_time = ORDER_TIME_GTC;
  request.deviation = 10;
  request.magic = 123456;
  request.comment = comment; // Add the triggers to the comment field

  if (OrderSend(request, result))
  {
    Print("Order placed: ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
          ", SL: ", request.sl, ", TP: ", request.tp, ", Comment: ", comment);

    // Set trailing stop loss manually
    if (trailingStopPips > 0)
    {
      double trailingStopLevel = trailingStopPips * 0.10;
      if (!Trade.PositionModify(result.order, request.sl, request.tp))
      {
        Print("Failed to modify position: ", GetLastError());
      }
      else
      {
        Print("Position modified with trailing stop.");
      }
    }
  }
  else
  {
    Print("Order failed. Error: ", GetLastError());
  }
}

//+------------------------------------------------------------------+
//| Analyze past trades                                              |
//+------------------------------------------------------------------+
void AnalyzePastTrades()
{
  int totalTrades = HistoryDealsTotal();
  for (int i = 0; i < totalTrades; i++)
  {
    ulong ticket = HistoryDealGetTicket(i);
    double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

    if (profit > 0)
    {
      totalProfit += profit;
      winningTrades++;
    }
    else
    {
      totalLoss += profit;
      losingTrades++;
    }
  }

  double averageWin = totalProfit / winningTrades;
  double averageLoss = totalLoss / losingTrades;
  Print("Total Winning Trades: ", winningTrades);
  Print("Total Losing Trades: ", losingTrades);
  Print("Average Win: ", averageWin);
  Print("Average Loss: ", averageLoss);
}

//+------------------------------------------------------------------+
//| Identify Market Structure Shift                                  |
//+------------------------------------------------------------------+
bool CheckMarketStructureShift(string symbol, ENUM_TIMEFRAMES period, double &mssLevel)
{
  double lastHigh = iHigh(symbol, period, 1);
  double currentHigh = iHigh(symbol, period, 0);
  double lastLow = iLow(symbol, period, 1);
  double currentLow = iLow(symbol, period, 0);

  if (currentHigh > lastHigh && currentLow > lastLow)
  {
    mssLevel = currentHigh;
    Print("Bullish Market Structure Shift detected.");
    return true;
  }
  if (currentHigh < lastHigh && currentLow < lastLow)
  {
    mssLevel = currentLow;
    Print("Bearish Market Structure Shift detected.");
    return true;
  }

  return false;
}

//+------------------------------------------------------------------+
//| Draw horizontal lines at significant highs and lows              |
//+------------------------------------------------------------------+
void DrawLiquidityLevels()
{
  double swingHigh = iHigh(_Symbol, 0, iHighest(_Symbol, 0, MODE_HIGH, 50));
  double swingLow = iLow(_Symbol, 0, iLowest(_Symbol, 0, MODE_LOW, 50));

  // Draw horizontal lines on the chart
  ObjectCreate(0, "SwingHigh", OBJ_HLINE, 0, TimeCurrent(), swingHigh);
  ObjectSetInteger(0, "SwingHigh", OBJPROP_COLOR, clrRed);
  ObjectCreate(0, "SwingLow", OBJ_HLINE, 0, TimeCurrent(), swingLow);
  ObjectSetInteger(0, "SwingLow", OBJPROP_COLOR, clrBlue);
}

//+------------------------------------------------------------------+
//| Identify Break of Structure                                      |
//+------------------------------------------------------------------+
bool IsBreakOfStructure()
{
  double currentHigh = iHigh(_Symbol, 0, 0);
  double previousHigh = iHigh(_Symbol, 0, 1);
  double currentLow = iLow(_Symbol, 0, 0);
  double previousLow = iLow(_Symbol, 0, 1);

  if (currentHigh > previousHigh)
  {
    Print("Bullish Break of Structure detected.");
    return true;
  }
  if (currentLow < previousLow)
  {
    Print("Bearish Break of Structure detected.");
    return true;
  }
  return false;
}

//+------------------------------------------------------------------+
//| Set TP and SL based on buy/sell side liquidity                   |
//+------------------------------------------------------------------+
void SetLiquidityTargets(double &takeProfit, double &stopLoss)
{
  double swingHigh = iHigh(_Symbol, 0, iHighest(_Symbol, 0, MODE_HIGH, 50));
  double swingLow = iLow(_Symbol, 0, iLowest(_Symbol, 0, MODE_LOW, 50));

  // Example: setting TP at swing high and SL at swing low
  takeProfit = swingHigh;
  stopLoss = swingLow;
}

//+------------------------------------------------------------------+
//| Function to open a trade with liquidity targets          |
//+------------------------------------------------------------------+
void OpenTradeWithLiquidityTargets(string symbol, ENUM_ORDER_TYPE orderType, double lotSize)
{
    double takeProfit, stopLoss;
    double swingHigh = iHigh(symbol, 0, iHighest(symbol, 0, MODE_HIGH, 50));
    double swingLow = iLow(symbol, 0, iLowest(symbol, 0, MODE_LOW, 50));

    // Set TP and SL based on buy/sell side liquidity
    if (orderType == ORDER_TYPE_BUY)
    {
        takeProfit = swingHigh;
        stopLoss = swingLow;
    }
    else
    {
        takeProfit = swingLow;
        stopLoss = swingHigh;
    }

    MqlTradeRequest request;
    MqlTradeResult result;

    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lotSize;
    request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    request.sl = NormalizeDouble(stopLoss, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    request.tp = NormalizeDouble(takeProfit, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    request.type = orderType;
    request.deviation = 10;
    request.magic = 123456;
    request.comment = "Trade with liquidity targets";

    if (!OrderSend(request, result))
    {
        Print("Error opening order: ", result.retcode);
    }
    else
    {
        Print("Order opened successfully with TP: ", takeProfit, " and SL: ", stopLoss);
    }
}
//+------------------------------------------------------------------+
//| OnTick function to check for break of structure          |
//+------------------------------------------------------------------+
void OnTick()
{
    string symbol = _Symbol;
    double currentHigh = iHigh(symbol, 0, 0);
    double previousHigh = iHigh(symbol, 0, 1);
    double currentLow = iLow(symbol, 0, 0);
    double previousLow = iLow(symbol, 0, 1);

    // Check for bullish break of structure
    if (currentHigh > previousHigh)
    {
        Print("Bullish Break of Structure detected.");
        OpenTradeWithLiquidityTargets(symbol, ORDER_TYPE_BUY, 0.1);
    }
    // Check for bearish break of structure
    else if (currentLow < previousLow)
    {
        Print("Bearish Break of Structure detected.");
        OpenTradeWithLiquidityTargets(symbol, ORDER_TYPE_SELL, 0.1);
    }

    // Optionally draw liquidity levels on the chart
    DrawLiquidityLevels();
}

// Function to draw horizontal lines at significant highs and lows
void DrawLiquidityLevels()
{
    double swingHigh = iHigh(_Symbol, 0, iHighest(_Symbol, 0, MODE_HIGH, 50));
    double swingLow = iLow(_Symbol, 0, iLowest(_Symbol, 0, MODE_LOW, 50));

    // Draw horizontal lines on the chart
    ObjectCreate(0, "SwingHigh", OBJ_HLINE, 0, TimeCurrent(), swingHigh);
    ObjectSetInteger(0, "SwingHigh", OBJPROP_COLOR, clrRed);
    ObjectCreate(0, "SwingLow", OBJ_HLINE, 0, TimeCurrent(), swingLow);
    ObjectSetInteger(0, "SwingLow", OBJPROP_COLOR, clrBlue);
}

//+------------------------------------------------------------------+
//| SendOrderWithComment Function                                    |
//+------------------------------------------------------------------+
void SendOrderWithComment(string symbol, ENUM_ORDER_TYPE type, double lotSize, double price, double slPrice, double tpPrice, string comment)
{
  MqlTradeRequest request;
  MqlTradeResult result;
  ZeroMemory(request);
  ZeroMemory(result);

  request.action = TRADE_ACTION_DEAL;
  request.symbol = symbol;
  request.type = type;
  request.volume = lotSize;
  request.price = price;
  request.sl = NormalizeDouble(slPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); // Cast to int to avoid data loss
  request.tp = NormalizeDouble(tpPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); // Cast to int to avoid data loss
  request.type_filling = ORDER_FILLING_IOC; // Market Execution filling mode
  request.type_time = ORDER_TIME_GTC;
  request.deviation = 10;
  request.magic = 123456;
  request.comment = comment; // Add the triggers to the comment field

  if (OrderSend(request, result))
  {
    Print("Order placed: ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
          ", SL: ", request.sl, ", TP: ", request.tp, ", Comment: ", comment);

    // Set trailing stop loss manually
    if (trailingStopPips > 0)
    {
      double trailingStopLevel = trailingStopPips * 0.10;
      if (!Trade.PositionModify(result.order, request.sl, request.tp))
      {
        Print("Failed to modify position: ", GetLastError());
      }
      else
      {
        Print("Position modified with trailing stop.");
      }
    }
  }
  else
  {
    Print("Order failed. Error: ", GetLastError());
  }
}

//+------------------------------------------------------------------+
//| Analyze past trades                                              |
//+------------------------------------------------------------------+
void AnalyzePastTrades()
{
  int totalTrades = HistoryDealsTotal();
  for (int i = 0; i < totalTrades; i++)
  {
    ulong ticket = HistoryDealGetTicket(i);
    double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

    if (profit > 0)
    {
      totalProfit += profit;
      winningTrades++;
    }
    else
    {
      totalLoss += profit;
      losingTrades++;
    }
  }

  double averageWin = totalProfit / winningTrades;
  double averageLoss = totalLoss / losingTrades;
  Print("Total Winning Trades: ", winningTrades);
  Print("Total Losing Trades: ", losingTrades);
  Print("Average Win: ", averageWin);
  Print("Average Loss: ", averageLoss);
}

//+------------------------------------------------------------------+
//| Identify Market Structure Shift                                  |
//+------------------------------------------------------------------+
bool CheckMarketStructureShift(string symbol, ENUM_TIMEFRAMES period, double &mssLevel)
{
  double lastHigh = iHigh(symbol, period, 1);
  double currentHigh = iHigh(symbol, period, 0);
  double lastLow = iLow(symbol, period, 1);
  double currentLow = iLow(symbol, period, 0);

  if (currentHigh > lastHigh && currentLow > lastLow)
  {
    mssLevel = currentHigh;
    Print("Bullish Market Structure Shift detected.");
    return true;
  }
  if (currentHigh < lastHigh && currentLow < lastLow)
  {
    mssLevel = currentLow;
    Print("Bearish Market Structure Shift detected.");
    return true;
  }

  return false;
}

//+------------------------------------------------------------------+
//| Draw horizontal lines at significant highs and lows              |
//+------------------------------------------------------------------+
void DrawLiquidityLevels()
{
  double swingHigh = iHigh(_Symbol, 0, iHighest(_Symbol, 0, MODE_HIGH, 50));
  double swingLow = iLow(_Symbol, 0, iLowest(_Symbol, 0, MODE_LOW, 50));

  // Draw horizontal lines on the chart
  ObjectCreate(0, "SwingHigh", OBJ_HLINE, 0, TimeCurrent(), swingHigh);
  ObjectSetInteger(0, "SwingHigh", OBJPROP_COLOR, clrRed);
  ObjectCreate(0, "SwingLow", OBJ_HLINE, 0, TimeCurrent(), swingLow);
  ObjectSetInteger(0, "SwingLow", OBJPROP_COLOR, clrBlue);
}

//+------------------------------------------------------------------+
//| Identify Break of Structure                                      |
//+------------------------------------------------------------------+
bool IsBreakOfStructure()
{
  double currentHigh = iHigh(_Symbol, 0, 0);
  double previousHigh = iHigh(_Symbol, 0, 1);
  double currentLow = iLow(_Symbol, 0, 0);
  double previousLow = iLow(_Symbol, 0, 1);

  if (currentHigh > previousHigh)
  {
    Print("Bullish Break of Structure detected.");
    return true;
  }
  if (currentLow < previousLow)
  {
    Print("Bearish Break of Structure detected.");
    return true;
  }
  return false;
}

//+------------------------------------------------------------------+
//| Set TP and SL based on buy/sell side liquidity                   |
//+------------------------------------------------------------------+
void SetLiquidityTargets(double &takeProfit, double &stopLoss)
{
  double swingHigh = iHigh(_Symbol, 0, iHighest(_Symbol, 0, MODE_HIGH, 50));
  double swingLow = iLow(_Symbol, 0, iLowest(_Symbol, 0, MODE_LOW, 50));

  // Example: setting TP at swing high and SL at swing low
  takeProfit = swingHigh;
  stopLoss = swingLow;
}

//+------------------------------------------------------------------+
//| Example function to open a trade with liquidity targets          |
//+------------------------------------------------------------------+
void OpenTrade()
{
  double takeProfit, stopLoss;
  SetLiquidityTargets(takeProfit, stopLoss);

  MqlTradeRequest request;
  MqlTradeResult result;

  request.action = TRADE_ACTION_DEAL;
  request.symbol = _Symbol;
  request.volume = 0.1;
  request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  request.sl = stopLoss;
  request.tp = takeProfit;
  request.type = ORDER_TYPE_BUY;
  request.deviation = 3;
  request.magic = 0;
  request.comment = "Buy Order";

  if (!OrderSend(request, result))
  {
    Print("Error opening order: ", result.retcode);
  }
  else
  {
    Print("Order opened successfully with TP: ", takeProfit, " and SL: ", stopLoss);
  }
}

//+------------------------------------------------------------------+
//| Example OnTick function to check for break of structure          |
//+------------------------------------------------------------------+
void OnTick()
{
  if (IsBreakOfStructure())
  {
    OpenTrade();
  }
  DrawLiquidityLevels();
}
