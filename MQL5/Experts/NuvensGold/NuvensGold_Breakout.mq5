#property strict
#property version   "1.00"
#property description "Nuvens Gold Breakout MT5 - clean-room multi-timeframe breakout EA"

#include <Trade/Trade.mqh>

input group "Signal"
input ENUM_TIMEFRAMES SignalTF = PERIOD_M30;
input int             BreakoutLookback = 20;
input int             ATRPeriod = 14;
input double          MinATR = 2.0;
input double          EntryATRBuffer = 0.10;
input double          SL_ATR = 1.50;
input double          TP_ATR = 2.00;
input bool            UseHigherTFTrend = true;
input ENUM_TIMEFRAMES HigherTF = PERIOD_H4;
input int             TrendMAPeriod = 50;

input group "Risk"
input double          RiskPerSignal = 0.25;
input double          MaxDailyLoss = 4.0;
input double          MaxTotalDrawdown = 8.0;
input double          InitialBalanceReference = 0.0;
input bool            UseEquityForRisk = true;
input long            MagicNumber = 26001501;
input int             MaxSpreadPoints = 500;

input group "Management"
input bool            UseBreakEven = true;
input double          BreakEvenAtR = 1.0;
input double          BreakEvenOffsetATR = 0.05;
input bool            UseSwingTrailing = true;
input double          TrailATR = 1.0;
input int             PendingExpiryHours = 24;
input bool            CancelOppositeOnEntry = false;

input group "Safety"
input bool            UseNewsPause = false;
input int             NewsPauseMinutes = 60;
input int             FridayStopHour = 20;

CTrade trade;
int atr_handle = INVALID_HANDLE;
int ma_handle = INVALID_HANDLE;
datetime last_bar = 0;
double high_water = 0.0;
double day_start_equity = 0.0;
int day_key = -1;

string Prefix() { return "NuvensGold_" + _Symbol + "_"; }

bool IsNewBar()
{
   datetime t = iTime(_Symbol, SignalTF, 0);
   if(t == 0 || t == last_bar) return false;
   last_bar = t;
   return true;
}

double GetATR(int shift=1)
{
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(atr_handle, 0, shift, 1, b) != 1) return 0.0;
   return b[0];
}

bool TrendAllows(const bool buy)
{
   if(!UseHigherTFTrend) return true;
   double ma[], close[];
   ArraySetAsSeries(ma, true); ArraySetAsSeries(close, true);
   if(CopyBuffer(ma_handle, 0, 1, 1, ma) != 1) return false;
   if(CopyClose(_Symbol, HigherTF, 1, 1, close) != 1) return false;
   return buy ? close[0] >= ma[0] : close[0] <= ma[0];
}

void ResetDay()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int key = dt.year * 1000 + dt.day_of_year;
   if(key != day_key) { day_key = key; day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY); }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(high_water <= 0.0) high_water = equity;
   if(equity > high_water) high_water = equity;
}

bool RiskBlocked()
{
   ResetDay();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(day_start_equity > 0 && equity <= day_start_equity * (1.0 - MaxDailyLoss / 100.0)) return true;
   if(high_water > 0 && equity <= high_water * (1.0 - MaxTotalDrawdown / 100.0)) return true;
   return false;
}

bool TradingWindow()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= FridayStopHour) return false;
   MqlTick tick; if(!SymbolInfoTick(_Symbol, tick)) return false;
   if((tick.ask - tick.bid) / _Point > MaxSpreadPoints) return false;
   return !RiskBlocked();
}

double LotsForRisk(const double stop_distance)
{
   double equity = UseEquityForRisk ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = equity * RiskPerSignal / 100.0;
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(stop_distance <= 0 || tick_size <= 0 || tick_value <= 0) return 0.0;
   double lots = risk_money / ((stop_distance / tick_size) * tick_value);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(min_lot, MathMin(max_lot, lots));
   return NormalizeDouble(MathFloor(lots / step) * step, 2);
}

void DeleteOurPendings()
{
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP) trade.OrderDelete(ticket);
   }
}

void PlaceBreakouts()
{
   if(!TradingWindow()) { DeleteOurPendings(); return; }
   double atr = GetATR(1);
   if(atr <= 0 || atr < MinATR) { DeleteOurPendings(); return; }
   double highs[], lows[];
   ArraySetAsSeries(highs, true); ArraySetAsSeries(lows, true);
   if(CopyHigh(_Symbol, SignalTF, 1, BreakoutLookback, highs) != BreakoutLookback) return;
   if(CopyLow(_Symbol, SignalTF, 1, BreakoutLookback, lows) != BreakoutLookback) return;
   double top = highs[ArrayMaximum(highs)] + EntryATRBuffer * atr;
   double bottom = lows[ArrayMinimum(lows)] - EntryATRBuffer * atr;
   double sl_buy = top - SL_ATR * atr, tp_buy = top + TP_ATR * atr;
   double sl_sell = bottom + SL_ATR * atr, tp_sell = bottom - TP_ATR * atr;
   MqlTick tick; if(!SymbolInfoTick(_Symbol, tick)) return;
   DeleteOurPendings();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   datetime expiry = TimeCurrent() + PendingExpiryHours * 3600;
   if(TrendAllows(true) && top > tick.ask)
      trade.BuyStop(LotsForRisk(top-sl_buy), top, _Symbol, sl_buy, tp_buy, ORDER_TIME_SPECIFIED, expiry, Prefix()+"BUY_BREAKOUT");
   if(TrendAllows(false) && bottom < tick.bid)
      trade.SellStop(LotsForRisk(sl_sell-bottom), bottom, _Symbol, sl_sell, tp_sell, ORDER_TIME_SPECIFIED, expiry, Prefix()+"SELL_BREAKOUT");
}

void ManagePositions()
{
   double atr = GetATR(0); if(atr <= 0) return;
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      double price = type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double risk = MathAbs(open - sl); if(risk <= 0) continue;
      double new_sl = sl;
      if(UseBreakEven && MathAbs(price-open) >= BreakEvenAtR*risk)
         new_sl = type == POSITION_TYPE_BUY ? open + BreakEvenOffsetATR*atr : open - BreakEvenOffsetATR*atr;
      if(UseSwingTrailing)
      {
         double candidate = type == POSITION_TYPE_BUY ? price - TrailATR*atr : price + TrailATR*atr;
         if(type == POSITION_TYPE_BUY) new_sl = MathMax(new_sl, candidate); else new_sl = MathMin(new_sl, candidate);
      }
      if(type == POSITION_TYPE_BUY && new_sl > sl && new_sl < price) trade.PositionModify(ticket, new_sl, tp);
      if(type == POSITION_TYPE_SELL && (sl == 0 || new_sl < sl) && new_sl > price) trade.PositionModify(ticket, new_sl, tp);
   }
}

int OnInit()
{
   atr_handle = iATR(_Symbol, SignalTF, ATRPeriod);
   ma_handle = iMA(_Symbol, HigherTF, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(atr_handle == INVALID_HANDLE || ma_handle == INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(MagicNumber);
   ResetDay();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteOurPendings();
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   if(ma_handle != INVALID_HANDLE) IndicatorRelease(ma_handle);
}

void OnTick()
{
   ResetDay();
   ManagePositions();
   if(IsNewBar()) PlaceBreakouts();
}
