// 应用入口 - Index
// 功能：开发调试入口，提供快捷访问各功能模块的按钮

import { Calculator } from '../../../calculator/view/pages/Calculator'
import { router } from '@kit.ArkUI'
import { Pomodoro } from '../../../pomodoro/view/pages/Pomodoro'
import display from '@ohos.display'

// 设计常量
class DesignColors {
  static readonly BG: string = '#FAFAF9'
  static readonly TEXT_PRIMARY: string = '#1C1917'
  static readonly TEXT_SECONDARY: string = '#78716C'
  static readonly BORDER: string = '#E7E5E4'
  static readonly ACCENT: string = '#1C1917'
}

class DesignSpacing {
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 12
  static readonly LG: number = 16
  static readonly XL: number = 24
  static readonly XXL: number = 32
  static readonly XXXL: number = 48
}

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack()
  @State isTablet: boolean = false

  aboutToAppear() {
    this.detectScreenSize()
  }

  private detectScreenSize(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync()
      const screenWidth = displayInfo.width / displayInfo.densityPixels
      this.isTablet = screenWidth >= 600
    } catch (err) {
      this.isTablet = false
    }
  }

  @Builder
  pathMap(routeName: string) {
    if (routeName === 'Calculator') {
      Calculator()
    } else if (routeName === 'Pomodoro') {
      Pomodoro()
    }
  }

  @Builder
  NavButton(title: string, subtitle: string, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Column() {
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignColors.TEXT_PRIMARY)

          Text(subtitle)
            .fontSize(12)
            .fontColor(DesignColors.TEXT_SECONDARY)
            .margin({ top: DesignSpacing.XS })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('>')
          .fontSize(18)
          .fontColor(DesignColors.TEXT_SECONDARY)
      }
      .width('100%')
      .padding({
        left: DesignSpacing.XL,
        right: DesignSpacing.XL,
        top: DesignSpacing.LG,
        bottom: DesignSpacing.LG
      })
    }
    .borderRadius(12)
    .margin({ bottom: DesignSpacing.MD })
    .borderWidth(1)
    .borderColor(DesignColors.BORDER)
    .backgroundColor('#FFFFFF')
    .width('100%')
    .onClick(action)
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(11)
      .fontColor(DesignColors.TEXT_SECONDARY)
      .fontWeight(FontWeight.Medium)
      .letterSpacing(1)
      .margin({ top: DesignSpacing.XXL, bottom: DesignSpacing.LG })
      .width('100%')
  }

  build() {
    Navigation(this.pathStack) {
      Scroll() {
        Column() {
          Column() {
            Text('Smart Study')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignColors.TEXT_PRIMARY)
              .letterSpacing(0.5)

            Text('智慧学习助手')
              .fontSize(13)
              .fontColor(DesignColors.TEXT_SECONDARY)
              .margin({ top: DesignSpacing.XS })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: DesignSpacing.XXXL, bottom: DesignSpacing.XXL })

          this.SectionTitle('主入口')

          this.NavButton('智慧学习主页', '完整功能入口', () => {
            router.pushUrl({ url: 'main/view/pages/MainPage' })
          })

          this.NavButton('登录 / 注册', '账号认证系统', () => {
            router.pushUrl({ url: 'auth/view/pages/LoginPage' })
          })

          this.SectionTitle('工具模块')

          this.NavButton('计算器', '科学计算 历史记录', () => {
            this.pathStack.pushPathByName('Calculator', null)
          })

          this.NavButton('番茄钟', '专注计时 情绪白噪', () => {
            this.pathStack.pushPathByName('Pomodoro', null)
          })

          this.NavButton('语音日记', '语音转文字 AI分析', () => {
            router.pushUrl({ url: 'diary/view/pages/HomePage' })
          })

          this.SectionTitle('数据模块')

          this.NavButton('目标管理', '目标设定与追踪', () => {
            router.pushUrl({ url: 'goal/view/pages/GoalManagement' })
          })

          this.NavButton('学习报告', '数据统计与分析', () => {
            router.pushUrl({ url: 'tools/view/pages/DashboardPage' })
          })

          this.NavButton('知识星图', '关键词可视化', () => {
            router.pushUrl({ url: 'tools/view/pages/StarMapPage' })
          })

          Blank()
            .height(DesignSpacing.XXXL)
        }
        .width('100%')
        .padding({
          left: this.isTablet ? DesignSpacing.XXXL : DesignSpacing.XL,
          right: this.isTablet ? DesignSpacing.XXXL : DesignSpacing.XL
        })
        .constraintSize({
          maxWidth: this.isTablet ? 500 : '100%'
        })
      }
      .height('100%')
      .width('100%')
      .backgroundColor(DesignColors.BG)
      .align(Alignment.Top)
    }
    .hideTitleBar(true)
    .navDestination(this.pathMap)
  }
}
