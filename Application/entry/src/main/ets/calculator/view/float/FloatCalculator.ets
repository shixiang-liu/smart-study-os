// ============================================================================
// 悬浮窗计算器 - FloatCalculator
// ============================================================================
// 功能：紧凑型计算器，支持拖拽移动
// 用途：全局悬浮窗模式下使用
// 依赖：FloatWindowService
// ============================================================================

import { window } from '@kit.ArkUI';
import { IconPaths, IconSize } from '../../../common/utils/IconPaths';
import { AppColors, AppSizes, AppShadows } from '../../../common/utils/AppTheme';

// ============================================================================
// 拖拽位置类型
// ============================================================================
class DragPosition {
  x: number = 0;
  y: number = 0;
}

// ============================================================================
// 悬浮窗计算器组件
// ============================================================================
@Entry
@Component
struct FloatCalculator {
  // ==================== 状态变量 ====================
  
  // 当前表达式
  @State private expression: string = '';
  
  // 计算结果
  @State private result: string = '0';
  
  // 拖拽位置
  @State private dragPosition: DragPosition = new DragPosition();
  
  // 悬浮窗实例
  private floatWindow: window.Window | null = null;
  
  // 拖拽手势配置
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.All });

  // ==================== 生命周期 ====================

  aboutToAppear() {
    // 获取悬浮窗实例
    try {
      this.floatWindow = window.findWindow('floatCalculator');
    } catch (err) {
      console.error('[FloatCalculator] findWindow failed:', err);
    }
  }

  // ==================== 窗口操作 ====================

  // 移动悬浮窗
  private moveWindow(offsetX: number, offsetY: number): void {
    if (this.floatWindow) {
      this.dragPosition.x += offsetX;
      this.dragPosition.y += offsetY;
      this.floatWindow.moveWindowTo(this.dragPosition.x, this.dragPosition.y);
    }
  }

  // 关闭悬浮窗
  private closeWindow(): void {
    if (this.floatWindow) {
      this.floatWindow.destroyWindow();
    }
  }

  // ==================== 计算逻辑 ====================

  private handleButton(btn: string): void {
    switch (btn) {
      case 'C':
        this.expression = '';
        this.result = '0';
        break;
      case '⌫':
        if (this.expression.length > 0) {
          this.expression = this.expression.slice(0, -1);
          this.calculateInstant();
        }
        break;
      case '=':
        this.calculateInstant();
        break;
      case '÷':
        this.expression += '/';
        break;
      case '×':
        this.expression += '*';
        break;
      default:
        this.expression += btn;
        this.calculateInstant();
        break;
    }
  }

  private calculateInstant(): void {
    if (!this.expression) {
      this.result = '0';
      return;
    }
    
    try {
      // 简单计算 - 使用安全的表达式解析器
      const expr = this.expression
        .replace(/×/g, '*')
        .replace(/÷/g, '/');
      
      // 手动解析简单表达式替代 Function 构造
      const value: number = this.evaluateExpression(expr);
      
      if (!isFinite(value) || isNaN(value)) {
        this.result = 'Error';
      } else {
        this.result = String(value);
      }
    } catch (err) {
      // 表达式不完整时保持上一个结果
    }
  }

  // 安全的表达式求值器（仅支持基本运算）
  private evaluateExpression(expr: string): number {
    // 移除空格
    expr = expr.replace(/\s/g, '');
    
    // 处理加减法（最低优先级）
    let lastPlusIndex = -1;
    let lastMinusIndex = -1;
    let depth = 0;
    
    for (let i = expr.length - 1; i >= 0; i--) {
      const char = expr.charAt(i);
      if (char === ')') depth++;
      else if (char === '(') depth--;
      else if (depth === 0) {
        if (char === '+' && i > 0) {
          lastPlusIndex = i;
          break;
        }
        if (char === '-' && i > 0) {
          lastMinusIndex = i;
          break;
        }
      }
    }
    
    if (lastPlusIndex > 0) {
      return this.evaluateExpression(expr.substring(0, lastPlusIndex)) + 
             this.evaluateExpression(expr.substring(lastPlusIndex + 1));
    }
    if (lastMinusIndex > 0) {
      return this.evaluateExpression(expr.substring(0, lastMinusIndex)) - 
             this.evaluateExpression(expr.substring(lastMinusIndex + 1));
    }
    
    // 处理乘除法
    let lastMulIndex = -1;
    let lastDivIndex = -1;
    depth = 0;
    
    for (let i = expr.length - 1; i >= 0; i--) {
      const char = expr.charAt(i);
      if (char === ')') depth++;
      else if (char === '(') depth--;
      else if (depth === 0) {
        if (char === '*') {
          lastMulIndex = i;
          break;
        }
        if (char === '/') {
          lastDivIndex = i;
          break;
        }
      }
    }
    
    if (lastMulIndex > 0) {
      return this.evaluateExpression(expr.substring(0, lastMulIndex)) * 
             this.evaluateExpression(expr.substring(lastMulIndex + 1));
    }
    if (lastDivIndex > 0) {
      return this.evaluateExpression(expr.substring(0, lastDivIndex)) / 
             this.evaluateExpression(expr.substring(lastDivIndex + 1));
    }
    
    // 处理括号
    if (expr.startsWith('(') && expr.endsWith(')')) {
      return this.evaluateExpression(expr.substring(1, expr.length - 1));
    }
    
    // 解析数字
    return parseFloat(expr);
  }

  // ==================== UI 构建 ====================

  build() {
    Column() {
      // 标题栏（可拖拽）
      Row() {
        // 拖拽手柄图标
        Shape() {
          Path().commands(IconPaths.MENU)
        }
        .width(IconSize.SM)
        .height(IconSize.SM)
        .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        .fill('#78716C')
        
        Text('计算器')
          .fontSize(14)
          .fontColor('#1C1917')
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: 8 })
        
        // 关闭按钮
        Button({ type: ButtonType.Circle }) {
          Shape() {
            Path().commands(IconPaths.CLOSE)
          }
          .width(IconSize.SM)
          .height(IconSize.SM)
          .viewPort({ x: 0, y: 0, width: 24, height: 24 })
          .fill('#78716C')
        }
        .width(28)
        .height(28)
        .backgroundColor('#F5F5F4')
        .onClick(() => this.closeWindow())
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 8 })
      .backgroundColor('#FAFAF9')
      .borderRadius({ topLeft: 12, topRight: 12 })
      .gesture(
        PanGesture(this.panOption)
          .onActionUpdate((event: GestureEvent) => {
            this.moveWindow(event.offsetX, event.offsetY);
          })
      )

      // 显示区
      Column({ space: 4 }) {
        Text(this.expression || '0')
          .fontSize(14)
          .fontColor('#78716C')
          .textAlign(TextAlign.End)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.result)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1C1917')
          .textAlign(TextAlign.End)
          .width('100%')
          .maxLines(1)
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F5F5F4')

      // 按钮区
      Grid() {
        ForEach(['C', '÷', '×', '⌫', '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '=', '%', '0', '.', ''], 
          (btn: string) => {
          GridItem() {
            if (btn) {
              Button(btn)
                .fontSize(18)
                .fontWeight(btn === '=' ? FontWeight.Bold : FontWeight.Normal)
                .width('100%')
                .height(44)
                .borderRadius(8)
                .backgroundColor(this.getButtonBackground(btn))
                .fontColor(this.getButtonFontColor(btn))
                .onClick(() => this.handleButton(btn))
            }
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(6)
      .columnsGap(6)
      .width('100%')
      .layoutWeight(1)
      .padding(8)
      .backgroundColor('#FAFAF9')
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAF9')
    .borderRadius(12)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.15)',
      offsetX: 0,
      offsetY: 4
    })
  }

  // 获取按钮背景色
  private getButtonBackground(btn: string): string {
    if (btn === '=') {
      return '#1C1917';
    }
    if (btn === 'C' || btn === '⌫') {
      return '#E7E5E4';
    }
    if (['+', '-', '×', '÷', '%'].includes(btn)) {
      return '#D6D3D1';
    }
    return '#F5F5F4';
  }

  // 获取按钮字体颜色
  private getButtonFontColor(btn: string): string {
    if (btn === '=') {
      return '#FFFFFF';
    }
    return '#1C1917';
  }
}
