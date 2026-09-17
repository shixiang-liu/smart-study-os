// ============================================================================
// 学习仪表盘 - Dashboard Page (Creamy UI Refactor)
// ============================================================================
// 风格：Creamy UI (Soft, Clean, Friendly)
// 核心：柔和图表 + 悬浮卡片 + 玩具感图标
// ============================================================================

import { AppColors, AppSizes, AppShadows, AppAnimations, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'
import { DashboardViewModel, FocusData, EmotionData } from '../../../tools/viewmodel/DashboardViewModel'
import { MemoryViewModel, ObstacleAnalysis } from '../../../diary/viewmodel/MemoryViewModel'
import { TaskStorageService } from '../../../goal/model/TaskStorageService'
import { Task } from '../../../goal/model/Task'
import display from '@ohos.display'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'

const BREAKPOINT_TABLET: number = 600

// 阻碍项接口
interface ObstacleItem {
  keyword: string
  count: number
  percentage: number
}

@Entry
@Component
struct DashboardPage {
  @State focusData: FocusData[] = []
  @State emotionData: EmotionData[] = []
  @State totalFocusMinutes: number = 0
  @State averageFocusMinutes: number = 0
  @State currentStreak: number = 0
  @State diaryCount: number = 0
  @State weeklyInsight: string = ''
  @State isLoading: boolean = true
  @State isGeneratingAIInsight: boolean = false
  @State isTablet: boolean = false
  @State screenWidth: number = 360
  @StorageLink('isDarkMode') isDarkMode: boolean = false

  // 学习阻碍数据
  @State obstacles: ObstacleItem[] = []
  @State obstacleReport: string = ''
  
  // 监听日记更新信号
  @StorageProp('diaryUpdatedAt') @Watch('onDiaryUpdated') diaryUpdatedAt: number = 0

  // 已完成任务数据
  @State completedTasks: Task[] = []
  @State showAllCompletedTasks: boolean = false

  private viewModel: DashboardViewModel = new DashboardViewModel()
  private memoryVM: MemoryViewModel = MemoryViewModel.getInstance()
  private taskService: TaskStorageService = TaskStorageService.getInstance()
  private context: common.UIAbilityContext | null = null

  aboutToAppear() {
    this.detectScreenSize()
    // 设置上下文，用于获取真实的专注记录
    this.context = getContext(this) as common.UIAbilityContext
    if (this.context) {
      this.viewModel.setContext(this.context)
      console.info('[DashboardPage] aboutToAppear: context已设置')
    } else {
      console.warn('[DashboardPage] aboutToAppear: 无法获取context')
    }
    this.loadData()
  }
  
  // 页面再次显示时刷新数据
  onPageShow() {
    console.info('[DashboardPage] 页面显示，刷新数据')
    // 确保 context 已设置
    if (!this.context) {
      this.context = getContext(this) as common.UIAbilityContext
      if (this.context) {
        this.viewModel.setContext(this.context)
        console.info('[DashboardPage] onPageShow: context已设置')
      } else {
        console.warn('[DashboardPage] onPageShow: 无法获取context')
      }
    }
    // 强制重新加载最新数据
    this.loadData()
  }

  // 日记更新回调
  onDiaryUpdated() {
    console.info('[DashboardPage] 监听到日记更新，刷新数据')
    // 确保 context 已设置
    if (!this.context) {
      this.context = getContext(this) as common.UIAbilityContext
      if (this.context) {
        this.viewModel.setContext(this.context)
        console.info('[DashboardPage] onDiaryUpdated: context已设置')
      } else {
        console.warn('[DashboardPage] onDiaryUpdated: 无法获取context')
      }
    }
    this.loadData()
  }
  
  // 问题1修复：监听专注记录更新
  @StorageProp('focusRecordUpdatedAt') @Watch('onFocusRecordUpdated') focusRecordUpdatedAt: number = 0
  
  onFocusRecordUpdated() {
    console.info('[DashboardPage] 监听到专注记录更新，刷新数据')
    // 确保 context 已设置
    if (!this.context) {
      this.context = getContext(this) as common.UIAbilityContext
      if (this.context) {
        this.viewModel.setContext(this.context)
        console.info('[DashboardPage] onFocusRecordUpdated: context已设置')
      } else {
        console.warn('[DashboardPage] onFocusRecordUpdated: 无法获取context')
      }
    }
    this.loadData()
  }

  private detectScreenSize(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync()
      this.screenWidth = displayInfo.width / displayInfo.densityPixels
      this.isTablet = this.screenWidth >= BREAKPOINT_TABLET
    } catch (err) {
      this.isTablet = false
    }
  }

  private async loadData(): Promise<void> {
    this.isLoading = true
    try {
      // 确保context已设置
      if (!this.context) {
        this.context = getContext(this) as common.UIAbilityContext
        if (this.context) {
          this.viewModel.setContext(this.context)
          console.info('[DashboardPage] loadData: context已设置')
        } else {
          console.error('[DashboardPage] loadData: 无法获取context，数据可能无法正确加载')
        }
      }
      
      console.info('[DashboardPage] 开始加载数据，context存在:', !!this.context)
      
      // 【直接测试读取日记数据】作为备用方案
      let directDiaryCount = 0
      if (this.context) {
        try {
          const UtilModule = await import('../../../common/utils/PreferencesUtil')
          const PreferencesUtil = UtilModule.PreferencesUtil
          const testNotes = await PreferencesUtil.loadNotes(this.context)
          directDiaryCount = Array.isArray(testNotes) ? testNotes.length : 0
          console.info('[DashboardPage] 【直接测试】本地日记数量:', directDiaryCount)
          if (directDiaryCount > 0) {
            console.info('[DashboardPage] 【直接测试】第一条日记ID:', testNotes[0].id, '标题:', testNotes[0].title)
          } else {
            console.warn('[DashboardPage] 【直接测试】未读取到日记数据，testNotes类型:', typeof testNotes, '是否为数组:', Array.isArray(testNotes))
          }
        } catch (testErr) {
          console.error('[DashboardPage] 【直接测试】读取日记失败:', testErr)
          console.error('[DashboardPage] 【直接测试】错误详情:', JSON.stringify(testErr))
        }
      } else {
        console.warn('[DashboardPage] 【直接测试】context不存在，无法直接读取日记')
      }
      
      // 确保在调用前再次设置context
      if (this.context) {
        this.viewModel.setContext(this.context)
        console.info('[DashboardPage] 已设置ViewModel的context')
      }
      
      const results = await Promise.all([
        this.viewModel.getFocusData(7),
        this.viewModel.getEmotionData(7),
        this.viewModel.getWeeklyStats(this.context || undefined),
        this.viewModel.generateWeeklyInsight(this.context || undefined)
      ])

      console.info('[DashboardPage] 数据加载结果:', {
        focusDataLength: results[0].length,
        emotionDataLength: results[1].length,
        weeklyStats: results[2],
        weeklyStatsDiaryCount: results[2].diaryCount,
        directDiaryCount: directDiaryCount,
        insightLength: results[3]?.length || 0
      })

      this.focusData = results[0]
      this.emotionData = results[1]
      this.totalFocusMinutes = results[2].totalMinutes
      this.averageFocusMinutes = results[2].averageMinutes
      this.currentStreak = results[2].streak
      
      // 【修复】优先使用ViewModel返回的值，如果为0则使用直接读取的结果
      const viewModelDiaryCount = results[2].diaryCount || 0
      // 直接使用较大的值，确保数据正确显示
      const finalDiaryCount = Math.max(viewModelDiaryCount, directDiaryCount)
      this.diaryCount = finalDiaryCount
      console.info('[DashboardPage] 设置diaryCount:', finalDiaryCount, '(ViewModel:', viewModelDiaryCount, ', 直接读取:', directDiaryCount, ')')
      
      this.weeklyInsight = results[3]
      
      console.info('[DashboardPage] 数据加载完成，最终diaryCount:', this.diaryCount, ', totalMinutes:', this.totalFocusMinutes, ', streak:', this.currentStreak)
      console.info('[DashboardPage] 【最终状态】所有状态变量已更新 - diaryCount:', this.diaryCount, ', totalFocusMinutes:', this.totalFocusMinutes, ', averageFocusMinutes:', this.averageFocusMinutes, ', currentStreak:', this.currentStreak)

      // 加载学习阻碍数据
      await this.loadObstacles()
      // 加载已完成任务
      await this.loadCompletedTasks()
    } catch (err) {
      console.error('[DashboardPage] Load failed:', err)
      console.error('[DashboardPage] 错误类型:', typeof err)
      console.error('[DashboardPage] 错误消息:', (err as Error)?.message)
      console.error('[DashboardPage] 错误堆栈:', (err as Error)?.stack)
      this.weeklyInsight = '暂无数据'
      // 确保即使出错也显示当前状态
      console.info('[DashboardPage] 当前状态 - diaryCount:', this.diaryCount, ', totalMinutes:', this.totalFocusMinutes)
    } finally {
      this.isLoading = false
      console.info('[DashboardPage] 数据加载流程完成，isLoading:', this.isLoading, ', 最终diaryCount:', this.diaryCount)
      // 强制触发UI更新：通过重新赋值确保@State变量触发UI刷新
      const finalDiaryCount = this.diaryCount
      const finalTotalMinutes = this.totalFocusMinutes
      const finalAverageMinutes = this.averageFocusMinutes
      const finalStreak = this.currentStreak
      // 重新赋值以触发UI刷新
      this.diaryCount = finalDiaryCount
      this.totalFocusMinutes = finalTotalMinutes
      this.averageFocusMinutes = finalAverageMinutes
      this.currentStreak = finalStreak
      console.info('[DashboardPage] 强制刷新UI状态 - diaryCount:', this.diaryCount, ', totalFocusMinutes:', this.totalFocusMinutes, ', averageFocusMinutes:', this.averageFocusMinutes, ', currentStreak:', this.currentStreak)
    }
  }

  // 加载已完成任务
  private async loadCompletedTasks(): Promise<void> {
    try {
      if (!this.context) {
        this.context = getContext(this) as common.UIAbilityContext
      }
      const tasks = await this.taskService.getCompletedTasks(this.context)
      // 只显示最近30天的已完成任务
      const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000
      this.completedTasks = tasks.filter(t => (t.completedAt || 0) >= thirtyDaysAgo)
    } catch (err) {
      console.error('[DashboardPage] Load completed tasks failed:', err)
      this.completedTasks = []
    }
  }

  private async deleteCompletedTask(taskId: string): Promise<void> {
    try {
      if (!this.context) {
        this.context = getContext(this) as common.UIAbilityContext
      }
      const ok = await this.taskService.removeCompletedTask(this.context, taskId)
      if (ok) {
        this.completedTasks = this.completedTasks.filter(t => t.id !== taskId)
      }
    } catch (err) {
      console.error('[DashboardPage] Delete completed task failed:', err)
    }
  }

  /** 加载学习阻碍分析数据 */
  private async loadObstacles(): Promise<void> {
    try {
      // 传递 context，以便从本地日记分析（作为 CloudDB 的 fallback）
      if (!this.context) {
        this.context = getContext(this) as common.UIAbilityContext
      }
      const obstacleData = await this.memoryVM.analyzeObstacles(7, this.context)
      // 只取前 5 个主要阻碍
      const items: ObstacleItem[] = []
      for (const o of obstacleData.slice(0, 5)) {
        const item: ObstacleItem = {
          keyword: o.keyword,
          count: o.count,
          percentage: o.percentage
        }
        items.push(item)
      }
      this.obstacles = items
      // 生成报告文本
      this.obstacleReport = await this.memoryVM.generateObstacleReport(7, this.context)
    } catch (err) {
      console.error('[DashboardPage] Load obstacles failed:', err)
      this.obstacles = []
      this.obstacleReport = ''
    }
  }

  private async requestAIInsight(): Promise<void> {
    this.isGeneratingAIInsight = true
    try {
      this.weeklyInsight = await this.viewModel.generateAIInsight()
    } catch (err) {
      console.error('[DashboardPage] AI failed:', err)
    } finally {
      this.isGeneratingAIInsight = false
    }
  }

  private getMaxFocusMinutes(): number {
    return Math.max(...this.focusData.map(d => d.minutes), 60)
  }

  private formatDuration(minutes: number): string {
    const hours = Math.floor(minutes / 60)
    const mins = minutes % 60
    return hours > 0 ? `${hours}h ${mins}m` : `${mins}m`
  }

  // ==================== UI Builders ====================

  build() {
    Column() {
      Scroll() {
        Column() {
          this.HeaderSection()
          this.StatsSection()

          if (this.isTablet) {
            Row({ space: AppSizes.SPACE_LG }) {
              Column() { this.FocusChartSection() }.layoutWeight(1)
              Column() { this.EmotionChartSection() }.layoutWeight(1)
            }
            .width('100%')
            .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
          } else {
            this.FocusChartSection()
            this.EmotionChartSection()
          }

          this.InsightAndObstacleSection()
          this.CompletedTasksSection()
          Blank().height(AppSizes.SPACE_4XL)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.isTablet ? 900 : '100%' })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BG_PRIMARY)
  }

  @Builder
  HeaderSection() {
    Column() {
      Text('学习报告')
        .fontSize(AppSizes.FONT_3XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
      Text('本周数据概览')
        .fontSize(AppSizes.FONT_SM)
        .fontColor(AppColors.TEXT_TERTIARY)
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      top: AppSizes.SPACE_4XL,
      left: AppSizes.SPACE_LG,
      right: AppSizes.SPACE_LG,
      bottom: AppSizes.SPACE_LG
    })
  }

  @Builder
  StatsSection() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      // 使用Swiss Spa渐变背景
      this.StatCard('总专注', this.formatDuration(this.totalFocusMinutes), '⏰', AppGradients.SPA_SKY)
      this.StatCard('日均', `${this.averageFocusMinutes}m`, '📈', AppGradients.SPA_MINT)
      this.StatCard('连续', `${this.currentStreak}天`, '🔥', AppGradients.SPA_PEACH)
      this.StatCard('日记', `${this.diaryCount}篇`, '📝', AppGradients.SPA_LAVENDER)
    }
    .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
    .margin({ bottom: AppSizes.SPACE_LG })
    .onAppear(() => {
      // 在UI出现时记录状态值（帮助调试）
      console.info('[DashboardPage] StatsSection onAppear - diaryCount:', this.diaryCount, ', totalFocusMinutes:', this.totalFocusMinutes, ', averageFocusMinutes:', this.averageFocusMinutes, ', currentStreak:', this.currentStreak, ', isLoading:', this.isLoading)
    })
  }

  @Builder
  StatCard(label: string, value: string, icon: string, gradient: LinearGradient) {
    Column() {
      Text(icon).fontSize(28)
      Text(value)
        .fontSize(AppSizes.FONT_XL)
        .fontWeight(FontWeight.Bold)
        // Swiss Spa 渐变背景较浅，强制使用深色文字以确保对比度
        .fontColor('#1F2937') 
        .margin({ top: 8 })
        .onAppear(() => {
          // 在文本出现时记录（确认实际显示的值，特别是日记卡片）
          if (label === '日记') {
            console.info('[DashboardPage] StatCard(日记)文本显示 - value:', value, ', label:', label, ', 当前diaryCount:', this.diaryCount)
          }
        })
      Text(label)
        .fontSize(AppSizes.FONT_XS)
        .fontColor('#4B5563')
        .margin({ top: 4 })
    }
    .width('48%') // 2 columns
    .padding(AppSizes.SPACE_LG)
    .linearGradient(gradient)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
    .margin({ bottom: AppSizes.SPACE_MD })
    .onAppear(() => {
      // 在UI出现时记录卡片的值（特别是日记卡片）
      if (label === '日记') {
        console.info('[DashboardPage] StatCard(日记)onAppear - value:', value, ', label:', label, ', 当前diaryCount:', this.diaryCount)
      }
    })
  }

  @Builder
  FocusChartSection() {
    Column() {
      Row() {
        Text('📊').fontSize(20)
        Text('专注时长')
          .fontSize(AppSizes.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ bottom: AppSizes.SPACE_LG })

      // Bar Chart
      Row({ space: 8 }) {
        ForEach(this.focusData, (item: FocusData) => {
          Column() {
            // Bar - 使用Swiss Spa渐变
            Column()
              .width('100%')
              .height(`${Math.max((item.minutes / this.getMaxFocusMinutes()) * 100, 10)}%`)
              .linearGradient(item.minutes > 0 ? AppGradients.SPA_SKY : {
                angle: 180,
                colors: [[AppColors.TEXT_DISABLED, 0], [AppColors.TEXT_DISABLED, 1]]
              })
              .borderRadius(8)
              .animation(AppAnimations.SPRING_SLOW)

            // Date
            Text(item.date)
              .fontSize(10)
              .fontColor(AppColors.TEXT_TERTIARY)
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .height(180)
          .justifyContent(FlexAlign.End)
        })
      }
    }
    .padding(AppSizes.SPACE_LG)
    .margin({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG, bottom: AppSizes.SPACE_LG })
    .linearGradient(this.isDarkMode ? {
      angle: 135,
      colors: [[AppColors.BG_DARK_SECONDARY, 0], [AppColors.BG_DARK_TERTIARY, 1]]
    } : {
      angle: 135,
      colors: [['#F8FAFC', 0], ['#EEF2FF', 1]]
    })
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
  }

  @Builder
  EmotionChartSection() {
    Column() {
      Row() {
        Text('❤️').fontSize(20)
        Text('情绪趋势')
          .fontSize(AppSizes.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ bottom: AppSizes.SPACE_LG })

      // Emotion Dots
      Row({ space: 8 }) {
        ForEach(this.emotionData, (item: EmotionData) => {
          Column() {
            // Dot
            Circle({ width: 16, height: 16 })
              .fill(this.getEmotionColor(item.score))
              .margin({ bottom: item.score * 10 }) // Height based on score
              .animation(AppAnimations.SPRING_BOUNCE)

            // Label
            Text(item.label)
              .fontSize(10)
              .fontColor(AppColors.TEXT_SECONDARY)
            
            // Date
            Text(item.date)
              .fontSize(10)
              .fontColor(AppColors.TEXT_TERTIARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .height(120)
          .justifyContent(FlexAlign.End)
        })
      }
    }
    .padding(AppSizes.SPACE_LG)
    .margin({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG, bottom: AppSizes.SPACE_LG })
    .linearGradient(this.isDarkMode ? {
      angle: 135,
      colors: [[AppColors.BG_DARK_SECONDARY, 0], [AppColors.BG_DARK_TERTIARY, 1]]
    } : {
      angle: 135,
      colors: [['#FFF5F5', 0], ['#FEF2F8', 1]]
    })
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
  }

  /** 本周洞察与阻碍分析（合并区块） */
  @Builder
  InsightAndObstacleSection() {
    Column({ space: AppSizes.SPACE_LG }) {
      // 标题栏
      Row() {
        Text('📊').fontSize(20)
        Text('本周总结')
          .fontSize(AppSizes.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
        Blank()
        Button(this.isGeneratingAIInsight ? '分析中...' : 'AI 深度分析')
          .height(32)
          .fontSize(12)
          .backgroundColor(AppColors.ACCENT)
          .borderRadius(16)
          .onClick(() => this.requestAIInsight())
          .enabled(!this.isGeneratingAIInsight)
      }
      .width('100%')

      // AI 洞察内容
      Column() {
        Row() {
          Text('💡').fontSize(16)
          Text('学习洞察')
            .fontSize(AppSizes.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ left: 6 })
        }
        .width('100%')
        .margin({ bottom: 8 })

        Text(this.weeklyInsight || '暂无数据，多记录一些日记吧~')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .lineHeight(22)
      }
      .width('100%')
      .padding(AppSizes.SPACE_MD)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : '#FFFDE7')
      .borderRadius(AppSizes.RADIUS_MD)

      // 学习阻碍
      Column() {
        Row() {
          Text('🚧').fontSize(16)
          Text('学习阻碍')
            .fontSize(AppSizes.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ left: 6 })
        }
        .width('100%')
        .margin({ bottom: 12 })

        if (this.obstacles.length > 0) {
          // 阻碍列表（横向展示前3个）
          Row({ space: 8 }) {
            ForEach(this.obstacles.slice(0, 3), (item: ObstacleItem, index: number) => {
              Column({ space: 4 }) {
                // 排名圆圈
                Text(`${index + 1}`)
                  .fontSize(11)
                  .fontColor(AppColors.TEXT_WHITE)
                  .fontWeight(FontWeight.Bold)
                  .width(20)
                  .height(20)
                  .textAlign(TextAlign.Center)
                  .backgroundColor(this.getObstacleColor(index))
                  .borderRadius(10)

                // 关键词
                Text(item.keyword)
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                // 次数
                Text(`${item.count}次`)
                  .fontSize(10)
                  .fontColor(AppColors.TEXT_TERTIARY)
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(AppColors.BG_PRIMARY)
              .borderRadius(10)
            })
          }
          .width('100%')

          // 改进建议
          Row() {
            Text('💡')
              .fontSize(12)
            Text(`建议：减少 "${this.obstacles[0].keyword}" 相关干扰`)
              .fontSize(AppSizes.FONT_XS)
              .fontColor(AppColors.TEXT_SECONDARY)
              .margin({ left: 4 })
          }
          .width('100%')
          .margin({ top: 10 })
        } else {
          // 无阻碍
          Row() {
            Text('🎉')
              .fontSize(16)
            Text('本周表现优秀，没有明显阻碍！')
              .fontSize(AppSizes.FONT_SM)
              .fontColor(AppColors.SUCCESS)
              .margin({ left: 6 })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(AppSizes.SPACE_MD)
      .backgroundColor(AppColors.BG_PRIMARY)
      .borderRadius(AppSizes.RADIUS_MD)
    }
    .padding(AppSizes.SPACE_LG)
    .margin({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
  }

  /** 获取阻碍排名颜色 */
  private getObstacleColor(index: number): string {
    if (index === 0) return AppColors.ERROR     // 红色 - 最严重
    if (index === 1) return AppColors.BRAND_AMBER  // 橙色
    if (index === 2) return '#FFC107'           // 黄色
    return AppColors.TEXT_TERTIARY              // 灰色
  }

  private getEmotionColor(score: number): string {
    if (score >= 4) return AppColors.SUCCESS // Green
    if (score >= 3) return AppColors.BRAND_AMBER // Yellow
    return AppColors.ERROR // Red
  }

  // 格式化任务完成时间
  private formatTaskDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = date.getMonth() + 1
    const day = date.getDate()
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${month}/${day} ${hours}:${minutes}`
  }

  /** 已完成任务列表 */
  @Builder
  CompletedTasksSection() {
    if (this.completedTasks.length > 0) {
      Column({ space: AppSizes.SPACE_MD }) {
        // 标题
        Row() {
          Text('✅').fontSize(20)
          Text('已完成任务')
            .fontSize(AppSizes.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 8 })
          Blank()
          Text(`共 ${this.completedTasks.length} 个`)
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_TERTIARY)
        }
        .width('100%')
        .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

        // 任务列表（默认折叠，展开显示全部）
        Column({ space: 8 }) {
          ForEach(this.showAllCompletedTasks ? this.completedTasks : this.completedTasks.slice(0, 5), (task: Task) => {
            this.renderCompletedTaskItem(task)
          }, (task: Task) => task.id)
        }
        .width('100%')
        .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

        // 折叠 / 展开按钮
        if (this.completedTasks.length > 5) {
          Button(this.showAllCompletedTasks ? '收起' : `展开全部（共 ${this.completedTasks.length} 个）`)
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.ACCENT)
            .backgroundColor(AppColors.ACCENT_BG)
            .borderRadius(AppSizes.RADIUS_MD)
            .height(36)
            .margin({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
            .onClick(() => {
              this.showAllCompletedTasks = !this.showAllCompletedTasks
            })
        }
      }
      .width('100%')
      .margin({ top: AppSizes.SPACE_LG })
    }
  }

  @Builder
  renderCompletedTaskItem(task: Task) {
    Row({ space: 12 }) {
      // 任务类型标识（目标/番茄/普通）
      Column() {
        if ((task.tag || '') === '目标') {
          Text('🎯').fontSize(16)
        } else if (task.estimatedPomodoros > 0) {
          Text('🍅').fontSize(16)
        } else {
          Text('📋').fontSize(16)
        }
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(task.title)
            .fontSize(AppSizes.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .decoration({ type: TextDecorationType.LineThrough })
            .layoutWeight(1)
          
          // 任务类型标签
          if ((task.tag || '') === '目标') {
            Text('目标')
              .fontSize(10)
              .fontColor(AppColors.TEXT_WHITE)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.SUCCESS)
              .borderRadius(4)
          } else if (task.estimatedPomodoros > 0) {
            Text('番茄钟')
              .fontSize(10)
              .fontColor(AppColors.TEXT_WHITE)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.ACCENT)
              .borderRadius(4)
          } else {
            Text('普通')
              .fontSize(10)
              .fontColor(AppColors.TEXT_SECONDARY)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.BG_TERTIARY)
              .borderRadius(4)
          }
        }
        .width('100%')

        // 任务详情
        Row({ space: 12 }) {
          // 如果是番茄钟任务，显示番茄数
          if (task.estimatedPomodoros > 0) {
            Text(`🍅 ${task.estimatedPomodoros} 个番茄`)
              .fontSize(AppSizes.FONT_XS)
              .fontColor(AppColors.TEXT_SECONDARY)
          }
          
          // 完成时间
          if (task.completedAt) {
            Text(this.formatTaskDate(task.completedAt))
              .fontSize(AppSizes.FONT_XS)
              .fontColor(AppColors.TEXT_TERTIARY)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧轻量删除入口（极简样式，替代左滑）
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Text('⋯')
          .fontSize(14)
          .fontColor(AppColors.TEXT_SECONDARY)
      }
      .width(28)
      .height(28)
      .backgroundColor(AppColors.BG_TERTIARY)
      .onClick(async () => {
        const result = await promptAction.showDialog({
          title: '删除记录',
          message: '确定删除这条已完成记录吗？',
          buttons: [
            { text: '取消', color: AppColors.TEXT_SECONDARY },
            { text: '删除', color: AppColors.ERROR }
          ]
        })

        if (result && result.index === 1) {
          await this.deleteCompletedTask(task.id)
        }
      })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_MD)
    .margin({ bottom: 8 })
  }
}
