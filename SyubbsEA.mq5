#include <Trade\Trade.mqh>

CTrade Trade;

// Input parameters for lot size, SL, and TP
input double LotSize = 0.02;         // Default lot size
input double StopLossPips = 20;      // Default SL in pips
input double TakeProfitPips = 20;    // Default TP in pips

// Define global variables
double lastMSSLevelM1 = 0.0;
datetime lastTradeTime = 0;

bool hnsTriggered = false;
bool inverseHnsTriggered = false;
bool mssTriggered = false;
bool breakRetestTriggered = false;
bool priceActionTriggered = false;
bool volumeTriggered = false;
bool crtTriggered = false;
bool amdTriggered = false;
bool liquidityGrabTriggered = false;
bool breakoutTriggered = false;

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

// Custom trim function to remove leading and trailing spaces
string Trim(string str)
{
    int start = 0;
    int end = StringLen(str) - 1;

    while (start <= end && StringGetCharacter(str, start) <= ' ')
        start++;
    while (end >= start && StringGetCharacter(str, end) <= ' ')
        end--;

    return StringSubstr(str, start, end - start + 1);
}

// Optimized Precision Entry Criteria
bool CheckPrecisionEntry(string symbol, ENUM_TIMEFRAMES higherTimeframe, ENUM_TIMEFRAMES lowerTimeframe)
{
    // Higher timeframe trend identification
    double ma200H = iMA(symbol, higherTimeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
    double currentPriceH = iClose(symbol, higherTimeframe, 0);
    bool isUptrendH = currentPriceH > ma200H;
    bool isDowntrendH = currentPriceH < ma200H;

    // Lower timeframe precise entry points
    double ma50L = iMA(symbol, lowerTimeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
    double currentPriceL = iClose(symbol, lowerTimeframe, 0);
    bool isUptrendL = currentPriceL > ma50L;
    bool isDowntrendL = currentPriceL < ma50L;

    // Confluence factors: Key support and resistance levels
    double supportLevel = iLow(symbol, lowerTimeframe, 3);
    double resistanceLevel = iHigh(symbol, lowerTimeframe, 3);

    if (isUptrendH && isUptrendL && currentPriceL > resistanceLevel)
    {
        Print("Precision entry criteria met: Uptrend and resistance breakout.");
        return true;
    }

    if (isDowntrendH && isDowntrendL && currentPriceL < supportLevel)
    {
        Print("Precision entry criteria met: Downtrend and support breakout.");
        return true;
    }

    return false;
}

// Strong Confirmation Signals
bool CheckStrongConfirmationSignals(string symbol, ENUM_TIMEFRAMES timeframe)
{
    // Example confirmation signals
    double ma50 = iMA(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
    double ma200 = iMA(symbol, timeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
    double rsi = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
    
    int macdHandle = iMACD(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
    double macdMain[], macdSignal[], macdHist[];
    CopyBuffer(macdHandle, 0, 0, 1, macdMain);
    CopyBuffer(macdHandle, 1, 0, 1, macdSignal);
    CopyBuffer(macdHandle, 2, 0, 1, macdHist);

    // Check if MA50 is above MA200 (indicating an uptrend)
    bool maConfirmation = (ma50 > ma200);
    // Check if RSI is in oversold/overbought regions
    bool rsiConfirmation = (rsi < 30 || rsi > 70);
    // Check if MACD main line crosses above/below signal line
    bool macdConfirmation = (macdMain[0] > macdSignal[0] || macdMain[0] < macdSignal[0]);

    return (maConfirmation && rsiConfirmation && macdConfirmation);
}

// Market Conditions Check
bool CheckMarketConditions(string symbol)
{
    // Avoid trading during high volatility news events
    datetime newsEventTime = D'2025.01.07 12:00'; // Example news event time
    datetime currentTime = TimeCurrent();
    if (currentTime >= newsEventTime - 3600 && currentTime <= newsEventTime + 3600)
    {
        Print("High volatility news event. No trades will be placed.");
        return false;
    }

    return true;
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
//| Check Candle Range Theory (CRT)                                  |
//+------------------------------------------------------------------+
bool CheckCandleRangeTheory(string symbol, ENUM_TIMEFRAMES period)
{
    double open = iOpen(symbol, period, 0);
    double close = iClose(symbol, period, 0);
    double high = iHigh(symbol, period, 0);
    double low = iLow(symbol, period, 0);

    double body = MathAbs(close - open);
    double range = high - low;

    // Refined logic: Detect large bullish or bearish candles with long bodies
    if (body > range * 0.6 && body > SymbolInfoDouble(symbol, SYMBOL_POINT) * 20)
    {
        Print("Candle Range Theory detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check AMD Cycle Detection                                        |
//+------------------------------------------------------------------+
bool CheckAMDCycleDetection(string symbol, ENUM_TIMEFRAMES period)
{
    double prevHigh = iHigh(symbol, period, 1);
    double currentHigh = iHigh(symbol, period, 0);
    double prevLow = iLow(symbol, period, 1);
    double currentLow = iLow(symbol, period, 0);

    if (currentHigh > prevHigh && currentLow > prevLow)
    {
        Print("AMD Cycle (Accumulation) detected.");
        return true;
    }
    if (currentHigh < prevHigh && currentLow < prevLow)
    {
        Print("AMD Cycle (Distribution) detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check Liquidity Grab Detection                                   |
//+------------------------------------------------------------------+
bool CheckLiquidityGrabDetection(string symbol, ENUM_TIMEFRAMES period)
{
    double open = iOpen(symbol, period, 0);
    double close = iClose(symbol, period, 0);
    double high = iHigh(symbol, period, 0);
    double low = iLow(symbol, period, 0);

    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    double range = high - low;

    // Refined logic: Detect significant wicks relative to the candle range
    if (upperWick > range * 0.5 || lowerWick > range * 0.5)
    {
        Print("Liquidity Grab detected.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check Price Action Patterns                                      |
//+------------------------------------------------------------------+
bool CheckPriceActionPatterns(string symbol, ENUM_TIMEFRAMES period)
{
    double open = iOpen(symbol, period, 0);
    double close = iClose(symbol, period, 0);
    double high = iHigh(symbol, period, 0);
    double low = iLow(symbol, period, 0);

    double body = MathAbs(close - open);
    double upperShadow = high - MathMax(open, close);
    double lowerShadow = MathMin(open, close) - low;

    // Refined logic: Detect pin bars and engulfing candles
    if ((upperShadow > body * 2 && lowerShadow < body * 0.5) || (lowerShadow > body * 2 && upperShadow < body * 0.5))
    {
        Print("Pin bar pattern detected.");
        return true;
    }

    if ((close > open && close - low > high - open) || (close < open && open - low > close - high))
    {
        Print("Engulfing candle pattern detected.");
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

    // Refined logic: Detect significant volume spikes
    if (currentVolume > averageVolume * 1.5)
    {
        Print("High volume detected.");
        return true;
    }

    return false;
}

// Function to calculate ATR
double CalculateATR(string symbol, int period, ENUM_TIMEFRAMES timeframe)
{
    return iATR(symbol, timeframe, period);
}

//+------------------------------------------------------------------+
//| Function to place an order without SL and TP, then modify it to add SL and TP
//+------------------------------------------------------------------+
bool ExecuteTradeWithModification(string symbol, int orderType, double lotSize, double stopLossPips, double takeProfitPips, string comment)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? askPrice : bidPrice;

    // Place the order without SL and TP
    bool result;
    if (orderType == ORDER_TYPE_BUY)
    {
        result = Trade.Buy(lotSize, symbol, price, 0, 0, comment);
    }
    else if (orderType == ORDER_TYPE_SELL)
    {
        result = Trade.Sell(lotSize, symbol, price, 0, 0, comment);
    }
    else
    {
        Print("Invalid order type");
        return false;
    }

    if (!result)
    {
        Print("OrderSend failed with error #", GetLastError());
        return false;
    }

    // Get the ticket of the last order
    ulong ticket = Trade.ResultOrder();
    Print("OrderSend succeeded with ticket #", ticket);

    // Calculate SL and TP prices
    double stopLossPrice, takeProfitPrice;
    if (orderType == ORDER_TYPE_BUY)
    {
        stopLossPrice = bidPrice - stopLossPips * point;
        takeProfitPrice = bidPrice + takeProfitPips * point;
    }
    else
    {
        stopLossPrice = askPrice + stopLossPips * point;
        takeProfitPrice = askPrice - takeProfitPips * point;
    }

    // Modify the order to add SL and TP
    if (!Trade.PositionModify(ticket, stopLossPrice, takeProfitPrice))
    {
        Print("PositionModify failed with error #", GetLastError());
        return false;
    }

    Print("Position modified to include SL: ", stopLossPrice, " and TP: ", takeProfitPrice);
    return true;
}

//+------------------------------------------------------------------+
//| Final OnTick Function with All Enhancements                      |
//+------------------------------------------------------------------+
void OnTick()
{
    string symbol = "GOLD";
    int orderType = ORDER_TYPE_SELL; // Example order type
    double lotSize = LotSize;        // Use input lot size
    double stopLossPips = StopLossPips; // Use input stop loss in pips
    double takeProfitPips = TakeProfitPips; // Use input take profit in pips

    // Ensure no more than 2 trades are open at a time
    if (PositionsTotal() >= 1000)
    {
        Print("Maximum of opened trades reached. No new trades will be opened.");
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
    int atrPeriod = 14;
    ENUM_TIMEFRAMES timeframe = PERIOD_M5;
    double atr = iATR(symbol, timeframe, atrPeriod);
    if (atr < 0.5)
    {
        Print("ATR filter not met. No trades will be placed.");
        return;
    }

    // Check precision entry criteria
    if (!CheckPrecisionEntry(symbol, PERIOD_H1, timeframe))
    {
        Print("Precision entry criteria not met. No trades will be placed.");
        return;
    }

    // Check strong confirmation signals
    if (!CheckStrongConfirmationSignals(symbol, timeframe))
    {
        Print("Strong confirmation signals not met. No trades will be placed.");
        return;
    }

    // Check market conditions
    datetime currentTime = TimeCurrent(); // Initialize currentTime
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct); // Convert datetime to MqlDateTime structure
    int hour = timeStruct.hour; // Extract hour from timeStruct

    // Ensure trading during active market sessions (London and New York sessions)
    if (hour < 8 || hour > 17)
    {
        Print("Outside active market sessions. No trades will be placed.");
        return;
    }

    // Trigger flags (use global variables)
    hnsTriggered = CheckHeadAndShoulders(symbol, timeframe);
    inverseHnsTriggered = CheckInverseHeadAndShoulders(symbol, timeframe);
    mssTriggered = CheckMarketStructureShift(symbol, PERIOD_M1, lastMSSLevelM1);
    breakRetestTriggered = CheckBreakAndRetest(symbol, timeframe);
    priceActionTriggered = CheckPriceActionPatterns(symbol, PERIOD_M1);
    volumeTriggered = CheckVolumeAnalysis(symbol, PERIOD_M1);
    crtTriggered = CheckCandleRangeTheory(symbol, timeframe);
    amdTriggered = CheckAMDCycleDetection(symbol, timeframe);
    liquidityGrabTriggered = CheckLiquidityGrabDetection(symbol, timeframe);
    breakoutTriggered = IdentifyBreakout(symbol, atrPeriod, timeframe, 2.0); // ATR breakout detection

    // Collect triggers that are true
    int triggerCount = 0;
    string comment = "";
    if (hnsTriggered) { triggerCount++; comment += "H&S "; }
    if (inverseHnsTriggered) { triggerCount++; comment += "Inverse H&S "; }
    if (mssTriggered) { triggerCount++; comment += "MSS "; }
    if (breakRetestTriggered) { triggerCount++; comment += "Break-Retest "; }
    if (priceActionTriggered) { triggerCount++; comment += "Price Action "; }
    if (volumeTriggered) { triggerCount++; comment += "Volume "; }
    if (crtTriggered) { triggerCount++; comment += "CRT "; }
    if (amdTriggered) { triggerCount++; comment += "AMD "; }
    if (liquidityGrabTriggered) { triggerCount++; comment += "Liquidity Grab "; }
    if (breakoutTriggered) { triggerCount++; comment += "Breakout "; }

    Print("Trigger count: ", triggerCount);

    // Determine order type based on triggers
    orderType = 0; // 0 for buy, 1 for sell
    if (inverseHnsTriggered || (mssTriggered && !hnsTriggered))
        orderType = 1;

    // Proceed only if at least four triggers are met
    if (triggerCount >= 4)
    {
        if (ExecuteTradeWithModification(symbol, orderType, lotSize, stopLossPips, takeProfitPips, Trim(comment)))
        {
            Print("Trade executed successfully. Comment: ", Trim(comment));
            // Reset triggers after a successful trade
            ResetTriggers();
        }
        else
        {
            Print("Trade execution failed.");
        }
    }
    else
    {
        Print("Not enough triggers met. No trades will be placed.");
    }

    // Call functions to manage open trades and apply trailing stop
    ApplyTrailingStop();
    ManageOpenTrades();
}
//+------------------------------------------------------------------+
//| Function to identify breakouts using ATR                         |
//+------------------------------------------------------------------+
bool IdentifyBreakout(string symbol, int period, ENUM_TIMEFRAMES timeframe, double threshold)
{
    double atr = iATR(symbol, timeframe, period);

    // Get the high and low prices of the current bar
    double currentHigh = iHigh(symbol, timeframe, 0);
    double currentLow = iLow(symbol, timeframe, 0);
    double currentRange = currentHigh - currentLow;

    if (currentRange > threshold * atr)
    {
        Print("Breakout detected!");
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Function to reset all triggers                                   |
//+------------------------------------------------------------------+
void ResetTriggers()
{
    hnsTriggered = false;
    inverseHnsTriggered = false;
    mssTriggered = false;
    breakRetestTriggered = false;
    priceActionTriggered = false;
    volumeTriggered = false;
    crtTriggered = false;
    amdTriggered = false;
    liquidityGrabTriggered = false;
    breakoutTriggered = false;
}
//+------------------------------------------------------------------+
//| Implement Trailing Stop Loss                                     |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
    double activationPips = 3.0; // Trailing stop activates after 30 pips (3.0 on Gold)
    double trailingPips = 1.0;   // Trailing stop distance is 10 pips (1.0 on Gold)

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                                  SymbolInfoDouble(symbol, SYMBOL_BID) :
                                  SymbolInfoDouble(symbol, SYMBOL_ASK);
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double activationLevel = entryPrice + activationPips * point * ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1);
            double newStopLoss;

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                if (currentPrice > activationLevel && (currentPrice - trailingPips * point) > stopLoss)
                {
                    newStopLoss = currentPrice - trailingPips * point;
                    Trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
                    Print("Trailing Stop adjusted for BUY position: ", ticket);
                }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                if (currentPrice < activationLevel && (currentPrice + trailingPips * point) < stopLoss)
                {
                    newStopLoss = currentPrice + trailingPips * point;
                    Trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
                    Print("Trailing Stop adjusted for SELL position: ", ticket);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
//| Manage Open Trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    double profitThreshold = 1000.0; // Example profit threshold

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);

            // Close the position if it reaches the profit threshold
            if (profit >= profitThreshold)
            {
                Trade.PositionClose(ticket);
                Print("Position closed due to reaching profit threshold: ", ticket);
            }
        }
    }
}
//+------------------------------------------------------------------+
//| Logging and Notifications                                        |
//+------------------------------------------------------------------+
void LogTradeActivity(string message)
{
    Print(message);
    // Optionally, send notifications
    // SendNotification(message);
}

//+------------------------------------------------------------------+
//| Error Handling                                                   |
//+------------------------------------------------------------------+

// Function to log error messages
void LogError(string context)
{
    int errorCode = GetLastError();
    string errorMessage = ErrorDescription(errorCode);
    Print("Error in ", context, ": [", errorCode, "] ", errorMessage);
    ResetLastError(); // Clear the last error
}

//+------------------------------------------------------------------+
//| Function to place an order with error handling                   |
//+------------------------------------------------------------------+
bool ExecuteTradeWithErrorHandling(string symbol, int orderType, double lotSize, double stopLossPips, double takeProfitPips)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

    // Calculate SL and TP prices
    double stopLossPrice, takeProfitPrice;
    if (orderType == 0) // Buy order
    {
        stopLossPrice = bidPrice - stopLossPips * point;
        takeProfitPrice = bidPrice + takeProfitPips * point;
    }
    else // Sell order
    {
        stopLossPrice = askPrice + stopLossPips * point;
        takeProfitPrice = askPrice - takeProfitPips * point;
    }

    Print("Placing order with SL: ", stopLossPrice, " and TP: ", takeProfitPrice);

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lotSize;
    request.deviation = 2; // Example slippage
    request.type_filling = ORDER_FILLING_FOK;

    if (orderType == 0) // Buy order
    {
        request.type = ORDER_TYPE_BUY;
        request.price = askPrice;
    }
    else // Sell order
    {
        request.type = ORDER_TYPE_SELL;
        request.price = bidPrice;
    }

    request.sl = stopLossPrice;
    request.tp = takeProfitPrice;
    request.comment = orderType == 0 ? "Buy order" : "Sell order";

    // Print the request details for debugging
    Print("Request details: ",
          "Symbol: ", request.symbol,
          ", Volume: ", request.volume,
          ", Type: ", request.type,
          ", Price: ", request.price,
          ", SL: ", request.sl,
          ", TP: ", request.tp);

    if (!OrderSend(request, result))
    {
        Print("OrderSend failed with error #", GetLastError());
        return false;
    }
    else
    {
        Print("OrderSend succeeded with ticket #", result.order);
        return true;
    }
}

//+------------------------------------------------------------------+
//| Recovery Mechanism                                               |
//+------------------------------------------------------------------+

// Function to check connection status
bool IsConnected()
{
    return TerminalInfoInteger(TERMINAL_CONNECTED);
}

// Function to retry trade execution
bool RetryTradeExecution(string symbol, int orderType, double lotSize, double stopLossPips, double takeProfitPips, int maxRetries)
{
    int retries = 0;
    while (retries < maxRetries)
    {
        if (IsConnected())
        {
            if (ExecuteTradeWithErrorHandling(symbol, orderType, lotSize, stopLossPips, takeProfitPips))
                return true;
        }
        Print("Retrying trade execution... Attempt: ", retries + 1);
        Sleep(1000); // Wait for 1 second before retrying
        retries++;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Supporting Functions                                             |
//+------------------------------------------------------------------+

// Function to check trend alignment across multiple timeframes
bool CheckTrendAlignment(string symbol)
{
    // Example trend alignment logic using moving averages
    double maShort = iMA(symbol, PERIOD_M15, 50, 0, MODE_SMA, PRICE_CLOSE);
    double maLong = iMA(symbol, PERIOD_H1, 200, 0, MODE_SMA, PRICE_CLOSE);
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

    if (currentPrice > maShort && currentPrice > maLong)
    {
        Print("Trend is aligned (Bullish).");
        return true;
    }
    if (currentPrice < maShort && currentPrice < maLong)
    {
        Print("Trend is aligned (Bearish).");
        return true;
    }

    Print("Trend is not aligned.");
    return false;
}

// Function to send an order with a comment using XM broker-compatible method
void SendOrderWithComment(string symbol, ENUM_ORDER_TYPE orderType, double lotSize, double entryPrice, double slPrice, double tpPrice, string comment)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = entryPrice;
    request.sl = slPrice;
    request.tp = tpPrice;
    request.deviation = 10; // Maximum price deviation in points
    request.magic = 123456; // Magic number for the order
    request.comment = comment;

    if (OrderSend(request, result))
    {
        Print("Order placed successfully: ", comment);
    }
    else
    {
        Print("Failed to place order: ", ResultRetcodeDescription(result.retcode));
    }
}

// Function to get the previous swing low
double GetPreviousSwingLow(string symbol, ENUM_TIMEFRAMES period)
{
    int bars = 10; // Number of bars to check for swing low
    double swingLow = iLow(symbol, period, bars);

    for (int i = 1; i < bars; i++)
    {
        double low = iLow(symbol, period, i);
        if (low < swingLow)
        {
            swingLow = low;
        }
    }

    return swingLow;
}

// Function to get the previous swing high
double GetPreviousSwingHigh(string symbol, ENUM_TIMEFRAMES period)
{
    int bars = 10; // Number of bars to check for swing high
    double swingHigh = iHigh(symbol, period, bars);

    for (int i = 1; i < bars; i++)
    {
        double high = iHigh(symbol, period, i);
        if (high > swingHigh)
        {
            swingHigh = high;
        }
    }

    return swingHigh;
}

// Function to get the next liquidity target
double GetNextLiquidityTarget(string symbol, ENUM_TIMEFRAMES period, int orderType)
{
    int bars = 10; // Number of bars to check for liquidity target
    double liquidityTarget = (orderType == 0) ? iHigh(symbol, period, bars) : iLow(symbol, period, bars);

    for (int i = 1; i < bars; i++)
    {
        double price = (orderType == 0) ? iHigh(symbol, period, i) : iLow(symbol, period, i);
        if ((orderType == 0 && price > liquidityTarget) || (orderType == 1 && price < liquidityTarget))
        {
            liquidityTarget = price;
        }
    }

    return liquidityTarget;
}


// Function to get error description
string ErrorDescription(int errorCode)
{
    switch (errorCode)
    {
        case 0: // ERR_NO_ERROR
            return "No error";
        case 1: // ERR_COMMON_ERROR
            return "Common error";
        case 3: // ERR_INVALID_TRADE_PARAMETERS
            return "Invalid trade parameters";
        // Add other error codes and descriptions as needed
        default:
            return "Unknown error";
    }
}

// Function to get result retcode description
string ResultRetcodeDescription(int retcode)
{
    switch (retcode)
    {
        case 10009: // TRADE_RETCODE_DONE
            return "Trade operation completed successfully";
        case 10006: // TRADE_RETCODE_ERROR
            return "Trade operation failed";
        // Add other result retcodes and descriptions as needed
        default:
            return "Unknown retcode";
    }
}