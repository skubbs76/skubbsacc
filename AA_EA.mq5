#include <Trade\Trade.mqh>

CTrade Trade;

// Input parameters
input double lotSize = 0.03;          // Input lot size
input int tpPips = 50;                // Take Profit in pips
input int slPips = 50;                // Stop Loss in pips
input int trailingStopPips = 15;      // Trailing Stop to kick in after 15 pips in profit direction
input int maxOpenTrades = 2;          // Maximum number of open trades
input double atrThreshold = 0.5;      // ATR threshold for volatility filter
input int cooldownMinutes = 15;       // Cooldown period between trades

// Define global variables
double lastMSSLevelM1 = 0.0;
double lastMSSLevelM5 = 0.0;
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("EA Initialized.");
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

    // Comment out the cooldown period
    /*
    // Avoid trading during cooldown period
    if (TimeCurrent() - lastTradeTime < cooldownMinutes * 60)
    {
        Print("Cooldown period active. No trades will be placed.");
        return;
    }
    */

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
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);  // Cast to int to avoid data loss

        // Calculate SL and TP prices in points (1 pip = 0.10 points for GOLD)
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
    request.sl = NormalizeDouble(slPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));  // Cast to int to avoid data loss
    request.tp = NormalizeDouble(tpPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));  // Cast to int to avoid data loss
    request.type_filling = ORDER_FILLING_IOC;  // Market Execution filling mode
    request.type_time = ORDER_TIME_GTC;
    request.deviation = 10;
    request.magic = 123456;
    request.comment = comment;  // Add the triggers to the comment field

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
//| Identify Head and Shoulders Pattern                              |
//+------------------------------------------------------------------+
bool CheckHeadAndShoulders(string symbol, ENUM_TIMEFRAMES period)
{
    double leftShoulder = iHigh(symbol, period, 3);
    double head = iHigh(symbol, period, 2);
    double rightShoulder = iHigh(symbol, period, 1);

    if (head > leftShoulder && head > rightShoulder)
    {
        Print("H&S pattern detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Identify Inverse Head and Shoulders Pattern                      |
//+------------------------------------------------------------------+
bool CheckInverseHeadAndShoulders(string symbol, ENUM_TIMEFRAMES period)
{
    double leftShoulder = iLow(symbol, period, 3);
    double head = iLow(symbol, period, 2);
    double rightShoulder = iLow(symbol, period, 1);

    if (head < leftShoulder && head < rightShoulder)
    {
        Print("Inverse H&S pattern detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Identify Break-and-Retest Pattern                                |
//+------------------------------------------------------------------+
bool CheckBreakAndRetest(string symbol, ENUM_TIMEFRAMES period)
{
    double prevClose = iClose(symbol, period, 1);
    double currentClose = iClose(symbol, period, 0);
    double supportLevel = iLow(symbol, period, 3);
    double resistanceLevel = iHigh(symbol, period, 3);

    if (currentClose > resistanceLevel && prevClose <= resistanceLevel)
    {
        Print("Break-and-Retest pattern detected: Resistance broken.");
        return true;
    }
    if (currentClose < supportLevel && prevClose >= supportLevel)
    {
        Print("Break-and-Retest pattern detected: Support broken.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check Price Action Patterns                                      |
//+------------------------------------------------------------------+
bool CheckPriceActionPatterns(string symbol, ENUM_TIMEFRAMES period)
{
    // Example: Check for pin bar pattern
    double open = iOpen(symbol, period, 0);
    double close = iClose(symbol, period, 0);
    double high = iHigh(symbol, period, 0);
    double low = iLow(symbol, period, 0);

    double body = MathAbs(close - open);
    double upperShadow = high - MathMax(open, close);
    double lowerShadow = MathMin(open, close) - low;

    if (upperShadow > body * 2 && lowerShadow < body * 0.5)
    {
        Print("Pin bar pattern detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check Volume Analysis                                            |
//+------------------------------------------------------------------+
bool CheckVolumeAnalysis(string symbol, ENUM_TIMEFRAMES period)
{
    int bars = 100;  // Number of bars to consider
    long volumes[];  // Declare an array to hold volume data
    ArraySetAsSeries(volumes, true);  // Set the array as series
    CopyTickVolume(symbol, period, 0, bars, volumes);  // Copy volume data into the array
    
    // Calculate the simple moving average (SMA) of the volume data
    int periodSMA = 20;  // Period for the SMA
    double sumVolumes = 0.0;
    for (int i = 0; i < periodSMA; i++)
    {
        sumVolumes += volumes[i];
    }
    double averageVolume = sumVolumes / periodSMA;
    
    double currentVolume = (double)volumes[0];  // Current volume

    if (currentVolume > averageVolume * 1.5)
    {
        Print("High volume detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check Trend Alignment Across Timeframes                          |
//+------------------------------------------------------------------+
bool CheckTrendAlignment(string symbol)
{
    int maPeriod = 50;
    ENUM_MA_METHOD maMethod = MODE_SMA;
    ENUM_APPLIED_PRICE appliedPrice = PRICE_CLOSE;

    double maM1 = iMA(symbol, PERIOD_M1, maPeriod, 0, maMethod, appliedPrice);
    double maM5 = iMA(symbol, PERIOD_M5, maPeriod, 0, maMethod, appliedPrice);
    double maM15 = iMA(symbol, PERIOD_M15, maPeriod, 0, maMethod, appliedPrice);
    double maH1 = iMA(symbol, PERIOD_H1, maPeriod, 0, maMethod, appliedPrice);
    double maH4 = iMA(symbol, PERIOD_H4, maPeriod, 0, maMethod, appliedPrice);
    double maDaily = iMA(symbol, PERIOD_D1, maPeriod, 0, maMethod, appliedPrice);

    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

    if (currentPrice > maM1 && currentPrice > maM5 && currentPrice > maM15 && currentPrice > maH1 && currentPrice > maH4 && currentPrice > maDaily)
    {
        Print("Trend alignment detected: Uptrend.");
        return true;
    }
    if (currentPrice < maM1 && currentPrice < maM5 && currentPrice < maM15 && currentPrice < maH1 && currentPrice < maH4 && currentPrice < maDaily)
    {
        Print("Trend alignment detected: Downtrend.");
        return true;
    }

    Print("No trend alignment detected.");
    return false;
}

//+------------------------------------------------------------------+
//| Check Draw on Liquidity (DOL)                                    |
//+------------------------------------------------------------------+
bool CheckDrawOnLiquidity(string symbol, ENUM_TIMEFRAMES period)
{
    // Example: Check for draw on liquidity by identifying recent highs and lows
    double recentHigh = iHigh(symbol, period, 1);
    double recentLow = iLow(symbol, period, 1);
    double currentHigh = iHigh(symbol, period, 0);
    double currentLow = iLow(symbol, period, 0);

    if (currentHigh > recentHigh)
    {
        Print("Draw on liquidity detected: New high above recent high.");
        return true;
    }
    if (currentLow < recentLow)
    {
        Print("Draw on liquidity detected: New low below recent low.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check Break of Structure (BOS)                                   |
//+------------------------------------------------------------------+
bool CheckBreakOfStructure(string symbol, ENUM_TIMEFRAMES period)
{
    // Example: Check for break of structure by identifying key support/resistance levels
    static double lastHigh = 0.0;
    static double lastLow = 0.0;
    double currentHigh = iHigh(symbol, period, 0);
    double currentLow = iLow(symbol, period, 0);

    if (currentHigh > lastHigh)
    {
        lastHigh = currentHigh;
        Print("Break of structure detected: New high above last high.");
        return true;
    }
    if (currentLow < lastLow)
    {
        lastLow = currentLow;
        Print("Break of structure detected: New low below last low.");
        return true;
    }

    lastHigh = currentHigh;
    lastLow = currentLow;
    return false;
}

//+------------------------------------------------------------------+
//| Check Liquidity Targeting                                        |
//+------------------------------------------------------------------+
bool CheckLiquidityTargeting(string symbol, ENUM_TIMEFRAMES period)
{
    // Example: Check for liquidity targeting by identifying previous highs and lows
    double prevHigh = iHigh(symbol, period, 1);
    double prevLow = iLow(symbol, period, 1);
    double currentHigh = iHigh(symbol, period, 0);
    double currentLow = iLow(symbol, period, 0);

    if (currentHigh > prevHigh)
    {
        Print("Liquidity targeting detected: New high above previous high.");
        return true;
    }
    if (currentLow < prevLow)
    {
        Print("Liquidity targeting detected: New low below previous low.");
        return true;
    }

    return false;
}