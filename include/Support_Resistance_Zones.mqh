#property copyright "Copyright 2023"
#property strict

// Constants
#define SR_MIN_TOUCHES 1  // Reduced from 2 to 1 for testing
#define ZONE_LOOKBACK 100  // Reduced from 300 to 100 candles

// Colors for zones
color SUPPORT_ZONE_COLOR = clrRed;
color RESISTANCE_ZONE_COLOR = clrBlue;

// Support/Resistance Zone Structure
struct SRZone
{
   double topBoundary;
   double bottomBoundary;
   double definingClose;
   bool isResistance;
   int touchCount;
   long chartObjectID_Top;
   long chartObjectID_Bottom;
   int shift;
};

// Add tracking for drawn zones
struct DrawnZone
{
    long chartObjectID_Top;
    long chartObjectID_Bottom;
    bool isActive;
};

// Global S/R Zone Arrays
SRZone g_activeSupportZones[];
SRZone g_activeResistanceZones[];
int g_nearestSupportZoneIndex = -1;
int g_nearestResistanceZoneIndex = -1;

// Global array to track drawn zones
DrawnZone g_drawnZones[];

// Add after the existing global variables
bool g_isAboveEMA = false;  // Tracks if price is above EMA

// Function implementations from Strategy2_SR_Engulfing_EA.mq5
// Copy all functions exactly as they are but remove their definitions from the EA

// Replace the existing UpdateAndDrawValidSRZones function with this implementation
void UpdateAndDrawValidSRZones(int lookbackPeriod, int sensitivityPips, double emaValue)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int available = CopyRates(_Symbol, PERIOD_CURRENT, 0, lookbackPeriod, rates);
    
    if(available < 2)  // Need at least 2 bars for comparison
    {
        Print("UpdateAndDrawValidSRZones: Insufficient data, bars available: ", available);
        return;
    }
    
    // Use available data even if less than requested
    lookbackPeriod = available;

    double sensitivity = sensitivityPips * _Point;
    
    // Add at the beginning of UpdateAndDrawValidSRZones after getting rates
    if(rates[0].close == rates[0].high && rates[0].close == rates[0].low)
    {
        // Skip invalid/incomplete candles
        return;
    }

    // Check if current candle breaks any existing zones
    for(int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        // Resistance is broken if candle closes above the zone
        if(rates[0].close > g_activeResistanceZones[i].topBoundary)
        {
            DeleteZoneObjects(g_activeResistanceZones[i]);
            ArrayRemove(g_activeResistanceZones, i, 1);
        }
    }

    for(int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        // Support is broken if candle closes below the zone
        if(rates[0].close < g_activeSupportZones[i].bottomBoundary)
        {
            DeleteZoneObjects(g_activeSupportZones[i]);
            ArrayRemove(g_activeSupportZones, i, 1);
        }
    }

    // Check for new zones
    if(rates[1].close > rates[0].close) // Potential support
    {
        double zonePrice = rates[0].low;
        if(!HasActiveZoneNearby(zonePrice, sensitivity))
        {
            SRZone newZone;
            newZone.bottomBoundary = zonePrice;
            newZone.topBoundary = MathMax(rates[0].open, rates[0].close);
            newZone.definingClose = rates[0].close;
            newZone.isResistance = false;
            newZone.shift = 0;
            newZone.chartObjectID_Top = TimeCurrent();
            newZone.chartObjectID_Bottom = TimeCurrent() + 1;

            if(ArrayResize(g_activeSupportZones, ArraySize(g_activeSupportZones) + 1) > 0)
            {
                g_activeSupportZones[ArraySize(g_activeSupportZones) - 1] = newZone;
                DrawZoneLines(newZone, SUPPORT_ZONE_COLOR);
            }
        }
    }
    else if(rates[1].close < rates[0].close) // Potential resistance
    {
        double zonePrice = rates[0].high;
        if(!HasActiveZoneNearby(zonePrice, sensitivity))
        {
            SRZone newZone;
            newZone.bottomBoundary = MathMin(rates[0].open, rates[0].close);
            newZone.topBoundary = zonePrice;
            newZone.definingClose = rates[0].close;
            newZone.isResistance = true;
            newZone.shift = 0;
            newZone.chartObjectID_Top = TimeCurrent();
            newZone.chartObjectID_Bottom = TimeCurrent() + 1;

            if(ArrayResize(g_activeResistanceZones, ArraySize(g_activeResistanceZones) + 1) > 0)
            {
                g_activeResistanceZones[ArraySize(g_activeResistanceZones) - 1] = newZone;
                DrawZoneLines(newZone, RESISTANCE_ZONE_COLOR);
            }
        }
    }
}

// New function to check for broken zones
void CheckAndRemoveBrokenZones(const MqlRates &rates[], double emaValue)
{
    // Check resistance zones
    for(int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        if(IsZoneBroken(g_activeResistanceZones[i], rates, 0, emaValue))
        {
            // Remove the zone's visual elements
            DeleteZoneObjects(g_activeResistanceZones[i]);
            // Remove from active zones array
            ArrayRemove(g_activeResistanceZones, i, 1);
        }
    }
    
    // Check support zones
    for(int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        if(IsZoneBroken(g_activeSupportZones[i], rates, 0, emaValue))
        {
            // Remove the zone's visual elements
            DeleteZoneObjects(g_activeSupportZones[i]);
            // Remove from active zones array
            ArrayRemove(g_activeSupportZones, i, 1);
        }
    }
}

// Update DeleteZoneObjects to ensure complete removal
void DeleteZoneObjects(const SRZone &zone)
{
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    
    // Force deletion of both lines
    if(ObjectFind(0, topName) >= 0)
        ObjectDelete(0, topName);
    if(ObjectFind(0, bottomName) >= 0)
        ObjectDelete(0, bottomName);
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw individual zone lines                                       |
//+------------------------------------------------------------------+
void DrawZoneLines(const SRZone &zone, const color lineColor)
{
    string topName = StringFormat("SRZone_%d_Top", zone.chartObjectID_Top);
    string bottomName = StringFormat("SRZone_%d_Bottom", zone.chartObjectID_Bottom);
    
    Print("Attempting to draw zone lines: ", topName, " and ", bottomName);
    
    // Delete any existing lines first
    ObjectDelete(0, topName);
    ObjectDelete(0, bottomName);
    
    // Get time range for the lines
    datetime startTime = iTime(_Symbol, PERIOD_CURRENT, zone.shift);
    datetime endTime = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT) * 100; // Extend into future
    
    Print("Creating zone lines from ", TimeToString(startTime), " to ", TimeToString(endTime));
    Print("Top boundary: ", zone.topBoundary, " Bottom boundary: ", zone.bottomBoundary);
    
    // Create top boundary line
    if(!ObjectCreate(0, topName, OBJ_TREND, 0, startTime, zone.topBoundary, endTime, zone.topBoundary))
    {
        Print("Failed to create top boundary line. Error: ", GetLastError());
        return;
    }
    
    // Create bottom boundary line
    if(!ObjectCreate(0, bottomName, OBJ_TREND, 0, startTime, zone.bottomBoundary, endTime, zone.bottomBoundary))
    {
        Print("Failed to create bottom boundary line. Error: ", GetLastError());
        ObjectDelete(0, topName);
        return;
    }
    
    // Set properties for top line
    ObjectSetInteger(0, topName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, topName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, topName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, topName, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, topName, OBJPROP_BACK, false);
    ObjectSetInteger(0, topName, OBJPROP_SELECTABLE, false);
    
    // Set properties for bottom line
    ObjectSetInteger(0, bottomName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, bottomName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, bottomName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, bottomName, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, bottomName, OBJPROP_BACK, false);
    ObjectSetInteger(0, bottomName, OBJPROP_SELECTABLE, false);
    
    // Fill the zone
    string fillName = StringFormat("SRZone_%d_Fill", zone.chartObjectID_Top);
    ObjectCreate(0, fillName, OBJ_RECTANGLE, 0, startTime, zone.topBoundary, endTime, zone.bottomBoundary);
    ObjectSetInteger(0, fillName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, fillName, OBJPROP_BACK, true);
    ObjectSetInteger(0, fillName, OBJPROP_FILL, true);
    ObjectSetInteger(0, fillName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, fillName, OBJPROP_HIDDEN, true);
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw zones and validate touches                                  |
//+------------------------------------------------------------------+
void DrawAndValidateZones(const MqlRates &rates[], double sensitivity, double emaValue)
{
   double currentPrice = rates[0].close;
   
   // Draw and validate resistance zones    
   for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
   {
      // Draw zone lines
      // Validate against current EMA before drawing
      bool isValid = g_activeResistanceZones[i].bottomBoundary > emaValue && 
                   g_activeResistanceZones[i].topBoundary > emaValue;
      color zoneColor = isValid ? clrRed : clrGray;
      DrawZoneLines(g_activeResistanceZones[i], zoneColor);
      
      // Count touches
      g_activeResistanceZones[i].touchCount = CountTouches(rates, g_activeResistanceZones[i], sensitivity, ZONE_LOOKBACK);
      
      // Update nearest resistance
      if(g_activeResistanceZones[i].bottomBoundary > currentPrice)
      {
         if(g_nearestResistanceZoneIndex == -1 || 
            g_activeResistanceZones[i].bottomBoundary < g_activeResistanceZones[g_nearestResistanceZoneIndex].bottomBoundary)
         {
            g_nearestResistanceZoneIndex = i;
         }
      }
   }
   
   // Draw and validate support zones
   for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
   {
      // Draw zone lines
      // Validate against current EMA before drawing
      bool isValid = g_activeSupportZones[i].topBoundary < emaValue && 
                   g_activeSupportZones[i].bottomBoundary < emaValue;
      color zoneColor = isValid ? clrGreen : clrGray;
      DrawZoneLines(g_activeSupportZones[i], zoneColor);
      
      // Count touches
      g_activeSupportZones[i].touchCount = CountTouches(rates, g_activeSupportZones[i], sensitivity, ZONE_LOOKBACK);
      
      // Update nearest support
      if(g_activeSupportZones[i].topBoundary < currentPrice)
      {
         if(g_nearestSupportZoneIndex == -1 || 
            g_activeSupportZones[i].topBoundary > g_activeSupportZones[g_nearestSupportZoneIndex].topBoundary)
         {
            g_nearestSupportZoneIndex = i;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add zone if it's valid (EMA position and proximity checks)       |
//+------------------------------------------------------------------+
bool AddZoneIfValid(SRZone &newZone, SRZone &existingZones[], double sensitivity, double emaValue)
{
    // Validate EMA position
    // Validate using the defining candle's open/close
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_CURRENT, newZone.shift, 1, rates);
    
    bool isValidEMA = newZone.isResistance 
        ? (rates[0].open > emaValue && rates[0].close > emaValue)
        : (rates[0].open < emaValue && rates[0].close < emaValue);
        
    if(!isValidEMA) {
        PrintFormat("Discarding %s zone - Boundaries [%.5f-%.5f] vs EMA %.5f",
                   newZone.isResistance ? "resistance" : "support",
                   newZone.bottomBoundary, newZone.topBoundary, emaValue);
        return false;
    }
    
    // Check if zone already exists
    for(int j = 0; j < ArraySize(existingZones); j++)
    {
        if(MathAbs(newZone.definingClose - existingZones[j].definingClose) < sensitivity)
            return false;
    }
    
    int size = ArraySize(existingZones);
    if(ArrayResize(existingZones, size + 1))
    {
        existingZones[size] = newZone;
        return true;
    }
    
    Print("Failed to resize zone array");
    return false;
}

// Update IsZoneBroken to be more precise
bool IsZoneBroken(const SRZone &zone, const MqlRates &rates[], int shift, double emaValue)
{
    if(shift >= ArraySize(rates)) return false;
    
    double candleOpen = rates[shift].open;
    double candleClose = rates[shift].close;
    bool isBullish = candleClose > candleOpen;
    
    if(zone.isResistance)
    {
        // Resistance broken when both open/close above zone
        if(candleOpen > zone.topBoundary && candleClose > zone.topBoundary)
        {
            Print("Resistance zone broken at ", TimeToString(rates[shift].time));
            // Only create new resistance zone if price is above EMA
            if(g_isAboveEMA)
            {
                CreateAndDrawNewZone(rates, shift, true, _Point * 10, emaValue);
            }
            return true;
        }
    }
    else
    {
        // Support broken when both open/close below zone
        if(candleOpen < zone.bottomBoundary && candleClose < zone.bottomBoundary)
        {
            Print("Support zone broken at ", TimeToString(rates[shift].time));
            // Only create new support zone if price is below EMA
            if(!g_isAboveEMA)
            {
                CreateAndDrawNewZone(rates, shift, false, _Point * 10, emaValue);
            }
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Count touches for a zone                                         |
//+------------------------------------------------------------------+
int CountTouches(const MqlRates &rates[], const SRZone &zone, double sensitivity, int lookbackPeriod = ZONE_LOOKBACK)
{
   int touches = 0;
   int barsToCheck = MathMin(lookbackPeriod, ArraySize(rates));
   
   for(int j = 0; j < barsToCheck; j++)
   {
      if(zone.isResistance)
      {
         if(MathAbs(rates[j].high - zone.topBoundary) <= sensitivity)
            touches++;
      }
      else
      {
         if(MathAbs(rates[j].low - zone.bottomBoundary) <= sensitivity)
            touches++;
      }
   }
   return touches;
}

//+------------------------------------------------------------------+
//| Delete all S/R zone lines                                        |
//+------------------------------------------------------------------+
void DeleteAllSRZoneLines()
{
   Print("DeleteAllSRZoneLines: Starting cleanup...");
   // Delete all objects with our prefix
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "SRZone_") == 0)
      {
         if(!ObjectDelete(0, objName))
         {
            Print("Failed to delete object ", objName, ". Error: ", GetLastError());
         }
      }
   }
   
   ChartRedraw(0);
   Print("DeleteAllSRZoneLines: Cleanup completed");
}

//+------------------------------------------------------------------+
//| Check if there's an active zone near the given price             |
//+------------------------------------------------------------------+
bool HasActiveZoneNearby(double price, double sensitivity)
{
    // Check resistance zones
    for(int i = 0; i < ArraySize(g_activeResistanceZones); i++)
    {
        if(MathAbs(price - g_activeResistanceZones[i].definingClose) < sensitivity)
            return true;
    }
    
    // Check support zones
    for(int i = 0; i < ArraySize(g_activeSupportZones); i++)
    {
        if(MathAbs(price - g_activeSupportZones[i].definingClose) < sensitivity)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if a new zone is valid at the given position               |
//+------------------------------------------------------------------+
bool IsNewValidZone(const MqlRates &rates[], int shift, double emaValue, bool isResistance)
{
    if(isResistance)
    {
        return rates[shift].close > emaValue &&                    // Price above EMA
               rates[shift].close > rates[shift-1].close &&        // Higher than previous
               rates[shift].close > rates[shift+1].close;          // Higher than next
    }
    else
    {
        return rates[shift].close < emaValue &&                    // Price below EMA
               rates[shift].close < rates[shift-1].close &&        // Lower than previous
               rates[shift].close < rates[shift+1].close;          // Lower than next
    }
}

//+------------------------------------------------------------------+
//| Create and draw a new zone                                       |
//+------------------------------------------------------------------+
void CreateAndDrawNewZone(const MqlRates &rates[], int shift, bool isResistance, double sensitivity, double emaValue)
{
    SRZone newZone;
    newZone.definingClose = rates[shift].close;
    newZone.shift = shift;
    newZone.isResistance = isResistance;
    newZone.touchCount = 1;
    
    if(isResistance)
    {
        newZone.bottomBoundary = MathMin(rates[shift].open, rates[shift].close);
        newZone.topBoundary = rates[shift].high;
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        
        AddZoneIfValid(newZone, g_activeResistanceZones, sensitivity, emaValue);
    }
    else
    {
        newZone.bottomBoundary = rates[shift].low;
        newZone.topBoundary = MathMax(rates[shift].open, rates[shift].close);
        newZone.chartObjectID_Top = TimeCurrent() + shift;
        newZone.chartObjectID_Bottom = TimeCurrent() + shift + 1;
        
        AddZoneIfValid(newZone, g_activeSupportZones, sensitivity, emaValue);
    }
    
    DrawZoneLines(newZone, isResistance ? RESISTANCE_ZONE_COLOR : SUPPORT_ZONE_COLOR);
}

// Add new function to count and validate zone touches
void CountAndValidateZoneTouches(const MqlRates &rates[], double sensitivity, int lookbackPeriod)
{
    // Process resistance zones
    for(int i = ArraySize(g_activeResistanceZones) - 1; i >= 0; i--)
    {
        g_activeResistanceZones[i].touchCount = CountTouches(rates, g_activeResistanceZones[i], sensitivity, lookbackPeriod);
        if(g_activeResistanceZones[i].touchCount < SR_MIN_TOUCHES)
        {
            Print("Removing resistance zone at ", g_activeResistanceZones[i].topBoundary, 
                  " - only ", g_activeResistanceZones[i].touchCount, " touches");
            ArrayRemove(g_activeResistanceZones, i, 1);
            continue;
        }
        else
        {
            Print("Keeping resistance zone at ", g_activeResistanceZones[i].topBoundary,
                  " - ", g_activeResistanceZones[i].touchCount, " touches");
        }
    }
    
    // Process support zones
    for(int i = ArraySize(g_activeSupportZones) - 1; i >= 0; i--)
    {
        g_activeSupportZones[i].touchCount = CountTouches(rates, g_activeSupportZones[i], sensitivity, lookbackPeriod);
        if(g_activeSupportZones[i].touchCount < SR_MIN_TOUCHES)
        {
            Print("Removing support zone at ", g_activeSupportZones[i].bottomBoundary,
                  " - only ", g_activeSupportZones[i].touchCount, " touches");
            ArrayRemove(g_activeSupportZones, i, 1);
            continue;
        }
        else
        {
            Print("Keeping support zone at ", g_activeSupportZones[i].bottomBoundary,
                  " - ", g_activeSupportZones[i].touchCount, " touches");
        }
    }
}

//+------------------------------------------------------------------+
//| Check for EMA crossover                                           |
//+------------------------------------------------------------------+
bool UpdateEMACrossoverState(const MqlRates &rates[], double emaValue)
{
    bool previousState = g_isAboveEMA;
    g_isAboveEMA = rates[0].close > emaValue;
    
    // Return true if there was a crossover
    bool crossover = previousState != g_isAboveEMA;
    if(crossover)
    {
        Print("EMA Crossover detected: Price is now ", g_isAboveEMA ? "above" : "below", " EMA");
    }
    
    return crossover;
}
