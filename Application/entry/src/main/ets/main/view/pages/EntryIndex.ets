// ============================================================================
// 应用入口页 - Index
// ============================================================================
// 功能：开发调试入口，提供快捷访问各功能模块的按钮
// 设计：Swiss Spa Minimalist - 极简白底、精确间距、无 emoji
// 说明：正式版本应直接跳转到 MainPage 或 LoginPage
// ============================================================================

import { Calculator } from '../../../calculator/view/pages/Calculator';
import { router } from '@kit.ArkUI';
import { Pomodoro } from '../../../pomodoro/view/pages/Pomodoro';
import display from '@ohos.display'

// ============================================================================
// 设计常量接口定义
// ============================================================================
import { AppColors, AppSizes } from '../../../common/utils/AppTheme';

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();

  // 响应式布局
  @State isTablet: boolean = false

  aboutToAppear() {
    this.detectScreenSize()
  }

  // 检测屏幕尺寸
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
      Calculator();
    } else if (routeName === 'Pomodoro') {
      Pomodoro();
    }
  }

  // ==================== 按钮组件 ====================
  // 使用纯文字 + 箭头，无 emoji，更专业
  @Builder
  NavButton(title: string, subtitle: string, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Column() {
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)

          Text(subtitle)
            .fontSize(12)
            .fontColor(AppColors.TEXT_SECONDARY)
            .margin({ top: AppSizes.SPACE_SM })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 箭头图标
        Text('→')
          .fontSize(18)
          .fontColor(AppColors.TEXT_SECONDARY)
      }
      .width('100%')
      .padding({
        left: AppSizes.SPACE_XL,
        right: AppSizes.SPACE_XL,
        top: AppSizes.SPACE_LG,
        bottom: AppSizes.SPACE_LG
      })
    }
    .borderRadius(12)
    .margin({ bottom: AppSizes.SPACE_MD })
    .borderWidth(1)
    .borderColor(AppColors.BORDER)
    .backgroundColor(AppColors.BG_SECONDARY)
    .width('100%')
    .onClick(action)
  }

  // ==================== 分组标题 ====================
  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(11)
      .fontColor(AppColors.TEXT_SECONDARY)
      .fontWeight(FontWeight.Medium)
      .letterSpacing(1)
      .margin({ top: AppSizes.SPACE_2XL, bottom: AppSizes.SPACE_LG })
      .width('100%')
  }

  // ==================== 主布局 ====================
  build() {
    Navigation(this.pathStack) {
      Scroll() {
        Column() {
          // 头部
          Column() {
            Text('Smart Study')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
              .letterSpacing(0.5)

            Text('智慧学习助手')
              .fontSize(13)
              .fontColor(AppColors.TEXT_SECONDARY)
              .margin({ top: AppSizes.SPACE_SM })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: AppSizes.SPACE_3XL, bottom: AppSizes.SPACE_2XL })

          // 主入口
          this.SectionTitle('主入口')

          this.NavButton('智慧学习主页', '完整功能入口', () => {
            router.pushUrl({ url: 'main/view/pages/MainPage' });
          })

          this.NavButton('登录 / 注册', '账号认证系统', () => {
            router.pushUrl({ url: 'auth/view/pages/LoginPage' });
          })

          // 工具模块
          this.SectionTitle('工具模块')

          this.NavButton('计算器', '科学计算器 · 历史记录', () => {
            this.pathStack.pushPathByName('Calculator', null);
          })

          this.NavButton('番茄钟', '专注计时 · 情绪白噪音', () => {
            this.pathStack.pushPathByName('Pomodoro', null);
          })

          this.NavButton('语音日记', '语音转文字 · AI 分析', () => {
            router.pushUrl({ url: 'diary/view/pages/HomePage' });
          })

          // 数据模块
          this.SectionTitle('数据模块')

          this.NavButton('目标管理', '目标设定与追踪', () => {
            router.pushUrl({ url: 'goal/view/pages/GoalManagement' });
          })

          this.NavButton('学习报告', '数据统计与分析', () => {
            router.pushUrl({ url: 'tools/view/pages/DashboardPage' });
          })

          this.NavButton('知识星图', '关键词可视化', () => {
            router.pushUrl({ url: 'tools/view/pages/StarMapPage' });
          })

          // 底部留白
          Blank()
            .height(AppSizes.SPACE_3XL)
        }
        .width('100%')
        .padding({
          left: this.isTablet ? AppSizes.SPACE_3XL : AppSizes.SPACE_XL,
          right: this.isTablet ? AppSizes.SPACE_3XL : AppSizes.SPACE_XL
        })
        .constraintSize({
          maxWidth: this.isTablet ? 500 : '100%'
        })
      }
      .height('100%')
      .width('100%')
      .backgroundColor(AppColors.BG_PRIMARY)
      .align(Alignment.Top)
    }
    .hideTitleBar(true)
    .navDestination(this.pathMap)
  }
}