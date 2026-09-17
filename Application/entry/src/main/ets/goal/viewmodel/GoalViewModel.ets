// 目标管理 - 处理目标的 CRUD 和倒计时计算
// 数据通过 CloudDBService 同步到云端
import { CloudDBService } from '../../common/services/CloudDBService'
import { Goal } from '../../goal/model/Goal'
import { Task, TaskPriority } from '../model/Task'
import { TaskStorageService } from '../model/TaskStorageService'
import { preferences } from '@kit.ArkData'
import common from '@ohos.app.ability.common'

// 目标状态码，与数据库字段对应
export enum GoalStatus {
  NOT_STARTED = 0,
  IN_PROGRESS = 1,
  COMPLETED = 2,
  OVERDUE = 3
}

// 倒计时展示数据
export interface GoalCountdown {
  goal: Goal
  daysLeft: number
  progress: number
  isOverdue: boolean
}

export class GoalViewModel {
  private static readonly LOCAL_GOALS_KEY: string = 'local_goals'
  private static readonly LOCAL_PREFS: string = 'goalLocalStore'
  private cloudDBService: CloudDBService
  private taskService: TaskStorageService

  constructor() {
    this.cloudDBService = CloudDBService.getInstance()
    this.taskService = TaskStorageService.getInstance()
  }

  async createGoal(title: string, deadline: Date): Promise<boolean> {
    try {
      const userId = (AppStorage.get('currentUserId') as string) || ''

      const goal = new Goal()
      goal.id = this.generateId()
      goal.title = title
      goal.deadline = deadline.getTime()
      goal.create_time = Date.now()  // 修复：设置创建时间用于进度计算
      goal.update_time = goal.create_time
      goal.user_id = userId
      goal.sync_status = 'pending'
      goal.progress = 0
      // 轻量兜底：如果未登录，先允许本地创建，云端 upsert 失败会有日志
      goal.status = GoalStatus.IN_PROGRESS

      try {
        const result = await this.cloudDBService.upsertGoal(goal)
        if (result > 0) {
          // 通知首页刷新目标数据
          this.notifyGoalUpdated()
          return true
        }
      } catch (cloudErr) {
        console.warn('[GoalViewModel] 云端创建失败，使用本地存储兜底:', cloudErr)
      }

      // 云端失败后尝试本地持久化
      await this.saveLocalGoal(goal)
      this.notifyGoalUpdated()
      return true
    } catch (err) {
      console.error('[GoalViewModel] 创建目标失败:', err)
      // ArkTS 不允许直接 throw unknown，统一转成 Error
      const message = (err as Error)?.message ?? 'createGoal failed'
      throw new Error(message)
    }
  }

  // 通知首页数据已更新
  private notifyGoalUpdated(): void {
    AppStorage.setOrCreate('goalUpdatedAt', Date.now())
  }

  async getAllGoals(): Promise<Goal[]> {
    try {
      const cloudGoals = await this.cloudDBService.queryAllGoals()
      if (cloudGoals && cloudGoals.length > 0) {
        return cloudGoals
      }
      return await this.loadLocalGoals()
    } catch (err) {
      console.error('[GoalViewModel] 获取目标失败:', err)
      return await this.loadLocalGoals()
    }
  }

  async getActiveGoals(): Promise<Goal[]> {
    try {
      const allGoals = await this.getAllGoals()
      return allGoals.filter(g => g.status === GoalStatus.IN_PROGRESS)
    } catch (err) {
      console.error('[GoalViewModel] 获取进行中目标失败:', err)
      return []
    }
  }

  // 找出最近截止的目标，用于 Dashboard 展示
  async getNearestGoalCountdown(): Promise<GoalCountdown | null> {
    try {
      const activeGoals = await this.getActiveGoals()
      if (activeGoals.length === 0) return null

      const now = Date.now()

      activeGoals.sort((a, b) => (a.deadline ?? 0) - (b.deadline ?? 0))

      const nearestGoal = activeGoals[0]
      const deadline = nearestGoal.deadline ?? 0
      const createTime = nearestGoal.create_time ?? 0
      const daysLeft = Math.ceil((deadline - now) / (1000 * 60 * 60 * 24))

      // 进度基于实际创建时间到截止时间计算
      let progress = 0
      if (createTime > 0 && deadline > createTime) {
        const totalDuration = deadline - createTime
        const elapsed = now - createTime
        progress = Math.min(100, Math.max(0, (elapsed / totalDuration) * 100))
      } else {
        // 如果没有创建时间，回退到基于剩余天数的估算（假设30天周期）
        const totalDays = 30
        const daysPassed = totalDays - daysLeft
        progress = Math.min(100, Math.max(0, (daysPassed / totalDays) * 100))
      }

      return {
        goal: nearestGoal,
        daysLeft: Math.max(0, daysLeft),
        progress: Math.round(progress),
        isOverdue: daysLeft < 0
      }
    } catch (err) {
      console.error('[GoalViewModel] 获取倒计时失败:', err)
      return null
    }
  }

  async updateGoalStatus(goalId: string, status: GoalStatus): Promise<boolean> {
    try {
      const goals = await this.cloudDBService.queryAllGoals()
      const goal = goals.find(g => g.id === goalId)

      if (!goal) return false

      goal.status = status
      const result = await this.cloudDBService.upsertGoal(goal)
      return result > 0
    } catch (err) {
      console.error('[GoalViewModel] 更新目标状态失败:', err)
      return false
    }
  }

  async completeGoal(goalId: string, context: common.Context): Promise<boolean> {
    const goal = await this.findGoalById(goalId)
    if (!goal) {
      console.warn('[GoalViewModel] completeGoal: 未找到目标', goalId)
      return false
    }

    // 标记完成
    goal.status = GoalStatus.COMPLETED
    goal.update_time = Date.now()

    // 尝试云端更新
    try {
      const result = await this.cloudDBService.upsertGoal(goal)
      if (result > 0) {
        await this.archiveGoalToHistory(goal, context)
        await this.deleteGoal(goalId)
        this.notifyGoalUpdated()
        return true
      }
    } catch (err) {
      console.warn('[GoalViewModel] 云端完成目标失败，改用本地兜底:', err)
    }

    // 本地兜底：保存到历史并从本地列表移除
    await this.archiveGoalToHistory(goal, context)
    const localGoals = await this.loadLocalGoals()
    const nextGoals = localGoals.filter(g => g.id !== goalId)
    await this.saveLocalGoals(nextGoals)
    this.notifyGoalUpdated()
    return true
  }

  async deleteGoal(goalId: string): Promise<boolean> {
    try {
      // 问题7修复：先从云端删除
      const goals = await this.cloudDBService.queryAllGoals()
      const goal = goals.find(g => g.id === goalId)

      if (!goal) {
        console.warn('[GoalViewModel] 云端未找到目标，尝试本地删除')
        // 直接尝试本地删除
        const localGoals = await this.loadLocalGoals()
        const nextGoals = localGoals.filter(g => g.id !== goalId)
        if (nextGoals.length !== localGoals.length) {
          await this.saveLocalGoals(nextGoals)
          this.notifyGoalUpdated()
          return true
        }
        return false
      }

      const result = await this.cloudDBService.deleteGoal(goal)
      if (result > 0) {
        // 成功删除后同时清理本地缓存
        const localGoals = await this.loadLocalGoals()
        const nextGoals = localGoals.filter(g => g.id !== goalId)
        await this.saveLocalGoals(nextGoals)
        this.notifyGoalUpdated()
        console.info('[GoalViewModel] 目标已从云端和本地删除:', goalId)
        return true
      }
    } catch (err) {
      console.error('[GoalViewModel] 删除目标失败，尝试本地删除:', err)
    }

    // 本地兜底删除
    const localGoals = await this.loadLocalGoals()
    const nextGoals = localGoals.filter(g => g.id !== goalId)
    if (nextGoals.length !== localGoals.length) {
      await this.saveLocalGoals(nextGoals)
      this.notifyGoalUpdated()
      return true
    }
    return false
  }

  // 启动时调用，自动把过期目标标记为 OVERDUE
  async checkOverdueGoals(): Promise<number> {
    try {
      const activeGoals = await this.getActiveGoals()
      const now = Date.now()
      let overdueCount = 0

      for (const goal of activeGoals) {
        if ((goal.deadline ?? 0) < now) {
          goal.status = GoalStatus.OVERDUE
          await this.cloudDBService.upsertGoal(goal)
          overdueCount++
        }
      }

      return overdueCount
    } catch (err) {
      console.error('[GoalViewModel] 检查过期目标失败:', err)
      return 0
    }
  }

  private async findGoalById(goalId: string): Promise<Goal | null> {
    try {
      const goals = await this.cloudDBService.queryAllGoals()
      const goal = goals.find(g => g.id === goalId)
      if (goal) {
        return goal
      }
    } catch (err) {
      console.warn('[GoalViewModel] findGoalById 云端失败:', err)
    }

    const localGoals = await this.loadLocalGoals()
    const local = localGoals.find(g => g.id === goalId)
    return local || null
  }

  private async archiveGoalToHistory(goal: Goal, context: common.Context): Promise<void> {
    try {
      const now = Date.now()
      const task: Task = {
        id: goal.id,
        title: goal.title || '未命名目标',
        estimatedPomodoros: 0,
        completedPomodoros: 0,
        isCompleted: true,
        priority: TaskPriority.MEDIUM,
        createdAt: goal.create_time || now,
        completedAt: now,
        tag: '目标'
      }
      await this.taskService.saveCompletedTasks(context, [task])
      console.info('[GoalViewModel] 已将完成的目标归档到已完成任务历史')
    } catch (err) {
      console.error('[GoalViewModel] 归档目标到历史失败:', err)
    }
  }

  // ================= 本地持久化兜底 =================
  private async loadLocalGoals(): Promise<Goal[]> {
    try {
      const ctx = this.getAppContext()
      const prefs = await preferences.getPreferences(ctx, GoalViewModel.LOCAL_PREFS)
      const json = await prefs.get(GoalViewModel.LOCAL_GOALS_KEY, '[]') as string
      const parsed: Goal[] = JSON.parse(json)
      return Array.isArray(parsed) ? parsed : []
    } catch (err) {
      console.warn('[GoalViewModel] 读取本地目标失败，返回空列表:', err)
      return []
    }
  }

  private async saveLocalGoal(goal: Goal): Promise<void> {
    const goals = await this.loadLocalGoals()
    goals.unshift(goal)
    await this.saveLocalGoals(goals)
  }

  private async saveLocalGoals(goals: Goal[]): Promise<void> {
    try {
      const ctx = this.getAppContext()
      const prefs = await preferences.getPreferences(ctx, GoalViewModel.LOCAL_PREFS)
      await prefs.put(GoalViewModel.LOCAL_GOALS_KEY, JSON.stringify(goals))
      await prefs.flush()
      console.info('[GoalViewModel] 已本地保存目标数量:', goals.length)
    } catch (err) {
      console.error('[GoalViewModel] 本地保存目标失败:', err)
    }
  }

  private getAppContext(): common.Context {
    const ctx = (getContext(this) as common.UIAbilityContext).getApplicationContext() as common.Context
    return ctx
  }

  private generateId(): string {
    return `goal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  }
}