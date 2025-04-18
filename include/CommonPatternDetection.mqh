//+------------------------------------------------------------------+
//|                                     CommonPatternDetection.mqh     |
//|                                                                    |
//|            Common EMA and Engulfing Pattern Detection Logic        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"

// Common Constants
#define EMA_PERIOD 20

// EMA Indicator Handle and Values
class CEMAValues
{
public:
   int handle;
   double values[];
   
   CEMAValues() : handle(INVALID_HANDLE) {}
};

CEMAValues g_ema;

// Pattern Detection Colors
color ENGULFING_BULLISH_COLOR = clrLime;
color ENGULFING_BEARISH_COLOR = clrRed;
color EMA_LINE_COLOR = clrRed;  // Changed from clrBlue to clrRed

//+------------------------------------------------------------------+
//| Initialize EMA indicator                                          |
//+------------------------------------------------------------------+
bool InitializeEMA()
{
   Print("InitializeEMA: Starting initialization...");
   
   if(g_ema.handle != INVALID_HANDLE)
   {
      Print("InitializeEMA: EMA already initialized with handle ", g_ema.handle);
      return true;
   }
   
   g_ema.handle = iMA(_Symbol, PERIOD_CURRENT, EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("InitializeEMA: Failed to create EMA indicator handle");
      return false;
   }
   
   Print("InitializeEMA: Successfully initialized with handle ", g_ema.handle);
   return true;
}

//+------------------------------------------------------------------+
//| Release EMA indicator                                             |
//+------------------------------------------------------------------+
void ReleaseEMA()
{
   Print("ReleaseEMA: Starting cleanup...");
   
   if(g_ema.handle != INVALID_HANDLE)
   {
      Print("ReleaseEMA: Releasing indicator handle ", g_ema.handle);
      if(!IndicatorRelease(g_ema.handle))
      {
         Print("ReleaseEMA: Failed to release indicator handle. Error: ", GetLastError());
      }
      g_ema.handle = INVALID_HANDLE;
      ArrayFree(g_ema.values);
      Print("ReleaseEMA: Cleanup completed");
   }
   else
   {
      Print("ReleaseEMA: No handle to release");
   }
}

//+------------------------------------------------------------------+
//| Update EMA values                                                 |
//+------------------------------------------------------------------+
bool UpdateEMAValues(int requiredBars)
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("UpdateEMAValues: Invalid EMA handle");
      return false;
   }
      
   // Use requested bars but ensure minimum of 3 for basic functionality
   int minBars = MathMax(requiredBars, 3);
   ArrayResize(g_ema.values, minBars);
   ArraySetAsSeries(g_ema.values, true);
   
   int copied = CopyBuffer(g_ema.handle, 0, 0, minBars, g_ema.values);
   if(copied < minBars)
   {
      Print("UpdateEMAValues: Failed to copy EMA values. Requested: ", minBars, ", Copied: ", copied);
      return false;
   }
   
   Print("UpdateEMAValues: Successfully copied ", copied, " bars");
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern                                       |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish, bool useTrendFilter = true, int lookbackCandles = 10)
{
    if (g_ema.handle == INVALID_HANDLE && useTrendFilter)
    {
        Print("IsEngulfing: Invalid EMA handle for trend filter");
        return false;
    }

    // Validate lookback parameter
    lookbackCandles = MathMax(1, lookbackCandles); // Ensure at least 1 candle is checked
    
    int maxIdx = shift + lookbackCandles;
    int bars = Bars(_Symbol, PERIOD_CURRENT);

    if (maxIdx >= bars)
    {
        Print("IsEngulfing: Not enough bars available. Required: ", maxIdx + 1, ", Available: ", bars);
        return false;
    }

    // Current candle data
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low1 = iLow(_Symbol, PERIOD_CURRENT, shift);

    PrintFormat("IsEngulfing: Checking candle at shift %d: Open=%.5f, Close=%.5f, High=%.5f, Low=%.5f", 
                shift, open1, close1, high1, low1);

    // Determine current candle direction
    bool currentIsBullish = (close1 > open1);
    bool currentIsBearish = (close1 < open1);
    
    // Use a small tolerance relative to the price to avoid false signals due to tiny differences
    double tolerance = _Point;

    // Check trend filter if required
    bool trendOkBull = !useTrendFilter; // Default to true if not using trend filter
    bool trendOkBear = !useTrendFilter;

    if (useTrendFilter)
    {
        // Make sure we have enough EMA values
        if (ArraySize(g_ema.values) <= shift + 1)
        {
            Print("IsEngulfing: Not enough EMA values for trend filter");
            return false;
        }
        
        double maValue = g_ema.values[shift];
        double maPrior = g_ema.values[shift + 1];
        
        // For bullish pattern, price should be above EMA or EMA should be rising
        trendOkBull = (close1 > maValue) || (maValue > maPrior);
        
        // For bearish pattern, price should be below EMA or EMA should be falling
        trendOkBear = (close1 < maValue) || (maValue < maPrior);
        
        PrintFormat("IsEngulfing: Trend filter - EMA(current)=%.5f, EMA(prior)=%.5f, Bull OK=%s, Bear OK=%s", 
                   maValue, maPrior, trendOkBull ? "Yes" : "No", trendOkBear ? "Yes" : "No");
    }

    // Calculate average candle sizes from previous candles
    double totalBodySize = 0;
    double totalCandleSize = 0;
    
    for (int i = 1; i <= lookbackCandles; i++)
    {
        int idx = shift + i;
        double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, idx);
        double prevClose = iClose(_Symbol, PERIOD_CURRENT, idx);
        double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, idx);
        double prevLow = iLow(_Symbol, PERIOD_CURRENT, idx);
        
        double bodySize = MathAbs(prevClose - prevOpen);
        double candleSize = prevHigh - prevLow;
        
        totalBodySize += bodySize;
        totalCandleSize += candleSize;
    }
    
    double avgBodySize = totalBodySize / lookbackCandles;
    double avgCandleSize = totalCandleSize / lookbackCandles;
    
    // Calculate current candle sizes
    double currentBodySize = MathAbs(close1 - open1);
    double currentCandleSize = high1 - low1;
    
    // Check if current candle is at least 30% larger than average
    bool isSizeSignificant = (currentBodySize >= avgBodySize * 1.3) || 
                             (currentCandleSize >= avgCandleSize * 1.3);
    
    PrintFormat("IsEngulfing: Size analysis - Avg Body=%.5f, Current Body=%.5f, Avg Candle=%.5f, Current Candle=%.5f, Significant=%s", 
               avgBodySize, currentBodySize, avgCandleSize, currentCandleSize, isSizeSignificant ? "Yes" : "No");
    
    if (!isSizeSignificant)
    {
        Print("IsEngulfing: Candle size not significant enough (30% larger than average required)");
        return false;
    }

    // Track which candles are engulfed
    int engulfedCandles = 0;
    string engulfedDetails = "";
    
    // Check each previous candle
    for (int i = 1; i <= lookbackCandles; i++)
    {
        int currentIdx = shift + i;
        double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, currentIdx);
        double prevClose = iClose(_Symbol, PERIOD_CURRENT, currentIdx);
        double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, currentIdx);
        double prevLow = iLow(_Symbol, PERIOD_CURRENT, currentIdx);
        
        PrintFormat("IsEngulfing: Checking previous candle at shift %d: Open=%.5f, Close=%.5f, High=%.5f, Low=%.5f", 
                    currentIdx, prevOpen, prevClose, prevHigh, prevLow);
        
        bool canEngulf = false;
        
        if (bullish)
        {
            bool prevIsBearish = (prevClose < prevOpen - tolerance);
            bool currentIsBullishWithTolerance = (close1 > open1 + tolerance);
            
            // Check for body engulfing
            bool engulfsBody = (open1 <= prevClose - tolerance) && (close1 >= prevOpen + tolerance);
            
            // Check for shadow engulfing
            bool engulfsShadow = (low1 <= prevLow - tolerance) && (high1 >= prevHigh + tolerance);

            // Pattern is valid if either body OR shadow engulfs
            canEngulf = prevIsBearish && currentIsBullishWithTolerance && (engulfsBody || engulfsShadow) && trendOkBull;
        }
        else
        {
            bool prevIsBullish = (prevClose > prevOpen + tolerance);
            bool currentIsBearishWithTolerance = (close1 < open1 - tolerance);
            
            // Check for body engulfing
            bool engulfsBody = (open1 >= prevClose + tolerance) && (close1 <= prevOpen - tolerance);
            
            // Check for shadow engulfing
            bool engulfsShadow = (low1 <= prevLow - tolerance) && (high1 >= prevHigh + tolerance);

            // Pattern is valid if either body OR shadow engulfs
            canEngulf = prevIsBullish && currentIsBearishWithTolerance && (engulfsBody || engulfsShadow) && trendOkBear;
        }
        
        if (canEngulf)
        {
            engulfedCandles++;
            engulfedDetails += " Candle at shift " + IntegerToString(currentIdx) + " is engulfed.";
            
            // If we only need one engulfed candle, we can return immediately
            Print("IsEngulfing: ", (bullish ? "Bullish" : "Bearish"), " engulfing pattern detected at shift ", shift, 
                  ". Engulfed candle at shift ", currentIdx, ". Size is significant (>30% larger than average)");
            DrawEngulfingPattern(shift, bullish);
            return true;
        }
    }

    Print("IsEngulfing: No engulfing pattern detected at shift ", shift);
    return false;
}

//+------------------------------------------------------------------+
//| Draw engulfing pattern marker                                     |
//+------------------------------------------------------------------+
void DrawEngulfingPattern(int shift, bool bullish)
{
    string objName = "EngulfPattern_" + IntegerToString(TimeCurrent() + shift);
    datetime patternTime = iTime(_Symbol, PERIOD_CURRENT, shift);
    double patternPrice = bullish ? iLow(_Symbol, PERIOD_CURRENT, shift) - 10 * _Point 
                                : iHigh(_Symbol, PERIOD_CURRENT, shift) + 10 * _Point;
    
    // Delete existing object if it exists
    ObjectDelete(0, objName);
    
    // Create arrow object
    if(!ObjectCreate(0, objName, OBJ_ARROW, 0, patternTime, patternPrice))
    {
        Print("Failed to create engulfing pattern marker. Error: ", GetLastError());
        return;
    }
    
    // Set object properties
    ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, bullish ? 233 : 234);  // Up/Down arrow
    ObjectSetInteger(0, objName, OBJPROP_COLOR, bullish ? ENGULFING_BULLISH_COLOR : ENGULFING_BEARISH_COLOR);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
    
    ChartRedraw(0);
}


//+------------------------------------------------------------------+
//| Draw EMA line                                                     |
//+------------------------------------------------------------------+
void DrawEMALine()
{
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("DrawEMALine: Invalid EMA handle");
      return;
   }
   
   // Define the number of candles to draw EMA for (300 for proper trend analysis)
   const int REQUIRED_CANDLES = 300;
   
   // Ensure we have enough EMA values
   if(ArraySize(g_ema.values) < REQUIRED_CANDLES)
   {
      // Resize and update the EMA values array
      if(!UpdateEMAValues(REQUIRED_CANDLES))
      {
         Print("DrawEMALine: Failed to update EMA values for ", REQUIRED_CANDLES, " candles");
         return;
      }
   }
   
   int available = ArraySize(g_ema.values);
   if(available < 2)
   {
      Print("DrawEMALine: Not enough data points. Available: ", available);
      return;
   }
   
   // Delete existing EMA lines
   ObjectsDeleteAll(0, "EMA_Line");
   
   // Draw EMA line segments connecting available points
   // Limit to REQUIRED_CANDLES or available candles, whichever is smaller
   int candles_to_draw = MathMin(available, REQUIRED_CANDLES);
   
   datetime time1, time2;
   double price1, price2;
   
   Print("DrawEMALine: Drawing EMA for ", candles_to_draw, " candles");
   
   for(int i = 1; i < candles_to_draw; i++)
   {
      string objName = "EMA_Line_" + IntegerToString(i);
      
      time1 = iTime(_Symbol, PERIOD_CURRENT, i);
      time2 = iTime(_Symbol, PERIOD_CURRENT, i-1);
      price1 = g_ema.values[i];
      price2 = g_ema.values[i-1];
      
      if(!ObjectCreate(0, objName, OBJ_TREND, 0, time1, price1, time2, price2))
      {
         Print("Failed to create EMA line segment. Error: ", GetLastError());
         continue;
      }
      
      ObjectSetInteger(0, objName, OBJPROP_COLOR, EMA_LINE_COLOR);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   }
   
   ChartRedraw(0);
}
