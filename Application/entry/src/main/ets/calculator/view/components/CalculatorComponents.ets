/**
 * @file CalculatorComponents.ets
 * @description 计算器UI组件库 - 从Calculator.ets拆分
 * 包含：显示区、按钮网格、历史记录项等可复用组件
 */

import { AppColors, AppSizes, AppShadows, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'

// ============================================================================
// 计算器显示区组件
// ============================================================================

@Component
export struct CalculatorDisplay {
  @Prop expression: string = ''
  @Prop result: string = '0'
  @Prop isDarkMode: boolean = false
  
  build() {
    Column({ space: 8 }) {
      // 表达式显示（较小字体）
      Text(this.expression || '0')
        .fontSize(24)
        .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
        .textAlign(TextAlign.End)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      // 结果显示（大字体）
      Text(this.result || '0')
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
        .textAlign(TextAlign.End)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(AppSizes.SPACE_LG)
    .linearGradient(this.isDarkMode ? {
      angle: 180,
      colors: [[AppColors.BG_DARK_SECONDARY, 0], [AppColors.BG_DARK_TERTIARY, 1]]
    } : AppGradients.SPA_SKY)
    .backdropBlur(10)
    .borderRadius(AppSizes.RADIUS_LG)
  }
}

// ============================================================================
// 计算器按钮组件
// ============================================================================

@Component
export struct CalculatorButton {
  @Prop label: string = ''
  @Prop isDarkMode: boolean = false
  @Prop isOperator: boolean = false
  @Prop isAction: boolean = false
  @Prop buttonSize: number = 60
  onButtonClick: () => void = () => {}
  
  private getButtonBg(): string {
    if (this.isOperator) {
      return AppColors.ACCENT
    }
    if (this.isAction) {
      return this.isDarkMode ? AppColors.BG_DARK_TERTIARY : AppColors.BG_TERTIARY
    }
    return this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY
  }
  
  private getTextColor(): string {
    if (this.isOperator) {
      return AppColors.TEXT_WHITE
    }
    if (this.isAction) {
      return AppColors.ERROR
    }
    return this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY
  }
  
  build() {
    Button(this.label)
      .width(this.buttonSize)
      .height(this.buttonSize)
      .fontSize(this.buttonSize > 50 ? 24 : 18)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.getTextColor())
      .backgroundColor(this.getButtonBg())
      .borderRadius(this.buttonSize / 2)
      .shadow(AppShadows.SHADOW_XS)
      .onClick(() => this.onButtonClick())
  }
}

// ============================================================================
// 历史记录项组件
// ============================================================================

// 历史记录条目接口
export interface HistoryItemData {
  id: number
  expression: string
  result: string
  timestamp: number
}

@Component
export struct CalculatorHistoryItem {
  @Prop item: HistoryItemData | null = null
  @Prop isDarkMode: boolean = false
  onSelect: (item: HistoryItemData) => void = () => {}
  onDelete: (item: HistoryItemData) => void = () => {}
  
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
  }
  
  build() {
    if (this.item) {
      Row() {
        Column({ space: 4 }) {
          Text(this.item.expression)
            .fontSize(AppSizes.FONT_SM)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`= ${this.item.result}`)
            .fontSize(AppSizes.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        
        Text(this.formatTime(this.item.timestamp))
          .fontSize(AppSizes.FONT_XS)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
      }
      .width('100%')
      .padding(AppSizes.SPACE_MD)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)
      .borderRadius(AppSizes.RADIUS_MD)
      .margin({ bottom: 8 })
      .onClick(() => {
        if (this.item) {
          this.onSelect(this.item)
        }
      })
    }
  }
}

// ============================================================================
// 模式切换按钮组件
// ============================================================================

@Component
export struct CalculatorModeToggle {
  @Prop isDegreeMode: boolean = true
  @Prop isDarkMode: boolean = false
  onToggle: () => void = () => {}
  
  build() {
    Button(undefined, { type: ButtonType.Normal }) {
      Text(this.isDegreeMode ? $r('app.string.calculator_degree') : $r('app.string.calculator_radian'))
        .fontSize(12)
        .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
    }
    .borderRadius(16)
    .height(26)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_TERTIARY)
    .onClick(() => this.onToggle())
  }
}
