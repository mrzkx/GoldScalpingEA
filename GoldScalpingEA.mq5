//+------------------------------------------------------------------+
//|                                            GoldScalpingEA.mq5    |
//|                     黄金日内短线EA - 多空双向                       |
//|                     基于RSI/WR超买超卖 + DMI趋势方向                |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- 枚举：信号模式
enum ENUM_SIGNAL_MODE
{
   MODE_RSI_WR     = 0,  // RSI/威廉指标 超买超卖反转
   MODE_DMI        = 1,  // DMI金叉死叉 趋势跟随
   MODE_COMBINED   = 2   // 综合模式（RSI/WR过滤 + DMI方向）
};

//--- 枚举：平仓模式
enum ENUM_EXIT_MODE
{
   EXIT_FIXED_SLTP   = 0,  // 固定止损止盈
   EXIT_SIGNAL_REVERSE = 1, // 反向信号平仓
   EXIT_BOTH         = 2   // 两者兼用（先到先出）
};

//--- 枚举：仓位计算模式
enum ENUM_LOT_MODE
{
   LOT_FIXED         = 0,  // 固定手数
   LOT_PERCENT_BALANCE = 1, // 账户余额百分比（复利）
   LOT_PERCENT_EQUITY  = 2, // 账户净值百分比（复利）
   LOT_RISK_PER_TRADE  = 3  // 按止损风险比例（凯利复利）
};

//--- 输入参数 - 通用
input string        Sep0              = "====== 通用参数 ======";
input ENUM_SIGNAL_MODE InpSignalMode  = MODE_COMBINED;     // 信号模式
input ENUM_EXIT_MODE   InpExitMode    = EXIT_BOTH;         // 平仓模式
input int           InpMagicNumber    = 20250430;          // EA魔术号
input int           InpMaxPositions   = 1;                 // 同方向最大持仓数
input int           InpStopLoss       = 300;               // 止损点数（0=不设）
input int           InpTakeProfit     = 500;               // 止盈点数（0=不设）
input int           InpBarShift       = 1;                 // 信号K线（1=已收盘K线）

//--- 输入参数 - 仓位管理（复利）
input string        SepLot            = "====== 仓位管理 ======";
input ENUM_LOT_MODE InpLotMode        = LOT_RISK_PER_TRADE; // 仓位计算模式
input double        InpFixedLot       = 0.01;              // 固定手数（LOT_FIXED时生效）
input double        InpRiskPercent    = 2.0;               // 风险百分比（1-10%，复利模式生效）
input double        InpMaxLot         = 10.0;              // 最大手数上限（安全限制）
input double        InpMinLot         = 0.01;              // 最小手数下限

//--- 输入参数 - 日内控制
input string        Sep1              = "====== 日内控制 ======";
input bool          InpDayTradeOnly   = true;              // 仅日内交易（收盘前平仓）
input int           InpStartHour      = 9;                 // 允许开仓起始小时（服务器时间）
input int           InpEndHour        = 22;                // 允许开仓截止小时
input int           InpCloseAllHour   = 23;                // 强制平仓小时
input int           InpCloseAllMinute = 0;                 // 强制平仓分钟
input bool          InpAvoidNews      = false;             // 大波动时段暂停（预留）

//--- 输入参数 - RSI
input string        Sep2              = "====== RSI参数 ======";
input int           InpRSIPeriod      = 14;                // RSI周期
input double        InpRSIOversold    = 30.0;              // RSI超卖阈值（做多）
input double        InpRSIOverbought  = 70.0;              // RSI超买阈值（做空）
input double        InpRSIExitLong    = 60.0;              // RSI多单平仓阈值
input double        InpRSIExitShort   = 40.0;              // RSI空单平仓阈值

//--- 输入参数 - 威廉指标
input string        Sep3              = "====== 威廉指标参数 ======";
input int           InpWRPeriod       = 14;                // 威廉指标周期
input double        InpWROversold     = -80.0;             // WR超卖阈值（做多）
input double        InpWROverbought   = -20.0;             // WR超买阈值（做空）

//--- 输入参数 - DMI/ADX
input string        Sep4              = "====== DMI参数 ======";
input int           InpDMIPeriod      = 14;                // DMI周期
input double        InpADXMin         = 20.0;              // ADX最低阈值（趋势确认）
input double        InpDIGapMin       = 3.0;               // +DI与-DI最小差距

//--- 输入参数 - 趋势过滤（可选）
input string        Sep5              = "====== 趋势过滤 ======";
input bool          InpUseTrendFilter = true;              // 启用趋势过滤
input int           InpTrendMAPeriod  = 50;                // 趋势MA周期（短周期适合日内）
input ENUM_MA_METHOD InpTrendMAMethod = MODE_EMA;          // 趋势MA类型

//--- 输入参数 - 移动止损
input string        Sep6              = "====== 移动止损 ======";
input bool          InpUseTrailing    = true;              // 启用移动止损
input int           InpTrailingStart  = 200;               // 盈利多少点后启动
input int           InpTrailingStep   = 100;               // 移动止损步进

//--- 全局变量
CTrade trade;
int handleRSI;
int handleWR;
int handleDMI;
int handleTrendMA;
datetime lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- 创建指标句柄
   handleRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   handleWR  = iWPR(_Symbol, PERIOD_CURRENT, InpWRPeriod);
   handleDMI = iADX(_Symbol, PERIOD_CURRENT, InpDMIPeriod);

   if(handleRSI == INVALID_HANDLE || handleWR == INVALID_HANDLE || handleDMI == INVALID_HANDLE)
   {
      Print("错误：指标句柄创建失败");
      return INIT_FAILED;
   }

   if(InpUseTrendFilter)
   {
      handleTrendMA = iMA(_Symbol, PERIOD_CURRENT, InpTrendMAPeriod, 0, InpTrendMAMethod, PRICE_CLOSE);
      if(handleTrendMA == INVALID_HANDLE)
      {
         Print("错误：趋势MA句柄创建失败");
         return INIT_FAILED;
      }
   }

   lastBarTime = 0;
   Print("GoldScalpingEA 初始化完成 | 模式: ", EnumToString(InpSignalMode));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleRSI     != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleWR      != INVALID_HANDLE) IndicatorRelease(handleWR);
   if(handleDMI     != INVALID_HANDLE) IndicatorRelease(handleDMI);
   if(handleTrendMA != INVALID_HANDLE) IndicatorRelease(handleTrendMA);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 日内强制平仓检查（每个tick都检查）
   if(InpDayTradeOnly)
      CheckDayClose();

   //--- 移动止损（每个tick都检查）
   if(InpUseTrailing)
      ManageTrailingStop();

   //--- 信号只在新K线时检查
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   //--- 检查交易时段
   if(!IsTradeTime()) return;

   //--- 获取所有指标数据
   double rsi, wr, adx, pdi, mdi, pdiPrev, mdiPrev, trendMA, currentClose;
   if(!GetIndicatorValues(rsi, wr, adx, pdi, mdi, pdiPrev, mdiPrev, trendMA, currentClose))
      return;

   //--- 生成信号
   int signal = GenerateSignal(rsi, wr, adx, pdi, mdi, pdiPrev, mdiPrev, trendMA, currentClose);

   //--- 反向信号平仓
   if(InpExitMode == EXIT_SIGNAL_REVERSE || InpExitMode == EXIT_BOTH)
      CheckSignalExit(signal, rsi);

   //--- 开仓
   if(signal == 1 && CountPositions(POSITION_TYPE_BUY) < InpMaxPositions)
   {
      OpenOrder(ORDER_TYPE_BUY, "BUY");
   }
   else if(signal == -1 && CountPositions(POSITION_TYPE_SELL) < InpMaxPositions)
   {
      OpenOrder(ORDER_TYPE_SELL, "SELL");
   }

   //--- 更新图表显示
   UpdateComment(rsi, wr, adx, pdi, mdi, trendMA, signal);
}

//+------------------------------------------------------------------+
//| 获取所有指标值                                                      |
//+------------------------------------------------------------------+
bool GetIndicatorValues(double &rsi, double &wr, double &adx,
                        double &pdi, double &mdi, double &pdiPrev, double &mdiPrev,
                        double &trendMA, double &currentClose)
{
   double buf[];
   ArraySetAsSeries(buf, true);

   // RSI
   if(CopyBuffer(handleRSI, 0, InpBarShift, 1, buf) < 1) return false;
   rsi = buf[0];

   // WR
   if(CopyBuffer(handleWR, 0, InpBarShift, 1, buf) < 1) return false;
   wr = buf[0];

   // ADX
   if(CopyBuffer(handleDMI, 0, InpBarShift, 1, buf) < 1) return false;
   adx = buf[0];

   // +DI 当前和前一根
   double pdiBuf[];
   ArraySetAsSeries(pdiBuf, true);
   if(CopyBuffer(handleDMI, 1, InpBarShift, 2, pdiBuf) < 2) return false;
   pdi     = pdiBuf[0];
   pdiPrev = pdiBuf[1];

   // -DI 当前和前一根
   double mdiBuf[];
   ArraySetAsSeries(mdiBuf, true);
   if(CopyBuffer(handleDMI, 2, InpBarShift, 2, mdiBuf) < 2) return false;
   mdi     = mdiBuf[0];
   mdiPrev = mdiBuf[1];

   // 趋势MA
   trendMA = 0;
   if(InpUseTrendFilter)
   {
      if(CopyBuffer(handleTrendMA, 0, InpBarShift, 1, buf) < 1) return false;
      trendMA = buf[0];
   }

   // 收盘价
   currentClose = iClose(_Symbol, PERIOD_CURRENT, InpBarShift);

   return true;
}

//+------------------------------------------------------------------+
//| 生成交易信号  1=做多  -1=做空  0=无信号                             |
//+------------------------------------------------------------------+
int GenerateSignal(double rsi, double wr, double adx,
                   double pdi, double mdi, double pdiPrev, double mdiPrev,
                   double trendMA, double currentClose)
{
   int signalRSI = 0;
   int signalDMI = 0;

   //=== RSI/WR 超买超卖信号 ===
   // 做多：RSI超卖 或 WR超卖
   bool rsiOversold  = (rsi <= InpRSIOversold);
   bool wrOversold   = (wr  <= InpWROversold);
   // 做空：RSI超买 或 WR超买
   bool rsiOverbought = (rsi >= InpRSIOverbought);
   bool wrOverbought  = (wr  >= InpWROverbought);

   if(rsiOversold || wrOversold)
      signalRSI = 1;   // 超卖做多
   else if(rsiOverbought || wrOverbought)
      signalRSI = -1;  // 超买做空

   //=== DMI 金叉死叉信号 ===
   bool goldenCross = (pdi > mdi) && (pdiPrev <= mdiPrev);  // +DI上穿-DI
   bool deathCross  = (pdi < mdi) && (pdiPrev >= mdiPrev);  // +DI下穿-DI
   bool adxConfirm  = (adx >= InpADXMin);
   bool diGapOK     = MathAbs(pdi - mdi) >= InpDIGapMin;

   if(goldenCross && adxConfirm && diGapOK)
      signalDMI = 1;   // 金叉做多
   else if(deathCross && adxConfirm && diGapOK)
      signalDMI = -1;  // 死叉做空

   //=== 趋势过滤 ===
   int trendBias = 0;  // 0=无偏向
   if(InpUseTrendFilter && trendMA > 0)
   {
      if(currentClose > trendMA)
         trendBias = 1;   // 价格在MA上方，偏多
      else
         trendBias = -1;  // 价格在MA下方，偏空
   }

   //=== 综合判断 ===
   int finalSignal = 0;

   switch(InpSignalMode)
   {
      case MODE_RSI_WR:
         finalSignal = signalRSI;
         break;

      case MODE_DMI:
         finalSignal = signalDMI;
         break;

      case MODE_COMBINED:
         // 综合模式：DMI给方向，RSI/WR做过滤确认
         // 做多：DMI金叉 + RSI不在超买区（避免追高）
         // 做空：DMI死叉 + RSI不在超卖区（避免追低）
         // 或者：RSI超卖 + DMI多头主导（+DI > -DI）
         // 或者：RSI超买 + DMI空头主导（-DI > +DI）
         if(signalDMI == 1 && rsi < InpRSIOverbought)
            finalSignal = 1;
         else if(signalDMI == -1 && rsi > InpRSIOversold)
            finalSignal = -1;
         else if(signalRSI == 1 && pdi > mdi && adxConfirm)
            finalSignal = 1;
         else if(signalRSI == -1 && mdi > pdi && adxConfirm)
            finalSignal = -1;
         break;
   }

   //=== 趋势过滤：如果启用，信号必须与趋势方向一致 ===
   if(InpUseTrendFilter && trendBias != 0 && finalSignal != 0)
   {
      if(finalSignal != trendBias)
         finalSignal = 0;  // 信号与趋势矛盾，过滤掉
   }

   return finalSignal;
}

//+------------------------------------------------------------------+
//| 检查反向信号平仓 / RSI回归平仓                                      |
//+------------------------------------------------------------------+
void CheckSignalExit(int signal, double rsi)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      long posType = PositionGetInteger(POSITION_TYPE);

      bool shouldClose = false;
      string reason = "";

      // 反向信号平仓
      if(posType == POSITION_TYPE_BUY && signal == -1)
      {
         shouldClose = true;
         reason = "反向做空信号";
      }
      else if(posType == POSITION_TYPE_SELL && signal == 1)
      {
         shouldClose = true;
         reason = "反向做多信号";
      }

      // RSI回归平仓（多单RSI回到60以上平仓，空单RSI回到40以下平仓）
      if(!shouldClose && InpSignalMode != MODE_DMI)
      {
         if(posType == POSITION_TYPE_BUY && rsi >= InpRSIExitLong)
         {
            shouldClose = true;
            reason = StringFormat("RSI回归%.1f≥%.1f", rsi, InpRSIExitLong);
         }
         else if(posType == POSITION_TYPE_SELL && rsi <= InpRSIExitShort)
         {
            shouldClose = true;
            reason = StringFormat("RSI回归%.1f≤%.1f", rsi, InpRSIExitShort);
         }
      }

      if(shouldClose)
      {
         Print("平仓 #", ticket, " 原因: ", reason);
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| 计算复利手数                                                       |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double lot = InpFixedLot;

   //--- 获取品种手数规格
   double lotMin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(lotStep <= 0) lotStep = 0.01;
   if(tickVal <= 0 || tickSize <= 0) tickVal = 1.0;

   switch(InpLotMode)
   {
      case LOT_FIXED:
         lot = InpFixedLot;
         break;

      case LOT_PERCENT_BALANCE:
      {
         //--- 余额百分比：手数 = 余额 * 风险% / 保证金需求
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskMoney = balance * InpRiskPercent / 100.0;
         double marginRequired = 0;
         if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
         {
            if(marginRequired > 0)
               lot = riskMoney / marginRequired;
         }
         break;
      }

      case LOT_PERCENT_EQUITY:
      {
         //--- 净值百分比：同上但用净值（更保守，亏损时自动缩仓）
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double riskMoney = equity * InpRiskPercent / 100.0;
         double marginRequired = 0;
         if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
         {
            if(marginRequired > 0)
               lot = riskMoney / marginRequired;
         }
         break;
      }

      case LOT_RISK_PER_TRADE:
      {
         //--- 按止损风险计算：每笔亏损不超过余额的X%
         //--- 公式：手数 = 可承受亏损金额 / (止损点数 * 每点价值)
         if(InpStopLoss <= 0)
         {
            Print("警告：风险模式需要设置止损，回退到余额百分比模式");
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double riskMoney = balance * InpRiskPercent / 100.0;
            double marginRequired = 0;
            if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
            {
               if(marginRequired > 0)
                  lot = riskMoney / marginRequired;
            }
            break;
         }

         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskMoney = balance * InpRiskPercent / 100.0;

         // 止损金额 = 手数 * 止损点数 * 每点价值
         // 每点价值 = tickValue / tickSize * point
         double pointValue = tickVal / tickSize * point;
         double slMoney = InpStopLoss * point * pointValue; // 1手的止损金额

         if(slMoney > 0)
            lot = riskMoney / (InpStopLoss * pointValue);

         break;
      }
   }

   //--- 手数规范化：对齐到lotStep
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;

   //--- 限制在安全范围内
   lot = MathMax(lot, MathMax(lotMin, InpMinLot));
   lot = MathMin(lot, MathMin(lotMax, InpMaxLot));

   //--- 精度处理
   lot = NormalizeDouble(lot, 2);

   return lot;
}

//+------------------------------------------------------------------+
//| 开仓                                                               |
//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE orderType, string tag)
{
   double price, sl = 0, tp = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(orderType == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(InpStopLoss > 0)   sl = NormalizeDouble(price - InpStopLoss * point, _Digits);
      if(InpTakeProfit > 0)  tp = NormalizeDouble(price + InpTakeProfit * point, _Digits);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(InpStopLoss > 0)   sl = NormalizeDouble(price + InpStopLoss * point, _Digits);
      if(InpTakeProfit > 0)  tp = NormalizeDouble(price - InpTakeProfit * point, _Digits);
   }

   if(price <= 0) return;

   //--- 动态计算手数
   double lotSize = CalculateLotSize();

   string comment = StringFormat("%s|%.2f|%s", tag, lotSize, TimeToString(TimeCurrent(), TIME_MINUTES));

   if(!trade.PositionOpen(_Symbol, orderType, lotSize, price, sl, tp, comment))
   {
      Print("开仓失败 ", tag, " 手数: ", lotSize,
            " 错误: ", trade.ResultRetcode(),
            " - ", trade.ResultRetcodeDescription());
   }
   else
   {
      Print("开仓成功 ", tag,
            " 手数: ", lotSize,
            " 价格: ", price,
            " SL: ", sl, " TP: ", tp,
            " 余额: ", AccountInfoDouble(ACCOUNT_BALANCE));
   }
}

//+------------------------------------------------------------------+
//| 日内强制平仓                                                       |
//+------------------------------------------------------------------+
void CheckDayClose()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.hour > InpCloseAllHour ||
      (dt.hour == InpCloseAllHour && dt.min >= InpCloseAllMinute))
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         Print("日内平仓 #", ticket, " 时间: ", TimeToString(TimeCurrent()));
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| 移动止损管理                                                       |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long   posType   = PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = (bid - openPrice) / point;

         if(profit >= InpTrailingStart)
         {
            double newSL = NormalizeDouble(bid - InpTrailingStep * point, _Digits);
            if(newSL > currentSL + point) // 只往盈利方向移
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = (openPrice - ask) / point;

         if(profit >= InpTrailingStart)
         {
            double newSL = NormalizeDouble(ask + InpTrailingStep * point, _Digits);
            if(currentSL == 0 || newSL < currentSL - point)
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 检查是否在允许交易时段                                              |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
   if(!InpDayTradeOnly) return true;

   MqlDateTime dt;
   TimeCurrent(dt);

   // 在允许开仓时段内
   if(dt.hour >= InpStartHour && dt.hour < InpEndHour)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 统计指定方向持仓数                                                  |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetInteger(POSITION_TYPE) == type)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| 更新图表显示                                                       |
//+------------------------------------------------------------------+
void UpdateComment(double rsi, double wr, double adx,
                   double pdi, double mdi, double trendMA, int signal)
{
   string signalStr = (signal == 1) ? "★ 做多 ★" :
                      (signal == -1) ? "★ 做空 ★" : "无信号";

   string trendStr = "";
   if(InpUseTrendFilter && trendMA > 0)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, InpBarShift);
      trendStr = StringFormat("EMA%d: %.2f | 价格%s均线\n",
                              InpTrendMAPeriod, trendMA,
                              close > trendMA ? "在上" : "在下");
   }

   //--- 仓位信息
   double nextLot = CalculateLotSize();
   string lotModeStr = "";
   switch(InpLotMode)
   {
      case LOT_FIXED:            lotModeStr = "固定手数"; break;
      case LOT_PERCENT_BALANCE:  lotModeStr = "余额复利"; break;
      case LOT_PERCENT_EQUITY:   lotModeStr = "净值复利"; break;
      case LOT_RISK_PER_TRADE:   lotModeStr = "风险复利"; break;
   }

   Comment(
      "═══ Gold Scalping EA ═══\n",
      "信号模式: ", EnumToString(InpSignalMode), "\n",
      "─────────────────────\n",
      StringFormat("RSI(%d): %.2f %s\n", InpRSIPeriod, rsi,
         rsi <= InpRSIOversold ? "[超卖→多]" :
         rsi >= InpRSIOverbought ? "[超买→空]" : ""),
      StringFormat("WR(%d): %.2f %s\n", InpWRPeriod, wr,
         wr <= InpWROversold ? "[超卖→多]" :
         wr >= InpWROverbought ? "[超买→空]" : ""),
      StringFormat("+DI: %.1f | -DI: %.1f | ADX: %.1f %s\n",
         pdi, mdi, adx,
         adx >= InpADXMin ? "[趋势有效]" : "[趋势弱]"),
      trendStr,
      "─────────────────────\n",
      "当前信号: ", signalStr, "\n",
      StringFormat("多单: %d | 空单: %d / 上限%d\n",
         CountPositions(POSITION_TYPE_BUY),
         CountPositions(POSITION_TYPE_SELL),
         InpMaxPositions),
      "─────────────────────\n",
      StringFormat("仓位模式: %s | 风险: %.1f%%\n", lotModeStr, InpRiskPercent),
      StringFormat("下笔手数: %.2f | 余额: %.2f\n", nextLot, AccountInfoDouble(ACCOUNT_BALANCE)),
      StringFormat("净值: %.2f\n", AccountInfoDouble(ACCOUNT_EQUITY)),
      StringFormat("交易时段: %02d:00 - %02d:00\n", InpStartHour, InpEndHour),
      "═══════════════════════"
   );
}
//+------------------------------------------------------------------+
