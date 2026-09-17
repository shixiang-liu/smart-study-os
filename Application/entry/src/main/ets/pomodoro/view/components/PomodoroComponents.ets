/**
 * @file PomodoroComponents.ets
 * @description 番茄钟UI组件库 - 从Pomodoro.ets拆分
 * 包含：统计卡片、任务列表项、控制按钮等可复用组件
 */

import { Task, TaskPriority } from '../../../goal/model/Task'
import {
  AppColors,
  AppSizes,
  AppShadows,
  AppAnimations,
  AppGradients,
  LinearGradient
} from '../../../common/utils/AppTheme'

// ============================================================================
// 组件属性接口定义
// ============================================================================

// 优先级信息接口
interface PriorityInfo {
  label: string
  color: string
}

// 统计卡片属性
export interface StatsCardProps {
  todayFocusMinutes: number
  todayPomodoros: number
}

// 任务项属性
export interface TaskItemProps {
  task: Task
  onComplete: (task: Task) => void
  onSelect: (task: Task) => void
}

// ============================================================================
// 统计卡片组件
// ============================================================================

@Component
export struct PomodoroStatsCards {
  @Prop todayFocusMinutes: number = 0
  @Prop todayPomodoros: number = 0

  build() {
    Row({ space: AppSizes.SPACE_MD }) {
      // 今日专注时长 - 使用SPA_SKY渐变
      Column({ space: 4 }) {
        Text(this.todayFocusMinutes.toString())
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text($r('app.string.pomodoro_today_focus'))
          .fontSize(AppSizes.FONT_XS)
          .fontColor(AppColors.TEXT_TERTIARY)
      }
      .layoutWeight(1)
      .padding(AppSizes.SPACE_LG)
      .linearGradient(AppGradients.SPA_SKY)
      .borderRadius(AppSizes.RADIUS_LG)
      .shadow(AppShadows.SHADOW_SM)

      // 今日番茄数 - 使用SPA_PEACH渐变
      Column({ space: 4 }) {
        Text(this.todayPomodoros.toString())
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.ACCENT)
        Text($r('app.string.pomodoro_today_pomodoros'))
          .fontSize(AppSizes.FONT_XS)
          .fontColor(AppColors.TEXT_TERTIARY)
      }
      .layoutWeight(1)
      .padding(AppSizes.SPACE_LG)
      .linearGradient(AppGradients.SPA_PEACH)
      .borderRadius(AppSizes.RADIUS_LG)
      .shadow(AppShadows.SHADOW_SM)
    }
    .width('100%')
    .margin({ bottom: AppSizes.SPACE_XL })
  }
}

// ============================================================================
// 任务列表项组件（紧凑版）
// ============================================================================

@Component
export struct PomodoroTaskItem {
  @Prop task: Task | null = null
  onComplete: (task: Task) => void = () => {
  }
  onSelect: (task: Task) => void = () => {
  }

  // 优先级显示(问题14修复)
  private getPriorityInfo(priority: TaskPriority): PriorityInfo {
    if (priority === TaskPriority.HIGH) {
      const info: PriorityInfo = { label: '高', color: '#EF4444' }
      return info
    } else if (priority === TaskPriority.MEDIUM) {
      const info: PriorityInfo = { label: '中', color: '#F59E0B' }
      return info
    } else if (priority === TaskPriority.LOW) {
      const info: PriorityInfo = { label: '低', color: '#10B981' }
      return info
    } else {
      const info: PriorityInfo = { label: '普通', color: AppColors.TEXT_TERTIARY }
      return info
    }
  }

  build() {
    if (this.task) {
      Row({ space: 12 }) {
        // 复选框
        Stack({ alignContent: Alignment.Center }) {
          Stack()
            .width(20)
            .height(20)
            .borderRadius(10)
            .border({ width: 2, color: AppColors.BORDER })
            .backgroundColor(Color.Transparent)
        }
        .width(20)
        .height(20)
        .onClick(() => {
          if (this.task) {
            this.onComplete(this.task)
          }
        })

        Column({ space: 4 }) {
          // 标题行
          Row({ space: 8 }) {
            Text(this.task.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            // 优先级标签(问题14修复)
            if (this.task.priority) {
              Text(this.getPriorityInfo(this.task.priority).label)
                .fontSize(10)
                .fontColor(Color.White)
                .padding({
                  left: 6,
                  right: 6,
                  top: 2,
                  bottom: 2
                })
                .backgroundColor(this.getPriorityInfo(this.task.priority).color)
                .borderRadius(4)
            }
          }
          .width('100%')

          // 进度和分类信息
          Row({ space: 12 }) {
            Text(`${this.task.completedPomodoros}/${this.task.estimatedPomodoros} 番茄`)
              .fontSize(12)
              .fontColor(AppColors.TEXT_SECONDARY)

            // 标签显示(问题14修复)
            if (this.task.tag && this.task.tag !== '') {
              Text(this.task.tag)
                .fontSize(11)
                .fontColor(AppColors.ACCENT)
                .padding({
                  left: 6,
                  right: 6,
                  top: 1,
                  bottom: 1
                })
                .backgroundColor(AppColors.ACCENT_BG)
                .borderRadius(4)
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(8)
      .margin({ bottom: 8 })
      .onClick(() => {
        if (this.task) {
          this.onSelect(this.task)
        }
      })
    }
  }
}

// ============================================================================
// 空状态提示组件
// ============================================================================

@Component
export struct PomodoroEmptyState {
  @Prop message: string = '暂无番茄钟待办'
  @Prop submessage: string = '请在主页添加番茄钟待办'
  @Prop emoji: string = '📋'

  build() {
    Column({ space: 8 }) {
      Text(this.emoji)
        .fontSize(32)
      Text(this.message)
        .fontSize(AppSizes.FONT_MD)
        .fontColor(AppColors.TEXT_TERTIARY)
      Text(this.submessage)
        .fontSize(AppSizes.FONT_XS)
        .fontColor(AppColors.TEXT_TERTIARY)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Center)
  }
}

// ============================================================================
// 底部导航栏组件
// ============================================================================

@Component
export struct PomodoroBottomNav {
  @Prop currentView: string = 'timer'
  onViewChange: (view: string) => void = () => {
  }

  build() {
    Row() {
      this.NavItem('⏱️', 'timer', this.currentView === 'timer')
      this.NavItem('📋', 'tasks', this.currentView === 'tasks')
      this.NavItem('📊', 'stats', this.currentView === 'stats')
      this.NavItem('⚙️', 'settings', this.currentView === 'settings')
    }
    .width('100%')
    .height(60)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius({ topLeft: AppSizes.RADIUS_LG, topRight: AppSizes.RADIUS_LG })
    .shadow(AppShadows.SHADOW_SM)
    .position({ x: 0, y: '100%' })
    .translate({ y: -60 })
  }

  @Builder
  private NavItem(icon: string, viewKey: string, isActive: boolean) {
    Column() {
      Text(icon)
        .fontSize(24)
        .opacity(isActive ? 1 : 0.5)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .onClick(() => {
      this.onViewChange(viewKey)
    })
  }
}
