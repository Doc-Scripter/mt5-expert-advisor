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
   if(g_ema.handle == INVALID_HANDLE)
   {
      Print("IsEngulfing: Invalid EMA handle");
      return false;
   }
      
   int i = shift;
   int priorIdx = i + 1;
   int bars = ArraySize(g_ema.values);
   
   if(priorIdx >= bars)
   {
      Print("IsEngulfing: Not enough bars in array. Required: ", priorIdx + 1, ", Available: ", bars);
      return false;
   }
      
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, i);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, i);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, priorIdx);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, priorIdx);
   
   if(open1 == 0 || close1 == 0 || open2 == 0 || close2 == 0)
   {
      Print("IsEngulfing: Invalid price data detected for shift ", shift);
      return false;
   }
      
   double tolerance = _Point;
   
   bool trendOkBull = !useTrendFilter;
   bool trendOkBear = !useTrendFilter;
   
   if(useTrendFilter)
   {
      double maPrior = g_ema.values[priorIdx];
      double midOCPrior = (open2 + close2) / 2.0;
      trendOkBull = midOCPrior < maPrior;
      trendOkBear = midOCPrior > maPrior;
   }
   
   if(bullish)
   {
      bool priorIsBearish = (close2 < open2 - tolerance);
      bool currentIsBullish = (close1 > open1 + tolerance);
      bool engulfsBody = (open1 < close2 - tolerance) && (close1 > open2 + tolerance);
      
   if(priorIsBearish && currentIsBullish && engulfsBody && trendOkBull)
   {
      Print("IsEngulfing: Bullish engulfing pattern detected at shift ", shift);
      DrawEngulfingPattern(i, true);
      return true;
   }
   }
   else
   {
      bool priorIsBullish = (close2 > open2 + tolerance);
      bool currentIsBearish = (close1 < open1 - tolerance);
      bool engulfsBody = (open1 > close2 + tolerance) && (close1 < open2 - tolerance);
      
   if(priorIsBullish && currentIsBearish && engulfsBody && trendOkBear)
   {
      Print("IsEngulfing: Bearish engulfing pattern detected at shift ", shift);
      DrawEngulfingPattern(i, false);
      return true;
   }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Draw engulfing pattern marker                                     |
//+------------------------------------------------------------------+
void DrawEngulfingPattern(int shift, bool bullish)
{
   string objName = "Engulfing_" + IntegerToString(shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   datetime time = iTime(_Symbol, PERIOD_CURRENT, shift);
   
   ObjectDelete(0, objName);
   ObjectCreate(0, objName, OBJ_ARROW, 0, time, bullish ? low : high);
   ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, bullish ? 225 : 226);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, bullish ? ENGULFING_BULLISH_COLOR : ENGULFING_BEARISH_COLOR);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
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
   
   int bars = ArraySize(g_ema.values);
   if(bars < 3)
   {
      Print("DrawEMALine: Insufficient bars for visualization. Available: ", bars);
      return;
   }
   
   // Delete ALL possible EMA lines first
   ObjectsDeleteAll(0, "EMA_Line");
   
   // Use available bars for visualization
   int lookback = MathMin(10, bars - 1);
   
   string objName = "EMA_Line";
   ObjectCreate(0, objName, OBJ_TREND, 0, 
      iTime(_Symbol, PERIOD_CURRENT, lookback), g_ema.values[lookback],
      iTime(_Symbol, PERIOD_CURRENT, 0), g_ema.values[0]);
   
   // Set line properties
   ObjectSetInteger(0, objName, OBJPROP_COLOR, EMA_LINE_COLOR);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   
   ChartRedraw(0);  // Force chart redraw to ensure clean display
}
