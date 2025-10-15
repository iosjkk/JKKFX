//+------------------------------------------------------------------+
//|                                             JKK_Retracements.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "JKK Rapid Growth EA"
#property link      ""
#property version   "1.02"
#property strict

//--- Input Parameters
//=== MAIN SETTINGS ===
input group "========== MAIN SETTINGS =========="
input bool     AutoTrade = true;                    // Auto trade
input bool     TradeBUY = true;                     // Trade BUY
input bool     TradeSELL = true;                    // Trade SELL
input int      GMTOffset = 0;                       // Local time offset from GMT (hours)
input bool     UseBrokerServerOffset = false;       // Use broker server offset instead of local offset
input int      BrokerServerOffset = 0;              // Broker server offset from GMT (hours)
input bool     TradeDuringLunch = true;             // To trade during lunch or not
input int      MaxSlippage = 3;                     // Max slippage (pips)
input int      MaxSpread = 30;                      // Max spread (pips)
input int      PauseAfterNewYorkHours = 1;          // Hours to pause after 18:00 GMT before final trade

//=== MONEY MANAGEMENT ===
input group "========== MONEY MANAGEMENT =========="
input string   UseFunds = "Balance";                // Use Funds (Balance/Equity)
input double   LotSize = 0.01;                      // Lot Size
input bool     UseAutoLot = false;                  // Use Auto lot
input double   PercentForAutoLot = 1.0;            // Percent for auto lot
input int      LifetimePendingOrders = 180;        // Lifetime of pending orders (minutes)
input bool     UseVirtualExpiration = false;        // Use Virtual Expiration
input int      PositionsToIncreaseLot = 5;         // Number of positions to increase lot
input double   MaxLotSize = 2.0;                   // Maximum lot size
input int      MaxOpenOrders = 15;                 // Max Open Orders, one direction
input int      VirtualStopLoss = 500;              // Virtual stop loss (pips)
input bool     Microlot = false;                   // Microlot
input double   MinPendingDistancePips = 20.0;      // Minimum distance between pending orders (pips)
input double   TargetProfitForDistance = 50.0;     // Target USD profit for distance calibration

//=== HEDGING SETTINGS ===
input group "========== HEDGING SETTINGS =========="
input bool     UseHedging = false;                 // Use hedging
input bool     WorkOnEveryTick = true;             // Work on every tick
input int      StartHedgingFromBE = 100;           // Start hedging from BE if DD (pips)
input double   HedgeLotMultiplier = 0.5;           // Hedge lot multiplier
input int      HedgeStopLoss = 100;                // Hedge Stop Loss (pips)
input int      HedgeTakeProfit = 50;               // Hedge Take Profit (pips)
input int      BEStart = 20;                       // BE Start (pips)
input int      HedgeBE = 10;                       // Hedge BE (pips)
input double   CloseAllProfit = 50.0;              // Close All Profit (money)
input int      MinDistanceForNewHedge = 30;        // Min Distance for new hedge after SL (pips)

//=== OTHER SETTINGS ===
input group "========== OTHER SETTINGS =========="
input bool     ShowTradingStatistic = true;        // Show Trading Statistic
input bool     ShowButtonsPanel = true;            // Show Buttons Panel
input int      MagicNumber = 123456;               // Magic number

//--- Global Variables
string EAName = "AdvancedAutoTradingEA";
string Prefix = "AATEA_";
bool tradingPaused = false;
datetime lastBarTime = 0;
datetime lastTickTime = 0;
datetime lastTradeHourGMT = 0;
double pointValue;
int digits;
double tickSize;
double minLot, maxLot, lotStep;
int hedgeTicket = -1;
datetime lastHedgeSL = 0;

//--- Display Variables
string infoCorner = "";
color infoColor = clrWhite;
int fontSize = 8;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print(EAName + ": Initializing...");

// Check if auto trading is enabled
   if(!IsTradeAllowed())
     {
      Alert(EAName + ": AutoTrading is disabled! Please enable it.");
      return(INIT_FAILED);
     }

// Initialize symbol properties
   digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   pointValue = Point;

// Adjust point value for 5-digit brokers
   if(digits == 3 || digits == 5)
     {
      pointValue = Point * 10;
     }

   tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   minLot = MarketInfo(Symbol(), MODE_MINLOT);
   maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

// Adjust for microlot
   if(Microlot)
     {
      minLot = minLot / 10.0;
      lotStep = lotStep / 10.0;
     }

   Print(EAName + ": Digits=", digits, " PointValue=", pointValue, " MinLot=", minLot, " MaxLot=", maxLot);
   Print(EAName + ": Initialization complete");

// Set timer for 1 minute
   EventSetTimer(60);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteAllObjects();
   Print(EAName + ": Deinitialization complete. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
// Prevent duplicate processing on same tick
   if(lastTickTime == Time[0])
      return;
   lastTickTime = Time[0];

// Check if auto trading is enabled
   if(!AutoTrade)
     {
      if(ShowTradingStatistic)
         UpdateInfoDisplay();
      return;
     }

// Check if trading is paused
   if(tradingPaused)
     {
      Print(EAName + ": Trading is paused");
      return;
     }

// Check equity drop
   if(!CheckEquityDrop())
     {
      tradingPaused = true;
      CloseAllTrades();
      return;
     }

// Check spread
   if(!IsSpreadAcceptable())
     {
      Print(EAName + ": Spread too high: ", GetCurrentSpread());
      return;
     }

   bool allowedTradingTime = IsTradingTime();

// Main trading logic
   if(allowedTradingTime)
      ManageOrders();

// Hedging logic
   if(UseHedging)
     {
      ManageHedging();
     }

// Check for close all profit
   if(CloseAllProfit > 0)
     {
      double totalProfit = CalculateTotalProfit();
      if(totalProfit >= CloseAllProfit)
        {
         Print(EAName + ": Close All Profit target reached: $", totalProfit);
         CloseAllTrades();
        }
     }

// Virtual expiration for pending orders
   if(UseVirtualExpiration)
     {
      CheckVirtualExpiration();
     }

// Update display
   if(ShowTradingStatistic)
      UpdateInfoDisplay();

   if(ShowButtonsPanel)
      DrawButtonsPanel();
  }

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
  {
   OnTick();
  }

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   double lot = LotSize;

   if(UseAutoLot)
     {
      double funds = 0;
      if(UseFunds == "Balance")
         funds = AccountBalance();
      else
         funds = AccountEquity();

      lot = NormalizeDouble(funds * PercentForAutoLot / 100.0 / 10000.0, 2);
     }

// Check if we need to increase lot based on open positions
   int openPositions = CountOrders(OP_BUY) + CountOrders(OP_SELL);
   if(openPositions >= PositionsToIncreaseLot)
     {
      double totalLots = GetTotalLots();
      lot = NormalizeDouble(totalLots * 1.5, 2);
     }

// Normalize lot size
   lot = NormalizeLot(lot);

// Apply limits
   if(lot > MaxLotSize)
      lot = MaxLotSize;
   if(lot < minLot)
      lot = minLot;

   return lot;
  }

//+------------------------------------------------------------------+
//| Normalize lot size                                                |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = NormalizeDouble(lot, 2);

   if(lot < minLot)
      lot = minLot;
   if(lot > maxLot)
      lot = maxLot;

   return lot;
  }

//+------------------------------------------------------------------+
//| Get current spread in pips                                        |
//+------------------------------------------------------------------+
double GetCurrentSpread()
  {
   return (Ask - Bid) / pointValue;
  }

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                     |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
  {
   if(MaxSpread <= 0)
      return true;
   return (GetCurrentSpread() <= MaxSpread);
  }

//+------------------------------------------------------------------+
//| Check trading time                                                |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   datetime currentGMT = ConvertServerToGMT(TimeCurrent());

// Lunch time check (12:00 - 14:00) if required
   int currentHour = TimeHour(currentGMT);
   if(!TradeDuringLunch && currentHour >= 12 && currentHour < 14)
      return false;

   return IsAllowedTradingHour(currentGMT);
  }

//+------------------------------------------------------------------+
//| Calculate server-to-local offset (seconds)                         |
//+------------------------------------------------------------------+
int GetServerLocalOffsetSeconds()
  {
   datetime serverNow = TimeCurrent();
   datetime localNow = TimeLocal();
   return (int)(serverNow - localNow);
  }

//+------------------------------------------------------------------+
//| Get server offset from GMT (seconds)                              |
//+------------------------------------------------------------------+
int GetServerToGmtOffsetSeconds()
  {
   datetime serverNow = TimeCurrent();
   datetime gmtNow = TimeGMT();
   if(serverNow <= 0 || gmtNow <= 0)
      return 0;
   return (int)(serverNow - gmtNow);
  }

//+------------------------------------------------------------------+
//| Determine local offset seconds (handles auto-detect)              |
//+------------------------------------------------------------------+
int DetermineLocalOffsetSeconds()
  {
   int manualOffsetSeconds = GMTOffset * 3600;
   if(manualOffsetSeconds != 0)
      return manualOffsetSeconds;

   datetime localNow = TimeLocal();
   datetime gmtNow = TimeGMT();
   static bool notified = false;

   if(localNow > 0 && gmtNow > 0)
     {
      int autoSeconds = (int)(localNow - gmtNow);
      if(autoSeconds != 0)
        {
         if(!notified)
           {
            double autoHours = autoSeconds / 3600.0;
            Print(EAName + ": Auto-detected local GMT offset: ", DoubleToStr(autoHours, 2), " hours. Set GMTOffset to override.");
            notified = true;
           }
         return autoSeconds;
        }
     }

   if(!notified)
     {
      Print(EAName + ": GMTOffset is 0. Using 0-hour adjustment. Configure GMTOffset for precise trading sessions.");
      notified = true;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Determine broker offset seconds (handles auto-detect)             |
//+------------------------------------------------------------------+
int DetermineBrokerOffsetSeconds()
  {
   int manualOffsetSeconds = BrokerServerOffset * 3600;
   if(manualOffsetSeconds != 0)
      return manualOffsetSeconds;

   int autoSeconds = GetServerToGmtOffsetSeconds();
   static bool notified = false;

   if(autoSeconds != 0)
     {
      if(!notified)
        {
         double autoHours = autoSeconds / 3600.0;
         Print(EAName + ": Auto-detected broker GMT offset: ", DoubleToStr(autoHours, 2), " hours. Set BrokerServerOffset to override.");
         notified = true;
        }
      return autoSeconds;
     }

   if(!notified)
     {
      Print(EAName + ": BrokerServerOffset is 0. Using 0-hour adjustment. Configure BrokerServerOffset for precise trading sessions.");
      notified = true;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Convert server time to GMT                                        |
//+------------------------------------------------------------------+
datetime ConvertServerToGMT(datetime serverTime)
  {
   if(serverTime <= 0)
      return 0;

   int offsetSeconds = 0;

   if(UseBrokerServerOffset)
     {
      offsetSeconds = DetermineBrokerOffsetSeconds();
     }
   else
     {
      int serverLocalDiff = GetServerLocalOffsetSeconds();
      int localOffsetSeconds = DetermineLocalOffsetSeconds();
      offsetSeconds = serverLocalDiff + localOffsetSeconds;
     }

   return serverTime - offsetSeconds;
  }

//+------------------------------------------------------------------+
//| Normalize datetime to the start of the hour                        |
//+------------------------------------------------------------------+
datetime NormalizeToHour(datetime value)
  {
   if(value <= 0)
      return 0;

   int seconds = (int)value;
   int remainder = seconds % 3600;
   return (datetime)(seconds - remainder);
  }

//+------------------------------------------------------------------+
//| Check if GMT hour is allowed                                      |
//+------------------------------------------------------------------+
bool IsAllowedTradingHour(datetime gmtTime)
  {
   int hour = TimeHour(gmtTime);
   int allowedHours[9];
   ArrayInitialize(allowedHours, -1);

   int count = 0;
   allowedHours[count++] = 8;
   allowedHours[count++] = 9;
   allowedHours[count++] = 10;
   allowedHours[count++] = 11;
   allowedHours[count++] = 15;
   allowedHours[count++] = 16;
   allowedHours[count++] = 17;
   allowedHours[count++] = 18;

   int finalHour = CalculateFinalGmtHour();
   bool finalExists = false;
   for(int i = 0; i < count; i++)
     {
      if(allowedHours[i] == finalHour)
        {
         finalExists = true;
         break;
        }
     }

   if(!finalExists)
      allowedHours[count++] = finalHour;

   for(int j = 0; j < count; j++)
     {
      if(allowedHours[j] < 0)
         continue;
      if(hour == allowedHours[j])
         return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Calculate final GMT hour after NY session                         |
//+------------------------------------------------------------------+
int CalculateFinalGmtHour()
  {
   int pauseHours = MathMax(0, PauseAfterNewYorkHours);
   int finalHour = 18 + pauseHours + 1;
   while(finalHour >= 24)
      finalHour -= 24;
   return finalHour;
  }

//+------------------------------------------------------------------+
//| Check equity drop                                                 |
//+------------------------------------------------------------------+
bool CheckEquityDrop()
  {
   double equity = AccountEquity();
   double balance = AccountBalance();

   if(balance <= 0)
      return true;

   double equityPercent = (equity / balance) * 100.0;

   if(equityPercent < 60.0)
     {
      Alert(EAName + ": EQUITY DROP ALERT! Equity: ", DoubleToStr(equityPercent, 2), "%");
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Count orders by type                                              |
//+------------------------------------------------------------------+
int CountOrders(int orderType, int magic = -1)
  {
   if(magic == -1)
      magic = MagicNumber;

   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == magic)
           {
            if(orderType == -1 || OrderType() == orderType)
               count++;
           }
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Get total lots                                                    |
//+------------------------------------------------------------------+
double GetTotalLots()
  {
   double totalLots = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
           {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
               totalLots += OrderLots();
           }
        }
     }
   return totalLots;
  }

//+------------------------------------------------------------------+
//| Calculate total profit                                            |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
  {
   double totalProfit = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
           {
            double orderReturn = OrderProfit() + OrderSwap() + OrderCommission();
            totalProfit += orderReturn;
           }
        }
     }
   return totalProfit;
  }

//+------------------------------------------------------------------+
//| Calculate pending distance in price                               |
//+------------------------------------------------------------------+
double CalculatePendingDistance()
  {
   double pipDistance = MinPendingDistancePips;

   if(TargetProfitForDistance > 0)
     {
      double pipValue = GetPipValueForStandardLot();
      if(pipValue > 0)
        {
         double profitBasedDistance = TargetProfitForDistance / pipValue;
         if(profitBasedDistance > pipDistance)
            pipDistance = profitBasedDistance;
        }
     }

  double priceDistance = pipDistance * pointValue;

// Align to the nearest tradable step to avoid invalid prices on exotic symbols
  if(tickSize > 0)
    {
     double steps = priceDistance / tickSize;
     priceDistance = tickSize * MathRound(steps);
    }

  if(priceDistance <= 0)
     priceDistance = pipDistance * pointValue;

  return priceDistance;
  }

//+------------------------------------------------------------------+
//| Get pip value for one standard lot                                |
//+------------------------------------------------------------------+
double GetPipValueForStandardLot()
  {
   if(tickSize <= 0)
      return 0;

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickValue <= 0)
      return 0;

   double pipValueForLot = tickValue * (pointValue / tickSize);
   return pipValueForLot;
  }

//+------------------------------------------------------------------+
//| Manage orders                                                     |
//+------------------------------------------------------------------+
void ManageOrders()
  {
   datetime serverHour = iTime(Symbol(), PERIOD_H1, 0);
   if(serverHour <= 0)
      return;

   datetime gmtHour = NormalizeToHour(ConvertServerToGMT(serverHour));

   if(gmtHour <= 0)
      gmtHour = NormalizeToHour(ConvertServerToGMT(TimeCurrent()));

// Check if we're in a new allowed hour
   if(gmtHour == lastTradeHourGMT)
      return;

   if(!IsAllowedTradingHour(gmtHour))
      return;

// Check if we have existing trades this server hour
   if(HasTradeThisHour(serverHour))
     {
      lastTradeHourGMT = gmtHour;
      return;
     }

// Count existing orders
   int buyOrders = CountOrders(OP_BUY) + CountOrders(OP_BUYLIMIT) + CountOrders(OP_BUYSTOP);
   int sellOrders = CountOrders(OP_SELL) + CountOrders(OP_SELLLIMIT) + CountOrders(OP_SELLSTOP);

// Calculate lot size
   double lot = CalculateLotSize();

// Calculate pending distance
   double pendingDistance = CalculatePendingDistance();

   if(!RefreshRates())
     {
      Print(EAName + ": Failed to refresh rates before placing pending orders. Error: ", GetLastError());
      return;
     }

// Place BUY limit order
   if(TradeBUY && buyOrders < MaxOpenOrders)
     {
      double buyPrice = NormalizeDouble(Bid - pendingDistance, digits);
      datetime expiration = TimeCurrent() + (LifetimePendingOrders * 60);

      string commentBuy = Prefix + "BUY_" + IntegerToString(TimeHour(gmtHour));

      int ticketBuy = OrderSend(Symbol(), OP_BUYLIMIT, lot, buyPrice, MaxSlippage, 0, 0,
                                commentBuy, MagicNumber, expiration, clrBlue);

      if(ticketBuy > 0)
         Print(EAName + ": BUY LIMIT placed at ", buyPrice, " Lot: ", lot, " Distance: ", pendingDistance);
      else
         Print(EAName + ": Error placing BUY LIMIT: ", GetLastError());
     }

// Place SELL limit order
   if(TradeSELL && sellOrders < MaxOpenOrders)
     {
      double sellPrice = NormalizeDouble(Ask + pendingDistance, digits);
      datetime expirationSell = TimeCurrent() + (LifetimePendingOrders * 60);

      string commentSell = Prefix + "SELL_" + IntegerToString(TimeHour(gmtHour));

      int ticketSell = OrderSend(Symbol(), OP_SELLLIMIT, lot, sellPrice, MaxSlippage, 0, 0,
                                 commentSell, MagicNumber, expirationSell, clrRed);

      if(ticketSell > 0)
         Print(EAName + ": SELL LIMIT placed at ", sellPrice, " Lot: ", lot, " Distance: ", pendingDistance);
      else
         Print(EAName + ": Error placing SELL LIMIT: ", GetLastError());
     }

   lastTradeHourGMT = gmtHour;
  }

//+------------------------------------------------------------------+
//| Check if trade exists this hour                                  |
//+------------------------------------------------------------------+
bool HasTradeThisHour(datetime hourTime)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
           {
            if(OrderOpenTime() >= hourTime)
               return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Manage hedging                                                    |
//+------------------------------------------------------------------+
void ManageHedging()
  {
   if(!UseHedging)
      return;

// Calculate current drawdown from breakeven
   double totalProfit = CalculateTotalProfit();
   double drawdownPips = MathAbs(totalProfit / pointValue / 10.0);

// Check if we need to open a hedge
   if(drawdownPips >= StartHedgingFromBE && hedgeTicket == -1)
     {
      // Check minimum distance after last hedge SL
      if(TimeCurrent() - lastHedgeSL < MinDistanceForNewHedge * 60)
         return;

      OpenHedge();
     }

// Manage existing hedge
   if(hedgeTicket > 0)
     {
      ManageHedgeBreakeven();
     }
  }

//+------------------------------------------------------------------+
//| Open hedge order                                                  |
//+------------------------------------------------------------------+
void OpenHedge()
  {
// Determine hedge direction (opposite to majority)
   int buyCount = CountOrders(OP_BUY);
   int sellCount = CountOrders(OP_SELL);

   int hedgeType = (buyCount > sellCount) ? OP_SELL : OP_BUY;
   double hedgeLot = GetTotalLots() * HedgeLotMultiplier;
   hedgeLot = NormalizeLot(hedgeLot);

   double price = (hedgeType == OP_BUY) ? Ask : Bid;
   double sl = 0, tp = 0;

   if(HedgeStopLoss > 0)
     {
      if(hedgeType == OP_BUY)
         sl = price - (HedgeStopLoss * pointValue);
      else
         sl = price + (HedgeStopLoss * pointValue);
     }

   if(HedgeTakeProfit > 0)
     {
      if(hedgeType == OP_BUY)
         tp = price + (HedgeTakeProfit * pointValue);
      else
         tp = price - (HedgeTakeProfit * pointValue);
     }

   string comment = Prefix + "HEDGE";
   hedgeTicket = OrderSend(Symbol(), hedgeType, hedgeLot, price, MaxSlippage, sl, tp,
                           comment, MagicNumber + 1, 0, clrYellow);

   if(hedgeTicket > 0)
      Print(EAName + ": HEDGE opened. Ticket: ", hedgeTicket, " Type: ", hedgeType, " Lot: ", hedgeLot);
   else
      Print(EAName + ": Error opening HEDGE: ", GetLastError());
  }

//+------------------------------------------------------------------+
//| Manage hedge breakeven                                            |
//+------------------------------------------------------------------+
void ManageHedgeBreakeven()
  {
   if(hedgeTicket <= 0)
      return;

   if(OrderSelect(hedgeTicket, SELECT_BY_TICKET))
     {
      if(OrderCloseTime() > 0)
        {
         // Hedge was closed
         lastHedgeSL = TimeCurrent();
         hedgeTicket = -1;
         return;
        }

      double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
      double openPrice = OrderOpenPrice();
      double pipDistance = MathAbs(currentPrice - openPrice) / pointValue;

      if(pipDistance >= BEStart && OrderStopLoss() == 0)
        {
         double newSL = openPrice + (HedgeBE * pointValue * ((OrderType() == OP_BUY) ? 1 : -1));
         bool modified = OrderModify(hedgeTicket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrYellow);

         if(modified)
            Print(EAName + ": Hedge moved to breakeven");
         else
            Print(EAName + ": Failed to move hedge to breakeven. Error: ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Check virtual expiration                                          |
//+------------------------------------------------------------------+
void CheckVirtualExpiration()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
           {
            if(OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT ||
               OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
              {
               datetime orderTime = OrderOpenTime();
                if(TimeCurrent() - orderTime >= LifetimePendingOrders * 60)
                  {
                   int ticket = OrderTicket();
                   if(DeleteOrderTicket(ticket, "Virtual expiration"))
                      Print(EAName + ": Pending order ", ticket, " expired and deleted");
                  }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper to close market orders safely                              |
//+------------------------------------------------------------------+
bool CloseOrderTicket(int ticket, double lots, double price, color arrowColor, string reason)
  {
   bool closed = OrderClose(ticket, lots, price, MaxSlippage, arrowColor);
   if(!closed)
      Print(EAName + ": Failed to close order ", ticket, " (", reason, "). Error: ", GetLastError());
   return closed;
  }

//+------------------------------------------------------------------+
//| Helper to delete pending orders safely                            |
//+------------------------------------------------------------------+
bool DeleteOrderTicket(int ticket, string reason)
  {
   bool deleted = OrderDelete(ticket);
   if(!deleted)
      Print(EAName + ": Failed to delete order ", ticket, " (", reason, "). Error: ", GetLastError());
   return deleted;
  }

//+------------------------------------------------------------------+
//| Close all trades                                                  |
//+------------------------------------------------------------------+
void CloseAllTrades()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
           {
            if(OrderType() == OP_BUY)
               CloseOrderTicket(OrderTicket(), OrderLots(), Bid, clrRed, "CloseAllTrades BUY");
            else
               if(OrderType() == OP_SELL)
                  CloseOrderTicket(OrderTicket(), OrderLots(), Ask, clrRed, "CloseAllTrades SELL");
               else
                  DeleteOrderTicket(OrderTicket(), "CloseAllTrades pending");
           }
        }
     }

   hedgeTicket = -1;
   Print(EAName + ": All trades closed");
  }

//+------------------------------------------------------------------+
//| Update info display                                               |
//+------------------------------------------------------------------+
void UpdateInfoDisplay()
  {
   int yPos = 20;
   int xPos = 20;

// Account Info
   CreateLabel("EA_Name", EAName, xPos, yPos, clrLime);
   yPos += 15;

   CreateLabel("EA_Balance", "Balance: $" + DoubleToStr(AccountBalance(), 2), xPos, yPos, clrWhite);
   yPos += 15;

   CreateLabel("EA_Equity", "Equity: $" + DoubleToStr(AccountEquity(), 2), xPos, yPos, clrWhite);
   yPos += 15;

   CreateLabel("EA_Profit", "Profit: $" + DoubleToStr(CalculateTotalProfit(), 2), xPos, yPos,
               (CalculateTotalProfit() >= 0) ? clrLime : clrRed);
   yPos += 15;

// Trade Info
   int totalOrders = CountOrders(-1);
   int buyOrders = CountOrders(OP_BUY);
   int sellOrders = CountOrders(OP_SELL);

   CreateLabel("EA_Orders", "Total Orders: " + IntegerToString(totalOrders), xPos, yPos, clrYellow);
   yPos += 15;

   CreateLabel("EA_Buy", "BUY: " + IntegerToString(buyOrders), xPos, yPos, clrDodgerBlue);
   yPos += 15;

   CreateLabel("EA_Sell", "SELL: " + IntegerToString(sellOrders), xPos, yPos, clrOrangeRed);
   yPos += 15;

   CreateLabel("EA_Lots", "Total Lots: " + DoubleToStr(GetTotalLots(), 2), xPos, yPos, clrWhite);
   yPos += 15;

   CreateLabel("EA_Spread", "Spread: " + DoubleToStr(GetCurrentSpread(), 1) + " pips", xPos, yPos, clrWhite);
  }

//+------------------------------------------------------------------+
//| Create label                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr)
  {
   if(ObjectFind(name) < 0)
     {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, 0);
      ObjectSet(name, OBJPROP_XDISTANCE, x);
      ObjectSet(name, OBJPROP_YDISTANCE, y);
     }

   ObjectSetText(name, text, fontSize, "Arial", clr);
  }

//+------------------------------------------------------------------+
//| Draw buttons panel                                                |
//+------------------------------------------------------------------+
void DrawButtonsPanel()
  {
   int xPos = 200;
   int yPos = 20;

   CreateButton("BTN_CloseAll", "Close All", xPos, yPos, 100, 25, clrRed);
   yPos += 30;

   CreateButton("BTN_CloseBuy", "Close BUY", xPos, yPos, 100, 25, clrBlue);
   yPos += 30;

   CreateButton("BTN_CloseSell", "Close SELL", xPos, yPos, 100, 25, clrRed);
   yPos += 30;

   string pauseText = tradingPaused ? "Resume" : "Pause";
   color pauseColor = tradingPaused ? clrLime : clrOrange;
   CreateButton("BTN_Pause", pauseText, xPos, yPos, 100, 25, pauseColor);
  }

//+------------------------------------------------------------------+
//| Create button                                                     |
//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y, int width, int height, color clr)
  {
   if(ObjectFind(name) < 0)
     {
      ObjectCreate(name, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, 0);
      ObjectSet(name, OBJPROP_XDISTANCE, x);
      ObjectSet(name, OBJPROP_YDISTANCE, y);
      ObjectSet(name, OBJPROP_XSIZE, width);
      ObjectSet(name, OBJPROP_YSIZE, height);
     }

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
  }

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == "BTN_CloseAll")
        {
         CloseAllTrades();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
        }
      else
         if(sparam == "BTN_CloseBuy")
           {
            CloseTradesByType(OP_BUY);
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
           }
         else
            if(sparam == "BTN_CloseSell")
              {
               CloseTradesByType(OP_SELL);
               ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
              }
            else
               if(sparam == "BTN_Pause")
                 {
                  tradingPaused = !tradingPaused;
                  ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
                  Alert(EAName + ": Trading " + (tradingPaused ? "PAUSED" : "RESUMED"));
                 }
     }
  }

//+------------------------------------------------------------------+
//| Close trades by type                                              |
//+------------------------------------------------------------------+
void CloseTradesByType(int orderType)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == orderType)
           {
            if(orderType == OP_BUY)
               CloseOrderTicket(OrderTicket(), OrderLots(), Bid, clrRed, "CloseTradesByType BUY");
            else
               if(orderType == OP_SELL)
                  CloseOrderTicket(OrderTicket(), OrderLots(), Ask, clrRed, "CloseTradesByType SELL");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Delete all objects                                                |
//+------------------------------------------------------------------+
void DeleteAllObjects()
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, "EA_") >= 0 || StringFind(name, "BTN_") >= 0)
         ObjectDelete(name);
     }
  }
//+------------------------------------------------------------------+
