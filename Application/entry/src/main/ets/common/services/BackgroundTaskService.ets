// ============================================================================
// 后台任务服务 - 保持番茄钟计时不中断
// ============================================================================
// 功能：申请/取消长时任务，监听任务取消事件
// 依赖：@kit.BackgroundTasksKit, @kit.AbilityKit
// ============================================================================
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'

// 后台任务类型
export enum BackgroundTaskType {
  AUDIO_PLAYBACK = 'audioPlayback',  // 音频播放（番茄钟白噪音）
  DATA_TRANSFER = 'dataTransfer'     // 数据传输（云同步）
}

// 任务状态回调
export type TaskCancelCallback = (reason: number) => void

export class BackgroundTaskService {
  private static instance: BackgroundTaskService | null = null
  private context: common.UIAbilityContext | null = null
  private isTaskRunning: boolean = false
  private cancelCallback: TaskCancelCallback | null = null

  private constructor() {}

  static getInstance(): BackgroundTaskService {
    if (!BackgroundTaskService.instance) {
      BackgroundTaskService.instance = new BackgroundTaskService()
    }
    return BackgroundTaskService.instance
  }

  // 初始化服务
  init(context: common.UIAbilityContext): void {
    this.context = context
    this.registerCancelListener()
  }

  // 注册任务取消监听
  private registerCancelListener(): void {
    try {
      backgroundTaskManager.on('continuousTaskCancel', (info) => {
        console.warn(`[BackgroundTask] 任务被取消, ID: ${info.id}, 原因: ${info.reason}`)
        this.isTaskRunning = false
        if (this.cancelCallback) {
          this.cancelCallback(info.reason)
        }
      })
    } catch (err) {
      // API 15+ 才支持，低版本忽略
      console.info('[BackgroundTask] 取消监听注册失败（可能是低版本API）')
    }
  }

  // 设置任务取消回调
  setOnCancelCallback(callback: TaskCancelCallback): void {
    this.cancelCallback = callback
  }

  // 申请后台任务（番茄钟使用）
  async startPomodoroTask(): Promise<boolean> {
    if (!this.context) {
      console.error('[BackgroundTask] 上下文未初始化')
      return false
    }

    if (this.isTaskRunning) {
      console.info('[BackgroundTask] 任务已在运行中')
      return true
    }

    try {
      // 构建 WantAgent - 点击通知时打开应用
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: this.context.abilityInfo.bundleName,
          abilityName: 'EntryAbility'
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }

      const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo)

      // 申请长时任务 - 使用音频播放模式（配合白噪音）
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        wantAgentObj
      )

      this.isTaskRunning = true
      console.info('[BackgroundTask] 番茄钟后台任务启动成功')
      return true
    } catch (err) {
      const error = err as BusinessError
      console.error(`[BackgroundTask] 启动失败: ${error.code} - ${error.message}`)
      return false
    }
  }

  // 停止后台任务
  async stopPomodoroTask(): Promise<boolean> {
    if (!this.context) {
      return false
    }

    if (!this.isTaskRunning) {
      return true
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context)
      this.isTaskRunning = false
      console.info('[BackgroundTask] 番茄钟后台任务已停止')
      return true
    } catch (err) {
      const error = err as BusinessError
      console.error(`[BackgroundTask] 停止失败: ${error.code} - ${error.message}`)
      return false
    }
  }

  // 获取任务运行状态
  isRunning(): boolean {
    return this.isTaskRunning
  }

  // 销毁服务
  destroy(): void {
    try {
      backgroundTaskManager.off('continuousTaskCancel')
    } catch (err) {
      // 忽略
    }
    this.stopPomodoroTask()
    this.context = null
    this.cancelCallback = null
  }
}
