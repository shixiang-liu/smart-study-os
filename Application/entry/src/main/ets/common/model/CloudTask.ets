// ============================================================================
// 任务云端模型 - CloudTask
// ============================================================================
// 对应 CloudDB 表：Task
// 主键：id
// 用于任务数据的云端同步
// ============================================================================

import { cloudDatabase } from '@kit.CloudFoundationKit'
import { Task, TaskPriority } from '../../goal/model/Task'

@Observed
export class CloudTask extends cloudDatabase.DatabaseObject {
  // 任务唯一标识
  public id: string = ''
  
  // 所属用户 ID
  public user_id: string = ''
  
  // 任务标题
  public title: string = ''
  
  // 任务描述
  public description: string = ''
  
  // 关联目标ID
  public goal_id: string = ''
  
  // 预计番茄数
  public estimated_pomodoros: number = 0
  
  // 实际完成番茄数
  public actual_pomodoros: number = 0
  
  // 是否已完成
  public is_completed: boolean = false
  
  // 完成时间
  public completed_at: number = 0
  
  // 标签
  public tag: string = ''
  
  // 创建时间
  public create_time: number = 0
  
  // 同步状态
  public sync_status: string = 'synced'

  constructor() {
    super()
  }

  // CloudDB 必需：返回对象类型名称
  naturalbase_ClassName(): string {
    return 'Task'
  }

  // CloudDB 主键字段
  getPrimaryKeyValue(): string {
    return this.id
  }

  // 从本地 Task 模型创建云端对象
  static fromLocalTask(task: Task, userId: string): CloudTask {
    const cloud = new CloudTask()
    cloud.id = task.id
    cloud.user_id = userId
    cloud.title = task.title
    cloud.description = task.description || ''
    cloud.goal_id = ''  // 需要从其他地方获取
    cloud.estimated_pomodoros = task.estimatedPomodoros
    cloud.actual_pomodoros = task.completedPomodoros
    cloud.is_completed = task.isCompleted
    cloud.completed_at = task.completedAt || 0
    cloud.tag = task.tag || ''
    cloud.create_time = task.createdAt
    cloud.sync_status = 'synced'
    return cloud
  }

  // 转换为本地 Task 模型
  toLocalTask(): Task {
    return {
      id: this.id,
      title: this.title,
      description: this.description,
      estimatedPomodoros: this.estimated_pomodoros,
      completedPomodoros: this.actual_pomodoros,
      isCompleted: this.is_completed,
      priority: TaskPriority.MEDIUM,  // 云端未存储优先级，使用默认值
      tag: this.tag,
      createdAt: this.create_time,
      completedAt: this.completed_at > 0 ? this.completed_at : undefined
    }
  }
}
