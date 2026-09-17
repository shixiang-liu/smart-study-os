// ============================================================================
// 科学计算器 - Calculator
// ============================================================================
// 功能：基础计算 + 科学计算 + 历史记录
// 架构：自实现表达式解析器（Tokenizer → RPN → Evaluator）
// 存储：历史记录本地持久化（Preferences），不同步云端
// 设计：支持暗色模式、紧凑模式（小窗）
// ============================================================================

import { promptAction } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { CalculatorViewModel, CalcHistoryItem } from '../../../calculator/viewmodel/CalculatorViewModel';
import { AppColors, AppSizes, AppShadows, AppAnimations, AppThemeManager, AppGradients, LinearGradient, getCardShadow } from '../../../common/utils/AppTheme';
import { CalculatorDisplay, CalculatorButton, CalculatorHistoryItem, CalculatorModeToggle, HistoryItemData } from '../components/CalculatorComponents';

// ============================================================================
// 类型定义
// ============================================================================

// 计算器模式：基础 / 科学
enum CalculatorMode {
  BASIC = 'basic',
  SCIENTIFIC = 'scientific'
}

// 历史记录条目
interface HistoryItem {
  id: number;
  expression: string;
  result: string;
  timestamp: number;
}

// 按日期分组的历史记录
interface HistoryGroup {
  dateLabel: string;
  items: HistoryItem[];
}

// 按钮单元格
interface ButtonCell {
  label: string;
  key: string;
}

// 按钮行
interface ButtonRow {
  key: string;
  cells: ButtonCell[];
}

// ============================================================================
// 类实现 - 满足 ArkTS 不允许对象字面量的约束
// ============================================================================

class ButtonCellImpl implements ButtonCell {
  label: string;
  key: string;

  constructor(label: string, key: string) {
    this.label = label;
    this.key = key;
  }
}

class ButtonRowImpl implements ButtonRow {
  key: string;
  cells: ButtonCell[];

  constructor(key: string, cells: ButtonCell[]) {
    this.key = key;
    this.cells = cells;
  }
}

class HistoryGroupImpl implements HistoryGroup {
  dateLabel: string;
  items: HistoryItem[];

  constructor(dateLabel: string, items: HistoryItem[]) {
    this.dateLabel = dateLabel;
    this.items = items;
  }
}

// ============================================================================
// 按钮布局配置
// ============================================================================

// 科学计算扩展按钮
const SCIENTIFIC_ROWS: ButtonRow[] = buildButtonRows([
  ['(', ')', '1/x', 'x²'],
  ['x³', 'xʸ', '√', 'sin'],
  ['cos', 'tan', 'log', 'ln'],
  ['π', 'e', '%', 'x!']
], 'sc');

// 基础按钮
const BASIC_ROWS: ButtonRow[] = buildButtonRows([
  ['MC', 'M+', 'M-', 'MR'],
  ['C', '÷', '×', '⌫'],
  ['7', '8', '9', '-'],
  ['4', '5', '6', '+'],
  ['1', '2', '3'],
  ['%', '0', '.']
], 'bs');

// 生成按钮行配置
// 每个按钮需要唯一 key，用于 ForEach 渲染
function buildButtonRows(labels: string[][], prefix: string): ButtonRow[] {
  const rows: ButtonRow[] = [];
  labels.forEach((row: string[], rowIndex: number) => {
    const cells: ButtonCell[] = [];
    row.forEach((label: string, colIndex: number) => {
      cells.push(new ButtonCellImpl(label, `${prefix}-cell-${rowIndex}-${colIndex}-${label}`));
    });
    rows.push(new ButtonRowImpl(`${prefix}-row-${rowIndex}`, cells));
  });
  return rows;
}

// ============================================================================
// 计算器组件
// ============================================================================

@Entry
@Component
export struct Calculator {
  // ==================== 状态变量 ====================

  // 当前输入的表达式（内部格式，如 *、/）
  @State private expression: string = '';

  // 计算结果显示
  @State private result: string = '0';

  // 是否高亮结果（按等号后放大显示）
  @State private highlightResult: boolean = false;

  // 当前模式（基础 / 科学）
  @State private mode: CalculatorMode = CalculatorMode.BASIC;

  // 是否显示历史记录视图
  @State private isHistoryView: boolean = false;

  // 历史记录列表
  @State private history: HistoryItem[] = [];

  // 内存值（MC/M+/M-/MR 功能）
  @State private memoryValue: number = 0;

  // 角度制 / 弧度制（用于三角函数）
  @State private isDegreeMode: boolean = true;

  // 暗色模式
  @StorageLink('isDarkMode') private isDarkMode: boolean = false;

  // ==================== 依赖 ====================

  // ViewModel 负责历史记录持久化
  private calcViewModel: CalculatorViewModel = CalculatorViewModel.getInstance();

  // ==================== 生命周期 ====================

  async aboutToAppear() {
    AppThemeManager.setIsDarkMode(this.isDarkMode);
    // 页面初始化时加载历史记录
    await this.loadPersistedHistory();
  }

  // ==================== 数据持久化 ====================

  // 从本地存储加载历史记录
  // 使用 Preferences，不同步到云端
  private async loadPersistedHistory(): Promise<void> {
    try {
      const savedHistory = await this.calcViewModel.loadHistory();
      this.history = savedHistory.map((item: CalcHistoryItem): HistoryItem => {
        const historyItem: HistoryItem = {
          id: item.id,
          expression: item.expression,
          result: item.result,
          timestamp: item.timestamp
        }
        return historyItem
      });
    } catch (err) {
      console.error('[Calculator] 加载历史记录失败:', err);
    }
  }

  // 保存历史记录条目
  private async saveHistoryItem(expression: string, result: string): Promise<void> {
    try {
      await this.calcViewModel.addHistory(expression, result);
    } catch (err) {
      console.error('[Calculator] 保存历史记录失败:', err);
    }
  }

  // ==================== 主入口 ====================

  build() {
    NavDestination() {
      // 两种视图模式切换
      if (this.isHistoryView) {
        this.renderHistoryView();
      } else {
        this.renderCalculatorView();
      }
    }
    .title(this.getTitle());
  }

  // ==================== 紧凑模式视图 ====================
  // 适合小窗浮窗使用，按钮更小，功能精简
  @Builder
  private renderCompactView() {
    Column() {
      // 紧凑显示区
      Column({ space: 4 }) {
        Text(this.getDisplayExpression())
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .textAlign(TextAlign.End)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Text(this.result)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .textAlign(TextAlign.End)
          .width('100%')
          .maxLines(1);
      }
      .width('100%')
      .padding(AppSizes.SPACE_MD)
      .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(AppSizes.RADIUS_MD)
      .shadow(AppShadows.SHADOW_XS);

      // 紧凑按钮网格
      Grid() {
        ForEach(['C', '÷', '×', '⌫', '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '=', '%', '0', '.', ''], (btn: string) => {
          GridItem() {
            if (btn) {
              Button(btn)
                .fontSize(18)
                .fontWeight(btn === '=' ? FontWeight.Bold : FontWeight.Normal)
                .width('100%')
                .height(44)
                .borderRadius(22)
                .backgroundColor(btn === '=' ? AppColors.ACCENT : (this.isOperator(btn) ? (this.isDarkMode ? '#3A3A3C' : '#F2F2F7') : (this.isDarkMode ? '#2C2C2E' : '#FFFFFF')))
                .linearGradient(btn === '=' ? AppGradients.PRIMARY_BTN : undefined)
                .fontColor(btn === '=' ? Color.White : AppColors.TEXT_PRIMARY)
                .shadow(this.isDarkMode ? undefined : AppShadows.SHADOW_SM)
                .onClick(() => this.handleCompactButton(btn));
            }
          }
        });
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(8)
      .columnsGap(8)
      .width('100%')
      .height(260)
      .margin({ top: AppSizes.SPACE_MD });

      // 退出紧凑模式按钮
      Button('展开完整计算器')
        .fontSize(AppSizes.FONT_XS)
        .height(32)
        .width('100%')
        .borderRadius(16)
        .backgroundColor(AppColors.TEXT_PRIMARY)
        .fontColor(Color.White)
        .margin({ top: AppSizes.SPACE_MD })
        .onClick(() => {
          // 已删除紧凑模式
        });
    }
    .width('100%')
    .height('100%')
    .padding(AppSizes.SPACE_MD)
    .backgroundColor(AppColors.BG_PRIMARY);
  }

  // ==================== 紧凑模式按钮处理 ====================
  // 精简版按钮逻辑，仅支持基础运算
  private handleCompactButton(btn: string) {
    switch (btn) {
      case 'C':
        // 清空表达式和结果
        this.expression = '';
        this.result = '0';
        this.highlightResult = false;
        break;
      case '⌫':
        // 删除最后一个字符
        if (this.expression.length > 0) {
          this.expression = this.expression.slice(0, -1);
          this.calculateInstant();
        }
        break;
      case '=':
        // 提交计算
        this.commitResult();
        break;
      case '÷':
        // 映射到内部运算符
        this.expression += '/';
        break;
      case '×':
        this.expression += '*';
        break;
      default:
        // 数字和其他符号直接追加
        this.expression += btn;
        this.calculateInstant();
        break;
    }
  }

  // ==================== 标题栏 ====================

  @Builder
  private getTitle() {
    Text(this.isHistoryView ? $r('app.string.calculator_history_title') : $r('app.string.calculator_title'))
      .fontSize($r('app.float.number_20'))
          .fontWeight(FontWeight.Bold)
      .margin({ left: $r('app.float.number_10') })
      .height('100%');
  }

  // ==================== 主计算器视图 ====================

  @Builder
  private renderCalculatorView() {
    Column({ space: 8 }) {
      // 顶部工具栏（角度/弧度、暗色模式、菜单）
      this.renderTopBar();

      // 表达式和结果显示区
      CalculatorDisplay({
        expression: this.expression,
        result: this.result,
        isDarkMode: this.isDarkMode
      })

      // 按钮区域（紧凑布局，确保科学模式下所有按钮在一屏内显示）
      Column({ space: 6 }) {
        // 科学计算扩展按钮（仅科学模式显示）
        if (this.mode === CalculatorMode.SCIENTIFIC) {
          this.renderScientificRows();
        }

        // 基础按钮区
        this.renderBasicRows(this.getPanelBg(), this.getPrimaryText(), this.getSecondaryText());
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getScaffoldBg())
    .padding({ left: 10, right: 10, bottom: 12, top: 4 });
  }

  // ==================== 顶部工具栏 ====================

  @Builder
  private renderTopBar() {
    Row({ space: 8 }) {
      // 角度/弧度切换
      CalculatorModeToggle({
        isDegreeMode: this.isDegreeMode,
        isDarkMode: this.isDarkMode,
        onToggle: () => { this.isDegreeMode = !this.isDegreeMode; }
      })

      // 帮助按钮 - 说明角度/弧度模式
      Button(undefined, { type: ButtonType.Circle }) {
        Text('?')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? AppColors.TEXT_WHITE : AppColors.TEXT_SECONDARY);
      }
      .width(26)
      .height(26)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_TERTIARY)
      .onClick(() => {
        this.showAngleModeHelp();
      });

      // 暗色模式切换
      // 使用文字图标代替 emoji
      Button(undefined, { type: ButtonType.Normal }) {
        Text(this.isDarkMode ? '○' : '●')
          .fontSize(12)
          .fontColor(this.isDarkMode ? AppColors.TEXT_WHITE : AppColors.TEXT_PRIMARY);
      }
      .borderRadius(16)
      .height(26)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_TERTIARY)
      .onClick(() => {
        this.isDarkMode = !this.isDarkMode;
      });

      Blank();

      // 更多菜单
      Button(undefined, { type: ButtonType.Circle }) {
        Text('⋮⋮')
          .fontSize(16)
          .fontColor(this.isDarkMode ? AppColors.TEXT_WHITE : AppColors.TEXT_PRIMARY);
      }
      .width(26)
      .height(26)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_TERTIARY)
      .onClick(() => {
        this.openMoreMenu();
      });
    }
    .width('100%')
    .height(32)
    .margin({ top: 4, bottom: 4 });
  }

  // 显示角度/弧度模式帮助说明
  private showAngleModeHelp(): void {
    promptAction.showDialog({
      title: '角度模式说明',
      message: '• DEG（角度制）：使用度数，如 sin(90°) = 1\n\n• RAD（弧度制）：使用弧度，如 sin(π/2) = 1\n\n日常计算建议使用角度制（DEG）\n数学/物理公式建议使用弧度制（RAD）',
      buttons: [{ text: '知道了', color: AppColors.ACCENT }]
    });
  }

  // ==================== 显示区 ====================
  // 上半部分：当前表达式（小字）
  // 下半部分：计算结果（大字）



  // ==================== 科学计算按钮 ====================

  @Builder
  private renderScientificRows() {
    Column({ space: 6 }) {
      ForEach(SCIENTIFIC_ROWS, (row: ButtonRow) => {
        Row({ space: 6 }) {
          ForEach(row.cells, (cell: ButtonCell) => {
            this.renderButton(cell, true);
          }, (cell: ButtonCell) => cell.key);
        }
        .width('100%');
      }, (row: ButtonRow) => row.key);
    }
    .margin({ bottom: 2 });
  }

  // ==================== 基础按钮区 ====================

  @Builder
  private renderBasicRows(panelBg: string, primaryText: string, secondaryText: string) {
    Column({ space: 6 }) {
      // 前四行普通渲染
      ForEach(BASIC_ROWS.slice(0, 4), (row: ButtonRow) => {
        Row({ space: 6 }) {
          ForEach(row.cells, (cell: ButtonCell) => {
            this.renderButton(
              cell,
              false,
              this.getBasicButtonBackground(cell, panelBg),
              this.getBasicButtonFontColor(cell, primaryText, secondaryText)
            );
          }, (cell: ButtonCell) => cell.key);
        }
        .width('100%');
      }, (row: ButtonRow) => row.key);

      // 最后两行特殊布局：等号按钮占据两行高度
      Row({ space: 6 }) {
        // 左侧：两行数字按钮
        Column({ space: 6 }) {
          // 第五行：1 2 3
          Row({ space: 6 }) {
            ForEach(BASIC_ROWS[4].cells, (cell: ButtonCell) => {
              this.renderButton(
                cell,
                false,
                this.getBasicButtonBackground(cell, panelBg),
                this.getBasicButtonFontColor(cell, primaryText, secondaryText)
              );
            }, (cell: ButtonCell) => cell.key);
          }
          .width('100%');

          // 第六行：% 0 .
          Row({ space: 6 }) {
            ForEach(BASIC_ROWS[5].cells, (cell: ButtonCell) => {
              this.renderButton(
                cell,
                false,
                this.getBasicButtonBackground(cell, panelBg),
                this.getBasicButtonFontColor(cell, primaryText, secondaryText)
              );
            }, (cell: ButtonCell) => cell.key);
          }
          .width('100%');
        }
        .layoutWeight(3);

        // 右侧：等号按钮（跨两行高度）
        this.renderEqualsButton();
      }
      .width('100%')
      .alignItems(VerticalAlign.Top);

    }
    .margin({ top: 4 });
  }

  // ==================== 等号按钮 ====================
  // 独立渲染，因为高度是普通按钮的两倍

  @Builder
  private renderEqualsButton() {
    Button(undefined, { type: ButtonType.Normal }) {
      Text('=')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_WHITE)
        .textAlign(TextAlign.Center);
    }
    .backgroundColor(AppColors.ACCENT)
    .linearGradient(AppGradients.PRIMARY_BTN)
    .borderRadius(AppSizes.RADIUS_LG) // 更柔和的圆角
    .height(102) // 两行高度：48 + 6间距 + 48 = 102
    .layoutWeight(1) // 只占一列宽度，与数字按钮列等宽
    .shadow(AppShadows.SHADOW_LG) // 悬浮阴影
    .onClick(() => {
      this.handleButton('=');
    });
  }

  // ==================== 通用按钮渲染 ====================

  @Builder
  private renderButton(cell: ButtonCell, isScientific: boolean = false, background: string = AppColors.BG_DARK_SECONDARY,
    fontColor: string = AppColors.BG_TERTIARY) {
    
    Button(undefined, { type: ButtonType.Normal }) {
      Text(cell.label)
        .fontSize(isScientific ? 16 : 22)
        .fontWeight(isScientific ? FontWeight.Normal : FontWeight.Medium)
        .fontColor(this.getButtonTextColor(cell, isScientific, fontColor));
    }
    .backgroundColor(this.getButtonBgColor(cell, isScientific, background))
    .linearGradient(this.getButtonGradient(cell))
    .borderRadius(isScientific ? AppSizes.RADIUS_MD : AppSizes.RADIUS_LG)
    .height(isScientific ? 36 : 48)
    .layoutWeight(1)
    .shadow(this.getButtonShadow(cell, isScientific))
    .onClick(() => {
      this.handleButton(cell.label);
    });
  }

  private getButtonGradient(cell: ButtonCell): LinearGradient | undefined {
    if (cell.label === 'C' || cell.label === '⌫') {
      return this.isDarkMode ? undefined : AppGradients.SPA_PEACH
    }
    if (['÷', '×', '-', '+'].includes(cell.label)) {
      return this.isDarkMode ? undefined : AppGradients.SPA_LAVENDER
    }
    return undefined
  }

  private getButtonTextColor(cell: ButtonCell, isScientific: boolean, defaultColor: string): string {
    if (cell.label === 'C' || cell.label === '⌫') {
      return this.isDarkMode ? '#FF9F43' : AppColors.TEXT_PRIMARY
    }
    if (['÷', '×', '-', '+'].includes(cell.label)) {
      return this.isDarkMode ? '#A78BFA' : AppColors.TEXT_PRIMARY
    }
    // 问题17修复：科学按键使用高对比度文字颜色
    if (isScientific) {
      return this.isDarkMode ? '#E8E8F0' : '#1E293B'  // 暗色模式用亮色，浅色模式用深色
    }
    return defaultColor
  }

  private getButtonBgColor(cell: ButtonCell, isScientific: boolean, defaultBg: string): string {
    if (!this.isDarkMode) {
      if (['C', '⌫', '÷', '×', '-', '+'].includes(cell.label)) {
        return 'transparent'
      }
      if (!isScientific) {
        return AppColors.BG_SECONDARY
      }
    }
    // 问题17修复：科学按钮使用更清晰的背景色
    if (isScientific) {
      // 暗色模式使用更深的背景色，浅色模式使用柔和的蓝灰色
      return this.isDarkMode ? '#3A3A4A' : '#E2E8F0'
    }
    return defaultBg
  }

  private getButtonShadow(cell: ButtonCell, isScientific: boolean): ShadowOptions {
    if (isScientific) return AppShadows.SHADOW_XS
    return this.isDarkMode ? AppShadows.SHADOW_XS : getCardShadow()
  }

  // ==================== 菜单 ====================

  // 问题16修复：删除紧凑模式
  private openMoreMenu() {
    promptAction.showActionMenu({
      title: $r('app.string.calculator_menu_title'),
      buttons: [
        {
          text: this.mode === CalculatorMode.BASIC ?
            $r('app.string.calculator_mode_scientific') : $r('app.string.calculator_mode_basic'),
          color: this.getMenuTextColor()
        },
        {
          text: $r('app.string.calculator_history_title'),
          color: this.getMenuTextColor()
        }
      ]
    }).then(result => {
      if (result.index === 0) {
        // 切换模式
        this.mode = this.mode === CalculatorMode.BASIC ? CalculatorMode.SCIENTIFIC : CalculatorMode.BASIC;
      } else if (result.index === 1) {
        // 显示历史
        this.isHistoryView = true;
      }
    }).catch(() => {});
  }

  // ==================== 按钮点击处理 ====================
  // 核心逻辑：根据按钮类型更新表达式或执行操作

  private handleButton(label: string) {
    // 新输入时取消高亮
    this.highlightResult = false;

    switch (label) {
      case 'C':
        // 清空所有
        this.expression = '';
        this.result = '0';
        break;
      case '⌫':
        // 退格
        this.expression = this.expression.slice(0, -1);
        // 如果表达式为空，重置结果为0
        if (this.expression === '') {
          this.result = '0';
        }
        break;
      case '=':
        // 提交计算
        this.commitResult();
        return;

      // ========== 内存功能 ==========
      case 'MC':
        // Memory Clear
        this.memoryValue = 0;
        return;
      case 'M+':
        // Memory Add
        this.memoryValue += this.getResultNumber();
        return;
      case 'M-':
        // Memory Subtract
        this.memoryValue -= this.getResultNumber();
        return;
      case 'MR':
        // Memory Recall
        this.expression += this.trimTrailingZeros(this.memoryValue.toString());
        break;

      // ========== 科学函数 ==========
      case 'sin':
      case 'cos':
      case 'tan':
      case 'log':
      case 'ln':
        // 函数名 + 左括号
        this.expression += `${label}(`;
        break;
      case '√':
        this.expression += 'sqrt(';
        break;
      case '1/x':
        this.expression += 'inv(';
        break;
      case 'x²':
        this.expression += '^2';
        break;
      case 'x³':
        this.expression += '^3';
        break;
      case 'xʸ':
        this.expression += '^';
        break;
      case 'x!':
        this.expression += '!';
        break;
      case 'π':
        this.expression += 'pi';
        break;
      case 'e':
        this.expression += 'e';
        break;
      case '%':
        this.expression += '%';
        break;

      default:
        // 数字和运算符
        this.expression += this.mapInput(label);
    }

    // 每次输入后即时计算
    this.calculateInstant();
  }

  // ==================== 输入映射 ====================
  // 将显示符号映射为内部运算符

  private mapInput(label: string): string {
    switch (label) {
      case '÷':
        return '/';
      case '×':
        return '*';
      default:
        return label;
    }
  }

  // ==================== 即时计算 ====================
  // 每次输入后实时显示结果

  private calculateInstant() {
    // 如果表达式为空，重置结果为0
    if (!this.expression || this.expression === '') {
      this.result = '0';
      return;
    }
    // 检查表达式是否可计算
    if (!this.canEvaluate()) {
      return;
    }
    try {
      // 词法分析 → 逆波兰表达式 → 求值
      const tokens: string[] = this.tokenize(this.expression);
      const rpn: string[] = this.toRpn(tokens);
      const value: number = this.evaluateRpn(rpn);

      // 处理特殊值和浮点精度
      if (!isFinite(value) || isNaN(value)) {
        this.result = 'Error';
      } else {
        // 使用toPrecision控制精度，修复0.1+0.2=0.30000004问题
        const preciseValue = Number(value.toPrecision(12));
        this.result = this.trimTrailingZeros(preciseValue.toString());
      }
    } catch (err) {
      this.result = 'Error';
    }
  }

  // 检查表达式是否可计算
  // 必须以数字、右括号、!、e、i(pi) 结尾
  private canEvaluate(): boolean {
    if (!this.expression) {
      return false;
    }
    const last: string = this.expression[this.expression.length - 1];
    return /[0-9)!ei]/.test(last);
  }

  // ==================== 提交结果 ====================
  // 按等号时：高亮结果 + 保存历史

  private commitResult() {
    if (!this.canEvaluate()) {
      return;
    }

    // 高亮结果
    this.highlightResult = true;
    this.calculateInstant();

    // 错误不保存历史
    if (this.result === 'Error') {
      return;
    }

    // 保存到历史记录
    const displayExpr = this.getDisplayExpression();
    const entry: HistoryItem = {
      id: Date.now(),
      expression: displayExpr,
      result: this.result,
      timestamp: Date.now()
    };
    // 添加到列表头部
    this.history.unshift(entry);

    // 限制历史记录数量
    if (this.history.length > 50) {
      this.history.pop();
    }

    // 持久化保存
    this.saveHistoryItem(displayExpr, this.result);
  }

  // ==================== 显示格式转换 ====================
  // 将内部表达式转换为用户友好格式

  private getDisplayExpression(): string {
    return this.expression
      .replace(/\*/g, '×')
      .replace(/\//g, '÷')
      .replace(/sqrt/g, '√')
      .replace(/pi/g, 'π');
  }

  // 获取当前结果的数值（用于内存操作）
  private getResultNumber(): number {
    return Number(this.result) || 0;
  }

  // 移除小数点后的多余零
  private trimTrailingZeros(value: string): string {
    if (value.indexOf('.') === -1) {
      return value;
    }
    return parseFloat(value).toString();
  }

  // ==================== 历史记录视图 ====================

  @Builder
  private renderHistoryView() {
    Column({ space: 16 }) {
      this.renderHistoryHeader();
      this.renderHistoryBody();
    }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isDarkMode ? '#000000' : '#FFFFFF')
    .padding({ left: 16, right: 16, bottom: 16 });
  }

  // 历史记录头部：返回按钮 + 标题 + 清空按钮
  @Builder
  private renderHistoryHeader() {
    Row({ space: 12 }) {
      // 返回按钮
      Button(undefined, { type: ButtonType.Circle }) {
        Text('←')
          .fontSize($r('app.float.number_20'))
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000');
      }
      .backgroundColor(this.isDarkMode ? '#2F2F2F' : '#E0E0E0')
      .onClick(() => {
        this.isHistoryView = false;
      });

      // 标题
      Text($r('app.string.calculator_history_title'))
        .fontSize($r('app.float.number_20'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000');

      Blank();

      // 清空按钮
      Button(undefined, { type: ButtonType.Circle }) {
        Image($r('app.media.ic_public_delete'))
          .width($r('app.float.number_20'))
          .height($r('app.float.number_20'));
      }
      .backgroundColor(this.isDarkMode ? '#2F2F2F' : '#E0E0E0')
      .onClick(() => {
        this.history = [];
      });
    }
    .margin({ top: 16 })
    .width('100%');
  }

  // 历史记录内容区
  @Builder
  private renderHistoryBody() {
    if (this.history.length === 0) {
      // 空状态
      Column() {
        Text($r('app.string.calculator_history_empty'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor(this.isDarkMode ? '#9E9E9E' : '#666666')
          .textAlign(TextAlign.Center);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    } else {
      // 按日期分组显示
      List() {
        ForEach(this.getGroupedHistory(), (group: HistoryGroup) => {
          ListItem() {
            this.renderHistoryGroup(group);
          };
        }, (group: HistoryGroup) => group.dateLabel);
      }
      .width('100%')
      .layoutWeight(1);
    }
  }

  // 历史记录分组（按日期）
  @Builder
  private renderHistoryGroup(group: HistoryGroup) {
    Column({ space: 12 }) {
      // 日期标签
      Text(group.dateLabel)
        .fontColor(this.isDarkMode ? '#9E9E9E' : '#666666')
        .fontSize($r('app.float.caption_font_size'));

      // 该日期下的所有记录
      Column({ space: 10 }) {
        ForEach(group.items, (item: HistoryItem) => {
          CalculatorHistoryItem({
            item: item,
            isDarkMode: this.isDarkMode,
            onSelect: (i) => {
              this.expression = i.expression;
              this.result = i.result;
              this.isHistoryView = false;
            }
          })
        }, (item: HistoryItem) => `${item.id}`);
      }
    }
    .width('100%')
    .padding({ bottom: 8 });
  }

  // 单条历史记录卡片
  @Builder
  private renderHistoryCard(item: HistoryItem) {
    Column({ space: 6 }) {
      Text(item.expression)
        .fontColor(this.isDarkMode ? '#C5C5C5' : '#666666')
        .fontSize($r('app.float.list_item_font_size'));
      Text(`=${item.result}`)
        .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
        .fontSize($r('app.float.number_20'))
        .fontWeight(FontWeight.Bold);
    }
    .padding(16)
    .backgroundColor(this.isDarkMode ? '#1F1F1F' : '#F5F5F5')
    .borderRadius($r('app.float.number_15'));
  }

  // ==================== 样式辅助 ====================

  // 获取基础按钮背景色
  private getBasicButtonBackground(cell: ButtonCell, panelBg: string): string {
    const opBgLight = '#E2E2E2';
    const opBgDark = '#2E2E32';
    const defaultLight = '#E8E8E8';
    const defaultDark = '#1F1F21';
    const warnLight = '#BDBDBD';
    const warnDark = '#3A3A3A';

    if (cell.label === '=') {
      return AppColors.ACCENT;
    }
    if (cell.label === 'C' || cell.label === '⌫') {
      return this.isDarkMode ? warnDark : warnLight;
    }
    // 运算符按钮
    if (cell.label === '÷' || cell.label === '×' || cell.label === '-' || cell.label === '+') {
      return this.isDarkMode ? opBgDark : opBgLight;
    }
    // 背景稍微和面板拉开对比
    return this.isDarkMode ? defaultDark : defaultLight;
  }

  // 获取基础按钮字体颜色
  private getBasicButtonFontColor(cell: ButtonCell, primaryText: string, secondaryText: string): string {
    if (cell.label === '=' || cell.label === 'C' || cell.label === '⌫') {
      return '#FFFFFF';
    }
    if (cell.label === '÷' || cell.label === '×' || cell.label === '-' || cell.label === '+') {
      return primaryText;
    }
    return secondaryText;
  }

  // 主题辅助：获取当前模式下的颜色
  private getScaffoldBg(): string {
    return this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY;
  }
  private getCardBg(): string {
    return this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY;
  }
  private getPanelBg(): string {
    return this.isDarkMode ? AppColors.BG_DARK_TERTIARY : AppColors.BG_TERTIARY;
  }
  private getPrimaryText(): string {
    return this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY;
  }
  private getSecondaryText(): string {
    return this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY;
  }

  // 获取菜单文字颜色（跟随系统暗色模式）
  private getMenuTextColor(): string {
    try {
      const config: resourceManager.Configuration = getContext(this).resourceManager.getConfigurationSync();
      if (config?.colorMode === resourceManager.ColorMode.DARK) {
        return '#FFFFFF';
      }
      return '#000000';
    } catch (_) {
      return '#000000';
    }
  }

  // 按日期分组历史记录
  private getGroupedHistory(): HistoryGroup[] {
    const map = new Map<string, HistoryItem[]>();

    // 按日期分组
    this.history.forEach((item: HistoryItem) => {
      const label: string = this.formatDate(item.timestamp);
      if (!map.has(label)) {
        map.set(label, []);
      }
      map.get(label)?.push(item);
    });

    // 转换为数组
    const groups: HistoryGroup[] = [];
    map.forEach((items: HistoryItem[], label: string) => {
      groups.push(new HistoryGroupImpl(label, items));
    });
    return groups;
  }

  // 格式化日期（月/日）
  private formatDate(timestamp: number): string {
    return new Intl.DateTimeFormat('zh-CN', { month: 'numeric', day: 'numeric' }).format(new Date(timestamp));
  }

  // ============================================================================
  // 表达式解析器
  // ============================================================================
  // 架构：Tokenizer → Shunting-yard → RPN Evaluator
  // 支持：四则运算、幂运算、括号、科学函数

  // ==================== 词法分析 ====================
  // 将表达式字符串拆分为 token 数组

  private tokenize(expr: string): string[] {
    const tokens: string[] = [];
    let i = 0;
    // 记录前一个 token 类型，用于判断负号
    let prevType: 'operator' | 'value' | 'leftParen' | undefined;

    while (i < expr.length) {
      const ch: string = expr[i];

      // 数字（含小数点）
      if (this.isDigit(ch) || ch === '.') {
        let num = ch;
        i++;
        while (i < expr.length && (this.isDigit(expr[i]) || expr[i] === '.')) {
          num += expr[i];
          i++;
        }
        tokens.push(num);
        prevType = 'value';
        continue;
      }

      // 常量 pi
      if (ch === 'p' && expr.substring(i, i + 2) === 'pi') {
        tokens.push('pi');
        i += 2;
        prevType = 'value';
        continue;
      }

      // 常量 e
      // 常量 e
      if (ch === 'e') {
        tokens.push('e');
        i++;
        prevType = 'value';
        continue;
      }

      // 函数名（sin, cos, tan, log, ln, sqrt, inv）
      if (/[a-z]/i.test(ch)) {
        let name = ch;
        i++;
        while (i < expr.length && /[a-z]/i.test(expr[i])) {
          name += expr[i];
          i++;
        }
        tokens.push(name);
        prevType = 'operator';
        continue;
      }

      // 阶乘符号
      if (ch === '!') {
        tokens.push('fact');
        i++;
        prevType = 'operator';
        continue;
      }

      // 左括号
      if (ch === '(') {
        tokens.push(ch);
        i++;
        prevType = 'leftParen';
        continue;
      }

      // 右括号
      if (ch === ')') {
        tokens.push(ch);
        i++;
        prevType = 'value';
        continue;
      }

      // 负号（出现在开头、运算符后、左括号后）
      if (ch === '-' && (prevType === undefined || prevType === 'operator' || prevType === 'leftParen')) {
        tokens.push('neg');
        i++;
        continue;
      }

      // 运算符
      if (this.isOperator(ch)) {
        tokens.push(ch);
        i++;
        prevType = 'operator';
        continue;
      }

      // 未知字符，跳过
      i++;
    }
    return tokens;
  }

  // 判断是否为数字
  private isDigit(char: string): boolean {
    return /[0-9]/.test(char);
  }

  // 判断是否为运算符
  private isOperator(token: string): boolean {
    return ['+', '-', '*', '/', '^', '%'].includes(token);
  }

  // ==================== 运算符优先级 ====================

  private precedence(token: string): number {
    switch (token) {
      case '+':
      case '-':
        return 1;
      case '*':
      case '/':
      case '%':
        return 2;
      case '^':
        return 3;
      default:
        return 4;
    }
  }

  // 判断是否为函数 token
  private isFunctionToken(token: string): boolean {
    return ['sin', 'cos', 'tan', 'log', 'ln', 'sqrt', 'inv', 'neg', 'fact'].includes(token);
  }

  // ==================== Shunting-yard 算法 ====================
  // 将中缀表达式转换为逆波兰表达式（RPN）

  private toRpn(tokens: string[]): string[] {
    const output: string[] = [];
    const operators: string[] = [];

    tokens.forEach((token: string) => {
      // 数字或常量直接输出
      if (this.isNumberToken(token) || token === 'pi' || token === 'e') {
        output.push(token);
      }
      // 函数压入栈
      else if (this.isFunctionToken(token)) {
        operators.push(token);
      }
      // 运算符：按优先级弹出
      else if (this.isOperator(token)) {
        while (operators.length > 0) {
          const top: string = operators[operators.length - 1];
          if ((this.isOperator(top) && this.precedence(top) >= this.precedence(token)) || this.isFunctionToken(top)) {
            output.push(operators.pop() as string);
          } else {
            break;
          }
        }
        operators.push(token);
      }
      // 左括号压入栈
      else if (token === '(') {
        operators.push(token);
      }
      // 右括号：弹出直到左括号
      else if (token === ')') {
        while (operators.length > 0 && operators[operators.length - 1] !== '(') {
          output.push(operators.pop() as string);
        }
        operators.pop(); // 弹出左括号
        // 如果栈顶是函数，也弹出
        if (operators.length > 0 && this.isFunctionToken(operators[operators.length - 1])) {
          output.push(operators.pop() as string);
        }
      }
    });

    // 弹出剩余运算符
    while (operators.length > 0) {
      output.push(operators.pop() as string);
    }
    return output;
  }

  // 判断是否为数字 token
  private isNumberToken(token: string): boolean {
    return /^\d+(\.\d+)?$/.test(token);
  }

  // ==================== RPN 求值 ====================
  // 使用栈计算逆波兰表达式

  private evaluateRpn(tokens: string[]): number {
    const stack: number[] = [];

    tokens.forEach((token: string) => {
      // 数字压栈
      if (this.isNumberToken(token)) {
        stack.push(Number(token));
      }
      // 常量 pi
      else if (token === 'pi') {
        stack.push(Math.PI);
      }
      // 常量 e
      else if (token === 'e') {
        stack.push(Math.E);
      }
      // 二元运算符
      else if (this.isOperator(token)) {
        const b: number = stack.pop() ?? 0;
        const a: number = stack.pop() ?? 0;
        switch (token) {
          case '+':
            stack.push(a + b);
            break;
          case '-':
            stack.push(a - b);
            break;
          case '*':
            stack.push(a * b);
            break;
          case '/':
            if (b === 0) {
              throw new Error('Division by zero');
            }
            stack.push(a / b);
            break;
          case '%':
            stack.push(a % b);
            break;
          case '^':
            stack.push(Math.pow(a, b));
            break;
        }
      }
      // 一元函数
      else if (this.isFunctionToken(token)) {
        const value: number = stack.pop() ?? 0;
        switch (token) {
          case 'sin':
            // 角度制/弧度制
            stack.push(this.isDegreeMode ? Math.sin(this.degToRad(value)) : Math.sin(value));
            break;
          case 'cos':
            stack.push(this.isDegreeMode ? Math.cos(this.degToRad(value)) : Math.cos(value));
            break;
          case 'tan':
            stack.push(this.isDegreeMode ? Math.tan(this.degToRad(value)) : Math.tan(value));
            break;
          case 'log':
            // 常用对数
            if (value <= 0) {
              throw new Error('Invalid logarithm argument');
            }
            stack.push(Math.log10(value));
            break;
          case 'ln':
            // 自然对数
            if (value <= 0) {
              throw new Error('Invalid logarithm argument');
            }
            stack.push(Math.log(value));
            break;
          case 'sqrt':
            // 平方根
            if (value < 0) {
              throw new Error('Invalid square root argument');
            }
            stack.push(Math.sqrt(value));
            break;
          case 'inv':
            // 倒数
            if (value === 0) {
              throw new Error('Division by zero');
            }
            stack.push(1 / value);
            break;
          case 'neg':
            // 负号
            stack.push(-value);
            break;
          case 'fact':
            // 阶乘
            stack.push(this.factorial(value));
            break;
        }
      }
    });

    return stack.pop() ?? 0;
  }

  // ==================== 辅助数学函数 ====================

  // 角度转弧度
  private degToRad(value: number): number {
    return value * Math.PI / 180;
  }

  // 阶乘（仅支持非负整数）
  private factorial(value: number): number {
    if (value < 0) {
      return NaN;
    }
    if (value === 0 || value === 1) {
      return 1;
    }
    let result = 1;
    for (let i = 2; i <= Math.floor(value); i++) {
      result *= i;
    }
    return result;
  }
}