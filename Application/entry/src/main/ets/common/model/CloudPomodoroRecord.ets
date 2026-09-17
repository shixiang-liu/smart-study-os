// ============================================================================
// 番茄钟记录云端模型 - CloudPomodoroRecord
// ============================================================================
// 对应 CloudDB 表：PomodoroRecord
// 主键：id
// 用于专注记录的云端同步
// ============================================================================

import { cloudDatabase } from '@kit.CloudFoundationKit'
import { FocusSession } from '../../pomodoro/model/FocusRecord'

@Observed
export class CloudPomodoroRecord extends cloudDatabase.DatabaseObject {
  // 记录唯一标识
  public id: string = ''
  
  // 所属用户 ID
  public user_id: string = ''
  
  // 任务名称
  public task_name: string = ''
  
  // 计划时长（分钟）
  public duration_minutes: number = 25
  
  // 实际时长（分钟）
  public actual_minutes: number = 0
  
  // 是否完成
  public is_completed: boolean = false
  
  // 开始时间
  public start_time: number = 0
  
  // 结束时间
  public end_time: number = 0
  
  // 同步状态
  public sync_status: string = 'synced'

  constructor() {
    super()
  }

  // CloudDB 必需：返回对象类型名称
  naturalbase_ClassName(): string {
    return 'PomodoroRecord'
  }

  // CloudDB 主键字段
  getPrimaryKeyValue(): string {
    return this.id
  }

  // 从本地 FocusSession 创建云端对象
  static fromFocusSession(session: FocusSession, userId: string): CloudPomodoroRecord {
    const cloud = new CloudPomodoroRecord()
    cloud.id = session.id || `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    cloud.user_id = userId
    cloud.task_name = session.taskTitle || ''
    cloud.duration_minutes = session.duration
    cloud.actual_minutes = session.duration
    cloud.is_completed = true
    cloud.start_time = session.startTime
    cloud.end_time = session.endTime || (session.startTime + (session.duration * 60 * 1000))
    cloud.sync_status = 'synced'
    return cloud
  }

  // 转换为本地 FocusSession
  toFocusSession(): FocusSession {
    return {
      id: this.id,
      startTime: this.start_time,
      endTime: this.end_time,
      duration: this.actual_minutes,
      taskId: '',
      taskTitle: this.task_name
    }
  }
}
