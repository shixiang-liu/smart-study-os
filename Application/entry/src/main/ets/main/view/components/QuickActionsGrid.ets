/**
 * @file QuickActionsGrid.ets
 * @description 首页快捷入口网格组件
 */

import { router } from '@kit.ArkUI'
import { AppColors, AppSizes, AppShadows, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'

@Component
export struct QuickActionsGrid {
  @StorageLink('isDarkMode') isDarkMode: boolean = false

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      this.QuickActionItem('📝', '写日记', 'diary/view/pages/HomePage', AppGradients.SPA_LAVENDER)
      this.QuickActionItem('🍅', '番茄钟', 'pomodoro/view/pages/Pomodoro', AppGradients.SPA_PEACH)
      this.QuickActionItem('🧮', '计算器', 'calculator/view/pages/Calculator', AppGradients.SPA_SKY)
      this.QuickActionItem('📊', '报表', 'tools/view/pages/DashboardPage', AppGradients.SPA_MINT)
    }
    .width('100%')
  }

  @Builder
  QuickActionItem(icon: string, label: string, url: string, gradient: LinearGradient) {
    Column() {
      Text(icon)
        .fontSize(32)
        .margin({ bottom: 8 })
      Text(label)
        .fontSize(AppSizes.FONT_XS)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
    }
    .width('23%')
    .height(100)
    .justifyContent(FlexAlign.Center)
    .linearGradient(this.isDarkMode ? {
      angle: 180,
      colors: [
        [AppColors.BG_DARK_ELEVATED, 0],
        [AppColors.BG_DARK_TERTIARY, 1]
      ]
    } : gradient)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
    .onClick(() => {
      router.pushUrl({ url: url })
    })
  }
}
