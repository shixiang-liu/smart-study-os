import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { PomodoroPreference, DEFAULT_POMODORO_PREFERENCE } from './PomodoroPreference';
import { CloudDBService } from '../../common/services/CloudDBService';
import { User } from '../../auth/model/User';

/**
 * 番茄钟存储服务
 * 支持本地KV存储和云端数据库同步
 */
export class PomodoroStorageService {
  private static instance: PomodoroStorageService;
  private dataPreferences: preferences.Preferences | null = null;
  private readonly PREFERENCE_KEY = 'pomodoro_preference';
  private readonly STORE_NAME = 'pomodoro_store';

  private constructor() {
  }

  public static getInstance(): PomodoroStorageService {
    if (!PomodoroStorageService.instance) {
      PomodoroStorageService.instance = new PomodoroStorageService();
    }
    return PomodoroStorageService.instance;
  }

  /**
   * 初始化本地存储
   */
  public async init(context: Context): Promise<void> {
    try {
      this.dataPreferences = await preferences.getPreferences(context, this.STORE_NAME);
      console.info('[PomodoroStorage] Init success.');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[PomodoroStorage] Init failed. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  /**
   * 获取偏好设置（优先从本地读取）
   */
  public async getPreference(context: Context): Promise<PomodoroPreference> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        const value: preferences.ValueType = await this.dataPreferences.get(this.PREFERENCE_KEY, '');
        if (value && typeof value === 'string' && value !== '') {
          const preference: PomodoroPreference = JSON.parse(value);
          return preference;
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[PomodoroStorage] Get preference failed. Code: ${error.code}, Message: ${error.message}`);
    }
    
    // 返回默认值（手动复制，不使用spread）
    return this.copyPreference(DEFAULT_POMODORO_PREFERENCE);
  }

  /**
   * 保存偏好设置到本地
   */
  public async savePreference(context: Context, preference: PomodoroPreference): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        const updatedPreference: PomodoroPreference = this.copyPreference(preference);
        updatedPreference.lastUpdated = Date.now();
        await this.dataPreferences.put(this.PREFERENCE_KEY, JSON.stringify(updatedPreference));
        await this.dataPreferences.flush();
        
        // 同步到云端（如果用户已登录）
        await this.syncToCloud(updatedPreference);
        
        console.info('[PomodoroStorage] Save preference success.');
        return true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[PomodoroStorage] Save preference failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return false;
  }

  /**
   * 更新部分偏好设置
   */
  public async updatePreference(context: Context, updates: Partial<PomodoroPreference>): Promise<boolean> {
    const current = await this.getPreference(context);
    const updated: PomodoroPreference = this.copyPreference(current);
    // 手动更新字段
    if (updates.workDuration !== undefined) updated.workDuration = updates.workDuration;
    if (updates.shortBreakDuration !== undefined) updated.shortBreakDuration = updates.shortBreakDuration;
    if (updates.longBreakDuration !== undefined) updated.longBreakDuration = updates.longBreakDuration;
    if (updates.longBreakInterval !== undefined) updated.longBreakInterval = updates.longBreakInterval;
    if (updates.whiteNoiseEnabled !== undefined) updated.whiteNoiseEnabled = updates.whiteNoiseEnabled;
    if (updates.whiteNoiseType !== undefined) updated.whiteNoiseType = updates.whiteNoiseType;
    if (updates.soundEnabled !== undefined) updated.soundEnabled = updates.soundEnabled;
    if (updates.startSoundEnabled !== undefined) updated.startSoundEnabled = updates.startSoundEnabled;
    if (updates.endSoundEnabled !== undefined) updated.endSoundEnabled = updates.endSoundEnabled;
    if (updates.tickSoundEnabled !== undefined) updated.tickSoundEnabled = updates.tickSoundEnabled;
    if (updates.emotionLinkEnabled !== undefined) updated.emotionLinkEnabled = updates.emotionLinkEnabled;
    if (updates.emotionRecommendation !== undefined) updated.emotionRecommendation = updates.emotionRecommendation;
    if (updates.totalPomodoros !== undefined) updated.totalPomodoros = updates.totalPomodoros;
    if (updates.totalFocusTime !== undefined) updated.totalFocusTime = updates.totalFocusTime;
    if (updates.whitelistApps !== undefined) updated.whitelistApps = updates.whitelistApps ? [...updates.whitelistApps] : [];
    if (updates.lastUpdated !== undefined) updated.lastUpdated = updates.lastUpdated;
    return await this.savePreference(context, updated);
  }

  /**
   * 复制偏好设置对象
   */
  private copyPreference(source: PomodoroPreference): PomodoroPreference {
    return {
      workDuration: source.workDuration,
      shortBreakDuration: source.shortBreakDuration,
      longBreakDuration: source.longBreakDuration,
      longBreakInterval: source.longBreakInterval,
      whiteNoiseEnabled: source.whiteNoiseEnabled,
      whiteNoiseType: source.whiteNoiseType,
      soundEnabled: source.soundEnabled,
      startSoundEnabled: source.startSoundEnabled,
      endSoundEnabled: source.endSoundEnabled,
      tickSoundEnabled: source.tickSoundEnabled,
      emotionLinkEnabled: source.emotionLinkEnabled,
      emotionRecommendation: source.emotionRecommendation,
      totalPomodoros: source.totalPomodoros,
      totalFocusTime: source.totalFocusTime,
      whitelistApps: source.whitelistApps ? [...source.whitelistApps] : [],
      lastUpdated: source.lastUpdated
    };
  }

  /**
   * 同步到云端数据库（预留字段）
   * 注意：需要在User模型中添加pomodoro_preference字段
   */
  private async syncToCloud(preference: PomodoroPreference): Promise<void> {
    try {
      // TODO: 当User模型添加pomodoro_preference字段后，实现云端同步
      // const user = await CloudDBService.getInstance().getCurrentUser();
      // if (user) {
      //   user.pomodoro_preference = JSON.stringify(preference);
      //   await CloudDBService.getInstance().upsertUser(user);
      // }
      console.info('[PomodoroStorage] Cloud sync placeholder (waiting for User model update)');
    } catch (err) {
      console.error(`[PomodoroStorage] Cloud sync failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 从云端同步偏好设置
   */
  public async syncFromCloud(context: Context, userId: string): Promise<boolean> {
    try {
      // TODO: 当User模型添加pomodoro_preference字段后，实现云端同步
      // const user = await CloudDBService.getInstance().getUser(userId);
      // if (user && user.pomodoro_preference) {
      //   const preference: PomodoroPreference = JSON.parse(user.pomodoro_preference);
      //   await this.savePreference(context, preference);
      //   return true;
      // }
      console.info('[PomodoroStorage] Cloud sync from placeholder (waiting for User model update)');
      return false;
    } catch (err) {
      console.error(`[PomodoroStorage] Cloud sync from failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 增加番茄钟统计
   */
  public async incrementPomodoroCount(context: Context, focusMinutes: number): Promise<void> {
    const preference = await this.getPreference(context);
    await this.updatePreference(context, {
      totalPomodoros: preference.totalPomodoros + 1,
      totalFocusTime: preference.totalFocusTime + focusMinutes
    });
  }
}

