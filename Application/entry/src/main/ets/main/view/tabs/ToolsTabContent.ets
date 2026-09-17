/**
 * @file ToolsTabContent.ets
 * @description 专注 Tab - 工具箱（从 MainPage 提取的独立组件）
 * @module main/view/tabs
 */

import { router } from '@kit.ArkUI'
import { AppColors, AppSizes, AppShadows, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'

@Component
export struct ToolsTabContent {
  @StorageLink('isDarkMode') isDarkMode: boolean = false

  build() {
    Column() {
      // 顶部标题区域 - 简洁设计
      Column() {
        Text('专注工具')
          .fontSize(AppSizes.FONT_2XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
        Text('高效学习，专注当下')
          .fontSize(AppSizes.FONT_XS)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSizes.SPACE_LG, top: AppSizes.SPACE_4XL })

      Scroll() {
        Column({ space: AppSizes.SPACE_LG }) {
          // 番茄钟卡片 - 使用SPA_PEACH渐变
          this.ToolCard('🍅', '番茄钟', '专注当下，高效产出', AppGradients.SPA_PEACH, () => {
            router.pushUrl({ url: 'pomodoro/view/pages/Pomodoro' })
          })

          // 计算器卡片 - 使用SPA_SKY渐变
          this.ToolCard('🧮', '计算器', '随手计算，灵感不丢', AppGradients.SPA_SKY, () => {
            router.pushUrl({ url: 'calculator/view/pages/Calculator' })
          })

          // 学习报告 - 使用SPA_MINT渐变
          this.ToolCard('📊', '学习报告', '回顾数据，优化习惯', AppGradients.SPA_MINT, () => {
            router.pushUrl({ url: 'tools/view/pages/DashboardPage' })
          })

          // 知识星图 - 使用SPA_LAVENDER渐变
          this.ToolCard('🪐', '知识星图', '探索你的思维宇宙', AppGradients.SPA_LAVENDER, () => {
            router.pushUrl({ url: 'tools/view/pages/StarMapPage' })
          })
        }
        .padding(AppSizes.SPACE_LG)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY)
  }

  @Builder
  ToolCard(icon: string, title: string, desc: string, gradient: LinearGradient, action: () => void) {
    Row() {
      Text(icon).fontSize(40)
      Column() {
        Text(title)
          .fontSize(AppSizes.FONT_LG)
          .fontWeight(FontWeight.Bold)
          // 问题5修复：暗色模式使用纯白色确保可读性
          .fontColor(this.isDarkMode ? '#FFFFFF' : AppColors.TEXT_PRIMARY)
        Text(desc)
          .fontSize(AppSizes.FONT_SM)
          // 问题5修复：暗色模式使用亮灰色
          .fontColor(this.isDarkMode ? '#D1D1D6' : AppColors.TEXT_SECONDARY)
          .margin({ top: 4 })
      }
      .margin({ left: AppSizes.SPACE_LG })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 问题5修复：暗色模式箭头使用亮色
      Text('→')
        .fontSize(20)
        .fontColor(this.isDarkMode ? '#ABABAF' : AppColors.TEXT_TERTIARY)
    }
    .width('100%')
    .padding(AppSizes.SPACE_XL)
    // 问题5修复：暗色模式使用更深的纯色背景，避免渐变导致对比度不足
    .backgroundColor(this.isDarkMode ? '#1C1C1E' : 'transparent')
    .linearGradient(this.isDarkMode ? undefined : gradient)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
    // 问题5修复：暗色模式添加更明显的边框
    .border({ width: this.isDarkMode ? 1 : 0, color: 'rgba(255, 255, 255, 0.15)' })
    .onClick(action)
  }
}
