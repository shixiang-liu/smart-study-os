/**
 * @file HomeTabContent.ets
 * @description 首页 Tab - 今日概览（从 MainPage 提取的独立组件）
 * @module main/view/tabs
 */

import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import display from '@ohos.display'
import { NewsService, NewsDetail } from '../../../common/services/NewsService'
import { NewsItem } from '../../../common/model/NewsItem'
import { NoteItem, LinkItem, LinkBlock, TextBlock } from '../../../diary/model/NoteItem'
import { AppColors, AppSizes, AppShadows, AppGradients, AppThemeManager, LinearGradient } from '../../../common/utils/AppTheme'
import { PreferencesUtil } from '../../../common/utils/PreferencesUtil'
import { GoalCountdown } from '../../../goal/viewmodel/GoalViewModel'
import { Task, TaskPriority } from '../../../goal/model/Task'
import { TaskStorageService } from '../../../goal/model/TaskStorageService'
import { FocusRecordService } from '../../../pomodoro/model/FocusRecordService'
import { GoalViewModel } from '../../../goal/viewmodel/GoalViewModel'
import { MemoryViewModel } from '../../../diary/viewmodel/MemoryViewModel'
import { ObstacleItem } from '../../model/HomeModels'
import { QuickActionsGrid } from '../components/QuickActionsGrid'
import { GoalKeeperCard } from '../components/GoalKeeperCard'
import { ObstacleHintCard } from '../components/ObstacleHintCard'
import { NewsCollection } from '../../../common/model/NewsCollection'
import { CloudDBService } from '../../../common/services/CloudDBService'

@Component
export struct HomeTabContent {
  @StorageLink('currentUserNickname') nickname: string = ''
  @StorageLink('currentUserAvatar') userAvatar: string = ''
  @State goalInfo: GoalCountdown | null = null
  @State todayFocusMinutes: number = 0
  @State todayTasks: Task[] = [] // 使用统一的Task模型
  @State pomodoroTasks: Task[] = [] // 番茄钟待办
  @State normalTasks: Task[] = [] // 普通待办
  @State isLoading: boolean = true
  @State showAddSheet: boolean = false
  @State isPomodoroSheet: boolean = false
  @State newTaskTitle: string = ''
  @State newTaskEstimated: number = 2 // 与默认中优先级保持一致
  @State newTaskPriority: TaskPriority = TaskPriority.MEDIUM
  @State newTaskDuration: number = 25 // 单个番茄时长（分钟）
  // 用于监听目标变化以刷新数据
  @StorageProp('goalUpdatedAt') @Watch('onGoalUpdated') goalUpdatedAt: number = 0
  @StorageProp('tasksUpdatedAt') @Watch('onTasksUpdated') tasksUpdatedAt: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  // 响应式布局
  @State isTablet: boolean = false
  private readonly BREAKPOINT_TABLET: number = 600
  private goalVM: GoalViewModel = new GoalViewModel()
  private taskService: TaskStorageService = TaskStorageService.getInstance()
  private recordService: FocusRecordService = FocusRecordService.getInstance()
  
  // 学习障碍数据
  @State obstacles: ObstacleItem[] = []
  @State obstacleReport: string = ''
  private memoryVM: MemoryViewModel = MemoryViewModel.getInstance()

  // 今日头条新闻数据
  @State newsList: NewsItem[] = []
  @State currentNewsIndex: number = 0
  @State newsScrollOffset: number = 0
  @State selectedNews: NewsItem | null = null
  @State showNewsDetail: boolean = false
  @State newsDetailContent: string = ''
  @State newsDetailSummary: string = ''
  @State isLoadingNewsDetail: boolean = false
  private newsTimer: number = -1
  private newsService = NewsService.getInstance()

  async aboutToAppear() {
    this.detectScreenSize()
    await this.loadData()
    await this.loadNews()
    this.startNewsAutoScroll()
  }

  /** 检测屏幕尺寸，判断是否为平板 */
  private detectScreenSize(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync()
      const screenWidth = displayInfo.width / displayInfo.densityPixels
      this.isTablet = screenWidth >= this.BREAKPOINT_TABLET
    } catch (err) {
      this.isTablet = false
    }
  }

  aboutToDisappear() {
    this.stopNewsAutoScroll()
  }

  // 当目标数据更新时刷新
  onGoalUpdated(): void {
    this.loadData()
  }

  onTasksUpdated(): void {
    this.loadTasks()
  }

  private async loadData(): Promise<void> {
    this.isLoading = true
    try {
      this.goalInfo = await this.goalVM.getNearestGoalCountdown()
      // 加载待办数据
      await this.loadTasks()
      // 加载今日专注时长
      await this.loadTodayFocusMinutes()
      // 加载学习障碍数据
      await this.loadObstacles()
    } catch (err) {
      console.error('HomeTab loadData failed:', err)
    }
    this.isLoading = false
  }

  // 加载待办数据（已完成的任务移到最下方）
  private async loadTasks(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const allTasks = await this.taskService.getTasks(context)
      
      // 分离未完成和已完成的任务
      const incompleteTasks = allTasks.filter(t => !t.isCompleted)
      const completedTasks = allTasks.filter(t => t.isCompleted)
      
      // 未完成的任务：分离普通待办和番茄钟待办
      this.pomodoroTasks = incompleteTasks.filter(t => t.estimatedPomodoros > 0)
      this.normalTasks = incompleteTasks.filter(t => t.estimatedPomodoros === 0)
      
      // 已完成的任务也分离（用于显示在底部）
      const completedPomodoroTasks = completedTasks.filter(t => t.estimatedPomodoros > 0)
      const completedNormalTasks = completedTasks.filter(t => t.estimatedPomodoros === 0)
      
      // 合并：未完成在前，已完成在后
      this.todayTasks = [
        ...this.pomodoroTasks,
        ...this.normalTasks,
        ...completedPomodoroTasks,
        ...completedNormalTasks
      ]
    } catch (err) {
      console.error('[HomeTab] Load tasks failed:', err)
      this.todayTasks = []
      this.pomodoroTasks = []
      this.normalTasks = []
    }
  }

  // 加载今日专注时长
  private async loadTodayFocusMinutes(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const today = new Date().toISOString().split('T')[0]
      const todayRecord = await this.recordService.getRecordByDate(context, today)
      this.todayFocusMinutes = todayRecord.focusMinutes || 0
    } catch (err) {
      console.error('[HomeTab] Load focus minutes failed:', err)
      this.todayFocusMinutes = 0
    }
  }
  
  /** 加载学习障碍分析数据 */
  private async loadObstacles(): Promise<void> {
    try {
      // 传递 context，以便从本地日记分析（作为 CloudDB 的 fallback）
      const context = getContext(this) as common.UIAbilityContext
      const obstacleData = await this.memoryVM.analyzeObstacles(7, context)
      // 只取前 3 个主要阻碍
      const items: ObstacleItem[] = []
      for (const o of obstacleData.slice(0, 3)) {
        const item: ObstacleItem = {
          keyword: o.keyword,
          count: o.count,
          percentage: o.percentage
        }
        items.push(item)
      }
      this.obstacles = items
      // 生成报告文本
      this.obstacleReport = await this.memoryVM.generateObstacleReport(7, context)
    } catch (err) {
      console.error('[HomeTab] Load obstacles failed:', err)
      this.obstacles = []
      this.obstacleReport = ''
    }
  }

  // ==================== 今日头条新闻 ====================

  /** 加载今日新闻 */
  private async loadNews(): Promise<void> {
    try {
      const news = await this.newsService.getTodayNews()
      this.newsList = news
      this.currentNewsIndex = 0
      this.newsScrollOffset = 0
      // 如果之前有定时器，先停止
      this.stopNewsAutoScroll()
      // 重新启动滚动
      if (news.length > 1) {
        this.startNewsAutoScroll()
      }
    } catch (err) {
      console.error('[HomeTab] Load news failed:', err)
      this.newsList = []
    }
  }

  /** 开始新闻自动滚动 */
  private startNewsAutoScroll(): void {
    if (this.newsTimer !== -1) return
    if (this.newsList.length <= 1) return

    this.newsTimer = setInterval(() => {
      this.currentNewsIndex = (this.currentNewsIndex + 1) % this.newsList.length
      animateTo({
        duration: 500,
        curve: Curve.EaseInOut
      }, () => {
        this.newsScrollOffset = -this.currentNewsIndex * 40 // 每条新闻高度约40
      })
    }, 4000) // 每4秒切换一条新闻
  }

  /** 停止新闻自动滚动 */
  private stopNewsAutoScroll(): void {
    if (this.newsTimer !== -1) {
      clearInterval(this.newsTimer)
      this.newsTimer = -1
    }
  }

  /** 点击新闻查看详情 */
  private async onNewsClick(news: NewsItem): Promise<void> {
    this.selectedNews = news
    this.showNewsDetail = true
    this.isLoadingNewsDetail = true
    
    try {
      // 获取新闻详情
      const detail = await this.newsService.getNewsDetail(news)
      if (detail) {
        this.newsDetailContent = detail.content
        this.newsDetailSummary = detail.summary
      } else {
        // 离线或获取失败时使用备用文案
        this.newsDetailSummary = news.summary || news.title
        this.newsDetailContent = `${news.title}\n\n暂无详细内容，请点击"查看原文"获取完整信息。`
      }
    } catch (err) {
      console.error('[HomeTab] 获取新闻详情失败:', err)
      // 离线备用：使用新闻基本信息
      this.newsDetailSummary = news.summary || news.title
      this.newsDetailContent = `${news.title}\n\n当前网络不可用，请稍后重试或点击"查看原文"。`
    } finally {
      this.isLoadingNewsDetail = false
    }
  }

  /** 关闭新闻详情弹窗 */
  private closeNewsDetail(): void {
    this.showNewsDetail = false
    this.selectedNews = null
    this.newsDetailContent = ''
    this.newsDetailSummary = ''
  }

  /** 跳转到新闻原文 */
  private openNewsUrl(url?: string): void {
    console.info('[HomeTab] openNewsUrl 被调用, URL:', url)
    
    if (!url || url.trim() === '') {
      console.warn('[HomeTab] URL为空')
      promptAction.showToast({ message: '暂无原文链接', duration: 2000 })
      return
    }
    
    console.info('[HomeTab] 准备打开新闻URL:', url)
    promptAction.showToast({ message: '正在打开原文...', duration: 1000 })
    
    // 先关闭弹窗
    this.closeNewsDetail()
    
    // 延迟一下再跳转，确保弹窗关闭动画完成
    setTimeout(() => {
      try {
        console.info('[HomeTab] 开始路由跳转, URL路径: view/pages/NewsWebViewPage')
        // 跳转到WebView页面显示新闻原文
        router.pushUrl({
          url: 'main/view/pages/NewsWebViewPage',
          params: {
            url: url,
            title: this.selectedNews?.title || '新闻原文'
          }
        }).then(() => {
          console.info('[HomeTab] 成功跳转到WebView页面')
        }).catch((err: Error) => {
          console.error('[HomeTab] 跳转失败:', JSON.stringify(err))
          const errorMsg = (err instanceof Error) ? err.message : String(err)
          promptAction.showToast({ message: '打开失败: ' + errorMsg, duration: 3000 })
        })
      } catch (err) {
        console.error('[HomeTab] 打开URL异常:', err)
        const errorMsg = (err instanceof Error) ? err.message : String(err)
        promptAction.showToast({ message: '打开失败: ' + errorMsg, duration: 3000 })
      }
      }, 300)
  }
  
  // 处理收藏逻辑（修复：使用超链接格式，包含标题和摘要）
  private async handleCollection(type: string, noteId?: string) {
     if (!this.selectedNews) return
     
     const title = this.selectedNews.title  // 使用新闻标题作为日记标题
     const newsUrl = this.selectedNews.url || ''
     const linkTitle = `📰 ${this.selectedNews.title}`  // 链接显示标题
     
     // 修复：使用超链接格式，包含标题、摘要和链接
     if (type === 'new') {
        try {
          // 先同步到云端
          await this.syncNewsToCloud('')
          
          // 构建格式化的内容：标题 + 来源信息 + 摘要 + 链接
          const formattedContent = `📰 ${title}\n\n来源: ${this.selectedNews.source} | 时间: ${this.selectedNews.publishTime}\n\n📝 摘要:\n${this.newsDetailSummary || '暂无摘要'}\n\n`
          
          // 关闭新闻详情弹窗
          this.closeNewsDetail()
          
          // 显示提示
          promptAction.showToast({ message: '正在创建日记...', duration: 1000 })
          
          // 跳转到日记编辑页面
          router.pushUrl({
            url: 'diary/view/pages/DetailPage',
            params: {
              initialTitle: title,  // 以新闻标题为日记标题
              initialContent: formattedContent,
              // 传递链接信息用于插入超链接
              initialLink: { title: linkTitle, url: newsUrl }
            }
          }).then(() => {
            console.info('[HomeTab] 成功跳转到日记编辑页面')
          }).catch((err: Error) => {
            console.error('[HomeTab] 跳转失败:', err)
            promptAction.showToast({ message: '跳转失败: ' + (err.message || String(err)), duration: 3000 })
          })
        } catch (err) {
          console.error('[HomeTab] 创建日记失败:', err)
          promptAction.showToast({ message: '创建日记失败: ' + (err as Error).message, duration: 2000 })
        }
     } else if (type === 'append' && noteId) {
        try {
           const context = getContext(this) as common.UIAbilityContext
           const notes = await PreferencesUtil.loadNotes(context)
           const targetNote = notes.find(n => n.id === noteId)
           
           if (targetNote) {
              // 修复：使用LinkItem格式插入超链接，同时添加新闻内容
              const linkItem = new LinkItem()
              linkItem.id = Date.now().toString()
              linkItem.title = linkTitle
              linkItem.url = newsUrl
              
              // 构建要追加的内容：分隔线 + 新闻标题 + 来源信息 + 摘要 + 链接
              const newsContent = `\n\n---\n\n📰 ${title}\n\n来源: ${this.selectedNews.source} | 时间: ${this.selectedNews.publishTime}\n\n📝 摘要:\n${this.newsDetailSummary || '暂无摘要'}\n\n🔗 `
              
              // 添加到日记的links数组
              if (!targetNote.links) {
                targetNote.links = []
              }
              targetNote.links.push(linkItem)
              
              // 更新内容文本（追加新闻信息）
              const currentContent = targetNote.content || ''
              targetNote.content = currentContent + newsContent
              
              // 同时更新contentBlocks（用于RichEditor恢复）
              if (!targetNote.contentBlocks) {
                targetNote.contentBlocks = []
              }
              // 添加文本块
              targetNote.contentBlocks.push(new TextBlock(newsContent))
              // 添加链接块
              targetNote.contentBlocks.push(new LinkBlock(linkItem.title, linkItem.url))
              
              // 更新richEditorSpans（用于编辑器恢复）
              try {
                interface SpanData {
                  type: string
                  value?: string
                  linkTitle?: string
                  linkUrl?: string
                }
                const spans: SpanData[] = targetNote.richEditorSpans ? JSON.parse(targetNote.richEditorSpans) as SpanData[] : []
                // 添加文本span
                spans.push({ type: 'text', value: newsContent })
                // 添加链接span
                spans.push({ type: 'link', linkTitle: linkItem.title, linkUrl: linkItem.url })
                targetNote.richEditorSpans = JSON.stringify(spans)
              } catch (e) {
                console.warn('[HomeTab] 更新richEditorSpans失败:', e)
              }
              
              targetNote.lastModifiedTime = Date.now()
              
              await PreferencesUtil.saveNote(context, targetNote)
              await this.syncNewsToCloud(noteId)  // 同步到云端并关联日记
              promptAction.showToast({ message: `已插入新闻到: ${targetNote.title || '无标题日记'}` })
              this.closeNewsDetail()
              
              // 导航到该日记
              setTimeout(() => {
                router.pushUrl({
                  url: 'diary/view/pages/DetailPage',
                  params: { noteId: noteId }
                })
              }, 300)
           }
        } catch (e) {
           console.error('Failed to append note', e)
           promptAction.showToast({ message: '添加失败' })
        }
     }
  }
  
  // 问题2修复：同步新闻收藏到CloudDB
  private async syncNewsToCloud(linkedDiaryId: string): Promise<void> {
    if (!this.selectedNews) return
    
    try {
      const userId: string = (AppStorage.get('currentUserId') as string) || ''
      if (!userId) return
      
      const collection = NewsCollection.create(userId, this.selectedNews.title, this.selectedNews.url || '')
      if (linkedDiaryId) {
        collection.linkToDiary(linkedDiaryId)
      }
      
      const cloudService = CloudDBService.getInstance()
      await cloudService.upsertNewsCollection(collection)
      console.info('[HomeTab] 新闻收藏已同步到云端')
    } catch (err) {
      console.warn('[HomeTab] 云端同步失败:', err)
      // 不影响本地操作
    }
  }

  newsCollectionDialogController: CustomDialogController | null = null
  
  private openCollectionDialog() {
     if (!this.selectedNews) return
     
     this.newsCollectionDialogController = new CustomDialogController({
        builder: NewsCollectionDialog({
           news: this.selectedNews,
           action: (type: 'new' | 'append', noteId?: string) => {
             this.handleCollection(type, noteId)
           }
        }),
        alignment: DialogAlignment.Center,
        customStyle: true
     })
     this.newsCollectionDialogController.open()
  }

  // 根据当前时间获取问候语
  private getGreeting(): string {
    const hour = new Date().getHours()
    if (hour >= 5 && hour < 12) {
      return 'Good Morning,'
    } else if (hour >= 12 && hour < 18) {
      return 'Good Afternoon,'
    } else if (hour >= 18 && hour < 22) {
      return 'Good Evening,'
    } else {
      return 'Good Night,'
    }
  }

  // 获取默认头像（使用昵称首字母或默认emoji）
  private getDefaultAvatar(): string {
    if (this.nickname && this.nickname.length > 0) {
      // 使用昵称首字符
      return this.nickname.charAt(0).toUpperCase()
    }
    // 默认emoji头像
    return '👤'
  }

  build() {
    Stack() {
      Column() {
        // ========== Header 顶部栏 (悬浮卡片风格) ==========
        Row() {
          Column() {
            Text(this.getGreeting())
              .fontSize(AppSizes.FONT_SM)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
            Text(this.nickname || '同学')
              .fontSize(AppSizes.FONT_2XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          // 头像/设置入口（更自然的样式）
          Stack({ alignContent: Alignment.Center }) {
            if (this.userAvatar && this.userAvatar.length <= 2) {
              // Emoji 头像
              Text(this.userAvatar)
                .fontSize(22)
            } else if (this.userAvatar) {
              // 图片头像
              Image(this.userAvatar)
                .width(38)
                .height(38)
                .borderRadius(19)
                .objectFit(ImageFit.Cover)
            } else {
              // 默认头像（昵称首字母或默认emoji）
              Text(this.getDefaultAvatar())
                .fontSize(this.getDefaultAvatar().length === 1 ? 18 : 22)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_SECONDARY)
            }
          }
          .width(38)
          .height(38)
          .borderRadius(19)
          // 深色模式使用更亮的底色与浅色描边，确保默认头像清晰
          .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.14)' : 'rgba(0, 0, 0, 0.04)')
          .border({
            width: 1,
            color: this.isDarkMode ? 'rgba(255, 255, 255, 0.18)' : 'rgba(0, 0, 0, 0.04)'
          })
          .onClick(() => {
            router.pushUrl({ url: 'profile/view/pages/ProfilePage' })
          })
        }
        .width('100%')
        .padding({
          top: AppSizes.SPACE_4XL,
          left: AppSizes.SPACE_LG,
          right: AppSizes.SPACE_LG,
          bottom: AppSizes.SPACE_LG
        })

        // ========== 今日头条 ==========
        if (this.newsList.length > 0) {
          this.renderNewsTicker()
        }

        // ========== 内容区 ==========
        Scroll() {
          Column({ space: AppSizes.SPACE_LG }) {
            // 1. 目标卡片 (Hero Card) - 始终作为大块展示
            Column() {
              GoalKeeperCard({ goalInfo: this.goalInfo })
            }
            .width('100%')

            // 2. 快捷入口 (Quick Actions)
            QuickActionsGrid()

            // 3. 本周学习障碍提示卡片
            if (this.obstacles.length > 0) {
              ObstacleHintCard({ obstacles: this.obstacles, obstacleReport: this.obstacleReport })
            }

            // 4. 今日待办 (Task List)
            this.TodayTasksCard()

            Blank().height(AppSizes.SPACE_5XL)
          }
          .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
          .constraintSize({ maxWidth: this.isTablet ? 900 : '100%' })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      // 新闻详情弹窗
      if (this.showNewsDetail && this.selectedNews) {
        this.renderNewsDetailDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY)
  }

  // 获取格式化的日期字符串
  private getFormattedDate(): string {
    const today = new Date()
    return this.newsService.formatDate(today)
  }

  // ========== 今日头条新闻滚动 ==========
  @Builder
  renderNewsTicker() {
    Column({ space: 0 }) {
      // 标题和日期
      Row({ space: AppSizes.SPACE_SM }) {
        Text('📰')
          .fontSize(16)
        Text('今日头条')
          .fontSize(AppSizes.FONT_SM)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
        Text(this.getFormattedDate())
          .fontSize(AppSizes.FONT_XS)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
        Blank()
      }
      .width('100%')
      .padding({ left: AppSizes.SPACE_MD, right: AppSizes.SPACE_MD, top: AppSizes.SPACE_SM, bottom: AppSizes.SPACE_XS })
      
      // 新闻滚动区域
      Stack() {
        Column() {
          ForEach(this.newsList, (news: NewsItem, index: number) => {
            Row({ space: AppSizes.SPACE_XS }) {
              Text('•')
                .fontSize(12)
                .fontColor(AppColors.ACCENT)
              Text(news.title)
                .fontSize(AppSizes.FONT_SM)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(news.source)
                .fontSize(AppSizes.FONT_XS)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
            }
            .width('100%')
            .height(40)
            .padding({ left: AppSizes.SPACE_MD, right: AppSizes.SPACE_MD })
            .onClick(() => {
              this.onNewsClick(news)
            })
          }, (news: NewsItem) => news.id)
        }
        .width('100%')
        .translate({ y: this.newsScrollOffset })
      }
      .width('100%')
      .height(40)
      .clip(true)
    }
    .width('100%')
    .linearGradient(this.isDarkMode ? {
      angle: 135,
      colors: [[AppColors.BG_DARK_SECONDARY, 0], [AppColors.BG_DARK_TERTIARY, 1]]
    } : {
      angle: 135,
      colors: [['#FFFBF0', 0], ['#FEF3C7', 1]]  // 暖黄渐变
    })
    .borderRadius(AppSizes.RADIUS_MD)
    .margin({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG, bottom: AppSizes.SPACE_MD })
    .shadow(AppShadows.SHADOW_SM)
  }

  // ========== 新闻详情弹窗 ==========
  @Builder
  renderNewsDetailDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {
          this.closeNewsDetail()
        })

      // 弹窗内容
      Column({ space: AppSizes.SPACE_MD }) {
        // 标题栏
        Row({ space: AppSizes.SPACE_SM }) {
          Text('📰')
            .fontSize(20)
          Text('新闻详情')
            .fontSize(AppSizes.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
            .layoutWeight(1)
          Text('×')
            .fontSize(28)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
            .onClick(() => {
              this.closeNewsDetail()
            })
        }
        .width('100%')
        .padding({ bottom: AppSizes.SPACE_SM })

        // 新闻标题
        if (this.selectedNews) {
          Text(this.selectedNews.title)
            .fontSize(AppSizes.FONT_MD)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
            .width('100%')
            .lineHeight(24)
        }

        // 新闻来源和时间
        if (this.selectedNews) {
          Row({ space: AppSizes.SPACE_SM }) {
            Text(this.selectedNews.source)
              .fontSize(AppSizes.FONT_XS)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
            Text('•')
              .fontSize(AppSizes.FONT_XS)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
            Text(this.selectedNews.publishTime)
              .fontSize(AppSizes.FONT_XS)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
          }
          .width('100%')
        }

        // 分割线
        Divider()
          .color(this.isDarkMode ? AppColors.DIVIDER_DARK : AppColors.DIVIDER)
          .margin({ top: AppSizes.SPACE_SM, bottom: AppSizes.SPACE_SM })

        // 新闻摘要
        Scroll() {
          Column({ space: AppSizes.SPACE_MD }) {
            if (this.isLoadingNewsDetail) {
              Row() {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color(AppColors.ACCENT)
                Text('加载中...')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
                  .margin({ left: AppSizes.SPACE_SM })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: AppSizes.SPACE_2XL, bottom: AppSizes.SPACE_2XL })
            } else {
              // 摘要标题
              Text('新闻摘要')
                .fontSize(AppSizes.FONT_SM)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
              
              // 摘要内容
              Text(this.newsDetailSummary || '暂无摘要')
                .fontSize(AppSizes.FONT_SM)
                .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
                .lineHeight(22)
                .width('100%')

              // 详细内容
              if (this.newsDetailContent && this.newsDetailContent !== '暂无详细内容') {
                Text('详细内容')
                  .fontSize(AppSizes.FONT_SM)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
                  .margin({ top: AppSizes.SPACE_MD })
                
                Text(this.newsDetailContent)
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
                  .lineHeight(22)
                  .width('100%')
              }
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)

        // 操作按钮
        Row({ space: AppSizes.SPACE_MD }) {
          Button('关闭')
            .type(ButtonType.Normal)
            .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_TERTIARY : AppColors.BG_TERTIARY)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
            .layoutWeight(1)
            .onClick(() => {
              this.closeNewsDetail()
            })

          // Save to Diary Button
          Button('收藏到日记')
            .type(ButtonType.Normal)
            .backgroundColor(AppColors.ACCENT)
            .fontColor(AppColors.TEXT_WHITE)
            .layoutWeight(1)
            .onClick(() => {
              this.openCollectionDialog()
            })

          if (this.selectedNews?.url) {
            Button('查看原文')
              .type(ButtonType.Normal)
              .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_TERTIARY : AppColors.BG_TERTIARY)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
              .layoutWeight(1)
              .onClick(() => {
                console.info('[HomeTab] 点击查看原文按钮, URL:', this.selectedNews?.url)
                this.openNewsUrl(this.selectedNews?.url)
              })
          } else {
            // 调试：如果没有URL，显示一个提示
            Button('查看原文')
              .type(ButtonType.Normal)
              .backgroundColor(AppColors.ACCENT)
              .fontColor(AppColors.TEXT_WHITE)
              .layoutWeight(1)
              .enabled(false)
              .opacity(0.5)
          }
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxHeight: '80%' })
      .padding(AppSizes.SPACE_LG)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)
      .borderRadius(AppSizes.RADIUS_XL)
      .shadow(AppShadows.SHADOW_LG)
    }
    .width('100%')
    .height('100%')
    .zIndex(1000)
  }

  // ========== 今日待办 ==========
  @Builder
  TodayTasksCard() {
    Column() {
      Row() {
        Text('今日待办')
          .fontSize(AppSizes.FONT_LG)
          .fontWeight(FontWeight.Bold)
        Blank()
        // 添加普通待办（+）
        Button(undefined, { type: ButtonType.Normal }) {
          Text('+')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(16)
        .margin({ right: AppSizes.SPACE_SM })
        .onClick(() => {
          this.newTaskTitle = ''
          this.isPomodoroSheet = false
          this.showAddSheet = true
        })
        // 添加番茄待办（🍅）
        Button(undefined, { type: ButtonType.Normal }) {
          Text('🍅')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.ACCENT_BG)
        .borderRadius(16)
        .onClick(() => {
          this.resetPomodoroForm()
          this.isPomodoroSheet = true
          this.showAddSheet = true
        })
      }
      .width('100%')
      .padding({ bottom: AppSizes.SPACE_MD })

      if (this.todayTasks.length === 0) {
        Column() {
          Text('☕️')
            .fontSize(32)
            .margin({ bottom: 8 })
          Text('暂无待办，享受生活吧')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_TERTIARY)
          
          // 快捷添加按钮
          Button('添加待办')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.ACCENT)
            .backgroundColor(AppColors.ACCENT_BG)
            .borderRadius(AppSizes.RADIUS_MD)
            .height(36)
            .margin({ top: AppSizes.SPACE_MD })
            .onClick(() => {
              this.isPomodoroSheet = false
              this.showAddSheet = true
            })
        }
        .width('100%')
        .padding(AppSizes.SPACE_XL)
        .alignItems(HorizontalAlign.Center)
      } else {
        // Task List - 显示所有待办（未完成在前，已完成在后）
        Column({ space: 8 }) {
          // 未完成的番茄钟待办
          if (this.pomodoroTasks.length > 0) {
            ForEach(this.pomodoroTasks, (task: Task) => {
              this.renderTaskItem(task, true)
            }, (task: Task) => task.id)
          }
          
          // 未完成的普通待办
          if (this.normalTasks.length > 0) {
            ForEach(this.normalTasks, (task: Task) => {
              this.renderTaskItem(task, false)
            }, (task: Task) => task.id)
          }
          
          // 已完成的任务（移到最下方）
          if (this.getCompletedTasks().length > 0) {
            // 分割线
            Divider()
              .strokeWidth(1)
              .color(AppColors.DIVIDER)
              .margin({ top: 8, bottom: 8 })
            
            ForEach(this.getCompletedTasks(), (task: Task) => {
              this.renderTaskItem(task, task.estimatedPomodoros > 0)
            }, (task: Task) => task.id)
          }
        }
      }
    }
    .width('100%')
    .padding(AppSizes.SPACE_LG)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
    .bindSheet($$this.showAddSheet, this.isPomodoroSheet ? this.AddPomodoroTaskSheet() : this.AddTaskSheet(), {
      height: this.isPomodoroSheet ? 600 : 400,
      showClose: true,
      dragBar: true,
      title: { title: this.isPomodoroSheet ? '添加番茄钟待办' : '添加普通待办' }
    })
  }

  // 渲染单个待办项
  @Builder
  renderTaskItem(task: Task, isPomodoro: boolean) {
    Row({ space: 12 }) {
      // 勾选框
      Checkbox({ name: task.id })
        .select(task.isCompleted)
        .selectedColor(isPomodoro ? AppColors.ACCENT : AppColors.SUCCESS)
        .onChange(async (value: boolean) => {
          await this.toggleTaskComplete(task, value)
        })

      Column({ space: 6 }) {
        // 标题 + 标签
        Row({ space: 6 }) {
          Text(task.title)
            .fontSize(AppSizes.FONT_MD)
            .fontColor(task.isCompleted ? AppColors.TEXT_HINT : AppColors.TEXT_PRIMARY)
            .decoration({ type: task.isCompleted ? TextDecorationType.LineThrough : TextDecorationType.None })
            .layoutWeight(1)

          // 任务类型标签
          Text(isPomodoro ? '番茄钟' : '普通')
            .fontSize(10)
            .fontColor(isPomodoro ? AppColors.TEXT_WHITE : AppColors.TEXT_SECONDARY)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(isPomodoro ? AppColors.ACCENT : AppColors.BG_TERTIARY)
            .borderRadius(6)
        }

        // 如果是番茄钟待办，显示番茄数
        if (isPomodoro && task.estimatedPomodoros > 0) {
          Row({ space: 4 }) {
            Text('🍅')
              .fontSize(12)
            Text(`${task.completedPomodoros}/${task.estimatedPomodoros} 番茄`)
              .fontSize(AppSizes.FONT_XS)
              .fontColor(AppColors.TEXT_SECONDARY)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 删除按钮
      Text('✕')
        .fontSize(14)
        .fontColor(AppColors.TEXT_HINT)
        .onClick(async () => {
          await this.deleteTask(task)
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(isPomodoro ? AppColors.ACCENT_BG : AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_MD)
    .margin({ bottom: 8 })
    .onClick(async () => {
      await this.toggleTaskComplete(task, !task.isCompleted)
    })
    .justifyContent(FlexAlign.Start)
  }

  // 切换待办完成状态
  private async toggleTaskComplete(task: Task, completed: boolean): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      task.isCompleted = completed
      if (completed) {
        task.completedAt = Date.now()
        // 如果是番茄钟待办，记录到专注统计
        if (task.estimatedPomodoros > 0) {
          await this.recordTaskCompletion(task)
        }
        // 保存到历史，便于报表展示
        await this.taskService.saveCompletedTasks(context, [task])
      } else {
        task.completedAt = undefined
      }
      await this.taskService.updateTask(context, task)
      await this.loadTasks()
      await this.loadTodayFocusMinutes()
      AppStorage.setOrCreate('tasksUpdatedAt', Date.now())
      
      // 移除自动清空逻辑，保留已完成任务显示
      if (completed) {
        promptAction.showToast({ message: '任务已完成', duration: 1500 })
      }
    } catch (err) {
      console.error('[HomeTab] Toggle task failed:', err)
    }
  }

  // 记录任务完成到专注统计
  private async recordTaskCompletion(task: Task): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const today = new Date().toISOString().split('T')[0]
      const todayRecord = await this.recordService.getRecordByDate(context, today)
      
      // 如果任务完成，使用预计番茄数；否则使用已完成番茄数
      const pomodoros: number = task.isCompleted ? task.estimatedPomodoros : task.completedPomodoros
      
      // 更新今日统计
      todayRecord.pomodoros = (todayRecord.pomodoros || 0) + pomodoros
      todayRecord.focusMinutes = (todayRecord.focusMinutes || 0) + (pomodoros * 25) // 每个番茄25分钟
      
      // 添加完成的任务记录
      if (!todayRecord.records) {
        todayRecord.records = []
      }
      todayRecord.records.push({
        id: `session_${Date.now()}`,
        taskId: task.id,
        taskTitle: task.title,
        duration: pomodoros * 25,
        startTime: task.createdAt,
        endTime: Date.now()
      })
      
      // 使用saveAllRecords保存记录
      const allRecords = await this.recordService.getAllRecords(context)
      allRecords.set(today, todayRecord)
      await this.recordService.saveAllRecords(context, allRecords)
    } catch (err) {
      console.error('[HomeTab] Record task completion failed:', err)
    }
  }

  // 获取已完成的任务列表
  private getCompletedTasks(): Task[] {
    return this.todayTasks.filter((t: Task) => t.isCompleted)
  }

  // 删除待办
  private async deleteTask(task: Task): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      await this.taskService.deleteTask(context, task.id)
      await this.loadTasks()
      AppStorage.setOrCreate('tasksUpdatedAt', Date.now())
      promptAction.showToast({ message: '待办已删除' })
    } catch (err) {
      console.error('[HomeTab] Delete task failed:', err)
    }
  }

  // ========== 本周学习障碍提示卡片 ==========
  @Builder
  ObstacleHintCard() {
    Column({ space: AppSizes.SPACE_SM }) {
      Row() {
        Text('🚧')
          .fontSize(20)
        Text('本周学习障碍')
          .fontSize(AppSizes.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
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
      if (this.obstacleReport) {
        Row() {
          Text('💡')
            .fontSize(12)
          Text(this.obstacleReport)
            .fontSize(AppSizes.FONT_XS)
            .fontColor(AppColors.TEXT_SECONDARY)
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
    if (index === 0) return AppColors.ERROR     // 红色 - 最严重
    if (index === 1) return '#FF9800'  // 橙色
    if (index === 2) return '#FFC107'           // 黄色
    return AppColors.TEXT_TERTIARY              // 灰色
  }

  // ========== 添加普通待办弹窗 ==========
  @Builder
  AddTaskSheet() {
    Column({ space: AppSizes.SPACE_LG }) {
      TextInput({ placeholder: '输入待办内容...', text: this.newTaskTitle })
        .fontSize(AppSizes.FONT_MD)
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(AppSizes.RADIUS_MD)
        .height(48)
        .onChange((value: string) => {
          this.newTaskTitle = value
        })

      Button('确认添加')
        .width('100%')
        .height(48)
        .fontSize(AppSizes.FONT_MD)
        .fontColor(AppColors.TEXT_WHITE)
        .backgroundColor(AppColors.ACCENT)
        .borderRadius(AppSizes.RADIUS_LG)
        .onClick(async () => {
          if (this.newTaskTitle.trim()) {
            await this.addNormalTask()
          } else {
            promptAction.showToast({ message: '请输入待办内容' })
          }
        })
    }
    .width('100%')
    .padding(AppSizes.SPACE_2XL)
  }

  // ========== 添加番茄钟待办弹窗 ==========
  @Builder
  AddPomodoroTaskSheet() {
    Column({ space: AppSizes.SPACE_LG }) {
      // 任务名称
      TextInput({ placeholder: '输入待办内容...', text: this.newTaskTitle })
        .fontSize(AppSizes.FONT_MD)
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(AppSizes.RADIUS_MD)
        .height(48)
        .onChange((value: string) => {
          this.newTaskTitle = value
        })

      // 预计番茄数
      Row({ space: 12 }) {
        Text('预计番茄数:')
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
          TextInput({ text: this.newTaskEstimated.toString() })
          .onChange((value: string) => {
            const num = parseInt(value)
            if (!isNaN(num) && num > 0) {
              this.newTaskEstimated = num
            }
          })
          .width(80)
          .height(40)
          .backgroundColor(AppColors.BG_TERTIARY)
          .borderRadius(AppSizes.RADIUS_MD)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 单个番茄时长（分钟）
      Row({ space: 12 }) {
        Text('单个番茄时长(分钟):')
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
        TextInput({ text: this.newTaskDuration.toString() })
          .onChange((value: string) => {
            const num = parseInt(value)
            if (!isNaN(num) && num > 0) {
              this.newTaskDuration = num
            }
          })
          .width(80)
          .height(40)
          .backgroundColor(AppColors.BG_TERTIARY)
          .borderRadius(AppSizes.RADIUS_MD)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 优先级选择
      Row({ space: 12 }) {
        Text('优先级:')
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
        Row({ space: 8 }) {
          Button('低')
            .fontSize(AppSizes.FONT_SM)
            .width(60)
            .height(32)
            .borderRadius(16)
            .fontColor(this.newTaskPriority === TaskPriority.LOW ? AppColors.TEXT_WHITE : AppColors.TEXT_SECONDARY)
            .backgroundColor(this.newTaskPriority === TaskPriority.LOW ? AppColors.SUCCESS : AppColors.BG_TERTIARY)
            .onClick(() => {
              this.newTaskPriority = TaskPriority.LOW
              this.newTaskEstimated = 1
            })
          Button('中')
            .fontSize(AppSizes.FONT_SM)
            .width(60)
            .height(32)
            .borderRadius(16)
            .fontColor(this.newTaskPriority === TaskPriority.MEDIUM ? AppColors.TEXT_WHITE : AppColors.TEXT_SECONDARY)
            .backgroundColor(this.newTaskPriority === TaskPriority.MEDIUM ? AppColors.WARNING : AppColors.BG_TERTIARY)
            .onClick(() => {
              this.newTaskPriority = TaskPriority.MEDIUM
              this.newTaskEstimated = 2
            })
          Button('高')
            .fontSize(AppSizes.FONT_SM)
            .width(60)
            .height(32)
            .borderRadius(16)
            .fontColor(this.newTaskPriority === TaskPriority.HIGH ? AppColors.TEXT_WHITE : AppColors.TEXT_SECONDARY)
            .backgroundColor(this.newTaskPriority === TaskPriority.HIGH ? AppColors.ERROR : AppColors.BG_TERTIARY)
            .onClick(() => {
              this.newTaskPriority = TaskPriority.HIGH
              this.newTaskEstimated = 3
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Button('确认添加')
        .width('100%')
        .height(48)
        .fontSize(AppSizes.FONT_MD)
        .fontColor(AppColors.TEXT_WHITE)
        .backgroundColor(AppColors.ACCENT)
        .borderRadius(AppSizes.RADIUS_LG)
        .onClick(async () => {
          if (this.newTaskTitle.trim()) {
            await this.addPomodoroTask()
          } else {
            promptAction.showToast({ message: '请输入待办内容' })
          }
        })
    }
    .width('100%')
    .padding(AppSizes.SPACE_2XL)
  }

  // 添加普通待办
  private async addNormalTask(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const newTask: Task = {
        id: `task_${Date.now()}`,
        title: this.newTaskTitle.trim(),
        estimatedPomodoros: 0, // 普通待办不需要番茄数
        completedPomodoros: 0,
        isCompleted: false,
        priority: TaskPriority.MEDIUM,
        createdAt: Date.now()
      }
      await this.taskService.addTask(context, newTask)
      AppStorage.setOrCreate('tasksUpdatedAt', Date.now())
      this.newTaskTitle = ''
      this.showAddSheet = false
      await this.loadTasks()
      promptAction.showToast({ message: '待办已添加' })
    } catch (err) {
      console.error('[HomeTab] Add normal task failed:', err)
      promptAction.showToast({ message: '添加失败，请重试' })
    }
  }

  // 添加番茄钟待办
  private async addPomodoroTask(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const newTask: Task = {
        id: `task_${Date.now()}`,
        title: this.newTaskTitle.trim(),
        estimatedPomodoros: this.newTaskEstimated,
        completedPomodoros: 0,
        isCompleted: false,
        priority: this.newTaskPriority,
        createdAt: Date.now(),
        plannedMinutes: this.newTaskEstimated * this.newTaskDuration
      }
      await this.taskService.addTask(context, newTask)
      AppStorage.setOrCreate('tasksUpdatedAt', Date.now())
      this.resetPomodoroForm()
      this.showAddSheet = false
      await this.loadTasks()
      promptAction.showToast({ message: '番茄钟待办已添加' })
    } catch (err) {
      console.error('[HomeTab] Add pomodoro task failed:', err)
      promptAction.showToast({ message: '添加失败，请重试' })
    }
  }

  /** 重置番茄待办表单到默认值（中优先级=2番茄） */
  private resetPomodoroForm(): void {
    this.newTaskTitle = ''
    this.newTaskPriority = TaskPriority.MEDIUM
    this.newTaskEstimated = 2
    this.newTaskDuration = 25
  }
}

@CustomDialog
struct NewsCollectionDialog {
  controller: CustomDialogController
  news: NewsItem | null = null
  action: (type: 'new' | 'append', noteId?: string) => void = () => {}
  
  @State notes: NoteItem[] = []
  @State selectedNoteId: string = 'new'
  @State isLoading: boolean = true

  async aboutToAppear() {
     try {
       const context = getContext(this) as common.UIAbilityContext
       const loaded = await PreferencesUtil.loadNotes(context)
       loaded.sort((a, b) => (b.lastModifiedTime || 0) - (a.lastModifiedTime || 0))
       this.notes = loaded
     } catch (e) {
       console.error('Failed to load notes', e)
     } finally {
       this.isLoading = false
     }
  }

  build() {
    Column() {
      Text('收藏到日记')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 24, bottom: 8 })
        .fontColor(AppColors.TEXT_PRIMARY)
      
      Text('请选择保存方式')
        .fontSize(14)
        .fontColor(AppColors.TEXT_TERTIARY)
        .margin({ bottom: 20 })

      Column({ space: 12 }) {
          // Option 1: Create New
          Row() {
            Column() {
                Text('新建日记').fontSize(16).fontColor(AppColors.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                Text('创建一篇新的日记包含此新闻').fontSize(12).fontColor(AppColors.TEXT_TERTIARY).margin({ top: 4 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            
            Radio({ value: 'new', group: 'collectionType' })
              .checked(this.selectedNoteId === 'new')
              .onChange((isChecked) => {
                 if(isChecked) this.selectedNoteId = 'new'
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.selectedNoteId === 'new' ? AppColors.BG_SECONDARY : AppColors.BG_TERTIARY)
          .borderRadius(12)
          .onClick(() => this.selectedNoteId = 'new')
          .animation({ duration: 200 })

          // Option 2: Append to existing
          if (this.notes.length > 0) {
              Text('或者添加到最近的日记:')
                .fontSize(12)
                .fontColor(AppColors.TEXT_TERTIARY)
                .width('100%')
                .margin({ top: 8, bottom: 4 })

              List({ space: 8 }) {
                 ForEach(this.notes.slice(0, 3), (note: NoteItem) => {
                    ListItem() {
                       Row() {
                         Column() {
                           Text(note.title || '无标题日记').fontSize(15).fontColor(AppColors.TEXT_PRIMARY).maxLines(1).textOverflow({overflow: TextOverflow.Ellipsis})
                           Text(new Date(note.createTime).toLocaleDateString()).fontSize(12).fontColor(AppColors.TEXT_HINT).margin({ top: 4 })
                         }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                         
                         Radio({ value: note.id, group: 'collectionType' })
                           .checked(this.selectedNoteId === note.id)
                           .onChange((isChecked) => {
                              if(isChecked) this.selectedNoteId = note.id
                           })
                       }
                       .width('100%')
                       .padding(12)
                       .backgroundColor(this.selectedNoteId === note.id ? AppColors.BG_SECONDARY : AppColors.BG_TERTIARY)
                       .borderRadius(10)
                       .onClick(() => this.selectedNoteId = note.id)
                    }
                 })
              }
              .height(180)
          }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // Buttons
      Row({ space: 16 }) {
         Button('取消')
           .onClick(()=>this.controller.close())
           .backgroundColor(AppColors.BG_TERTIARY)
           .fontColor(AppColors.TEXT_SECONDARY)
           .layoutWeight(1)
           
         Button('确定')
           .onClick(() => {
             if (this.selectedNoteId === 'new') {
                this.action('new')
             } else {
                this.action('append', this.selectedNoteId)
             }
             this.controller.close()
           })
           .backgroundColor(AppColors.ACCENT)
           .fontColor(AppColors.TEXT_WHITE)
           .layoutWeight(1)
      }
      .width('100%')
      .padding(24)
    }
    .backgroundColor(AppColors.BG_PRIMARY)
    .borderRadius(24)
    .width('90%')
  }
}
