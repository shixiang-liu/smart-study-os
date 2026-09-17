import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { FocusRecord, FocusSession, DEFAULT_FOCUS_RECORD } from './FocusRecord';
import { CloudDBService } from '../../common/services/CloudDBService';
import { CloudPomodoroRecord } from '../../common/model/CloudPomodoroRecord';

/**
 * 专注记录服务 - 本地 + 云端双向同步
 * 
 * 同步策略：
 * 1. 本地优先：所有操作先在本地完成，确保离线可用
 * 2. 异步同步：本地操作成功后异步同步到云端
 * 3. 失败静默：云端同步失败不影响本地操作
 */
export class FocusRecordService {
  private static instance: FocusRecordService;
  private dataPreferences: preferences.Preferences | null = null;
  private readonly RECORDS_KEY = 'pomodoro_focus_records';
  private readonly STORE_NAME = 'pomodoro_store';
  private cloudDBService: CloudDBService;

  private constructor() {
    this.cloudDBService = CloudDBService.getInstance();
  }

  public static getInstance(): FocusRecordService {
    if (!FocusRecordService.instance) {
      FocusRecordService.instance = new FocusRecordService();
    }
    return FocusRecordService.instance;
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
      console.info('[FocusRecordService] Init: 开始初始化，context类型:', typeof context, 'context存在:', !!context);
      console.info('[FocusRecordService] Init: STORE_NAME =', this.STORE_NAME, ', RECORDS_KEY =', this.RECORDS_KEY);
      this.dataPreferences = await preferences.getPreferences(context, this.STORE_NAME);
      console.info('[FocusRecordService] Init success. dataPreferences存在:', !!this.dataPreferences);
      
      // 验证：尝试读取一次数据，确认存储可用
      if (this.dataPreferences) {
        const testValue = await this.dataPreferences.get(this.RECORDS_KEY, '{}');
        console.info('[FocusRecordService] Init: 验证读取，当前存储的值类型:', typeof testValue, '值长度:', typeof testValue === 'string' ? testValue.length : 'N/A');
        if (typeof testValue === 'string' && testValue !== '{}') {
          try {
            const testRecords: Record<string, FocusRecord> = JSON.parse(testValue);
            const testKeys = Object.keys(testRecords);
            console.info('[FocusRecordService] Init: 当前存储中有', testKeys.length, '条记录，日期:', testKeys);
          } catch (parseErr) {
            console.warn('[FocusRecordService] Init: 解析当前存储数据失败:', parseErr);
          }
        } else {
          console.info('[FocusRecordService] Init: 当前存储为空（初始状态）');
        }
      } else {
        console.error('[FocusRecordService] Init: dataPreferences为null，初始化失败');
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FocusRecordService] Init failed. Code: ${error.code}, Message: ${error.message}`);
      console.error('[FocusRecordService] Init: 错误详情:', JSON.stringify(err));
      if ((err as Error)?.stack) {
        console.error('[FocusRecordService] Init: 错误堆栈:', (err as Error).stack);
      }
    }
  }

  /**
   * 获取所有记录
   */
  public async getAllRecords(context: Context): Promise<Map<string, FocusRecord>> {
    try {
      if (!this.dataPreferences) {
        console.info('[FocusRecordService] getAllRecords: 初始化 Preferences')
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        const value: preferences.ValueType = await this.dataPreferences.get(this.RECORDS_KEY, '{}');
        console.info('[FocusRecordService] getAllRecords: 读取到的原始值类型:', typeof value, ', 值长度:', typeof value === 'string' ? value.length : 'N/A')
        
        if (value && typeof value === 'string') {
          if (value === '{}') {
            console.warn('[FocusRecordService] getAllRecords: 数据为空（{}），返回空Map')
            return new Map<string, FocusRecord>();
          }
          
          try {
            const records: Record<string, FocusRecord> = JSON.parse(value);
            const map = new Map<string, FocusRecord>();
            const keys = Object.keys(records);
            console.info('[FocusRecordService] getAllRecords: 解析成功，找到', keys.length, '条记录，日期:', keys)
            
            Object.keys(records).forEach(date => {
              const record = records[date];
              map.set(date, record);
              console.info('[FocusRecordService] getAllRecords: 日期', date, '- 专注时长:', record.focusMinutes, '分钟, 番茄数:', record.pomodoros)
            });
            
            return map;
          } catch (parseErr) {
            console.error('[FocusRecordService] getAllRecords: JSON解析失败:', parseErr)
            console.error('[FocusRecordService] getAllRecords: 原始值:', value.substring(0, 200))
            return new Map<string, FocusRecord>();
          }
        } else {
          console.warn('[FocusRecordService] getAllRecords: 值类型不是字符串，类型:', typeof value)
        }
      } else {
        console.error('[FocusRecordService] getAllRecords: dataPreferences 为 null')
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FocusRecordService] Get records failed. Code: ${error.code}, Message: ${error.message}`);
      console.error('[FocusRecordService] 错误堆栈:', (err as Error)?.stack);
    }
    return new Map<string, FocusRecord>();
  }

  /**
   * 保存所有记录（本地 + 云端同步）
   */
  public async saveAllRecords(context: Context, records: Map<string, FocusRecord>): Promise<boolean> {
    try {
      console.info('[FocusRecordService] saveAllRecords: 开始保存，context存在:', !!context, '记录数量:', records.size)
      
      if (!this.dataPreferences) {
        console.info('[FocusRecordService] saveAllRecords: dataPreferences不存在，开始初始化')
        await this.init(context);
      }
      
      if (!this.dataPreferences) {
        console.error('[FocusRecordService] saveAllRecords: 初始化后dataPreferences仍为null')
        return false;
      }
      
      const recordsObj: Record<string, FocusRecord> = {};
      records.forEach((record, date) => {
        recordsObj[date] = record;
      });
      
      // 1. 先保存到本地
      const recordsJson = JSON.stringify(recordsObj);
      const recordCount = Object.keys(recordsObj).length;
      console.info('[FocusRecordService] saveAllRecords: 准备保存', recordCount, '条记录')
      console.info('[FocusRecordService] saveAllRecords: 记录内容预览:', recordsJson.substring(0, 500))
      console.info('[FocusRecordService] saveAllRecords: RECORDS_KEY =', this.RECORDS_KEY, ', STORE_NAME =', this.STORE_NAME)
      
      await this.dataPreferences.put(this.RECORDS_KEY, recordsJson);
      await this.dataPreferences.flush();
      console.info('[FocusRecordService] Save records to local success. 已保存', recordCount, '条记录');
      
      // 【验证】立即读取验证数据是否真的被保存
      try {
        const verifyValue = await this.dataPreferences.get(this.RECORDS_KEY, '{}');
        console.info('[FocusRecordService] saveAllRecords: 【验证读取】读取到的值类型:', typeof verifyValue, '长度:', typeof verifyValue === 'string' ? verifyValue.length : 'N/A')
        if (typeof verifyValue === 'string' && verifyValue !== '{}') {
          try {
            const verifyRecords: Record<string, FocusRecord> = JSON.parse(verifyValue);
            const verifyKeys = Object.keys(verifyRecords);
            console.info('[FocusRecordService] saveAllRecords: 【验证成功】读取到', verifyKeys.length, '条记录，日期:', verifyKeys)
          } catch (parseErr) {
            console.error('[FocusRecordService] saveAllRecords: 【验证失败】JSON解析错误:', parseErr)
          }
        } else {
          console.error('[FocusRecordService] saveAllRecords: 【验证失败】保存后读取到的数据为空或类型错误')
        }
      } catch (verifyErr) {
        console.error('[FocusRecordService] saveAllRecords: 【验证失败】读取验证时出错:', verifyErr)
      }
      
      // 问题1修复：触发专注记录更新信号，通知学习报告刷新
      try {
        AppStorage.setOrCreate('focusRecordUpdatedAt', Date.now())
        console.info('[FocusRecordService] saveAllRecords: 已触发更新信号')
      } catch (e) {
        console.warn('[FocusRecordService] 触发更新信号失败:', e)
      }
      
      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FocusRecordService] Save records failed. Code: ${error.code}, Message: ${error.message}`);
      console.error('[FocusRecordService] Save records failed. 错误详情:', JSON.stringify(err));
      if ((err as Error)?.stack) {
        console.error('[FocusRecordService] Save records failed. 错误堆栈:', (err as Error).stack);
      }
    }
    return false;
  }

  /**
   * 获取指定日期的记录
   */
  public async getRecordByDate(context: Context, date: string): Promise<FocusRecord> {
    const allRecords = await this.getAllRecords(context);
    const existing = allRecords.get(date);
    if (existing) {
      return existing;
    }
    // 手动复制默认记录
    return {
      date: date,
      focusMinutes: DEFAULT_FOCUS_RECORD.focusMinutes,
      pomodoros: DEFAULT_FOCUS_RECORD.pomodoros,
      records: []
    };
  }

  /**
   * 添加专注会话（本地 + 云端同步）
   */
  public async addSession(context: Context, session: FocusSession): Promise<boolean> {
    console.info('[FocusRecordService] addSession: 开始添加会话，context存在:', !!context)
    console.info('[FocusRecordService] addSession: 会话信息 - ID:', session.id, ', 时长:', session.duration, '分钟, 任务:', session.taskTitle || '无')
    
    try {
      const today = this.getTodayDate();
      console.info('[FocusRecordService] addSession: 今日日期:', today)
      
      let record = await this.getRecordByDate(context, today);
      console.info('[FocusRecordService] addSession: 获取到的今日记录 - 专注时长:', record.focusMinutes, '分钟, 番茄数:', record.pomodoros)
      
      record.records.push(session);
      record.focusMinutes += session.duration;
      record.pomodoros += 1;
      console.info('[FocusRecordService] addSession: 更新后的记录 - 专注时长:', record.focusMinutes, '分钟, 番茄数:', record.pomodoros, ', 会话数:', record.records.length)
      
      const allRecords = await this.getAllRecords(context);
      console.info('[FocusRecordService] addSession: 当前所有记录数量:', allRecords.size)
      allRecords.set(today, record);
      
      const success = await this.saveAllRecords(context, allRecords);
      console.info('[FocusRecordService] addSession: saveAllRecords返回结果:', success)
      
      // 异步同步到云端
      if (success) {
        this.syncSessionToCloud(session);
      } else {
        console.error('[FocusRecordService] addSession: 保存失败，跳过云端同步')
      }
      
      return success;
    } catch (err) {
      console.error('[FocusRecordService] addSession: 发生错误:', err)
      console.error('[FocusRecordService] addSession: 错误详情:', JSON.stringify(err))
      if ((err as Error)?.stack) {
        console.error('[FocusRecordService] addSession: 错误堆栈:', (err as Error).stack)
      }
      return false;
    }
  }

  /**
   * 同步单个会话到云端
   */
  private async syncSessionToCloud(session: FocusSession): Promise<void> {
    const userId = this.getUserId();
    if (!userId) {
      console.warn('[FocusRecordService] 未登录，跳过云端同步');
      return;
    }

    try {
      const cloudRecord = CloudPomodoroRecord.fromFocusSession(session, userId);
      await this.cloudDBService.upsertPomodoroRecord(cloudRecord);
      console.info('[FocusRecordService] 会话云端同步成功');
    } catch (err) {
      console.warn('[FocusRecordService] 会话云端同步失败:', err);
    }
  }

  /**
   * 获取今日日期字符串
   */
  private getTodayDate(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * 获取最近N天的记录（返回所有日期的记录，包括没有数据的日期）
   */
  public async getRecentRecords(context: Context, days: number): Promise<FocusRecord[]> {
    console.info('[FocusRecordService] getRecentRecords: 开始获取最近', days, '天的记录')
    const allRecords = await this.getAllRecords(context);
    console.info('[FocusRecordService] getRecentRecords: getAllRecords返回', allRecords.size, '条记录')
    const records: FocusRecord[] = [];
    const today = new Date();
    
    // 从最远的日期到今天的顺序（与 getPastDays 保持一致）
    for (let i = days - 1; i >= 0; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      const dateStr = this.formatDate(date);
      const existing = allRecords.get(dateStr);
      
      if (existing) {
        // 添加已存在的记录（无论是否有数据，都返回完整记录）
        console.info('[FocusRecordService] getRecentRecords: 找到日期', dateStr, '- 专注时长:', existing.focusMinutes, '分钟')
        records.push(existing);
      } else {
        // 如果没有记录，创建一个空的记录对象，确保所有日期都有数据
        console.info('[FocusRecordService] getRecentRecords: 日期', dateStr, '无记录，创建空记录')
        records.push({
          date: dateStr,
          focusMinutes: 0,
          pomodoros: 0,
          records: []
        });
      }
    }
    
    console.info('[FocusRecordService] getRecentRecords: 返回', records.length, '条记录')
    return records;
  }
  
  private formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * 清空所有专注记录
   */
  public async clearAllRecords(context: Context): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        await this.init(context);
      }
      
      if (this.dataPreferences) {
        await this.dataPreferences.put(this.RECORDS_KEY, '{}');
        await this.dataPreferences.flush();
        console.info('[FocusRecordService] Clear all records success.');
        
        // 触发专注记录更新信号，通知学习报告刷新
        try {
          AppStorage.setOrCreate('focusRecordUpdatedAt', Date.now())
        } catch (e) {
          console.warn('[FocusRecordService] 触发更新信号失败:', e)
        }
        
        return true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FocusRecordService] Clear all records failed. Code: ${error.code}, Message: ${error.message}`);
    }
    return false;
  }

  /**
   * 从云端拉取数据并合并到本地（登录后调用）
   */
  public async syncFromCloud(context: Context): Promise<void> {
    const userId = this.getUserId();
    if (!userId) {
      console.warn('[FocusRecordService] 未登录，跳过云端同步');
      return;
    }

    try {
      // 获取最近30天的云端记录
      const now = Date.now();
      const thirtyDaysAgo = now - 30 * 24 * 60 * 60 * 1000;
      const cloudRecords = await this.cloudDBService.getPomodoroRecordsByTimeRange(userId, thirtyDaysAgo, now);
      
      if (cloudRecords.length === 0) {
        console.info('[FocusRecordService] 云端无专注记录');
        return;
      }

      // 获取本地记录
      const localRecords = await this.getAllRecords(context);

      // 将云端记录按日期分组并合并
      for (const cloudRecord of cloudRecords) {
        const session = cloudRecord.toFocusSession();
        const dateStr = this.formatDate(new Date(cloudRecord.start_time));
        
        let dayRecord = localRecords.get(dateStr);
        if (!dayRecord) {
          dayRecord = {
            date: dateStr,
            focusMinutes: 0,
            pomodoros: 0,
            records: []
          };
        }

        // 检查是否已存在相同ID的会话
        const exists = dayRecord.records.some(s => s.id === session.id);
        if (!exists) {
          dayRecord.records.push(session);
          dayRecord.focusMinutes += session.duration;
          dayRecord.pomodoros += 1;
        }

        localRecords.set(dateStr, dayRecord);
      }

      // 保存合并后的数据
      await this.saveAllRecords(context, localRecords);
      console.info('[FocusRecordService] 云端数据合并成功');
    } catch (err) {
      console.error('[FocusRecordService] 从云端同步失败:', err);
    }
  }
}

