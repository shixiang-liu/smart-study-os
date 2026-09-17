// 目标管理页面 - 创建、查看、管理学习目标
import { promptAction, router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import window from '@ohos.window'
import { AppColors, AppSizes, AppShadows, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'
import { IconPaths } from '../../../common/utils/IconPaths'
import { GoalViewModel, GoalStatus, GoalCountdown } from '../../../goal/viewmodel/GoalViewModel'
import { Goal } from '../../../goal/model/Goal'

@Entry
@Component
struct GoalManagement {
  @State goals: Goal[] = []
  @State isLoading: boolean = true
  @State showAddDialog: boolean = false
  @State newGoalTitle: string = ''
  @State newGoalDate: Date = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)  // 默认30天后
  @State isSelectionMode: boolean = false
  @State selectedGoalIds: Set<string> = new Set()
  @State lastDeleteHintTime: number = 0
  @State topSafeHeight: number = 0
  @State bottomSafeHeight: number = 0

  private viewModel: GoalViewModel = new GoalViewModel()

  async aboutToAppear() {
    await this.setFullScreen()
    await this.loadGoals()
  }
  
  async setFullScreen() {
    try {
      const windowClass = await window.getLastWindow(getContext(this))
      await windowClass.setWindowLayoutFullScreen(true)
      const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      this.topSafeHeight = px2vp(avoidArea.topRect.height)
      this.bottomSafeHeight = px2vp(avoidArea.bottomRect.height)
    } catch (e) {
      this.topSafeHeight = 44
      this.bottomSafeHeight = 34
    }
  }

  private async loadGoals(): Promise<void> {
    this.isLoading = true
    try {
      this.goals = await this.viewModel.getAllGoals()
    } catch (err) {
      console.error('加载目标失败:', err)
    }
    this.isLoading = false
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 顶部安全区
          Column()
            .width('100%')
            .height(this.topSafeHeight)
            .backgroundColor(AppColors.BG_PRIMARY)
          
          // 顶部标题栏
          Row() {
            Row() {
              Text('‹')
                .fontSize(28)
                .fontColor(AppColors.TEXT_PRIMARY)
                .fontWeight(FontWeight.Normal)
                .offset({ y: -2 })
            }
            .width(40)
            .height(40)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(AppColors.BG_SECONDARY)
            .borderRadius(20)
            .shadow(AppShadows.SHADOW_XS)
            .onClick(() => {
              if (this.isSelectionMode) {
                this.isSelectionMode = false
                this.selectedGoalIds.clear()
              } else {
                router.back()
              }
            })

            Text(this.isSelectionMode ? `已选 ${this.selectedGoalIds.size} 项` : '目标管理')
              .fontSize(AppSizes.FONT_XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ left: AppSizes.SPACE_LG })

            Blank()

            // 多选/全选操作
            if (this.isSelectionMode) {
              Row({ space: AppSizes.SPACE_MD }) {
                Text('全选')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(AppColors.ACCENT)
                  .onClick(() => {
                    this.goals.forEach(g => {
                      if (g.id) this.selectedGoalIds.add(g.id)
                    })
                    this.selectedGoalIds = new Set(this.selectedGoalIds)
                  })
                
                Text('删除')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(this.selectedGoalIds.size > 0 ? AppColors.ERROR : AppColors.TEXT_HINT)
                  .onClick(() => {
                    if (this.selectedGoalIds.size === 0) return
                    
                    AlertDialog.show({
                      title: '删除目标',
                      message: `确定要删除选中的 ${this.selectedGoalIds.size} 个目标吗？`,
                      primaryButton: {
                        value: '取消',
                        action: () => {}
                      },
                      secondaryButton: {
                        value: '删除',
                        fontColor: AppColors.ERROR,
                        action: async () => {
                          for (const id of this.selectedGoalIds) {
                            await this.viewModel.deleteGoal(id)
                          }
                          this.selectedGoalIds.clear()
                          this.isSelectionMode = false
                          // 强制触发首页刷新
                          AppStorage.setOrCreate('goalsRefreshFlag', Date.now())
                          await this.loadGoals()
                          promptAction.showToast({ message: '删除成功' })
                        }
                      }
                    })
                  })
              }
            } else {
              Text('管理')
                .fontSize(AppSizes.FONT_SM)
                .fontColor(AppColors.ACCENT)
                .onClick(() => {
                  this.isSelectionMode = true
                })
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })

          // 目标列表
          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(40)
                .height(40)
              Text('加载中...')
                .fontSize(AppSizes.FONT_SM)
                .fontColor(AppColors.TEXT_TERTIARY)
                .margin({ top: AppSizes.SPACE_MD })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.goals.length === 0) {
            this.EmptyState()
          } else {
            this.GoalList()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(AppColors.BG_PRIMARY)

        // 美化的添加按钮
        Row() {
          Button() {
            Row() {
              Text('+')
                .fontSize(24)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_WHITE)
              Text('添加目标')
                .fontSize(AppSizes.FONT_MD)
                .fontColor(AppColors.TEXT_WHITE)
                .margin({ left: AppSizes.SPACE_SM })
            }
          }
          .height(50)
          .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_XL })
          .borderRadius(25)
          .borderRadius(25)
          .backgroundColor(AppColors.ACCENT)
          .linearGradient(AppGradients.PRIMARY_BTN)
          .shadow(AppShadows.SHADOW_MD)
          .onClick(() => {
            this.showAddDialog = true
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: '100%' })
        .translate({ x: 0, y: -90 })
      }
    }
    .hideTitleBar(true)
    .bindSheet($$this.showAddDialog, this.AddGoalSheet(), {
      height: 650,
      showClose: true,
      dragBar: true,
      title: { title: '添加新目标' }
    })
  }

  @Builder
  EmptyState() {
    Column() {
      // Unicode 符号代替 emoji
      Text('◎')
        .fontSize(64)
        .fontColor(AppColors.TEXT_TERTIARY)

      Text('还没有目标')
        .fontSize(AppSizes.FONT_LG)
        .fontColor(AppColors.TEXT_SECONDARY)
        .margin({ top: AppSizes.SPACE_LG })

      Text('点击下方按钮添加你的第一个目标')
        .fontSize(AppSizes.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .margin({ top: AppSizes.SPACE_SM })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  GoalList() {
    Scroll() {
      Column({ space: AppSizes.SPACE_MD }) {
        // 进行中的目标
        ForEach(this.goals.filter(g => g.status === GoalStatus.IN_PROGRESS), (goal: Goal) => {
          this.GoalCard(goal)
        })

        // 已完成的目标
        if (this.goals.filter(g => g.status === GoalStatus.COMPLETED).length > 0) {
          Text('已完成')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: AppSizes.SPACE_LG })

          ForEach(this.goals.filter(g => g.status === GoalStatus.COMPLETED), (goal: Goal) => {
            this.GoalCard(goal)
          })
        }

        Blank().height(120)
      }
      .padding({
        left: AppSizes.SPACE_2XL,
        right: AppSizes.SPACE_2XL,
        top: AppSizes.SPACE_LG
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  GoalCard(goal: Goal) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Column() {
            Text(goal.title ?? '未命名目标')
              .fontSize(AppSizes.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(goal.status === GoalStatus.COMPLETED ? AppColors.TEXT_TERTIARY : AppColors.TEXT_PRIMARY)
              .decoration({
                type: goal.status === GoalStatus.COMPLETED ? TextDecorationType.LineThrough : TextDecorationType.None
              })

          Text(this.formatDeadline(goal.deadline ?? 0))
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_TERTIARY)
            .margin({ top: AppSizes.SPACE_XS })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (goal.status === GoalStatus.IN_PROGRESS) {
          Column() {
            Text(this.getDaysLeft(goal.deadline ?? 0).toString())
              .fontSize(AppSizes.FONT_2XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getDaysLeft(goal.deadline ?? 0) <= 3 ? AppColors.ERROR : AppColors.ACCENT)

            Text('天')
              .fontSize(AppSizes.FONT_XS)
              .fontColor(AppColors.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Center)
        } else {
          Text('✓')
            .fontSize(24)
            .fontColor(AppColors.SUCCESS)
        }
      }
      .width('100%')

      // 进度条
      if (goal.status === GoalStatus.IN_PROGRESS) {
        Progress({ value: this.getProgress(goal), total: 100 })
          .color(this.getDaysLeft(goal.deadline ?? 0) <= 3 ? AppColors.ERROR : AppColors.ACCENT)
          .backgroundColor(AppColors.BG_TERTIARY)
          .height(4)
          .width('100%')
          .margin({ top: AppSizes.SPACE_MD })
      }

      // 操作按钮
      if (goal.status === GoalStatus.IN_PROGRESS && !this.isSelectionMode) {
        Row({ space: AppSizes.SPACE_MD }) {
          Button('完成')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.SUCCESS)
            .backgroundColor(AppColors.SUCCESS_BG)
            .borderRadius(AppSizes.RADIUS_SM)
            .height(32)
            .onClick(async () => {
              const context = getContext(this) as common.UIAbilityContext
              await this.viewModel.completeGoal(goal.id ?? '', context)
              await this.loadGoals()
              promptAction.showToast({ message: '恭喜完成目标！' })
            })

          Button('删除')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.ERROR)
            .backgroundColor(AppColors.ERROR_BG)
            .borderRadius(AppSizes.RADIUS_SM)
            .height(32)
            .onClick(async () => {
              AlertDialog.show({
                title: '删除目标',
                message: `确定要删除"${goal.title ?? '未命名目标'}"吗？`,
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '删除',
                  fontColor: AppColors.ERROR,
                  action: async () => {
                    try {
                      const goalId = goal.id ?? ''
                      await this.viewModel.deleteGoal(goalId)
                      promptAction.showToast({ message: '目标已删除' })
                      // 通知首页刷新
                      AppStorage.setOrCreate('goalUpdatedAt', Date.now())
                      await this.loadGoals()
                    } catch (err) {
                      console.error('[GoalManagement] 删除目标失败:', err)
                      promptAction.showToast({ message: '删除失败，请重试' })
                    }
                  }
                }
              })
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: AppSizes.SPACE_MD })
      }
    }
    .width('100%')
    .padding(this.isSelectionMode ? { left: AppSizes.SPACE_2XL, right: AppSizes.SPACE_LG, top: AppSizes.SPACE_LG, bottom: AppSizes.SPACE_LG } : AppSizes.SPACE_LG)
    .backgroundColor(this.isSelectionMode && this.selectedGoalIds.has(goal.id ?? '') ? AppColors.ACCENT_BG : AppColors.BG_SECONDARY)
    .linearGradient(this.isSelectionMode && this.selectedGoalIds.has(goal.id ?? '') ? undefined : AppGradients.CARD_SUBTLE)
    .borderRadius(AppSizes.RADIUS_LG)
    .border({ color: this.isSelectionMode && this.selectedGoalIds.has(goal.id ?? '') ? AppColors.ACCENT : '#00000000', width: this.isSelectionMode && this.selectedGoalIds.has(goal.id ?? '') ? 2 : 0 })
    .shadow(AppShadows.SHADOW_SM)
    .onClick(() => {
      if (!this.isSelectionMode) return
      const id = goal.id ?? ''
      if (!id) return
      if (this.selectedGoalIds.has(id)) {
        this.selectedGoalIds.delete(id)
      } else {
        this.selectedGoalIds.add(id)
      }
      this.selectedGoalIds = new Set(this.selectedGoalIds)
    })

      // 选择模式：左上角选择指示器
      if (this.isSelectionMode) {
        Row() {
          if (this.selectedGoalIds.has(goal.id ?? '')) {
            Text('✓')
              .fontSize(14)
              .fontColor(AppColors.TEXT_WHITE)
              .fontWeight(FontWeight.Bold)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(AppColors.ACCENT)
          } else {
            Row()
              .width(24)
              .height(24)
              .borderRadius(12)
              .border({ width: 2, color: AppColors.TEXT_HINT })
              .backgroundColor(AppColors.BG_SECONDARY)
          }
        }
        .position({ x: 8, y: 8 })
      }
    }
  }

  @Builder
  AddGoalSheet() {
    Column({ space: AppSizes.SPACE_2XL }) {
      // 目标标题
      Column() {
        Text('目标名称')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_TERTIARY)
          .width('100%')

        TextInput({ placeholder: '例如：期末考试、四级考试' })
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
          .backgroundColor(AppColors.BG_TERTIARY)
          .borderRadius(AppSizes.RADIUS_MD)
          .height(48)
          .margin({ top: AppSizes.SPACE_SM })
          .onChange((value) => {
            this.newGoalTitle = value
          })
      }

      // 截止日期
      Column() {
        Text('截止日期')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_TERTIARY)
          .width('100%')

        Row() {
          Text(this.formatDate(this.newGoalDate))
            .fontSize(AppSizes.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)

          Blank()

          Shape() {
            Path()
              .commands(IconPaths.CALENDAR)
              .fill(AppColors.TEXT_TERTIARY)
          }
          .width(24)
          .height(24)
          .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        }
        .width('100%')
        .height(48)
        .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(AppSizes.RADIUS_MD)
        .margin({ top: AppSizes.SPACE_SM })
        .onClick(() => {
          // TODO: 日期选择器
          DatePickerDialog.show({
            start: new Date(),
            end: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
            selected: this.newGoalDate,
            onDateAccept: (value) => {
              this.newGoalDate = value
            }
          })
        })
      }

      // 创建按钮
      Button('创建目标')
        .width('100%')
        .height(48)
        .fontSize(AppSizes.FONT_MD)
        .fontColor(AppColors.TEXT_WHITE)
        .backgroundColor(AppColors.ACCENT)
        .linearGradient(AppGradients.PRIMARY_BTN)
        .borderRadius(AppSizes.RADIUS_LG)
        .onClick(async () => {
          if (!this.newGoalTitle.trim()) {
            promptAction.showToast({ message: '请输入目标名称' })
            return
          }

          try {
            const success = await this.viewModel.createGoal(this.newGoalTitle, this.newGoalDate)
            if (success) {
              promptAction.showToast({ message: '目标创建成功！' })
              this.showAddDialog = false
              this.newGoalTitle = ''
              this.newGoalDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
              // 通知首页刷新
              AppStorage.setOrCreate('goalUpdatedAt', Date.now())
              await this.loadGoals()
            } else {
              promptAction.showToast({ message: '创建失败，请检查网络或稍后重试' })
            }
          } catch (err) {
            console.error('[GoalManagement] 创建目标异常:', err)
            const bizErr = err as BusinessError<object>
            const msg = (bizErr && bizErr.message) ? bizErr.message : '创建失败，请检查网络或稍后重试'
            promptAction.showToast({ message: msg })
          }
        })
    }
    .width('100%')
    .padding(AppSizes.SPACE_2XL)
  }

  private getDaysLeft(deadline: number): number {
    const diff = deadline - Date.now()
    return Math.max(0, Math.ceil(diff / (1000 * 60 * 60 * 24)))
  }

  private formatDeadline(timestamp: number): string {
    if (timestamp === 0) return '未设置截止日期'
    const date = new Date(timestamp)
    const daysLeft = this.getDaysLeft(timestamp)
    return `${date.getMonth() + 1}月${date.getDate()}日 · ${daysLeft <= 0 ? '已过期' : `剩余${daysLeft}天`}`
  }

  private formatDate(date: Date): string {
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`
  }

  private getProgress(goal: Goal): number {
    if (!goal.create_time || !goal.deadline) return 0
    const total = goal.deadline - goal.create_time
    const elapsed = Date.now() - goal.create_time
    return Math.min(100, Math.max(0, (elapsed / total) * 100))
  }
}
