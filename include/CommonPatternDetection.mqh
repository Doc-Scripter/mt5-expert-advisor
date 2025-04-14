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
bool IsEngulfing(int shift, bool bullish, bool useTrendFilter = false)
{
    if (g_ema.handle == INVALID_HANDLE && useTrendFilter)
    {
        Print("IsEngulfing: Invalid EMA handle for trend filter");
        return false;
    }

    int priorIdx = shift + 1;
    int bars = Bars(_Symbol, PERIOD_CURRENT);

    if (priorIdx >= bars)
    {
        Print("IsEngulfing: Not enough bars available. Required: ", priorIdx + 1, ", Available: ", bars);
        return false;
    }

    double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low1 = iLow(_Symbol, PERIOD_CURRENT, shift);

    double open2 = iOpen(_Symbol, PERIOD_CURRENT, priorIdx);
    double close2 = iClose(_Symbol, PERIOD_CURRENT, priorIdx);
    double high2 = iHigh(_Symbol, PERIOD_CURRENT, priorIdx);
    double low2 = iLow(_Symbol, PERIOD_CURRENT, priorIdx);

    PrintFormat("IsEngulfing: Checking candle at shift %d: Open=%.5f, Close=%.5f, High=%.5f, Low=%.5f", 
                shift, open1, close1, high1, low1);
    PrintFormat("IsEngulfing: Previous candle at shift %d: Open=%.5f, Close=%.5f, High=%.5f, Low=%.5f", 
                priorIdx, open2, close2, high2, low2);

    double tolerance = _Point;

    bool trendOkBull = !useTrendFilter;
    bool trendOkBear = !useTrendFilter;

    if (useTrendFilter)
    {
        // Make sure we have enough EMA values
        if (ArraySize(g_ema.values) <= priorIdx)
        {
            Print("IsEngulfing: Not enough EMA values for trend filter");
            return false;
        }
        
        double maValue = g_ema.values[shift];
        double maPrior = g_ema.values[priorIdx];
        
        // For bullish pattern, price should be above EMA or EMA should be rising
        trendOkBull = (close1 > maValue) || (maValue > maPrior);
        
        // For bearish pattern, price should be below EMA or EMA should be falling
        trendOkBear = (close1 < maValue) || (maValue < maPrior);
        
        PrintFormat("IsEngulfing: Trend filter - EMA(current)=%.5f, EMA(prior)=%.5f, Bull OK=%s, Bear OK=%s", 
                   maValue, maPrior, trendOkBull ? "Yes" : "No", trendOkBear ? "Yes" : "No");
    }

    if (bullish)
    {
        bool priorIsBearish = (close2 < open2 - tolerance);
        bool currentIsBullish = (close1 > open1 + tolerance);
        
        // Check for body engulfing
        bool engulfsBody = (open1 <= close2 - tolerance) && (close1 >= open2 + tolerance);
        
        // Check for shadow engulfing
        bool engulfsShadow = (low1 <= low2 - tolerance) && (high1 >= high2 + tolerance);

        // Pattern is valid if either body OR shadow engulfs
        if (priorIsBearish && currentIsBullish && (engulfsBody || engulfsShadow) && trendOkBull)
        {
            Print("IsEngulfing: Bullish engulfing pattern detected at shift ", shift);
            DrawEngulfingPattern(shift, true);
            return true;
        }
    }
    else
    {
        bool priorIsBullish = (close2 > open2 + tolerance);
        bool currentIsBearish = (close1 < open1 - tolerance);
        
        // Check for body engulfing
        bool engulfsBody = (open1 >= close2 + tolerance) && (close1 <= open2 - tolerance);
        
        // Check for shadow engulfing
        bool engulfsShadow = (low1 <= low2 - tolerance) && (high1 >= high2 + tolerance);

        // Pattern is valid if either body OR shadow engulfs
        if (priorIsBullish && currentIsBearish && (engulfsBody || engulfsShadow) && trendOkBear)
        {
            Print("IsEngulfing: Bearish engulfing pattern detected at shift ", shift);
            DrawEngulfingPattern(shift, false);
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
   
   int available = ArraySize(g_ema.values);
   if(available < 2)
   {
      Print("DrawEMALine: Not enough data points. Available: ", available);
      return;
   }
   
   // Delete existing EMA lines
   ObjectsDeleteAll(0, "EMA_Line");
   
   // Draw EMA line segments connecting available points
   datetime time1, time2;
   double price1, price2;
   
   for(int i = 1; i < available; i++)
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
