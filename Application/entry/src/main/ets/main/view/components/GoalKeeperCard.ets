/**
 * @file GoalKeeperCard.ets
 * @description 目标倒计时卡片组件
 */

import { router } from '@kit.ArkUI'
import { AppColors, AppSizes, AppShadows, AppGradients } from '../../../common/utils/AppTheme'
import { GoalCountdown } from '../../../goal/viewmodel/GoalViewModel'

@Component
export struct GoalKeeperCard {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @Prop goalInfo: GoalCountdown | null = null

  build() {
    Column() {
      if (!this.goalInfo) {
        // 空状态 - 邀请用户设置目标
        Column({ space: AppSizes.SPACE_SM }) {
          Stack() {
            Text('🎯')
              .fontSize(40)
          }
          .width(70)
          .height(70)
          .alignContent(Alignment.Center)
          .linearGradient(this.isDarkMode ? {
            angle: 135,
            colors: [
              [AppColors.BG_DARK_ELEVATED, 0],
              [AppColors.BG_DARK_TERTIARY, 1]
            ]
          } : AppGradients.SPA_LAVENDER)
          .borderRadius(35)

          Text('设置一个目标，让学习更有方向')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
        }
        .width('100%')
        .padding(AppSizes.SPACE_XL)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)  // 问题11修复：垂直居中
      } else {
        // 有目标 - 展示倒计时（问题11修复：居中对齐）
        Column({ space: AppSizes.SPACE_LG }) {
          Row({ space: AppSizes.SPACE_LG }) {
            // 左侧：倒计时天数
            Stack() {
              Column({ space: 2 }) {
                Text(this.goalInfo.daysLeft.toString())
                  .fontSize(36)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
                Text('天')
                  .fontSize(AppSizes.FONT_XS)
                  .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
              }
            }
            .width(90)
            .height(90)
            .alignContent(Alignment.Center)
            .linearGradient(this.isDarkMode ? {
              angle: 135,
              colors: [
                [AppColors.BG_DARK_ELEVATED, 0],
                [AppColors.BG_DARK_TERTIARY, 1]
              ]
            } : AppGradients.SPA_MINT)
            .borderRadius(45)

            // 右侧：目标信息
            Column({ space: 6 }) {
              Text('距离目标')
                .fontSize(AppSizes.FONT_XS)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)

              Text(this.goalInfo.goal?.title ?? '未命名')
                .fontSize(AppSizes.FONT_LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 进度条
              Row({ space: 6 }) {
                Progress({ value: this.goalInfo.progress, total: 100, type: ProgressType.Linear })
                  .width('70%')
                  .height(6)
                  .color(AppColors.SUCCESS)
                  .backgroundColor(AppColors.BG_TERTIARY)
                Text(`${this.goalInfo.progress}%`)
                  .fontSize(AppSizes.FONT_XS)
                  .fontColor(AppColors.SUCCESS)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)  // 问题11修复：Row居中
        }
        .width('100%')
        .padding(AppSizes.SPACE_LG)
        .justifyContent(FlexAlign.Center)  // 问题11修复：Column居中
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)  // 问题11修复：整体居中
    .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_MD)
    .onClick(() => {
      router.pushUrl({ url: 'goal/view/pages/GoalManagement' })
    })
  }
}
