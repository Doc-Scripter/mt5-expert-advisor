//+------------------------------------------------------------------+
//|                                           EMA_Engulfing_EA.mq5    |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Include spread check functionality
#include "include/SpreadCheck.mqh"

// Input parameters
input int         EMA_Period = 20;       // EMA period
input double      Lot_Size_1 = 0.01;     // First entry lot size
input double      Lot_Size_2 = 0.02;     // Second entry lot size
input double      RR_Ratio_1 = 1.7;      // Risk:Reward ratio for first target
input double      RR_Ratio_2 = 2.0;      // Risk:Reward ratio for second target
input int         Max_Spread = 180;      // Maximum spread for logging purposes only
input bool        Use_Strategy_1 = true; // Use EMA crossing + engulfing strategy
input bool        Use_Strategy_2 = true; // Use S/R engulfing strategy
input bool        Use_Strategy_3 = true; // Use breakout + EMA engulfing strategy
input int         SL_Buffer_Pips = 5;    // Additional buffer for stop loss in pips
input int         SR_Lookback = 50;      // Lookback period for S/R detection
input double      SR_Strength = 3;       // Minimum touches for valid S/R

// Global variables
int emaHandle;
double emaValues[];
int barCount;
ulong posTicket1 = 0;
ulong posTicket2 = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Initialize barCount to track new bars
   barCount = Bars(_Symbol, PERIOD_CURRENT);
   
   // Display information about the current symbol
   Print("Symbol: ", _Symbol, ", Digits: ", _Digits, ", Point: ", _Point);
   Print("SPREAD LIMITING REMOVED: EA will trade regardless of spread conditions");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have a new bar
   int currentBars = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBars == barCount)
      return;  // No new bar, exit
      
   barCount = currentBars;
   
   // Update indicators
   if(!UpdateIndicators())
      return;
      
   // Check for open positions
   if(HasOpenPositions())
      return;
      
   // Log current spread for reference (but don't use it to limit trading)
   IsSpreadAcceptable(Max_Spread);
   
   // Reset comment
   Comment("");
      
   // Check strategy conditions
   if(Use_Strategy_1 && CheckStrategy1())
      return;
      
   if(Use_Strategy_2 && CheckStrategy2())
      return;
      
   if(Use_Strategy_3 && CheckStrategy3())
      return;
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Get EMA values for the last 3 bars
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 0, 3, emaValues) < 3)
   {
      Print("Failed to copy EMA indicator values");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if there are open positions for this symbol                |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if the current bar forms an engulfing pattern              |
//+------------------------------------------------------------------+
bool IsEngulfing(int shift, bool bullish)
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   if(bullish) // Bullish engulfing
   {
      return (open1 > close1) && // Prior candle is bearish
             (open2 < close2) && // Current candle is bullish
             (open2 <= close1) && // Current open is below or equal to prior close
             (close2 > open1);    // Current close is above prior open
   }
   else // Bearish engulfing
   {
      return (open1 < close1) && // Prior candle is bullish
             (open2 > close2) && // Current candle is bearish
             (open2 >= close1) && // Current open is above or equal to prior close
             (close2 < open1);    // Current close is below prior open
   }
}

//+------------------------------------------------------------------+
//| Check if price crossed EMA                                       |
//+------------------------------------------------------------------+
bool CrossedEMA(int shift, bool upward)
{
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double close0 = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   if(upward)
      return close1 < emaValues[shift + 1] && close0 > emaValues[shift];
   else
      return close1 > emaValues[shift + 1] && close0 < emaValues[shift];
}

//+------------------------------------------------------------------+
//| Check if price stayed on one side of EMA                         |
//+------------------------------------------------------------------+
bool StayedOnSideOfEMA(int startBar, int bars, bool above)
{
   for(int i = startBar; i < startBar + bars; i++)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      
      if(above && close < emaValues[i])
         return false;
      
      if(!above && close > emaValues[i])
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Find nearest support/resistance level                            |
//+------------------------------------------------------------------+
double FindNearestSR(bool findResistance)
{
   double levels[];
   int levelCount = 0;
   
   // Look for potential S/R points in the lookback period
   for(int i = 1; i < SR_Lookback - 1; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      
      if(findResistance)
      {
         if(IsResistanceLevel(i, SR_Strength))
         {
            ArrayResize(levels, levelCount + 1);
            levels[levelCount] = high;
            levelCount++;
         }
      }
      else
      {
         if(IsSupportLevel(i, SR_Strength))
         {
            ArrayResize(levels, levelCount + 1);
            levels[levelCount] = low;
            levelCount++;
         }
      }
   }
   
   // Find the nearest level to current price
   if(levelCount > 0)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double nearestLevel = levels[0];
      double minDistance = MathAbs(currentPrice - nearestLevel);
      
      for(int i = 1; i < levelCount; i++)
      {
         double distance = MathAbs(currentPrice - levels[i]);
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestLevel = levels[i];
         }
      }
      
      return nearestLevel;
   }
   
   return 0; // No level found
}

//+------------------------------------------------------------------+
//| Check if the bar is a resistance level                           |
//+------------------------------------------------------------------+
bool IsResistanceLevel(int barIndex, double strength)
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, barIndex);
   int count = 0;
   
   // Check if the high is a local maximum
   if(high > iHigh(_Symbol, PERIOD_CURRENT, barIndex + 1) && 
      high > iHigh(_Symbol, PERIOD_CURRENT, barIndex - 1))
   {
      // Count how many times price approached this level
      for(int i = 0; i < SR_Lookback; i++)
      {
         double barHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
         if(MathAbs(barHigh - high) <= 10 * _Point)
            count++;
      }
   }
   
   return count >= strength;
}

//+------------------------------------------------------------------+
//| Check if the bar is a support level                              |
//+------------------------------------------------------------------+
bool IsSupportLevel(int barIndex, double strength)
{
   double low = iLow(_Symbol, PERIOD_CURRENT, barIndex);
   int count = 0;
   
   // Check if the low is a local minimum
   if(low < iLow(_Symbol, PERIOD_CURRENT, barIndex + 1) && 
      low < iLow(_Symbol, PERIOD_CURRENT, barIndex - 1))
   {
      // Count how many times price approached this level
      for(int i = 0; i < SR_Lookback; i++)
      {
         double barLow = iLow(_Symbol, PERIOD_CURRENT, i);
         if(MathAbs(barLow - low) <= 10 * _Point)
            count++;
      }
   }
   
   return count >= strength;
}

//+------------------------------------------------------------------+
//| Check if price broke through resistance/support                  |
//+------------------------------------------------------------------+
bool BrokeLevel(int shift, double level, bool breakUp)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   if(breakUp)
      return prevClose < level && close > level;
   else
      return prevClose > level && close < level;
}

//+------------------------------------------------------------------+
//| Calculate take profit based on risk-reward ratio                 |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double entryPrice, double stopLoss, double rrRatio)
{
   if(isBuy)
      return entryPrice + (entryPrice - stopLoss) * rrRatio;
   else
      return entryPrice - (stopLoss - entryPrice) * rrRatio;
}

//+------------------------------------------------------------------+
//| Strategy 1: EMA crossing + engulfing without closing opposite    |
//+------------------------------------------------------------------+
bool CheckStrategy1()
{
   // Check for bullish setup
   if(CrossedEMA(1, true) && IsEngulfing(0, true) && StayedOnSideOfEMA(0, 3, true))
   {
      double resistance = FindNearestSR(true);
      if(resistance > 0)
      {
         ExecuteTrade(true, resistance);
         return true;
      }
   }
   
   // Check for bearish setup
   if(CrossedEMA(1, false) && IsEngulfing(0, false) && StayedOnSideOfEMA(0, 3, false))
   {
      double support = FindNearestSR(false);
      if(support > 0)
      {
         ExecuteTrade(false, support);
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 2: Engulfing at support/resistance                      |
//+------------------------------------------------------------------+
bool CheckStrategy2()
{
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Find nearest support and resistance
   double resistance = FindNearestSR(true);
   double support = FindNearestSR(false);
   
   // Check for bullish engulfing near support
   if(support > 0 && MathAbs(currentPrice - support) < 20 * _Point && IsEngulfing(0, true))
   {
      ExecuteTrade(true, resistance);
      return true;
   }
   
   // Check for bearish engulfing near resistance
   if(resistance > 0 && MathAbs(currentPrice - resistance) < 20 * _Point && IsEngulfing(0, false))
   {
      ExecuteTrade(false, support);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy 3: Break past resistance + EMA engulfing                |
//+------------------------------------------------------------------+
bool CheckStrategy3()
{
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Find nearest resistance and support
   double resistance = FindNearestSR(true);
   double support = FindNearestSR(false);
   
   if(resistance == 0 || support == 0)
      return false;
   
   // Check for bullish engulfing pattern
   if(IsEngulfing(0, true))
   {
      // Look for recently broken resistance levels (within the last 5 bars)
      for(int i = 1; i <= 5; i++)
      {
         // Check if bar i broke through resistance
         if(BrokeLevel(i, resistance, true))
         {
            // Check if price stayed on the right side of EMA
            if(StayedOnSideOfEMA(0, 3, true))
            {
               double newResistance = FindNearestSR(true);
               if(newResistance > 0 && newResistance > resistance)
               {
                  Print("Strategy 3 - Bullish breakout detected at bar ", i, " with engulfing pattern");
                  ExecuteTrade(true, newResistance);
                  return true;
               }
            }
         }
      }
   }
   
   // Check for bearish engulfing pattern
   if(IsEngulfing(0, false))
   {
      // Look for recently broken support levels (within the last 5 bars)
      for(int i = 1; i <= 5; i++)
      {
         // Check if bar i broke through support
         if(BrokeLevel(i, support, false))
         {
            // Check if price stayed on the right side of EMA
            if(StayedOnSideOfEMA(0, 3, false))
            {
               double newSupport = FindNearestSR(false);
               if(newSupport > 0 && newSupport < support)
               {
                  Print("Strategy 3 - Bearish breakout detected at bar ", i, " with engulfing pattern");
                  ExecuteTrade(false, newSupport);
                  return true;
               }
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                        |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isBuy, double targetLevel)
{
   // Log current spread at time of trade execution (for information only)
   LogCurrentSpread();
   
   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = 0;
   double takeProfit1 = 0;
   double takeProfit2 = 0;
   
   // Calculate stop loss based on the previous candle
   if(isBuy)
   {
      stopLoss = iLow(_Symbol, PERIOD_CURRENT, 1) - SL_Buffer_Pips * _Point;
   }
   else
   {
      stopLoss = iHigh(_Symbol, PERIOD_CURRENT, 1) + SL_Buffer_Pips * _Point;
   }
   
   // Make sure the stop loss isn't too close to current price
   double minSLDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   
   if(isBuy && (currentPrice - stopLoss) < minSLDistance)
   {
      stopLoss = currentPrice - minSLDistance;
      Print("Stop loss adjusted due to minimum distance requirement");
   }
   else if(!isBuy && (stopLoss - currentPrice) < minSLDistance)
   {
      stopLoss = currentPrice + minSLDistance;
      Print("Stop loss adjusted due to minimum distance requirement");
   }
   
   // Calculate take profit levels
   takeProfit1 = CalculateTakeProfit(isBuy, currentPrice, stopLoss, RR_Ratio_1);
   takeProfit2 = CalculateTakeProfit(isBuy, currentPrice, stopLoss, RR_Ratio_2);
   
   // Check if the TP is beyond the target level, adjust if necessary
   if(isBuy)
   {
      if(takeProfit1 > targetLevel)
      {
         takeProfit1 = targetLevel - 5 * _Point;
         Print("TP1 adjusted to stay below resistance level");
      }
         
      if(takeProfit2 > targetLevel)
      {
         takeProfit2 = targetLevel;
         Print("TP2 adjusted to target resistance level");
      }
   }
   else
   {
      if(takeProfit1 < targetLevel)
      {
         takeProfit1 = targetLevel + 5 * _Point;
         Print("TP1 adjusted to stay above support level");
      }
         
      if(takeProfit2 < targetLevel)
      {
         takeProfit2 = targetLevel;
         Print("TP2 adjusted to target support level");
      }
   }
   
   // Place first order
   MqlTradeRequest request1 = {};
   MqlTradeResult result1 = {};
   
   request1.action = TRADE_ACTION_DEAL;
   request1.symbol = _Symbol;
   request1.volume = Lot_Size_1;
   request1.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request1.price = currentPrice;
   request1.sl = stopLoss;
   request1.tp = takeProfit1;
   request1.deviation = 10;
   request1.magic = 123456;
   request1.comment = "Strategy " + string(isBuy ? "Buy" : "Sell") + " TP1";
   
   // Check return value of OrderSend
   bool orderSent1 = OrderSend(request1, result1);
   if(!orderSent1 || result1.retcode != TRADE_RETCODE_DONE)
   {
      Print("First order failed. Error code: ", GetLastError(), 
            ", Return code: ", result1.retcode, 
            ", Message: ", result1.comment);
      return;
   }
   
   if(result1.retcode == TRADE_RETCODE_DONE)
   {
      posTicket1 = result1.deal;
      
      // Place second order
      MqlTradeRequest request2 = {};
      MqlTradeResult result2 = {};
      
      request2.action = TRADE_ACTION_DEAL;
      request2.symbol = _Symbol;
      request2.volume = Lot_Size_2;
      request2.type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request2.price = currentPrice;
      request2.sl = stopLoss;
      request2.tp = takeProfit2;
      request2.deviation = 10;
      request2.magic = 123456;
      request2.comment = "Strategy " + string(isBuy ? "Buy" : "Sell") + " TP2";
      
      // Check return value of OrderSend
      bool orderSent2 = OrderSend(request2, result2);
      if(!orderSent2 || result2.retcode != TRADE_RETCODE_DONE)
      {
         Print("Second order failed. Error code: ", GetLastError(), 
               ", Return code: ", result2.retcode, 
               ", Message: ", result2.comment);
         return;
      }
      
      if(result2.retcode == TRADE_RETCODE_DONE)
      {
         posTicket2 = result2.deal;
         
         string direction = isBuy ? "BUY" : "SELL";
         Print("Executed ", direction, " trades. SL at ", stopLoss, ", TP1 at ", takeProfit1, ", TP2 at ", takeProfit2);
      }
      else
      {
         Print("Failed to execute second trade. Error: ", GetLastError());
      }
   }
   else
   {
      Print("Failed to execute first trade. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
