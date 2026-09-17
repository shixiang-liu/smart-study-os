/**
 * @file MainPage.ets
 * @description 主页面 - 负责各个模块的整合与导航 (Refactored)
 */

import { AppColors, AppSizes, AppShadows, AppAnimations, AppGradients, AppThemeManager, LinearGradient } from '../../../common/utils/AppTheme'
import { GoalViewModel } from '../../../goal/viewmodel/GoalViewModel'
import { TaskStorageService } from '../../../goal/model/TaskStorageService'
import { Task, TaskPriority } from '../../../goal/model/Task'
import { AuthViewModel } from '../../../auth/viewmodel/AuthViewModel'
import { CloudDBService } from '../../../common/services/CloudDBService'
import { router, promptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { waitForAGCInit } from '../../../entryability/EntryAbility'
import { common } from '@kit.AbilityKit'

// Import Tab Components
import { HomeTabContent } from '../tabs/HomeTabContent'
import { DiaryTabContent } from '../tabs/DiaryTabContent'
import { ToolsTabContent } from '../tabs/ToolsTabContent'
import { ProfileTabContent } from '../tabs/ProfileTabContent'

interface TabItem {
  icon3D: string // 3D Emoji 图标
  label: string
}

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false
  @StorageLink('currentUserNickname') nickname: string = ''
  @StorageLink('isDarkMode') isDarkMode: boolean = false

  // ========== 全局AI分析弹窗状态 ==========
  @StorageLink('shouldShowAIDialog') shouldShowAIDialog: boolean = false
  @StorageLink('pendingAIGoals') pendingAIGoals: string = ''
  @StorageLink('pendingAITodos') pendingAITodos: string = ''
  @StorageLink('aiEncouragement') aiEncouragement: string = ''
  @State selectedAIGoals: string[] = []
  @State selectedAITodos: string[] = []

  // Tab 配置 (Creamy UI: 3D Icons)
  private tabList: TabItem[] = [
    { icon3D: '🏠', label: '首页' },
    { icon3D: '🪐', label: '洞察' },
    { icon3D: '⏳', label: '专注' },
    { icon3D: '👤', label: '我的' }
  ]

  async aboutToAppear() {
    // 确保 AGConnect 初始化完毕（避免CloudDB认证提前失败）
    try {
      await waitForAGCInit()
    } catch (err) {
      hilog.warn(0x0000, '[MainPage]', 'waitForAGCInit timeout, continue')
    }
    AppThemeManager.setIsDarkMode(this.isDarkMode)
    // 检查是否有AI结果待显示
    this.checkAIDialogOnLoad()
  }

  // ==================== TabBar Builder ====================
  @Builder
  TabBarBuilder(item: TabItem, index: number) {
    Column() {
      // 图标容器
      Column() {
        Text(item.icon3D)
          .fontSize(this.currentIndex === index ? 28 : 24)
          .animation(AppAnimations.SPRING_BOUNCE)
          .scale({ x: this.currentIndex === index ? 1.1 : 1, y: this.currentIndex === index ? 1.1 : 1 })
      }
      .height(32)
      .justifyContent(FlexAlign.Center)

      Text(item.label)
        .fontSize(10)
        .fontColor(this.currentIndex === index
          ? (this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
          : (this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY))
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 2 })
        .opacity(this.currentIndex === index ? 1 : 0.6)
        .animation(AppAnimations.SPRING_NORMAL)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 2 })
  }

  // ========== 全局AI分析弹窗 (完整实现，从 HomePage 迁移) ==========
  @Builder
  GlobalAIAnalysisDialog() {
    Stack() {
      // 背景遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColors.OVERLAY_DARK)
        .onClick(() => {
          this.shouldShowAIDialog = false
          AppStorage.setOrCreate('shouldShowAIDialog', false)
        })

      // 对话框内容
      Column({ space: AppSizes.SPACE_LG }) {
        // 标题
        Row() {
          Text('✨ AI智能分析')
            .fontSize(AppSizes.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Blank()
          // 关闭按钮
          Text('×')
            .fontSize(24)
            .fontColor(AppColors.TEXT_SECONDARY)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor(AppColors.BG_TERTIARY)
            .onClick(() => {
              this.shouldShowAIDialog = false
              AppStorage.setOrCreate('shouldShowAIDialog', false)
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: AppSizes.SPACE_MD }) {
            // 暖心回复
            if (this.aiEncouragement) {
              Column({ space: AppSizes.SPACE_SM }) {
                Row() {
                  Text('💬')
                    .fontSize(16)
                  Text('暖心回复')
                    .fontSize(AppSizes.FONT_MD)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .margin({ left: 6 })
                }
                .width('100%')

                Text(this.aiEncouragement)
                  .fontSize(AppSizes.FONT_MD)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .lineHeight(24)
                  .width('100%')
              }
              .width('100%')
              .padding(AppSizes.SPACE_MD)
              .backgroundColor(AppColors.SUCCESS_BG)
              .borderRadius(AppSizes.RADIUS_MD)
            }

            // 目标建议
            if (this.pendingAIGoals) {
              this.AIGoalsList()
            }

            // 待办建议
            if (this.pendingAITodos) {
              this.AITodosList()
            }
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 400 })
        .width('100%')

        // 底部按钮
        Row({ space: AppSizes.SPACE_MD }) {
          Button('稍后再说')
            .layoutWeight(1)
            .height(46)
            .fontSize(AppSizes.FONT_MD)
            .backgroundColor(AppColors.BG_TERTIARY)
            .fontColor(AppColors.TEXT_PRIMARY)
            .borderRadius(AppSizes.RADIUS_MD)
            .onClick(() => {
              this.shouldShowAIDialog = false
            AppStorage.setOrCreate('shouldShowAIDialog', false)
              this.clearAIData()
            })

          Button('确认添加')
            .layoutWeight(1)
            .height(46)
            .fontSize(AppSizes.FONT_MD)
            .backgroundColor(AppColors.ACCENT)
            .fontColor(AppColors.TEXT_WHITE)
            .borderRadius(AppSizes.RADIUS_MD)
            .onClick(() => {
              this.confirmAddAIResults()
            })
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 500 })
      .padding(AppSizes.SPACE_2XL)
      .backgroundColor(AppColors.BG_PRIMARY)
      .borderRadius(AppSizes.RADIUS_XL)
      .shadow(AppShadows.SHADOW_LG)
    }
    .width('100%')
    .height('100%')
    .zIndex(10000)
  }

  // ==================== 主布局 ====================
  build() {
    Stack() {
      // 主内容 - Tabs
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        // 首页 Tab
        TabContent() {
          HomeTabContent()
        }
        .tabBar(this.TabBarBuilder(this.tabList[0], 0))

        // 洞察 Tab (日记)
        TabContent() {
          DiaryTabContent()
        }
        .tabBar(this.TabBarBuilder(this.tabList[1], 1))

        // 专注 Tab (工具)
        TabContent() {
          ToolsTabContent()
        }
        .tabBar(this.TabBarBuilder(this.tabList[2], 2))

        // 我的 Tab
        TabContent() {
          ProfileTabContent()
        }
        .tabBar(this.TabBarBuilder(this.tabList[3], 3))
      }
      .barHeight(64) // 加高底部栏
      .barBackgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_GLASS)
      .backgroundBlurStyle(BlurStyle.Thin) // 开启毛玻璃
      .onChange((index: number) => {
        animateTo(AppAnimations.SPRING_NORMAL, () => {
          this.currentIndex = index
        })
      })
      .width('100%')
      .height('100%')
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY)

      // 全局AI分析弹窗 - 覆盖在所有Tab之上
      if (this.shouldShowAIDialog) {
        this.GlobalAIAnalysisDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ========== AI 弹窗辅助方法（从 HomePage 迁移） ==========
  // Ref: docs-master/en/application-dev/ui/state-management/arkts-appstorage.md
  /** 解析AI目标 */
  private parseAIGoals(jsonStr: string): string[] {
    try {
      const parsed: ESObject = JSON.parse(jsonStr)
      if (Array.isArray(parsed)) {
        return parsed as string[]
      }
      return []
    } catch (e) {
      console.error('[MainPage] 解析AI目标失败:', e)
      return []
    }
  }

  /** 解析AI待办 */
  private parseAITodos(jsonStr: string): string[] {
    try {
      const parsed: ESObject = JSON.parse(jsonStr)
      if (Array.isArray(parsed)) {
        return parsed as string[]
      }
      return []
    } catch (e) {
      console.error('[MainPage] 解析AI待办失败:', e)
      return []
    }
  }

  /** 获取AI目标列表 */
  private getAIGoals(): string[] {
    if (!this.pendingAIGoals) {
      return []
    }
    return this.parseAIGoals(this.pendingAIGoals)
  }

  /** 获取AI待办列表 */
  private getAITodos(): string[] {
    if (!this.pendingAITodos) {
      return []
    }
    return this.parseAITodos(this.pendingAITodos)
  }

  /** AI目标列表 */
  @Builder AIGoalsList() {
    ForEach(this.getAIGoals(), (goal: string, index: number) => {
      Column({ space: AppSizes.SPACE_SM }) {
        if (index === 0) {
          Row() {
            Text('🎯')
              .fontSize(16)
            Text('建议添加的目标')
              .fontSize(AppSizes.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ left: 6 })
          }
          .width('100%')
          .margin({ bottom: AppSizes.SPACE_SM })
        }

        Row({ space: AppSizes.SPACE_SM }) {
          Checkbox()
            .select(this.selectedAIGoals.includes(goal))
            .selectedColor(AppColors.ACCENT)
            .onChange((checked: boolean) => {
              if (checked) {
                this.selectedAIGoals = [...this.selectedAIGoals, goal]
              } else {
                this.selectedAIGoals = this.selectedAIGoals.filter((g: string) => g !== goal)
              }
            })
          Text(goal)
            .fontSize(AppSizes.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(AppSizes.SPACE_SM)
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(AppSizes.RADIUS_SM)
      }
      .width('100%')
      .padding(index === 0 ? AppSizes.SPACE_MD : { left: AppSizes.SPACE_MD, right: AppSizes.SPACE_MD, bottom: AppSizes.SPACE_MD })
      .backgroundColor(AppColors.INFO_BG)
      .borderRadius(AppSizes.RADIUS_MD)
    }, (goal: string, index: number) => `goal_${index}`)
  }

  /** AI待办列表 */
  @Builder AITodosList() {
    ForEach(this.getAITodos(), (todo: string, index: number) => {
      Column({ space: AppSizes.SPACE_SM }) {
        if (index === 0) {
          Row() {
            Text('✅')
              .fontSize(16)
            Text('建议添加的待办')
              .fontSize(AppSizes.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ left: 6 })
          }
          .width('100%')
          .margin({ bottom: AppSizes.SPACE_SM })
        }

        Row({ space: AppSizes.SPACE_SM }) {
          Checkbox()
            .select(this.selectedAITodos.includes(todo))
            .selectedColor(AppColors.ACCENT)
            .onChange((checked: boolean) => {
              if (checked) {
                this.selectedAITodos = [...this.selectedAITodos, todo]
              } else {
                this.selectedAITodos = this.selectedAITodos.filter((t: string) => t !== todo)
              }
            })
          Text(todo)
            .fontSize(AppSizes.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(AppSizes.SPACE_SM)
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(AppSizes.RADIUS_SM)
      }
      .width('100%')
      .padding(index === 0 ? AppSizes.SPACE_MD : { left: AppSizes.SPACE_MD, right: AppSizes.SPACE_MD, bottom: AppSizes.SPACE_MD })
      .backgroundColor(AppColors.WARNING_BG)
      .borderRadius(AppSizes.RADIUS_MD)
    }, (todo: string, index: number) => `todo_${index}`)
  }

  // 确认添加AI分析结果 - 真正添加目标和待办
  async confirmAddAIResults(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext
    let addedGoals = 0
    let addedTodos = 0
    
    // 添加目标
    if (this.selectedAIGoals.length > 0) {
      const goalVM = new GoalViewModel()
      const defaultDeadline = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // 30天后
      for (const goalTitle of this.selectedAIGoals) {
        try {
          await goalVM.createGoal(goalTitle, defaultDeadline)
          addedGoals++
        } catch (e) {
          console.error('[MainPage] 添加目标失败:', e)
        }
      }
    }
    
    // 添加待办（作为任务）
    if (this.selectedAITodos.length > 0) {
      const taskService = TaskStorageService.getInstance()
      for (const todoTitle of this.selectedAITodos) {
        const task: Task = {
          id: `task_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
          title: todoTitle,
          estimatedPomodoros: 1,
          completedPomodoros: 0,
          isCompleted: false,
          priority: TaskPriority.MEDIUM,
          createdAt: Date.now(),
          tag: 'AI建议'
        }
        try {
          await taskService.addTask(context, task)
          addedTodos++
        } catch (e) {
          console.error('[MainPage] 添加待办失败:', e)
        }
      }
    }
    
    promptAction.showToast({
      message: `已添加 ${addedGoals} 个目标和 ${addedTodos} 个待办`,
      duration: 2000
    })

    this.shouldShowAIDialog = false
    AppStorage.setOrCreate('shouldShowAIDialog', false)
    this.clearAIData()
  }

  /** 清除AI数据 */
  clearAIData(): void {
    this.selectedAIGoals = []
    this.selectedAITodos = []
    AppStorage.setOrCreate('pendingAIGoals', '')
    AppStorage.setOrCreate('pendingAITodos', '')
    AppStorage.setOrCreate('aiEncouragement', '')
  }

  /** 检查是否有AI分析结果待显示 */
  private checkAIDialogOnLoad(): void {
    const shouldShow = AppStorage.get('shouldShowAIDialog') as boolean | undefined
    const goals = AppStorage.get('pendingAIGoals') as string | undefined
    const todos = AppStorage.get('pendingAITodos') as string | undefined
    const encouragement = AppStorage.get('aiEncouragement') as string | undefined

    console.info('[MainPage] 检查AI对话框:', {
      shouldShow,
      hasGoals: !!goals,
      hasTodos: !!todos,
      hasEncouragement: !!encouragement
    })

    if (shouldShow) {
      // 如果有目标或待办需要确认，显示弹窗
      if (goals || todos) {
        console.info('[MainPage] 有待确认项目，显示对话框')
        // StorageLink 自动驱动弹窗显示
      } else if (encouragement) {
        // 只有鼓励消息，使用Toast显示（更轻量）
        promptAction.showToast({
          message: `💬 ${encouragement}`,
          duration: 3000
        })
        // 清除显示标记，避免重复
        AppStorage.setOrCreate('shouldShowAIDialog', false)
        AppStorage.setOrCreate('aiEncouragement', '')
        this.shouldShowAIDialog = false
        console.info('[MainPage] 仅鼓励消息，用Toast显示')
      }
    }
  }
}
