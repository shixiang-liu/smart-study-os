// ============================================================================
// 设置页面 - SettingsPage
// ============================================================================
// 功能：应用设置、主题切换、通知管理等
// ============================================================================

import { AppColors, AppSizes } from '../../../common/utils/AppTheme'
import { IconPaths } from '../../../common/utils/IconPaths'
import { router, promptAction } from '@kit.ArkUI'
import { PreferencesUtil } from '../../../common/utils/PreferencesUtil'

@Entry
@Component
struct SettingsPage {
  @StorageLink('currentColorMode') currentColorMode: string = 'light'
  @State notificationEnabled: boolean = true
  @State soundEnabled: boolean = true
  @State vibrationEnabled: boolean = true
  @State autoStartPomodoro: boolean = false

  async aboutToAppear() {
    // 加载设置
    this.notificationEnabled = (await PreferencesUtil.get<boolean>('notificationEnabled', true)) ?? true
    this.soundEnabled = (await PreferencesUtil.get<boolean>('soundEnabled', true)) ?? true
    this.vibrationEnabled = (await PreferencesUtil.get<boolean>('vibrationEnabled', true)) ?? true
    this.autoStartPomodoro = (await PreferencesUtil.get<boolean>('autoStartPomodoro', false)) ?? false
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部导航栏
        Row() {
          Shape() {
            Path()
              .commands(IconPaths.ARROW_BACK)
              .fill(AppColors.TEXT_PRIMARY)
          }
          .width(24)
          .height(24)
          .viewPort({
            x: 0,
            y: 0,
            width: 24,
            height: 24
          })
          .onClick(() => router.back())

          Text('设置')
            .fontSize(AppSizes.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ left: AppSizes.SPACE_LG })

          Blank()
        }
        .width('100%')
        .height(56)
        .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

        // 设置列表
        Scroll() {
          Column({ space: AppSizes.SPACE_LG }) {
            // 外观设置
            Column({ space: AppSizes.SPACE_SM }) {
              Text('外观')
                .fontSize(AppSizes.FONT_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_TERTIARY)
                .width('100%')
                .padding({ left: AppSizes.SPACE_SM })

              Column() {
                this.ThemeSettingItem()
              }
              .width('100%')
              .backgroundColor(AppColors.BG_SECONDARY)
              .borderRadius(AppSizes.RADIUS_LG)
            }
            .width('100%')

            // 通知设置
            Column({ space: AppSizes.SPACE_SM }) {
              Text('通知')
                .fontSize(AppSizes.FONT_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_TERTIARY)
                .width('100%')
                .padding({ left: AppSizes.SPACE_SM })

              Column() {
                // 推送通知
                Row() {
                  Column({ space: 2 }) {
                    Text('推送通知')
                      .fontSize(AppSizes.FONT_MD)
                      .fontColor(AppColors.TEXT_PRIMARY)
                    Text('接收学习提醒和专注完成通知')
                      .fontSize(AppSizes.FONT_SM)
                      .fontColor(AppColors.TEXT_TERTIARY)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.notificationEnabled })
                    .selectedColor(AppColors.ACCENT)
                    .onChange((isOn: boolean) => {
                      this.notificationEnabled = isOn
                      PreferencesUtil.put('notificationEnabled', isOn)
                    })
                }
                .width('100%')
                .height(64)
                .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

                Divider().color(AppColors.DIVIDER).margin({ left: 16 })

                // 提示音
                Row() {
                  Column({ space: 2 }) {
                    Text('提示音')
                      .fontSize(AppSizes.FONT_MD)
                      .fontColor(AppColors.TEXT_PRIMARY)
                    Text('专注结束时播放提示音')
                      .fontSize(AppSizes.FONT_SM)
                      .fontColor(AppColors.TEXT_TERTIARY)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.soundEnabled })
                    .selectedColor(AppColors.ACCENT)
                    .onChange((isOn: boolean) => {
                      this.soundEnabled = isOn
                      PreferencesUtil.put('soundEnabled', isOn)
                    })
                }
                .width('100%')
                .height(64)
                .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

                Divider().color(AppColors.DIVIDER).margin({ left: 16 })

                // 震动
                Row() {
                  Column({ space: 2 }) {
                    Text('震动')
                      .fontSize(AppSizes.FONT_MD)
                      .fontColor(AppColors.TEXT_PRIMARY)
                    Text('专注结束时震动提醒')
                      .fontSize(AppSizes.FONT_SM)
                      .fontColor(AppColors.TEXT_TERTIARY)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.vibrationEnabled })
                    .selectedColor(AppColors.ACCENT)
                    .onChange((isOn: boolean) => {
                      this.vibrationEnabled = isOn
                      PreferencesUtil.put('vibrationEnabled', isOn)
                    })
                }
                .width('100%')
                .height(64)
                .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
              }
              .width('100%')
              .backgroundColor(AppColors.BG_SECONDARY)
              .borderRadius(AppSizes.RADIUS_LG)
            }
            .width('100%')

            // 番茄钟设置
            Column({ space: AppSizes.SPACE_SM }) {
              Text('番茄钟')
                .fontSize(AppSizes.FONT_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_TERTIARY)
                .width('100%')
                .padding({ left: AppSizes.SPACE_SM })

              Column() {
                Row() {
                  Column({ space: 2 }) {
                    Text('自动开始下一个番茄')
                      .fontSize(AppSizes.FONT_MD)
                      .fontColor(AppColors.TEXT_PRIMARY)
                    Text('休息结束后自动开始专注')
                      .fontSize(AppSizes.FONT_SM)
                      .fontColor(AppColors.TEXT_TERTIARY)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.autoStartPomodoro })
                    .selectedColor(AppColors.ACCENT)
                    .onChange((isOn: boolean) => {
                      this.autoStartPomodoro = isOn
                      PreferencesUtil.put('autoStartPomodoro', isOn)
                    })
                }
                .width('100%')
                .height(64)
                .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
              }
              .width('100%')
              .backgroundColor(AppColors.BG_SECONDARY)
              .borderRadius(AppSizes.RADIUS_LG)
            }
            .width('100%')

            // 关于
            Column({ space: AppSizes.SPACE_SM }) {
              Text('关于')
                .fontSize(AppSizes.FONT_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_TERTIARY)
                .width('100%')
                .padding({ left: AppSizes.SPACE_SM })

              Column() {
                // 版本
                Row() {
                  Text('版本')
                    .fontSize(AppSizes.FONT_MD)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .layoutWeight(1)
                  Text('1.0.0')
                    .fontSize(AppSizes.FONT_MD)
                    .fontColor(AppColors.TEXT_TERTIARY)
                }
                .width('100%')
                .height(56)
                .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

                Divider().color(AppColors.DIVIDER).margin({ left: 16 })

                // 开发者
                Row() {
                  Text('开发者')
                    .fontSize(AppSizes.FONT_MD)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .layoutWeight(1)
                  Text('Smart Study Team')
                    .fontSize(AppSizes.FONT_MD)
                    .fontColor(AppColors.TEXT_TERTIARY)
                }
                .width('100%')
                .height(56)
                .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
              }
              .width('100%')
              .backgroundColor(AppColors.BG_SECONDARY)
              .borderRadius(AppSizes.RADIUS_LG)
            }
            .width('100%')

            // 底部留白
            Blank().height(AppSizes.SPACE_4XL)
          }
          .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.BG_PRIMARY)
    }
    .hideTitleBar(true)
  }

  @Builder
  ThemeSettingItem() {
    Row() {
      Shape() {
        Path()
          .commands(IconPaths.MOON)
          .fill(AppColors.TEXT_SECONDARY)
      }
      .width(24)
      .height(24)
      .viewPort({
        x: 0,
        y: 0,
        width: 24,
        height: 24
      })

      Column({ space: 2 }) {
        Text('主题模式')
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)

        Text(this.currentColorMode === 'dark' ? '深色' : '浅色')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_TERTIARY)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: AppSizes.SPACE_LG })
      .layoutWeight(1)

      // 主题切换 Toggle
      Toggle({ type: ToggleType.Switch, isOn: this.currentColorMode === 'dark' })
        .selectedColor(AppColors.ACCENT)
        .onChange((isOn: boolean) => {
          const newMode = isOn ? 'dark' : 'light'
          this.currentColorMode = newMode
          AppStorage.setOrCreate('currentColorMode', newMode)
          PreferencesUtil.put('currentColorMode', newMode)
          promptAction.showToast({ message: isOn ? '已切换至深色模式' : '已切换至浅色模式' })
        })
    }
    .width('100%')
    .height(64)
    .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
  }
}
