/**
 * @file DiaryTabContent.ets
 * @description 洞察 Tab - 录音中心（从 MainPage 提取的独立组件）
 * @module main/view/tabs
 */

import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AppColors, AppSizes, AppShadows, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'
import { MemoryViewModel, StarMapDataItem } from '../../../diary/viewmodel/MemoryViewModel'

@Component
export struct DiaryTabContent {
  @State starMapData: StarMapDataItem[] = []
  @State isRecording: boolean = false
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  private memoryViewModel: MemoryViewModel = new MemoryViewModel()

  async aboutToAppear() {
    // 尝试加载真实的用户高频关键词数据
    try {
      // 传递 context，以便从本地日记提取关键词（作为 CloudDB 的 fallback）
      const context = getContext(this) as common.UIAbilityContext
      const keywords = await this.memoryViewModel.getStarMapData(context)
      if (keywords && keywords.length > 0) {
        // 取前 5 个高频词展示在背景
        this.starMapData = keywords.slice(0, 5)
      } else {
        // 没有数据时保持简洁背景
        this.starMapData = []
      }
    } catch (e) {
      console.error('[DiaryTabContent] 加载关键词失败:', e)
      // 加载失败时保持简洁背景
      this.starMapData = []
    }
  }

  build() {
    Stack() {
      // 1. 背景：知识星图 (Faded)
      Column() {
        this.StarMapBackground()
      }
      .width('100%')
      .height('100%')
      .opacity(0.25)

      // 2. 内容层
      Column({ space: AppSizes.SPACE_XL }) {
        this.TopActionRow()

        Column() {
          Text('此刻的想法...')
            .fontSize(AppSizes.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ bottom: AppSizes.SPACE_3XL })

          // 巨型录音按钮
          Column() {
            Text('🎙️')
              .fontSize(48)
              .fontColor(AppColors.TEXT_WHITE)
          }
          .width(120)
          .height(120)
          .borderRadius(60)
          .backgroundColor(AppColors.ACCENT)
          .linearGradient(AppGradients.PRIMARY_BTN)
          .justifyContent(FlexAlign.Center)
          .shadow(AppShadows.SHADOW_LG)
          .onClick(() => {
            router.pushUrl({ url: 'diary/view/pages/HomePage' })
          })

          Text('点击进入语音日记')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_TERTIARY)
            .margin({ top: AppSizes.SPACE_LG })

          // 每日灵感卡片 - 暗夜模式优化（问题7修复：移除点击跳转，仅作展示）
          Column() {
            Text('💡 每日灵感')
              .fontSize(AppSizes.FONT_XS)
              .fontColor(this.isDarkMode ? '#FFD700' : AppColors.ACCENT)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 4 })
            Text('"记录生活中的小确幸，是治愈焦虑的良方。"')
              .fontSize(AppSizes.FONT_SM)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .lineHeight(20)
          }
          .width('100%')
          .padding(AppSizes.SPACE_LG)
          .backgroundColor(this.isDarkMode ? 'rgba(255, 215, 0, 0.1)' : AppColors.BG_SECONDARY)
          .linearGradient(this.isDarkMode ? undefined : AppGradients.CARD_SUBTLE)
          .borderRadius(AppSizes.RADIUS_LG)
          .border({ 
            width: this.isDarkMode ? 1.5 : 0, 
            color: this.isDarkMode ? 'rgba(255, 215, 0, 0.2)' : '#00000000' 
          })
          .shadow(AppShadows.SHADOW_SM)
          .margin({ top: AppSizes.SPACE_4XL })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ top: AppSizes.SPACE_4XL, left: AppSizes.SPACE_XL, right: AppSizes.SPACE_XL, bottom: AppSizes.SPACE_5XL })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY)
  }

  // 顶部三个快捷动作
  @Builder
  TopActionRow() {
    Row({ space: AppSizes.SPACE_MD }) {
      this.BlueChip('📝', '记录', () => {
        router.pushUrl({ url: 'diary/view/pages/HomePage' })
      })
      this.OrangeChip('✨', '开始', () => {
        router.pushUrl({ url: 'diary/view/pages/DetailPage' })
      })
      this.PurpleChip('🪐', '探索', () => {
        router.pushUrl({ url: 'diary/view/pages/DiaryListPage' })
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
  }

  // 蓝色按钮
  @Builder
  BlueChip(icon: string, label: string, onClick: () => void) {
    Column({ space: 6 }) {
      Text(icon)
        .fontSize(22)
      Text(label)
        .fontSize(AppSizes.FONT_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#FFFFFF' : AppColors.TEXT_PRIMARY)
    }
    .width('30%')
    .height(92)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(59, 130, 246, 0.18)' : '#E8F1FF')
    .borderRadius(AppSizes.RADIUS_MD)
    .border({ 
      width: this.isDarkMode ? 1.5 : 1, 
      color: this.isDarkMode ? 'rgba(255, 255, 255, 0.25)' : '#3B82F6' 
    })
    .shadow({
      radius: 10,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.06)',
      offsetY: 6
    })
    .onClick(onClick)
  }

  // 橙色按钮
  @Builder
  OrangeChip(icon: string, label: string, onClick: () => void) {
    Column({ space: 6 }) {
      Text(icon)
        .fontSize(22)
      Text(label)
        .fontSize(AppSizes.FONT_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#FFFFFF' : AppColors.TEXT_PRIMARY)
    }
    .width('30%')
    .height(92)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(245, 158, 11, 0.18)' : '#FFF6E5')
    .borderRadius(AppSizes.RADIUS_MD)
    .border({ 
      width: this.isDarkMode ? 1.5 : 1, 
      color: this.isDarkMode ? 'rgba(255, 255, 255, 0.25)' : '#F59E0B' 
    })
    .shadow({
      radius: 10,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.06)',
      offsetY: 6
    })
    .onClick(onClick)
  }

  // 紫色按钮
  @Builder
  PurpleChip(icon: string, label: string, onClick: () => void) {
    Column({ space: 6 }) {
      Text(icon)
        .fontSize(22)
      Text(label)
        .fontSize(AppSizes.FONT_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#FFFFFF' : AppColors.TEXT_PRIMARY)
    }
    .width('30%')
    .height(92)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(139, 92, 246, 0.18)' : '#F3E8FF')
    .borderRadius(AppSizes.RADIUS_MD)
    .border({ 
      width: this.isDarkMode ? 1.5 : 1, 
      color: this.isDarkMode ? 'rgba(255, 255, 255, 0.25)' : '#8B5CF6' 
    })
    .shadow({
      radius: 10,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.06)',
      offsetY: 6
    })
    .onClick(onClick)
  }

  @Builder
  StarMapBackground() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.starMapData, (item: StarMapDataItem, index: number) => {
        Column() {
          Text(item.keyword)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(
              this.isDarkMode 
                ? AppColors.TEXT_DARK_PRIMARY 
                : AppColors.TEXT_PRIMARY
            )
        }
        .width(68)
        .height(68)
        .borderRadius(34)
        .backgroundColor(
          this.isDarkMode 
            ? (index % 2 === 0 ? 'rgba(10, 89, 247, 0.18)' : 'rgba(255, 193, 7, 0.18)')
            : (index % 2 === 0 ? '#E8F1FF' : '#FFF6E5')
        )
        .border({
          width: 1,
          color: this.isDarkMode 
            ? (index % 2 === 0 ? 'rgba(10, 89, 247, 0.35)' : 'rgba(255, 193, 7, 0.35)')
            : (index % 2 === 0 ? '#BFDBFE' : '#FDE68A')
        })
        .justifyContent(FlexAlign.Center)
        .margin(8)
        .shadow({
          radius: 3,
          color: this.isDarkMode ? 'rgba(0, 0, 0, 0.16)' : 'rgba(0, 0, 0, 0.05)',
          offsetY: 1
        })
      })
    }
  }
}
