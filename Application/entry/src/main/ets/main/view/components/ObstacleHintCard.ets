/**
 * @file ObstacleHintCard.ets
 * @description 学习障碍提示卡片组件
 */

import { AppColors, AppSizes, AppShadows, AppGradients } from '../../../common/utils/AppTheme'
import { ObstacleItem } from '../../model/HomeModels'

@Component
export struct ObstacleHintCard {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @Prop obstacles: ObstacleItem[] = []
  @Prop obstacleReport: string = ''

  build() {
    Column({ space: AppSizes.SPACE_SM }) {
      Row() {
        Text('🚧')
          .fontSize(20)
        Text('本周学习障碍')
          .fontSize(AppSizes.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
          .margin({ left: 6 })
      }
      .width('100%')
      .margin({ bottom: AppSizes.SPACE_SM })

      // 阻碍关键词列表
      Row({ space: 8 }) {
        ForEach(this.obstacles.slice(0, 3), (item: ObstacleItem, index: number) => {
          Column({ space: 4 }) {
            // 排名圆圈
            Text(`${index + 1}`)
              .fontSize(11)
              .fontColor(AppColors.TEXT_WHITE)
              .width(20)
              .height(20)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.getObstacleColor(index))
              .borderRadius(10)

            // 关键词
            Text(item.keyword)
              .fontSize(AppSizes.FONT_SM)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            // 次数
            Text(`${item.count}次`)
              .fontSize(AppSizes.FONT_XS)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
          }
          .layoutWeight(1)
          .padding(10)
          .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_TERTIARY : AppColors.BG_PRIMARY)
          .borderRadius(10)
        })
      }
      .width('100%')

      // 改进建议
      if (this.obstacleReport) {
        Row() {
          Text('💡')
            .fontSize(12)
          Text(this.obstacleReport)
            .fontSize(AppSizes.FONT_XS)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
            .margin({ left: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(AppSizes.SPACE_MD)
    .linearGradient(this.isDarkMode ? {
      angle: 135,
      colors: [
        [AppColors.BG_DARK_SECONDARY, 0],
        [AppColors.BG_DARK_TERTIARY, 1]
      ]
    } : AppGradients.SPA_ROSE)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
  }

  /** 获取阻碍排名颜色 */
  private getObstacleColor(index: number): string {
    if (index === 0) return AppColors.ERROR
    if (index === 1) return '#FF9800'
    return '#FFC107'
  }
}
