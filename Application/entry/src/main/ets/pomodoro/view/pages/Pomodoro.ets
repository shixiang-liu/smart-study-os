// ============================================================================
// 番茄钟 - Pomodoro
// ============================================================================
// 功能：专注计时 + 任务管理 + 白噪音 + 专注统计
// 架构：状态机模式（IDLE → WORKING → BREAK → IDLE）
// 存储：本地 Preferences，不同步云端
// 特色：情绪联动白噪音（AI 推荐）、任务关联专注记录、后台持续运行
// ============================================================================

import { PomodoroStorageService } from '../../../pomodoro/model/PomodoroStorageService';
import { PomodoroPreference } from '../../../pomodoro/model/PomodoroPreference';
import { AudioPlayer } from '../../../common/components/AudioPlayer';
import { Task, TaskPriority, DEFAULT_TASK } from '../../../goal/model/Task';
import { TaskStorageService } from '../../../goal/model/TaskStorageService';
import { FocusRecordService } from '../../../pomodoro/model/FocusRecordService';
import { FocusSession, FocusRecord } from '../../../pomodoro/model/FocusRecord';
import { promptAction, router } from '@kit.ArkUI';
import { PomodoroViewModel, SmartNoiseResult, WhiteNoiseType } from '../../../pomodoro/viewmodel/PomodoroViewModel';
import { BackgroundTaskService } from '../../../common/services/BackgroundTaskService';
import { CloudDBService } from '../../../common/services/CloudDBService';
import common from '@ohos.app.ability.common';
import { AppColors, AppSizes, AppShadows, AppAnimations, AppGradients, LinearGradient } from '../../../common/utils/AppTheme';
import { PomodoroStatsCards, PomodoroTaskItem, PomodoroEmptyState, PomodoroBottomNav } from '../components/PomodoroComponents';

// ============================================================================
// 状态枚举
// ============================================================================

// 番茄钟状态（状态机）
enum PomodoroState {
  IDLE = 'idle',           // 空闲，等待开始
  WORKING = 'working',     // 专注中
  SHORT_BREAK = 'short_break', // 短休息
  LONG_BREAK = 'long_break',   // 长休息
  PAUSED = 'paused'        // 暂停
}

// 当前计时类型
enum PomodoroType {
  WORK = 'work',
  SHORT_BREAK = 'short_break',
  LONG_BREAK = 'long_break'
}

// 页面视图模式
enum ViewMode {
  TIMER = 'timer',
  TASKS = 'tasks',
  STATS = 'stats',
  SETTINGS = 'settings'
}

interface TimerState {
  remainingSeconds: number;
  state: PomodoroState;
  currentType: PomodoroType;
  startTimestamp: number;
  pomodoroCount: number;
  savedAt: number;
}

// ============================================================================
// 番茄钟组件
// ============================================================================

@Entry
@Component
export struct Pomodoro {
  // ==================== 计时器状态 ====================

  // 当前状态（状态机核心）
  @State private state: PomodoroState = PomodoroState.IDLE;

  // 当前计时类型（工作/短休/长休）
  @State private currentType: PomodoroType = PomodoroType.WORK;

  // 剩余秒数
  @State private remainingSeconds: number = 25 * 60;

  // 进度（0-1），用于进度条显示
  @State private progress: number = 0;

  // 用户偏好设置
  @State private preference: PomodoroPreference | null = null;

  // 当前视图模式
  @State private viewMode: ViewMode = ViewMode.TIMER;

  // 暗色模式
  @StorageLink('isDarkMode') private isDarkMode: boolean = false;

  // ==================== 任务管理状态 ====================

  // 任务列表
  @State private tasks: Task[] = [];

  // 当前专注的任务
  @State private currentTask: Task | null = null;

  // 对话框显示控制
  @State private showAddTaskDialog: boolean = false;

  // 正在编辑的任务
  @State private editingTask: Task | null = null;

  // 新任务表单字段
  @State private newTaskTitle: string = '';
  @State private newTaskEstimated: number = 1;
  @State private newTaskPriority: TaskPriority = TaskPriority.MEDIUM;

  // ==================== 统计信息 ====================

  // 今日专注时长（分钟）
  @State private todayFocusMinutes: number = 0;

  // 今日完成的番茄数
  @State private todayPomodoros: number = 0;

  // ==================== 内部计时器 ====================

  // setInterval 的返回值
  private timer: number = -1;

  // 当前计时类型的总秒数
  private totalSeconds: number = 25 * 60;

  // 已完成番茄计数（用于判断长休息）
  private pomodoroCount: number = 0;
  
  // 计时开始时间戳（用于后台时间校准）
  private startTimestamp: number = 0;

  // ==================== 设置编辑状态 ====================

  @State private editingWorkDuration: number = 25;
  @State private editingShortBreak: number = 5;
  @State private editingLongBreak: number = 15;
  @State private editingLongBreakInterval: number = 4;
  @State private editingWhiteNoiseEnabled: boolean = false;
  @State private editingWhiteNoiseType: string = 'none';
  @State private editingSoundEnabled: boolean = true;
  @State private whitelistApps: string[] = [];
  @State private recentRecords: FocusRecord[] = [];

  // ==================== 情绪联动白噪音 ====================
  // AI 根据当前情绪推荐最适合的白噪音类型

  @State private currentEmotion: string = '平静';
  @State private aiNoiseRecommendation: string = '';
  @State private aiNoiseReason: string = '';
  @State private showEmotionPicker: boolean = false;
  @State private latestDiaryMood: string = ''; // 从日记中获取的最新情绪

  // ==================== 服务依赖 ====================

  private storageService: PomodoroStorageService = PomodoroStorageService.getInstance();
  private taskService: TaskStorageService = TaskStorageService.getInstance();
  private recordService: FocusRecordService = FocusRecordService.getInstance();
  private audioPlayer: AudioPlayer = AudioPlayer.getInstance();
  private backgroundService: BackgroundTaskService = BackgroundTaskService.getInstance();
  private context: Context = getContext(this);

  // ==================== 生命周期 ====================

  async aboutToAppear() {
    // 初始化顺序：偏好 → 任务 → 统计 → 加载最新情绪 → AI推荐 → 计时器 → 后台服务
    await this.loadPreference();
    await this.loadTasks();
    await this.loadStatistics();
    await this.loadLatestDiaryMood();
    await this.loadEmotionNoiseRecommendation();
    await this.restoreTimerState(); // 恢复上次保存的计时器状态
    this.initBackgroundService();
  }
  
  // 初始化后台任务服务
  private initBackgroundService(): void {
    try {
      const uiContext = getContext(this) as common.UIAbilityContext;
      this.backgroundService.init(uiContext);
      
      // 监听后台任务取消事件
      this.backgroundService.setOnCancelCallback((reason: number) => {
        console.warn('[Pomodoro] 后台任务被取消，原因:', reason);
        // 任务被取消时暂停计时（用户可能主动关闭了通知）
        if (this.state === PomodoroState.WORKING || 
            this.state === PomodoroState.SHORT_BREAK || 
            this.state === PomodoroState.LONG_BREAK) {
          this.pauseTimer();
          promptAction.showToast({ message: '后台任务已停止', duration: 2000 });
        }
      });
    } catch (err) {
      console.error('[Pomodoro] 初始化后台服务失败:', err);
    }
  }

  // 加载最新日记情绪（监听成员A解析的Mood字段）
  private async loadLatestDiaryMood(): Promise<void> {
    try {
      const cloudDB = CloudDBService.getInstance();
      const diaries = await cloudDB.getDiariesByTime();
      
      // 获取最新的日记情绪
      if (diaries && diaries.length > 0) {
        const latestDiary = diaries[0]; // 已按时间倒序排列
        const mood = latestDiary.mood || '';
        if (mood) {
          this.latestDiaryMood = mood;
          // 如果当前情绪是手动选择的，优先使用日记情绪
          if (this.currentEmotion === '平静' || !this.currentEmotion) {
            this.currentEmotion = mood;
          }
        }
      }
    } catch (err) {
      console.error('[Pomodoro] 加载最新日记情绪失败:', err);
    }
  }

  // 加载情绪联动白噪音推荐
  // AI 分析当前情绪，推荐最适合的白噪音
  private async loadEmotionNoiseRecommendation(): Promise<void> {
    try {
      const vm = PomodoroViewModel.getInstance();
      // 优先使用日记中的情绪，如果没有则使用手动选择的情绪
      const emotionToUse = this.latestDiaryMood || this.currentEmotion || '平静';
      
      // 如果情绪为空或无效，使用默认情绪
      if (!emotionToUse || emotionToUse.trim() === '') {
        this.aiNoiseRecommendation = WhiteNoiseType.RAIN;
        this.aiNoiseReason = '默认推荐：雨声有助于保持专注';
        return;
      }
      
      const result: SmartNoiseResult = await vm.getSmartNoiseRecommendation(emotionToUse, '学习');
      this.aiNoiseRecommendation = result.noiseType;
      this.aiNoiseReason = result.reason || '根据您的情绪推荐';
    } catch (err) {
      console.error('[Pomodoro] 加载AI推荐失败:', err);
      // 失败时使用默认推荐
      this.aiNoiseRecommendation = WhiteNoiseType.RAIN;
      this.aiNoiseReason = '默认推荐：雨声有助于保持专注';
    }
  }

  // 更新情绪后重新获取推荐
  private async updateEmotion(emotion: string): Promise<void> {
    this.currentEmotion = emotion;
    await this.loadEmotionNoiseRecommendation();
  }

  async aboutToUpdate() {
    await this.loadStatistics();
  }

  aboutToDisappear() {
    // 保存计时器状态（防止重置）
    this.saveTimerState();
    // 清理资源
    this.stopTimer();
    this.audioPlayer.release();
    this.backgroundService.destroy();
  }

  // 保存计时器状态
  private saveTimerState(): void {
    if (this.state !== PomodoroState.IDLE) {
      const timerState: TimerState = {
        remainingSeconds: this.remainingSeconds,
        state: this.state,
        currentType: this.currentType,
        startTimestamp: this.startTimestamp,
        pomodoroCount: this.pomodoroCount,
        savedAt: Date.now()
      };
      AppStorage.setOrCreate('pomodoroTimerState', JSON.stringify(timerState));
      console.info('[Pomodoro] 计时器状态已保存');
    }
  }

  // 恢复计时器状态
  private async restoreTimerState(): Promise<void> {
    try {
      const savedStateStr = AppStorage.get<string>('pomodoroTimerState');
      if (savedStateStr) {
        const savedState = JSON.parse(savedStateStr) as TimerState;
        
        // 检查保存时间是否在 2 小时内（有效期）
        const timeSinceSave = Date.now() - savedState.savedAt;
        if (timeSinceSave < 2 * 60 * 60 * 1000) {
          // 如果之前是运行状态，计算已经过去的时间
          if (savedState.state === PomodoroState.WORKING || 
              savedState.state === PomodoroState.SHORT_BREAK || 
              savedState.state === PomodoroState.LONG_BREAK) {
            const elapsedSeconds = Math.floor(timeSinceSave / 1000);
            this.remainingSeconds = Math.max(0, savedState.remainingSeconds - elapsedSeconds);
            this.state = savedState.remainingSeconds > 0 ? PomodoroState.PAUSED : PomodoroState.IDLE;
          } else {
            // 暂停状态直接恢复
            this.remainingSeconds = savedState.remainingSeconds;
            this.state = savedState.state;
          }
          
          this.currentType = savedState.currentType;
          this.pomodoroCount = savedState.pomodoroCount;
          this.totalSeconds = this.preference ? this.preference.workDuration * 60 : 25 * 60;
          this.updateProgress();
          console.info('[Pomodoro] 计时器状态已恢复');
          
          // 清除已恢复的状态
          AppStorage.delete('pomodoroTimerState');
          return;
        }
      }
    } catch (e) {
      console.warn('[Pomodoro] 恢复计时器状态失败:', e);
    }
    
    // 没有保存的状态，使用默认初始化
    this.initializeTimer();
  }

  // ==================== 数据加载 ====================

  // 加载用户偏好设置
  private async loadPreference(): Promise<void> {
    this.preference = await this.storageService.getPreference(this.context);
    if (this.preference) {
      // 同步到编辑状态
      this.whitelistApps = [...(this.preference.whitelistApps || [])];
      this.editingWorkDuration = this.preference.workDuration;
      this.editingShortBreak = this.preference.shortBreakDuration;
      this.editingLongBreak = this.preference.longBreakDuration;
      this.editingLongBreakInterval = this.preference.longBreakInterval;
      this.editingWhiteNoiseEnabled = this.preference.whiteNoiseEnabled;
      this.editingWhiteNoiseType = this.preference.whiteNoiseType;
      this.editingSoundEnabled = this.preference.soundEnabled;
    }
    this.initializeTimer();
  }

  // 加载任务列表
  private async loadTasks(): Promise<void> {
    this.tasks = await this.taskService.getTasks(this.context);
    // 默认选中第一个未完成任务
    this.currentTask = this.tasks.find(t => !t.isCompleted) || null;
  }

  // 加载统计数据
  private async loadStatistics(): Promise<void> {
    // 今日统计
    const today = this.getTodayDate();
    const todayRecord = await this.recordService.getRecordByDate(this.context, today);
    this.todayPomodoros = todayRecord.pomodoros || 0;
    this.todayFocusMinutes = todayRecord.focusMinutes || 0;

    // 最近7天记录（过滤空记录）
    const allRecords = await this.recordService.getRecentRecords(this.context, 7);
    const filteredRecords: FocusRecord[] = [];
    allRecords.forEach(record => {
      if (record.pomodoros > 0 || record.focusMinutes > 0) {
        filteredRecords.push(record);
      }
    });
    this.recentRecords = filteredRecords;
  }

  // 获取今日日期字符串
  private getTodayDate(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  // ==================== 计时器控制 ====================

  // 初始化计时器（根据偏好设置）
  private initializeTimer(): void {
    if (this.preference) {
      this.totalSeconds = this.preference.workDuration * 60;
      this.remainingSeconds = this.totalSeconds;
      this.updateProgress();
    }
  }

  // 开始计时
  private async startTimer(): Promise<void> {
    // 只有空闲或暂停状态可以开始
    if (this.state === PomodoroState.IDLE || this.state === PomodoroState.PAUSED) {
      // 根据当前类型设置状态
      this.state = this.currentType === PomodoroType.WORK ?
        PomodoroState.WORKING :
        (this.currentType === PomodoroType.SHORT_BREAK ?
          PomodoroState.SHORT_BREAK : PomodoroState.LONG_BREAK);

      // 申请后台任务（保持计时不中断）
      const bgSuccess = await this.backgroundService.startPomodoroTask();
      if (!bgSuccess) {
        console.warn('[Pomodoro] 后台任务申请失败，计时可能在息屏后中断');
      }

      // 播放开始提示音
      if (this.preference?.startSoundEnabled) {
        this.audioPlayer.playSound('start', this.context);
      }

      // 播放白噪音 - 情绪联动功能
      // 如果启用了情绪联动，根据最新日记情绪自动选择白噪音
      if (this.preference?.whiteNoiseEnabled) {
        let noiseTypeToPlay = this.preference.whiteNoiseType;
        
        // 如果启用了情绪联动，且最新日记有情绪数据，则根据情绪自动选择
        if (this.preference.emotionLinkEnabled && this.latestDiaryMood) {
          const vm = PomodoroViewModel.getInstance();
          try {
            const emotionKey = this.latestDiaryMood.toLowerCase();
            // 根据情绪映射到白噪音类型
            if (emotionKey.includes('焦虑') || emotionKey.includes('anxious')) {
              noiseTypeToPlay = 'rain'; // 焦虑 -> 雨声
            } else if (emotionKey.includes('兴奋') || emotionKey.includes('excited')) {
              noiseTypeToPlay = 'library'; // 兴奋 -> 图书馆
            } else {
              // 使用AI推荐的白噪音
              const recommendation = await vm.getSmartNoiseRecommendation(this.latestDiaryMood, '学习');
              noiseTypeToPlay = recommendation.noiseType;
            }
          } catch (err) {
            console.error('[Pomodoro] 情绪联动白噪音推荐失败:', err);
            // 失败时使用用户设置的白噪音类型
          }
        }
        
        // 确保播放白噪音（修复：无论是否情绪联动都要播放）
        if (noiseTypeToPlay && noiseTypeToPlay !== 'none') {
          console.info('[Pomodoro] 开始播放白噪音:', noiseTypeToPlay);
          this.audioPlayer.playWhiteNoise(noiseTypeToPlay, this.context);
        }
      } else {
        console.info('[Pomodoro] 白噪音功能未启用');
      }
      // 记录开始时间戳（用于后台校准）
      this.startTimestamp = Date.now() - ((this.totalSeconds - this.remainingSeconds) * 1000);
      
      // 启动计时器（每秒更新）
      this.timer = setInterval(() => {
        // 使用时间戳计算实际剩余时间（解决后台计时不准问题）
        const elapsed = Math.floor((Date.now() - this.startTimestamp) / 1000);
        this.remainingSeconds = Math.max(0, this.totalSeconds - elapsed);
        this.updateProgress();
        
        if (this.remainingSeconds <= 0) {
          this.onTimerComplete();
        }
      }, 1000);
    }
  }

  // 暂停计时
  private async pauseTimer(): Promise<void> {
    if (this.state === PomodoroState.WORKING ||
        this.state === PomodoroState.SHORT_BREAK ||
        this.state === PomodoroState.LONG_BREAK) {
      this.state = PomodoroState.PAUSED;
      this.stopTimer();
      // 暂停时释放后台任务
      await this.backgroundService.stopPomodoroTask();
    }
  }

  // 停止计时器（清除 interval）
  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 重置计时器到初始状态
  private async resetTimer(): Promise<void> {
    this.stopTimer();
    this.state = PomodoroState.IDLE;
    this.initializeTimer();
    this.audioPlayer.stopWhiteNoise();
    // 重置时释放后台任务
    await this.backgroundService.stopPomodoroTask();
  }

  // ==================== 计时完成处理 ====================
  // 核心状态转换逻辑：工作 → 休息 → 工作

  private async onTimerComplete(): Promise<void> {
    this.stopTimer();

    // 播放结束提示音
    if (this.preference?.endSoundEnabled) {
      this.audioPlayer.playSound('end', this.context);
    }

    // 停止白噪音
    this.audioPlayer.stopWhiteNoise();

    if (this.currentType === PomodoroType.WORK) {
      // 工作完成 → 进入休息
      this.pomodoroCount++;

      if (this.preference) {
        // 计算实际专注时长（基于startTimestamp，单位分钟）
        const actualDuration = Math.floor((Date.now() - this.startTimestamp) / 1000 / 60);
        const effectiveDuration = actualDuration > 0 ? actualDuration : this.preference.workDuration;
        
        // 更新番茄计数（使用实际时长）
        await this.storageService.incrementPomodoroCount(
          this.context,
          effectiveDuration
        );

        // 记录专注会话（使用实际时长）
        const session: FocusSession = {
          id: Date.now().toString(),
          startTime: this.startTimestamp,
          endTime: Date.now(),
          duration: effectiveDuration,
          taskId: this.currentTask?.id,
          taskTitle: this.currentTask?.title
        };
        console.info('[Pomodoro] 准备保存专注会话 - 时长:', effectiveDuration, '分钟, context存在:', !!this.context);
        const saveSuccess = await this.recordService.addSession(this.context, session);
        console.info('[Pomodoro] 专注会话保存结果:', saveSuccess);
        await this.loadStatistics();
      }

      // 更新任务进度
      if (this.currentTask) {
        await this.taskService.completePomodoro(this.context, this.currentTask.id);
        await this.loadTasks();

        // 检查任务是否已完成
        const updatedTask = this.tasks.find(t => t.id === this.currentTask!.id);
        if (updatedTask && updatedTask.completedPomodoros >= updatedTask.estimatedPomodoros && !updatedTask.isCompleted) {
          await this.toggleTaskComplete(updatedTask);
        }
      }

      // 决定休息类型：每 N 个番茄后长休息
      const shouldLongBreak = this.preference &&
        this.pomodoroCount % this.preference.longBreakInterval === 0;

      if (shouldLongBreak) {
        this.currentType = PomodoroType.LONG_BREAK;
        this.totalSeconds = this.preference!.longBreakDuration * 60;
      } else {
        this.currentType = PomodoroType.SHORT_BREAK;
        this.totalSeconds = this.preference!.shortBreakDuration * 60;
      }

      this.state = PomodoroState.IDLE;
      this.remainingSeconds = this.totalSeconds;
      this.updateProgress();

      promptAction.showToast({
        message: this.getCompleteMessage(),
        duration: 2000
      });
    } else {
      // 休息完成 → 准备下一个工作周期
      this.currentType = PomodoroType.WORK;
      this.totalSeconds = this.preference!.workDuration * 60;
      this.state = PomodoroState.IDLE;
      this.remainingSeconds = this.totalSeconds;
      this.updateProgress();

      promptAction.showToast({
        message: $r('app.string.pomodoro_break_complete'),
        duration: 2000
      });
    }
  }

  // 更新进度条
  private updateProgress(): void {
    if (this.totalSeconds > 0) {
      this.progress = (this.totalSeconds - this.remainingSeconds) / this.totalSeconds;
    } else {
      this.progress = 0;
    }
  }

  // 格式化时间显示（MM:SS）
  private formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  // 获取完成提示消息
  private getCompleteMessage(): ResourceStr {
    return $r('app.string.pomodoro_work_complete');
  }

  // ==================== 任务管理 ====================

  // 添加新任务
  private async addTask(): Promise<void> {
    // 验证标题
    if (!this.newTaskTitle.trim()) {
      promptAction.showToast({
        message: $r('app.string.pomodoro_task_title_required'),
        duration: 2000
      });
      return;
    }

    const newTask: Task = {
      id: Date.now().toString(),
      title: this.newTaskTitle,
      estimatedPomodoros: this.newTaskEstimated,
      completedPomodoros: 0,
      isCompleted: false,
      priority: this.newTaskPriority,
      createdAt: Date.now()
    };

    await this.taskService.addTask(this.context, newTask);
    await this.loadTasks();

    // 重置表单
    this.newTaskTitle = '';
    this.newTaskEstimated = 1;
    this.newTaskPriority = TaskPriority.MEDIUM;
    this.showAddTaskDialog = false;
  }

  // 删除任务
  private async deleteTask(task: Task): Promise<void> {
    await this.taskService.deleteTask(this.context, task.id);
    await this.loadTasks();
  }

  // 完成任务
  private async completeTask(task: Task): Promise<void> {
    await this.toggleTaskComplete(task);
  }

  // 选择任务（开始专注）
  private selectTask(task: Task): void {
    this.currentTask = task;
    this.viewMode = ViewMode.TIMER;
  }

  // ==================== 主布局 ====================

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主内容区
        Column() {
          if (this.viewMode === ViewMode.TIMER) {
            this.renderTimerView();
          } else if (this.viewMode === ViewMode.TASKS) {
            this.renderTasksView();
          } else if (this.viewMode === ViewMode.STATS) {
            this.renderStatsView();
          } else {
            this.renderSettingsView();
          }
        }
        .width('100%')
        .height('100%')
        .padding({ bottom: 60 })
        .backgroundColor(AppColors.BG_PRIMARY)

        // 底部导航栏 (仅在非专注模式下显示)
        if (this.state !== PomodoroState.WORKING) {
          PomodoroBottomNav({
            currentView: this.viewMode,
            onViewChange: (mode: string) => { this.viewMode = mode as ViewMode; }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.getTitle());
  }

  @Builder
  private getTitle() {
    Text($r('app.string.pomodoro_title'))
      .fontSize($r('app.float.number_20'))
      .fontWeight(FontWeight.Bold)
      .margin({ left: $r('app.float.number_10') })
      .height('100%');
  }

  @Builder
  private renderTimerView() {
    Scroll() {
      Column({ space: 0 }) {
        // 顶部统计卡片 (仅在非专注模式下显示)
        if (this.state !== PomodoroState.WORKING) {
          PomodoroStatsCards({
            todayFocusMinutes: this.todayFocusMinutes,
            todayPomodoros: this.todayPomodoros
          })
        }
        
        // 圆形进度条
        this.renderTimerCircle();
        
        // 当前任务显示
        this.renderCurrentTask();
        
        // 任务列表（显示在首页，只显示番茄钟待办，即estimatedPomodoros > 0的任务）
        if (this.state !== PomodoroState.WORKING && this.getPomodoroTasks().length > 0) {
          Column({ space: 8 }) {
            Text($r('app.string.pomodoro_task_list'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
              .width('100%')
              .margin({ top: 8 });
            
            // 显示所有番茄钟待办（可滚动）
            ForEach(this.getPomodoroTasks(), (task: Task) => {
              PomodoroTaskItem({
                task: task,
                onComplete: () => this.toggleTaskComplete(task),
                onSelect: () => this.selectTask(task)
              })
            }, (task: Task) => task.id);
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8, bottom: 8 });
        } else if (this.state !== PomodoroState.WORKING && this.getPomodoroTasks().length === 0) {
          // 没有番茄钟待办时显示提示
          PomodoroEmptyState()
        }
        
        // 控制按钮
        this.renderControlButtons();
      }
      .width('100%')
      .padding({ top: 20, left: 20, right: 20, bottom: 20 });
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .scrollable(ScrollDirection.Vertical);
  }
  
  @Builder
  private renderTaskItemCompact(task: Task) {
    Row({ space: 12 }) {
      // 复选框
      Stack({ alignContent: Alignment.Center }) {
        Stack()
          .width(20)
          .height(20)
          .borderRadius(10)
          .border({ width: 2, color: AppColors.BORDER })
          .backgroundColor(Color.Transparent);
      }
      .width(20)
      .height(20)
      .onClick(() => {
        this.toggleTaskComplete(task);
      });
      
      Column({ space: 4 }) {
        Text(task.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${task.completedPomodoros}/${task.estimatedPomodoros} 番茄`)
          .fontSize(12)
          .fontColor(AppColors.TEXT_SECONDARY);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(8)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.selectTask(task);
    });
  }

  @Builder
  private renderStatsCards() {
    Row({ space: AppSizes.SPACE_MD }) {
      // 今日专注时长
      Column({ space: 4 }) {
        Text(this.todayFocusMinutes.toString())
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY);
        Text($r('app.string.pomodoro_today_focus'))
          .fontSize(AppSizes.FONT_XS)
          .fontColor(AppColors.TEXT_TERTIARY);
      }
      .layoutWeight(1)
      .padding(AppSizes.SPACE_LG)
      .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(AppSizes.RADIUS_LG)
      .shadow(AppShadows.SHADOW_SM);
      
      // 今日番茄数
      Column({ space: 4 }) {
        Text(this.todayPomodoros.toString())
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.ACCENT);
        Text($r('app.string.pomodoro_today_pomodoros'))
          .fontSize(AppSizes.FONT_XS)
          .fontColor(AppColors.TEXT_TERTIARY);
      }
      .layoutWeight(1)
      .padding(AppSizes.SPACE_LG)
      .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(AppSizes.RADIUS_LG)
      .shadow(AppShadows.SHADOW_SM);
    }
    .width('100%')
    .margin({ bottom: AppSizes.SPACE_XL });
  }

  @Builder
  private renderTimerCircle() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 外层柔光晕 (Soft Glow)
      Circle()
        .width(280)
        .height(280)
        .fill(this.getProgressColor())
        .opacity(0.1)
        .animation(AppAnimations.SPRING_SLOW);

      // 2. 背景圆环 (Track)
      Circle()
        .width(240)
        .height(240)
        .fill(Color.Transparent)
        .stroke(AppColors.BG_TERTIARY)
        .strokeWidth(20)
        .strokeLineCap(LineCapStyle.Round);
      
      // 3. 进度圆环 (Progress)
      Circle()
        .width(240)
        .height(240)
        .fill(Color.Transparent)
        .stroke(this.getProgressColor())
        .strokeWidth(20)
        .strokeLineCap(LineCapStyle.Round)
        .strokeDashArray([240 * Math.PI * 2 * this.progress, 240 * Math.PI * 2]) // 简单的进度模拟，实际需要计算周长
        .rotate({ angle: -90 })
        .animation(AppAnimations.SPRING_NORMAL);
      
      // 4. 中央内容
      Column({ space: 8 }) {
        Text(this.formatTime(this.remainingSeconds))
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .fontFamily('HarmonyOS Sans Display');
        
        Text(this.getTypeText())
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.TEXT_SECONDARY)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor('rgba(255,255,255,0.2)')
          .backdropBlur(10)
          .borderRadius(16);
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(300)
    .height(300)
    .margin({ bottom: AppSizes.SPACE_2XL });
  }

  @Builder
  private renderCurrentTask() {
    if (this.currentTask) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text($r('app.string.pomodoro_current_task'))
            .fontSize(12)
            .fontColor(AppColors.TEXT_HINT);
          Text(this.currentTask.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(`${this.currentTask.completedPomodoros}/${this.currentTask.estimatedPomodoros} 番茄`)
            .fontSize(14)
            .fontColor(AppColors.TEXT_SECONDARY);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .padding(16)
      .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(12)
      .margin({ bottom: 24 })
      .shadow(AppShadows.SHADOW_SM);
    } else {
      Row() {
        Text($r('app.string.pomodoro_no_task'))
          .fontSize(16)
          .fontColor(AppColors.TEXT_HINT);
      }
      .width('100%')
      .padding(16)
      .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(12)
      .margin({ bottom: 24 })
      .justifyContent(FlexAlign.Center)
      .shadow(AppShadows.SHADOW_SM);
    }
  }

  @Builder
  private renderControlButtons() {
    Row({ space: AppSizes.SPACE_LG }) {
      // 重置按钮
      Button({ type: ButtonType.Circle }) {
        Text('↺')
          .fontSize(24)
          .fontColor(AppColors.TEXT_SECONDARY)
      }
      .width(56)
      .height(56)
      .backgroundColor(AppColors.BG_SECONDARY)
      .shadow(AppShadows.SHADOW_SM)
      .onClick(() => {
        this.resetTimer();
      });
      
      // 开始/暂停按钮 (大) - 问题15修复：增强可见性
      Button({ type: ButtonType.Normal }) {
        Text(this.getControlButtonText())
          .fontSize(AppSizes.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_WHITE)
      }
      .width(140)
      .height(64)
      .borderRadius(32)
      // 问题15修复：WORKING状态使用橙色警示色，更清晰
      .backgroundColor(this.state === PomodoroState.IDLE || this.state === PomodoroState.PAUSED 
        ? AppColors.ACCENT 
        : '#FF9800')  // 橙色暂停按钮
      .linearGradient(this.state === PomodoroState.IDLE || this.state === PomodoroState.PAUSED 
        ? AppGradients.PRIMARY_BTN 
        : { angle: 180, colors: [['#FFB74D', 0], ['#FF9800', 1]] })  // 橙色渐变
      .shadow(AppShadows.SHADOW_MD)
      .onClick(() => {
        if (this.state === PomodoroState.IDLE || this.state === PomodoroState.PAUSED) {
          this.startTimer();
        } else {
          this.pauseTimer();
        }
      });

      // 更多设置按钮
      Button({ type: ButtonType.Circle }) {
        Text('⚙️')
          .fontSize(20)
      }
      .width(56)
      .height(56)
      .backgroundColor(AppColors.BG_SECONDARY)
      .shadow(AppShadows.SHADOW_SM)
      .onClick(() => {
        this.viewMode = ViewMode.SETTINGS;
      });
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: AppSizes.SPACE_XL });
  }

  @Builder
  private renderTasksView() {
    Column() {
      // 标题固定在顶部
      Row({ space: 8 }) {
        Text('当前番茄待办')
          .fontSize(AppSizes.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text(`${this.getPomodoroTasks().length} 个`)
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .padding({ left: 8, right: 12, top: 4, bottom: 4 })
          .backgroundColor(AppColors.ACCENT_BG)
          .borderRadius(12)
      }
      .width('100%')
      .padding({ top: AppSizes.SPACE_2XL, bottom: AppSizes.SPACE_MD, left: AppSizes.SPACE_2XL, right: AppSizes.SPACE_2XL })
      
      // 内容区域
      if (this.getPomodoroTasks().length > 0) {
        // 有任务时显示列表
        Scroll() {
          Column({ space: AppSizes.SPACE_XL }) {
            Column({ space: AppSizes.SPACE_SM }) {
              ForEach(this.getPomodoroTasks(), (task: Task) => {
                this.renderTaskItem(task);
              }, (task: Task) => task.id);
            }
            .width('100%')
            .padding({ left: AppSizes.SPACE_2XL, right: AppSizes.SPACE_2XL })
            
            // 已完成记录
            if (this.getCompletedPomodoroTasks().length > 0) {
              Column({ space: AppSizes.SPACE_MD }) {
                // 标题卡片
                Row({ space: 8 }) {
                  Text('已完成番茄')
                    .fontSize(AppSizes.FONT_LG)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.TEXT_PRIMARY)
                  Text(`${this.getCompletedPomodoroTasks().length} 个`)
                    .fontSize(AppSizes.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .padding({ left: 8, right: 12, top: 4, bottom: 4 })
                    .backgroundColor(AppColors.SUCCESS_BG)
                    .borderRadius(12)
                }
                .width('100%')
                .padding({ top: AppSizes.SPACE_LG, bottom: AppSizes.SPACE_SM })
                
                Column({ space: AppSizes.SPACE_SM }) {
                  ForEach(this.getCompletedPomodoroTasks(), (task: Task) => {
                    this.renderTaskItem(task);
                  }, (task: Task) => task.id);
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: AppSizes.SPACE_2XL, right: AppSizes.SPACE_2XL, bottom: AppSizes.SPACE_4XL })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      } else {
        // 无任务时，空状态提示居中显示
        Column({ space: AppSizes.SPACE_MD }) {
          Text('📋')
            .fontSize(48)
            .opacity(0.6)
          Text('暂无未完成的番茄任务')
            .fontSize(AppSizes.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('去主页添加一个番茄钟待办，开始专注吧')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%');
  }
  
  /**
   * 获取排序后的任务列表（未完成的在前，已完成的在后）
   */
  private getSortedTasks(): Task[] {
    const incomplete: Task[] = [];
    const completed: Task[] = [];
    this.tasks.forEach(t => {
      if (!t.isCompleted) {
        incomplete.push(t);
      } else {
        completed.push(t);
      }
    });
    const result: Task[] = [];
    incomplete.forEach(t => result.push(t));
    completed.forEach(t => result.push(t));
    return result;
  }
  
  /**
   * 获取未完成的任务列表
   */
  private getIncompleteTasks(): Task[] {
    const result: Task[] = [];
    this.tasks.forEach(t => {
      if (!t.isCompleted) {
        result.push(t);
      }
    });
    return result;
  }

  /**
   * 获取番茄钟待办（estimatedPomodoros > 0 且未完成）
   */
  private getPomodoroTasks(): Task[] {
    return this.tasks.filter(t => !t.isCompleted && t.estimatedPomodoros > 0);
  }

  /** 获取已完成的番茄钟任务 */
  private getCompletedPomodoroTasks(): Task[] {
    return this.tasks.filter(t => t.isCompleted && t.estimatedPomodoros > 0);
  }
  
  /**
   * 获取有数据的记录列表（过滤掉空数据）
   */
  private getRecordsWithData(): FocusRecord[] {
    const result: FocusRecord[] = [];
    this.recentRecords.forEach(record => {
      if (record.pomodoros > 0 || record.focusMinutes > 0) {
        result.push(record);
      }
    });
    return result;
  }
  
  @Builder
  private renderAddTaskDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.showAddTaskDialog = false;
          this.newTaskTitle = '';
          this.newTaskEstimated = 1;
        });
      
      // 对话框内容
      Column({ space: 16 }) {
        Text($r('app.string.pomodoro_add_task'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%');
        
        // 任务名称输入
        TextInput({ placeholder: $r('app.string.pomodoro_task_title_placeholder'), text: this.newTaskTitle })
          .onChange((value: string) => {
            this.newTaskTitle = value;
          })
          .width('100%')
          .height(48)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 12, right: 12 });
        
        // 预计番茄数
        Row({ space: 12 }) {
          Text($r('app.string.pomodoro_task_estimated'))
            .fontSize(14)
            .fontColor(AppColors.TEXT_SECONDARY);
          TextInput({ text: this.newTaskEstimated.toString() })
            .onChange((value: string) => {
              const num = parseInt(value);
              if (!isNaN(num) && num > 0) {
                this.newTaskEstimated = num;
              }
            })
            .width(80)
            .height(40)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 });
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween);
        
        // 优先级选择（自动设置番茄数）
        Row({ space: 12 }) {
          Text($r('app.string.pomodoro_task_priority'))
            .fontSize(14)
            .fontColor(AppColors.TEXT_SECONDARY);
          Row({ space: 8 }) {
            // 低优先级
            Button(undefined, { type: ButtonType.Normal }) {
              Text($r('app.string.pomodoro_task_priority_low'))
                .fontSize(12)
                .fontColor(this.newTaskPriority === TaskPriority.LOW ? '#FFFFFF' : '#666666');
            }
            .width(60)
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.newTaskPriority === TaskPriority.LOW ? AppColors.SUCCESS : AppColors.BG_TERTIARY)
            .onClick(() => {
              this.newTaskPriority = TaskPriority.LOW;
              this.newTaskEstimated = 1; // 低优先级默认1个番茄
            });
            
            // 中优先级
            Button(undefined, { type: ButtonType.Normal }) {
              Text($r('app.string.pomodoro_task_priority_medium'))
                .fontSize(12)
                .fontColor(this.newTaskPriority === TaskPriority.MEDIUM ? '#FFFFFF' : '#666666');
            }
            .width(60)
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.newTaskPriority === TaskPriority.MEDIUM ? AppColors.WARNING : AppColors.BG_TERTIARY)
            .onClick(() => {
              this.newTaskPriority = TaskPriority.MEDIUM;
              this.newTaskEstimated = 2; // 中优先级默认2个番茄
            });
            
            // 高优先级
            Button(undefined, { type: ButtonType.Normal }) {
              Text($r('app.string.pomodoro_task_priority_high'))
                .fontSize(12)
                .fontColor(this.newTaskPriority === TaskPriority.HIGH ? '#FFFFFF' : '#666666');
            }
            .width(60)
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.newTaskPriority === TaskPriority.HIGH ? AppColors.ERROR : AppColors.BG_TERTIARY)
            .onClick(() => {
              this.newTaskPriority = TaskPriority.HIGH;
              this.newTaskEstimated = 3; // 高优先级默认3个番茄
            });
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween);
        
        // 按钮
        Row({ space: 12 }) {
          Button(undefined, { type: ButtonType.Normal }) {
            Text($r('app.string.pomodoro_cancel'))
              .fontSize(16)
              .fontColor(AppColors.TEXT_SECONDARY);
          }
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor('#F5F5F5')
          .onClick(() => {
            this.showAddTaskDialog = false;
            this.newTaskTitle = '';
            this.newTaskEstimated = 1;
          });
          
          Button(undefined, { type: ButtonType.Normal }) {
            Text($r('app.string.pomodoro_save'))
              .fontSize(16)
              .fontColor(AppColors.TEXT_WHITE);
          }
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(AppColors.SUCCESS)
          .onClick(() => {
            this.addTask();
          });
        }
        .width('100%');
      }
      .width('90%')
      .padding(24)
          .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(16)
      .shadow({ radius: 8, color: '#1F000000', offsetX: 0, offsetY: 4 });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private renderTaskItem(task: Task) {
    Row({ space: AppSizes.SPACE_MD }) {
      // 复选框
      Stack({ alignContent: Alignment.Center }) {
        if (task.isCompleted) {
          // 已完成：显示绿色对勾
          Stack({ alignContent: Alignment.Center }) {
            Stack()
              .width(22)
              .height(22)
              .borderRadius(11)
              .backgroundColor(AppColors.SUCCESS);
            Text('✓')
              .fontSize(14)
              .fontColor(AppColors.TEXT_WHITE)
              .fontWeight(FontWeight.Bold);
          }
          .width(22)
          .height(22);
        } else {
          // 未完成：显示空复选框
          Stack()
            .width(22)
            .height(22)
            .borderRadius(11)
            .border({ width: 2, color: AppColors.TEXT_TERTIARY })
            .backgroundColor(Color.Transparent);
        }
      }
      .width(22)
      .height(22)
      .onClick(() => {
        this.toggleTaskComplete(task);
      });
      
      // 任务信息
      Column({ space: 6 }) {
        Text(task.title)
          .fontSize(AppSizes.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(task.isCompleted ? AppColors.TEXT_TERTIARY : AppColors.TEXT_PRIMARY)
          .decoration({ type: task.isCompleted ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(22);
        Row({ space: AppSizes.SPACE_XS }) {
          Text(`${task.completedPomodoros}/${task.estimatedPomodoros} 番茄`)
            .fontSize(AppSizes.FONT_XS)
            .fontColor(AppColors.TEXT_SECONDARY);
          if (task.priority === TaskPriority.HIGH) {
            Text('高')
              .fontSize(AppSizes.FONT_2XS)
              .fontColor(AppColors.ERROR)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.ERROR_BG)
              .borderRadius(8);
          } else if (task.priority === TaskPriority.MEDIUM) {
            Text('中')
              .fontSize(AppSizes.FONT_2XS)
              .fontColor(AppColors.WARNING)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.WARNING_BG)
              .borderRadius(8);
          } else if (task.priority === TaskPriority.LOW) {
            Text('低')
              .fontSize(AppSizes.FONT_2XS)
              .fontColor(AppColors.SUCCESS)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(AppColors.SUCCESS_BG)
              .borderRadius(8);
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .padding(AppSizes.SPACE_LG)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
    .margin({ bottom: AppSizes.SPACE_SM })
    .onClick(() => {
      if (!task.isCompleted) {
        this.selectTask(task);
      }
    });
  }
  
  /**
   * 切换任务完成状态
   */
  private async toggleTaskComplete(task: Task): Promise<void> {
    const wasCompleted = task.isCompleted;
    task.isCompleted = !task.isCompleted;
    if (task.isCompleted) {
      task.completedAt = Date.now();
    } else {
      task.completedAt = undefined;
    }
    await this.taskService.updateTask(this.context, task);
    await this.loadTasks();
    AppStorage.setOrCreate('tasksUpdatedAt', Date.now());
    
    // 如果任务完成，更新统计（记录完成的任务）
    if (task.isCompleted && !wasCompleted) {
      // 任务完成时，记录到专注记录中
      const today = this.getTodayDate();
      const todayRecord = await this.recordService.getRecordByDate(this.context, today);
      // 可以在这里添加任务完成的额外统计逻辑
      await this.loadStatistics();
    }
  }

  @Builder
  private renderStatsView() {
    Scroll() {
      Column({ space: 20 }) {
        Text($r('app.string.pomodoro_statistics'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ top: 20 });
        
        // 今日统计卡片
        Column({ space: 16 }) {
          this.renderStatCard($r('app.string.pomodoro_today_focus'), `${this.todayFocusMinutes} 分钟`);
          this.renderStatCard($r('app.string.pomodoro_today_pomodoros'), `${this.todayPomodoros} 个`);
        }
        .width('100%')
        .padding({ left: 20, right: 20 });
        
        // 最近7天统计（只显示有数据的）
        if (this.recentRecords.length > 0) {
          Column({ space: 12 }) {
            Text($r('app.string.pomodoro_statistics_recent_days'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
              .width('100%')
              .margin({ top: 8 });
            
            ForEach(this.recentRecords, (record: FocusRecord) => {
              this.renderDayStatCard(record);
            }, (record: FocusRecord) => record.date);
          }
          .width('100%')
          .padding({ left: 20, right: 20 });
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%');
  }
  
  @Builder
  private renderDayStatCard(record: FocusRecord) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(record.date)
            .fontSize(14)
            .fontColor(AppColors.TEXT_SECONDARY);
          Text(`${record.focusMinutes} 分钟 · ${record.pomodoros} 个番茄`)
            .fontSize(12)
            .fontColor(AppColors.TEXT_TERTIARY);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%');
      
      // 显示完成的任务列表
      if (record.records && record.records.length > 0) {
        Column({ space: 4 }) {
          ForEach(record.records, (session: FocusSession) => {
            if (session.taskTitle) {
              Row({ space: 8 }) {
                Text('•')
                  .fontSize(12)
                  .fontColor('#4CAF50');
                Text(session.taskTitle)
                  .fontSize(12)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1);
                Text(`${session.duration}分钟`)
                  .fontSize(11)
                  .fontColor(AppColors.TEXT_TERTIARY);
              }
              .width('100%');
            }
          }, (session: FocusSession) => session.id);
        }
        .width('100%')
        .margin({ top: 8 })
        .padding({ top: 8 })
        .border({ width: 1, color: '#F0F0F0' });
      }
    }
    .width('100%')
    .padding(16)
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.BG_SECONDARY)
    .linearGradient(AppGradients.CARD_SUBTLE)
    .borderRadius(12)
    .margin({ bottom: 8 })
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.04)', offsetX: 0, offsetY: 3 });
  }

  @Builder
  private renderStatCard(title: ResourceStr, value: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(14)
        .fontColor('#999999');
      Text(value)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY);
    }
    .width('100%')
    .padding(24)
    .width('100%')
    .padding(24)
    .backgroundColor(AppColors.BG_SECONDARY)
    .linearGradient(AppGradients.SPA_SKY)
    .borderRadius(16)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.05)', offsetX: 0, offsetY: 4 });
  }

  @Builder
  private renderSettingsView() {
    Scroll() {
      Column({ space: 20 }) {
        Text($r('app.string.pomodoro_settings'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ top: 20 });
        
        // 基础设置
        Column({ space: 16 }) {
          this.renderBasicSettingsSection();
          this.renderWhiteNoiseSettingsSection();
          // 应用白名单功能已删除
        }
        .width('100%')
        .padding({ left: 20, right: 20 });
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY);
  }
  
  @Builder
  private renderBasicSettingsSection() {
    Column({ space: 12 }) {
      Text('基础设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%');
      
      Column({ space: 12 }) {
        this.renderBasicSettings();
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)
      .borderRadius(12)
      .shadow({ radius: 4, color: '#1F000000', offsetX: 0, offsetY: 2 });
    }
    .width('100%');
  }
  
  @Builder
  private renderWhiteNoiseSettingsSection() {
    Column({ space: 12 }) {
      Text('白噪音设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%');
      
      Column({ space: 12 }) {
        this.renderWhiteNoiseSettings();
        
        // 情绪联动 AI 推荐
        this.renderEmotionNoiseSection();
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)
      .borderRadius(12)
      .shadow({ radius: 4, color: '#1F000000', offsetX: 0, offsetY: 2 });
    }
    .width('100%');
  }

  // 情绪联动白噪音推荐
  @Builder
  private renderEmotionNoiseSection() {
    Column({ space: 12 }) {
      // 分割线
      Divider()
        .strokeWidth(1)
        .color('#E0E0E0')
        .margin({ top: 8, bottom: 8 });

      // 情绪联动标题
      Row() {
        Text('✨ 智能情绪联动')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY);
        Blank();
        Text('AI 推荐')
          .fontSize(10)
          .fontColor(AppColors.TEXT_WHITE)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(AppColors.SUCCESS)
          .borderRadius(8);
      }
      .width('100%');

      // 当前情绪选择
      Row({ space: 6 }) {
        Text('当前情绪:')
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY);
        
        ForEach(['😊 开心', '😌 平静', '😰 焦虑', '😔 低落', '🔥 专注'], (item: string) => {
          Column() {
            Text(item.split(' ')[0])
              .fontSize(18)
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.currentEmotion === item.split(' ')[1] ? '#E8F5E9' : '#F5F5F5')
          .border({
            width: this.currentEmotion === item.split(' ')[1] ? 2 : 0,
            color: '#4CAF50'
          })
          .onClick(() => {
            this.updateEmotion(item.split(' ')[1]);
          });
        });
      }
      .width('100%')
      .justifyContent(FlexAlign.Start);

      // AI 推荐结果
      if (this.aiNoiseRecommendation && this.aiNoiseRecommendation !== 'none') {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('🎵')
              .fontSize(16);
            Text(`推荐: ${this.getWhiteNoiseTypeText(this.aiNoiseRecommendation)}`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY);
          }

          Text(this.aiNoiseReason)
            .fontSize(12)
            .fontColor(AppColors.TEXT_SECONDARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          // 应用推荐按钮
          Button('应用此推荐')
            .fontSize(12)
            .height(32)
            .width('100%')
            .borderRadius(16)
            .backgroundColor(AppColors.SUCCESS)
            .fontColor(AppColors.TEXT_WHITE)
            .margin({ top: 4 })
            .onClick(() => {
              if (this.preference) {
                this.preference.whiteNoiseEnabled = true;
                this.preference.whiteNoiseType = this.aiNoiseRecommendation;
                this.storageService.savePreference(this.context, this.preference);
                this.audioPlayer.playWhiteNoise(this.aiNoiseRecommendation, this.context);
                promptAction.showToast({ message: '已应用 AI 推荐' });
              }
            });
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.isDarkMode ? 'rgba(76, 175, 80, 0.15)' : '#F1F8E9')
        .borderRadius(8)
        .margin({ top: 4 });
      }
    }
    .width('100%');
  }
  
  @Builder
  private renderWhitelistSettingsSection() {
    Column({ space: 12 }) {
      Text('应用白名单')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%');
      
      Column({ space: 12 }) {
        this.renderWhitelistSettings();
      }
      .width('100%')
      .padding(16)
          .backgroundColor(AppColors.BG_SECONDARY)
      .borderRadius(12)
      .shadow({ radius: 4, color: '#1F000000', offsetX: 0, offsetY: 2 });
    }
    .width('100%');
  }
  
  @Builder
  private renderBasicSettings() {
    // 工作时长
    Row({ space: 12 }) {
      Text($r('app.string.pomodoro_work_duration'))
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY)
        .layoutWeight(1);
      TextInput({ text: this.preference?.workDuration.toString() || '25' })
        .onChange((value: string) => {
          const num = parseInt(value);
          if (!isNaN(num) && num > 0) {
            this.editingWorkDuration = num;
          }
        })
        .width(80)
        .height(40)
        .backgroundColor(AppColors.BG_TERTIARY)
        .fontColor(AppColors.TEXT_PRIMARY)
        .borderRadius(8);
      Text('分钟')
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY);
    }
    .width('100%');
    
    // 短休息时长
    Row({ space: 12 }) {
      Text($r('app.string.pomodoro_short_break_duration'))
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY)
        .layoutWeight(1);
      TextInput({ text: this.preference?.shortBreakDuration.toString() || '5' })
        .onChange((value: string) => {
          const num = parseInt(value);
          if (!isNaN(num) && num > 0) {
            this.editingShortBreak = num;
          }
        })
        .width(80)
        .height(40)
        .backgroundColor(AppColors.BG_TERTIARY)
        .fontColor(AppColors.TEXT_PRIMARY)
        .borderRadius(8);
      Text('分钟')
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY);
    }
    .width('100%');
    
    // 长休息时长
    Row({ space: 12 }) {
      Text($r('app.string.pomodoro_long_break_duration'))
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY)
        .layoutWeight(1);
      TextInput({ text: this.preference?.longBreakDuration.toString() || '15' })
        .onChange((value: string) => {
          const num = parseInt(value);
          if (!isNaN(num) && num > 0) {
            this.editingLongBreak = num;
          }
        })
        .width(80)
        .height(40)
        .backgroundColor(AppColors.BG_TERTIARY)
        .fontColor(AppColors.TEXT_PRIMARY)
        .borderRadius(8);
      Text('分钟')
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY);
    }
    .width('100%');
    
    // 保存按钮
    Button(undefined, { type: ButtonType.Normal }) {
      Text($r('app.string.pomodoro_save'))
        .fontSize(16)
        .fontColor('#FFFFFF');
    }
    .width('100%')
    .height(44)
    .borderRadius(22)
    .backgroundColor('#4CAF50')
    .margin({ top: 8 })
    .onClick(() => {
      this.saveBasicSettings();
    });
  }
  
  @Builder
  private renderWhiteNoiseSettings() {
    // 启用白噪音
    Row({ space: 12 }) {
      Text($r('app.string.pomodoro_white_noise_enabled'))
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY)
        .layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: this.preference?.whiteNoiseEnabled || false })
        .onChange((isOn: boolean) => {
          if (this.preference) {
            this.preference.whiteNoiseEnabled = isOn;
            this.storageService.savePreference(this.context, this.preference);
            if (isOn && this.preference.whiteNoiseType !== 'none') {
              this.audioPlayer.playWhiteNoise(this.preference.whiteNoiseType, this.context);
            } else {
              this.audioPlayer.stopWhiteNoise();
            }
          }
        });
    }
    .width('100%');
    
    // 白噪音类型 - 暗夜模式优化
    if (this.preference?.whiteNoiseEnabled) {
      Row({ space: 12 }) {
        Text($r('app.string.pomodoro_white_noise_title'))
          .fontSize(14)
          .fontColor(AppColors.TEXT_SECONDARY)
          .layoutWeight(1);
        Button(undefined, { type: ButtonType.Normal }) {
          Text(this.getWhiteNoiseTypeText(this.preference?.whiteNoiseType || 'none'))
            .fontSize(14)
            .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY);
        }
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_TERTIARY : AppColors.BG_TERTIARY)
        .border({ 
          width: this.isDarkMode ? 1 : 0, 
          color: this.isDarkMode ? 'rgba(255, 255, 255, 0.15)' : '#00000000' 
        })
        .onClick(() => {
          this.showWhiteNoiseMenu();
        });
      }
      .width('100%')
      .margin({ top: 8 });
    }
  }
  
  @Builder
  private renderWhitelistSettings() {
    Text($r('app.string.pomodoro_whitelist_desc'))
      .fontSize(12)
      .fontColor('#999999')
      .width('100%')
      .margin({ bottom: 8 });
    
    if (this.whitelistApps.length === 0) {
      Text($r('app.string.pomodoro_whitelist_empty'))
        .fontSize(14)
        .fontColor('#999999')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(20);
    } else {
      ForEach(this.whitelistApps, (app: string) => {
        Row({ space: 12 }) {
          Text(app)
            .fontSize(14)
            .fontColor(AppColors.TEXT_PRIMARY)
            .layoutWeight(1);
          Button(undefined, { type: ButtonType.Circle }) {
            Text('×')
              .fontSize(20)
              .fontColor(AppColors.ERROR);
          }
          .width(32)
          .height(32)
          .backgroundColor('#FFEBEE')
          .onClick(() => {
            this.removeWhitelistApp(app);
          });
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .margin({ bottom: 8 });
      }, (app: string) => app);
    }
    
    Button(undefined, { type: ButtonType.Normal }) {
      Text($r('app.string.pomodoro_whitelist_add'))
        .fontSize(14)
        .fontColor('#4CAF50');
    }
    .width('100%')
    .height(40)
    .borderRadius(20)
    .backgroundColor('#E8F5E9')
    .margin({ top: 8 })
    .onClick(() => {
      this.addWhitelistApp();
    });
  }
  
  private async saveBasicSettings(): Promise<void> {
    if (this.preference) {
      this.preference.workDuration = this.editingWorkDuration;
      this.preference.shortBreakDuration = this.editingShortBreak;
      this.preference.longBreakDuration = this.editingLongBreak;
      this.preference.longBreakInterval = this.editingLongBreakInterval;
      await this.storageService.savePreference(this.context, this.preference);
      this.initializeTimer();
      promptAction.showToast({
        message: '设置已保存',
        duration: 2000
      });
    }
  }
  
  private getWhiteNoiseTypeText(type: string): string {
    switch (type) {
      case 'rain':
        return '雨声';
      case 'ocean':
        return '海浪';
      case 'forest':
        return '森林';
      case 'library':
        return '图书馆';
      case 'fire':
        return '壁炉';
      case 'none':
        return '无';
      default:
        return '无';
    }
  }
  
  private async showWhiteNoiseMenu(): Promise<void> {
    if (!this.preference) return;
    
    interface WhiteNoiseOption {
      text: Resource;
      value: string;
    }
    
    const options: WhiteNoiseOption[] = [
      { text: $r('app.string.pomodoro_white_noise_none'), value: 'none' },
      { text: $r('app.string.pomodoro_white_noise_rain'), value: 'rain' },
      { text: $r('app.string.pomodoro_white_noise_ocean'), value: 'ocean' },
      { text: $r('app.string.pomodoro_white_noise_forest'), value: 'forest' }
    ];
    
    const buttonTexts: Resource[] = [
      $r('app.string.pomodoro_white_noise_none'),
      $r('app.string.pomodoro_white_noise_rain'),
      $r('app.string.pomodoro_white_noise_ocean'),
      $r('app.string.pomodoro_white_noise_forest')
    ];
    
    // 注意：由于 Resource 类型限制，暂时只使用原有的4个选项
    // 如果需要添加 library 和 fire，需要在 string.json 中添加资源定义
    const buttonTextsWithLibrary: Resource[] = [
      $r('app.string.pomodoro_white_noise_none'),
      $r('app.string.pomodoro_white_noise_rain'),
      $r('app.string.pomodoro_white_noise_ocean'),
      $r('app.string.pomodoro_white_noise_forest')
    ];
    
    const optionsWithLibrary: WhiteNoiseOption[] = [
      { text: $r('app.string.pomodoro_white_noise_none'), value: 'none' },
      { text: $r('app.string.pomodoro_white_noise_rain'), value: 'rain' },
      { text: $r('app.string.pomodoro_white_noise_ocean'), value: 'ocean' },
      { text: $r('app.string.pomodoro_white_noise_forest'), value: 'forest' }
    ];
    
    promptAction.showActionMenu({
      title: $r('app.string.pomodoro_white_noise_title'),
      buttons: [
        { text: buttonTextsWithLibrary[0], color: this.isDarkMode ? '#FFFFFF' : '#333333' },
        { text: buttonTextsWithLibrary[1], color: this.isDarkMode ? '#FFFFFF' : '#333333' },
        { text: buttonTextsWithLibrary[2], color: this.isDarkMode ? '#FFFFFF' : '#333333' },
        { text: buttonTextsWithLibrary[3], color: this.isDarkMode ? '#FFFFFF' : '#333333' }
      ]
    }).then(async result => {
      const selected = optionsWithLibrary[result.index];
      if (selected) {
        this.preference!.whiteNoiseType = selected.value;
        this.preference!.whiteNoiseEnabled = selected.value !== 'none';
        
        // 偏好学习功能：记录用户手动选择的白噪音
        if (selected.value !== 'none') {
          const vm = PomodoroViewModel.getInstance();
          const emotionKey = this.latestDiaryMood || this.currentEmotion || '平静';
          await vm.recordNoiseSelection(emotionKey, selected.value as WhiteNoiseType);
          console.info(`[Pomodoro] 已记录偏好: ${emotionKey} -> ${selected.value}`);
        }
        
        if (this.state === PomodoroState.WORKING || 
            this.state === PomodoroState.SHORT_BREAK || 
            this.state === PomodoroState.LONG_BREAK) {
          if (this.preference!.whiteNoiseEnabled) {
            this.audioPlayer.playWhiteNoise(selected.value, this.context);
          } else {
            this.audioPlayer.stopWhiteNoise();
          }
        }
        
        this.storageService.savePreference(this.context, this.preference!);
      }
    }).catch(() => {});
  }

  private async removeWhitelistApp(app: string): Promise<void> {
    if (this.preference) {
      this.preference.whitelistApps = this.preference.whitelistApps.filter(a => a !== app);
      await this.storageService.savePreference(this.context, this.preference);
      this.whitelistApps = [...this.preference.whitelistApps];
    }
  }

  private async addWhitelistApp(): Promise<void> {
    // TODO: 实现应用选择器
    promptAction.showToast({
      message: '应用选择功能开发中',
      duration: 2000
    });
  }

  // ==================== 底部导航栏 ====================

  @Builder
  private renderBottomNav() {
    Row({ space: 0 }) {
      // 使用 Unicode 符号代替 emoji
      this.renderNavItem(ViewMode.TIMER, '◷', $r('app.string.pomodoro_title'));
      this.renderNavItem(ViewMode.TASKS, '≡', $r('app.string.pomodoro_task_list'));
      this.renderNavItem(ViewMode.STATS, '▤', $r('app.string.pomodoro_statistics'));
      this.renderNavItem(ViewMode.SETTINGS, '⚙', $r('app.string.pomodoro_settings'));
    }
    .width('100%')
    .height(60)
          .backgroundColor(AppColors.BG_SECONDARY)
    .shadow({ radius: 8, color: '#1F000000', offsetX: 0, offsetY: -2 })
    .alignItems(VerticalAlign.Bottom);
  }

  @Builder
  private renderNavItem(mode: ViewMode, icon: string, label: ResourceStr) {
    Column({ space: 4 }) {
      Text(icon)
        .fontSize(24)
        .fontColor(this.viewMode === mode ? '#1C1917' : '#999999');
      Text(label)
        .fontSize(12)
        .fontColor(this.viewMode === mode ? '#1C1917' : '#999999');
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(async () => {
      this.viewMode = mode;
      // 切换到统计页面时重新加载数据
      if (mode === ViewMode.STATS) {
        await this.loadStatistics();
      }
    });
  }

  private getTypeText(): ResourceStr {
    switch (this.currentType) {
      case PomodoroType.WORK:
        return $r('app.string.pomodoro_type_work');
      case PomodoroType.SHORT_BREAK:
        return $r('app.string.pomodoro_type_short_break');
      case PomodoroType.LONG_BREAK:
        return $r('app.string.pomodoro_type_long_break');
      default:
        return '';
    }
  }

  private getControlButtonText(): ResourceStr {
    if (this.state === PomodoroState.IDLE || this.state === PomodoroState.PAUSED) {
      return $r('app.string.pomodoro_start');
    } else {
      return $r('app.string.pomodoro_pause');
    }
  }

  private getControlButtonColor(): string {
    if (this.state === PomodoroState.IDLE || this.state === PomodoroState.PAUSED) {
      return '#4CAF50';
    } else {
      return '#FF9800';
    }
  }

  private getProgressColor(): string {
    switch (this.currentType) {
      case PomodoroType.WORK:
        return '#F44336';
      case PomodoroType.SHORT_BREAK:
        return '#4CAF50';
      case PomodoroType.LONG_BREAK:
        return '#2196F3';
      default:
        return '#F44336';
    }
  }
}
