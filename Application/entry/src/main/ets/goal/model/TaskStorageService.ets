import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Task } from './Task';
import { CloudDBService } from '../../common/services/CloudDBService';
import { CloudTask } from '../../common/model/CloudTask';

/**
 * 任务存储服务 - 本地 + 云端双向同步
 * 
 * 同步策略：
 * 1. 本地优先：所有操作先在本地完成，确保离线可用
 * 2. 异步同步：本地操作成功后异步同步到云端
 * 3. 失败静默：云端同步失败不影响本地操作，下次登录时重新同步
 */
export class TaskStorageService {
  private static instance: TaskStorageService;
  private dataPreferences: preferences.Preferences | null = null;
  private readonly TASKS_KEY = 'pomodoro_tasks';
  private readonly COMPLETED_TASKS_KEY = 'completed_tasks_history';
  private readonly STORE_NAME = 'pomodoro_store';
  private cloudDBService: CloudDBService;

  private constructor() {
    this.cloudDBService = CloudDBService.getInstance();
  }

  public static getInstance(): TaskStorageService {
    if (!TaskStorageService.instance) {
      TaskStorageService.instance = new TaskStorageService();
    }
    return TaskStorageService.instance;
  }

  /**
   * 获取当前用户ID
   */
  private getUserId(): string {
    return AppStorage.get<string>('currentUserId') || '';
  }

  /**
   * 初始化本地存储
   */
  public async init(context: Context): Promise<void> {
    try {
      this.dataPreferences = await preferences.getPreferences(context, this.STORE_NAME);
      console.info('[TaskStorage] Init success.');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Init failed. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  /**
   * 获取所有任务（本地）
   */
  public async getTasks(context: Context): Promise<Task[]> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        const value: preferences.ValueType = await this.dataPreferences.get(this.TASKS_KEY, '[]');
        if (value && typeof value === 'string' && value !== '[]') {
          const tasks: Task[] = JSON.parse(value);
          return tasks;
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Get tasks failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return [];
  }

  /**
   * 保存任务列表（本地 + 云端同步）
   */
  public async saveTasks(context: Context, tasks: Task[]): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        // 1. 先保存到本地
        await this.dataPreferences.put(this.TASKS_KEY, JSON.stringify(tasks));
        await this.dataPreferences.flush();
        console.info('[TaskStorage] Save tasks to local success.');
        
        // 2. 异步同步到云端（不阻塞本地操作）
        this.syncTasksToCloud(tasks);
        
        return true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Save tasks failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return false;
  }

  /**
   * 异步同步任务到云端
   */
  private async syncTasksToCloud(tasks: Task[]): Promise<void> {
    const userId = this.getUserId();
    if (!userId) {
      console.warn('[TaskStorage] 未登录，跳过云端同步');
      return;
    }

    try {
      const cloudTasks: CloudTask[] = tasks.map(t => CloudTask.fromLocalTask(t, userId));
      await this.cloudDBService.upsertTasks(cloudTasks);
      console.info('[TaskStorage] 云端同步成功');
    } catch (err) {
      console.warn('[TaskStorage] 云端同步失败，数据已保存到本地:', err);
    }
  }

  /**
   * 添加任务
   */
  public async addTask(context: Context, task: Task): Promise<boolean> {
    const tasks = await this.getTasks(context);
    tasks.push(task);
    const success = await this.saveTasks(context, tasks);
    
    // 额外同步单个任务到云端
    if (success) {
      this.syncSingleTaskToCloud(task);
    }
    
    return success;
  }

  /**
   * 同步单个任务到云端
   */
  private async syncSingleTaskToCloud(task: Task): Promise<void> {
    const userId = this.getUserId();
    if (!userId) return;

    try {
      const cloudTask = CloudTask.fromLocalTask(task, userId);
      await this.cloudDBService.upsertTask(cloudTask);
      console.info('[TaskStorage] 单任务云端同步成功:', task.id);
    } catch (err) {
      console.warn('[TaskStorage] 单任务云端同步失败:', err);
    }
  }

  /**
   * 更新任务
   */
  public async updateTask(context: Context, task: Task): Promise<boolean> {
    const tasks = await this.getTasks(context);
    const index = tasks.findIndex(t => t.id === task.id);
    if (index >= 0) {
      tasks[index] = task;
      const success = await this.saveTasks(context, tasks);
      
      if (success) {
        this.syncSingleTaskToCloud(task);
      }
      
      return success;
    }
    return false;
  }

  /**
   * 删除任务
   */
  public async deleteTask(context: Context, taskId: string): Promise<boolean> {
    const tasks = await this.getTasks(context);
    const filtered = tasks.filter(t => t.id !== taskId);
    const success = await this.saveTasks(context, filtered);
    
    // 同步删除到云端
    if (success) {
      this.syncDeleteTaskToCloud(taskId);
    }
    
    return success;
  }

  /**
   * 同步删除任务到云端
   */
  private async syncDeleteTaskToCloud(taskId: string): Promise<void> {
    const userId = this.getUserId();
    if (!userId) return;

    try {
      await this.cloudDBService.deleteTaskById(taskId);
      console.info('[TaskStorage] 云端删除成功:', taskId);
    } catch (err) {
      console.warn('[TaskStorage] 云端删除失败:', err);
    }
  }

  /**
   * 完成任务的一个番茄钟
   */
  public async completePomodoro(context: Context, taskId: string): Promise<boolean> {
    const tasks = await this.getTasks(context);
    const task = tasks.find(t => t.id === taskId);
    if (task) {
      task.completedPomodoros++;
      if (task.completedPomodoros >= task.estimatedPomodoros) {
        task.isCompleted = true;
        task.completedAt = Date.now();
      }
      const success = await this.saveTasks(context, tasks);
      
      if (success) {
        this.syncSingleTaskToCloud(task);
      }
      
      return success;
    }
    return false;
  }

  /**
   * 保存已完成任务到历史记录
   */
  public async saveCompletedTasks(context: Context, completedTasks: Task[]): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        // 获取现有历史记录
        const existingValue: preferences.ValueType = await this.dataPreferences.get(this.COMPLETED_TASKS_KEY, '[]');
        let history: Task[] = [];
        if (existingValue && typeof existingValue === 'string' && existingValue !== '[]') {
          history = JSON.parse(existingValue);
        }
        
        // 添加新完成的任务
        history.push(...completedTasks);
        
        // 保存
        await this.dataPreferences.put(this.COMPLETED_TASKS_KEY, JSON.stringify(history));
        await this.dataPreferences.flush();
        console.info('[TaskStorage] Save completed tasks success.');
        
        // 同步到云端
        this.syncCompletedTasksToCloud(completedTasks);
        
        return true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Save completed tasks failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return false;
  }

  /**
   * 同步已完成任务到云端
   */
  private async syncCompletedTasksToCloud(tasks: Task[]): Promise<void> {
    const userId = this.getUserId();
    if (!userId) return;

    try {
      const cloudTasks: CloudTask[] = tasks.map(t => CloudTask.fromLocalTask(t, userId));
      await this.cloudDBService.upsertTasks(cloudTasks);
      console.info('[TaskStorage] 已完成任务云端同步成功');
    } catch (err) {
      console.warn('[TaskStorage] 已完成任务云端同步失败:', err);
    }
  }

  /**
   * 获取已完成任务历史
   */
  public async getCompletedTasks(context: Context): Promise<Task[]> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        const value: preferences.ValueType = await this.dataPreferences.get(this.COMPLETED_TASKS_KEY, '[]');
        if (value && typeof value === 'string' && value !== '[]') {
          const tasks: Task[] = JSON.parse(value);
          // 按完成时间倒序排列
          return tasks.sort((a, b) => (b.completedAt || 0) - (a.completedAt || 0));
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Get completed tasks failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return [];
  }

  /**
   * 删除一条已完成任务记录（用于报表手动清理）
   */
  public async removeCompletedTask(context: Context, taskId: string): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }

      if (this.dataPreferences) {
        const value: preferences.ValueType = await this.dataPreferences.get(this.COMPLETED_TASKS_KEY, '[]');
        let history: Task[] = [];
        if (value && typeof value === 'string' && value !== '[]') {
          history = JSON.parse(value);
        }

        const nextHistory = history.filter((t: Task) => t.id !== taskId);
        await this.dataPreferences.put(this.COMPLETED_TASKS_KEY, JSON.stringify(nextHistory));
        await this.dataPreferences.flush();
        console.info('[TaskStorage] Remove completed task success:', taskId);
        
        // 同步删除到云端
        this.syncDeleteTaskToCloud(taskId);
        
        return true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Remove completed task failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return false;
  }

  /**
   * 清空所有任务（本地 + 云端）
   */
  public async clearAllTasks(context: Context): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        // 清除待办任务
        await this.dataPreferences.put(this.TASKS_KEY, '[]');
        // 清除已完成任务历史
        await this.dataPreferences.put(this.COMPLETED_TASKS_KEY, '[]');
        await this.dataPreferences.flush();
        console.info('[TaskStorage] Clear all local tasks success.');
        
        // 注意：云端清除在 CloudDBService.clearAllData() 中统一处理
        
        return true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[TaskStorage] Clear all tasks failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return false;
  }

  /**
   * 从云端拉取数据并合并到本地（登录后调用）
   */
  public async syncFromCloud(context: Context): Promise<void> {
    const userId = this.getUserId();
    if (!userId) {
      console.warn('[TaskStorage] 未登录，跳过云端同步');
      return;
    }

    try {
      // 获取云端任务
      const cloudTasks = await this.cloudDBService.getTasksByUser(userId);
      if (cloudTasks.length === 0) {
        console.info('[TaskStorage] 云端无任务数据');
        return;
      }

      // 获取本地任务
      const localTasks = await this.getTasks(context);
      const localTaskMap = new Map<string, Task>();
      localTasks.forEach(t => localTaskMap.set(t.id, t));

      // 合并策略：云端优先（如果本地没有则添加）
      const mergedTasks: Task[] = [...localTasks];
      for (const cloudTask of cloudTasks) {
        if (!localTaskMap.has(cloudTask.id)) {
          mergedTasks.push(cloudTask.toLocalTask());
        }
      }

      // 保存合并后的数据（不触发云端同步，避免循环）
      if (this.dataPreferences) {
        await this.dataPreferences.put(this.TASKS_KEY, JSON.stringify(mergedTasks));
        await this.dataPreferences.flush();
        console.info('[TaskStorage] 云端数据合并成功，共', mergedTasks.length, '条任务');
      }
    } catch (err) {
      console.error('[TaskStorage] 从云端同步失败:', err);
    }
  }
}

