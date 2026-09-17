// ============================================================================
// 混合存储服务 - HybridStorageService
// ============================================================================
// 功能：本地存储 + 云端同步的混合模式
// 策略：离线优先 - 先写本地再同步云端，离线时加入待同步队列
// 依赖：Preferences（本地）、CloudDiaryService（云端）、NetworkService（网络）
// ============================================================================

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { NetworkService } from './NetworkService';
import { CloudDBService } from '../CloudDBService';
import { CloudDiaryService } from './CloudDiaryService';
import { NoteItem } from '../../diary/model/NoteItem';

// ============================================================================
// 缓存条目类型 - 记录数据、时间戳、同步状态
// ============================================================================
export class CacheItem {
  data: string;        // JSON 序列化的数据
  timestamp: number;   // 最后更新时间戳
  synced: boolean;     // 是否已同步到云端

  constructor(data: string, timestamp: number, synced: boolean) {
    this.data = data;
    this.timestamp = timestamp;
    this.synced = synced;
  }
}

// ============================================================================
// 待同步队列条目
// ============================================================================
export class PendingSyncItem {
  key: string;
  data: string;
  operation: 'upsert' | 'delete';
  timestamp: number;

  constructor(key: string, data: string, operation: 'upsert' | 'delete', timestamp: number) {
    this.key = key;
    this.data = data;
    this.operation = operation;
    this.timestamp = timestamp;
  }
}

// ============================================================================
// 同步配置
// ============================================================================
export class SyncConfig {
  // 数据过期时间（毫秒）- 超过此时间会从云端刷新
  staleTime: number = 5 * 60 * 1000; // 默认 5 分钟
  
  // 是否在计费网络下同步
  syncOnMetered: boolean = false;
  
  // 最大重试次数
  maxRetries: number = 3;

  constructor(staleTime?: number, syncOnMetered?: boolean, maxRetries?: number) {
    if (staleTime !== undefined) {
      this.staleTime = staleTime;
    }
    if (syncOnMetered !== undefined) {
      this.syncOnMetered = syncOnMetered;
    }
    if (maxRetries !== undefined) {
      this.maxRetries = maxRetries;
    }
  }
}

// ============================================================================
// 混合存储服务 - 单例模式
// ============================================================================
export class HybridStorageService {
  private static instance: HybridStorageService;
  
  // 本地 Preferences 实例
  private localCache: preferences.Preferences | null = null;
  
  // 存储名称
  private readonly STORE_NAME = 'hybrid_storage';
  
  // 待同步队列存储键
  private readonly PENDING_QUEUE_KEY = '__pending_sync_queue__';
  
  // 待同步队列
  private pendingQueue: PendingSyncItem[] = [];
  
  // 同步配置
  private config: SyncConfig = new SyncConfig();
  
  // 是否正在同步
  private isSyncing: boolean = false;
  
  // 依赖服务
  private networkService: NetworkService;
  private cloudService: CloudDBService;
  private cloudDiaryService: CloudDiaryService;
  
  // 上下文（延迟初始化）
  private context: Context | null = null;

  private constructor() {
    this.networkService = NetworkService.getInstance();
    this.cloudService = CloudDBService.getInstance();
    this.cloudDiaryService = CloudDiaryService.getInstance();
  }

  // ==================== 单例入口 ====================
  public static getInstance(): HybridStorageService {
    if (!HybridStorageService.instance) {
      HybridStorageService.instance = new HybridStorageService();
    }
    return HybridStorageService.instance;
  }

  // ==================== 初始化 ====================

  /**
   * 初始化服务
   * @param context 应用上下文
   * @param config 同步配置（可选）
   */
  public async init(context: Context, config?: SyncConfig): Promise<void> {
    this.context = context;
    
    if (config) {
      this.config = config;
    }

    try {
      // 初始化本地存储
      this.localCache = await preferences.getPreferences(context, this.STORE_NAME);
      
      // 加载待同步队列
      await this.loadPendingQueue();
      
      // 初始化云服务
      await this.cloudService.init();
      
      // 启动网络监听
      this.networkService.startNetworkMonitor();
      
      // 注册网络变化回调
      this.networkService.addCallback((isOnline: boolean) => {
        if (isOnline) {
          this.processPendingQueue();
        }
      });
      
      // 如果当前在线，处理待同步队列
      if (this.networkService.getIsOnline()) {
        this.processPendingQueue();
      }
      
      console.info('[HybridStorage] Init success.');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[HybridStorage] Init failed. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  // ==================== 数据操作 ====================

  /**
   * 保存数据（离线优先策略）
   * @param key 存储键
   * @param data 数据对象（将被 JSON 序列化）
   * @returns 是否成功保存到本地
   */
  public async saveData(key: string, data: object): Promise<boolean> {
    const jsonData = JSON.stringify(data);
    const timestamp = Date.now();
    
    // 1. 先保存到本地
    const localSuccess = await this.saveToLocal(key, jsonData, timestamp, false);
    if (!localSuccess) {
      return false;
    }
    
    // 2. 尝试同步到云端
    if (this.canSync()) {
      const syncSuccess = await this.syncToCloud(key, jsonData, 'upsert');
      if (syncSuccess) {
        // 更新本地同步状态
        await this.saveToLocal(key, jsonData, timestamp, true);
      } else {
        // 同步失败，加入待同步队列
        this.addToPendingQueue(key, jsonData, 'upsert');
      }
    } else {
      // 离线状态，加入待同步队列
      this.addToPendingQueue(key, jsonData, 'upsert');
    }
    
    return true;
  }

  /**
   * 读取数据（本地优先策略）
   * @param key 存储键
   * @param defaultValue 默认值
   * @returns 数据对象或默认值
   */
  public async getData<T>(key: string, defaultValue: T): Promise<T> {
    // 1. 先从本地缓存读取
    const localData = await this.getFromLocal(key);
    
    if (localData !== null) {
      // 检查是否需要从云端刷新
      const cacheItem = JSON.parse(localData) as CacheItem;
      const isStale = Date.now() - cacheItem.timestamp > this.config.staleTime;
      
      if (isStale && this.canSync()) {
        // 异步从云端刷新，但先返回本地数据
        this.refreshFromCloud(key);
      }
      
      try {
        return JSON.parse(cacheItem.data) as T;
      } catch (err) {
        console.error('[HybridStorage] Parse local data failed:', err);
      }
    }
    
    // 2. 本地没有，尝试从云端获取
    if (this.canSync()) {
      const cloudData = await this.fetchFromCloud(key);
      if (cloudData !== null) {
        // 保存到本地
        await this.saveToLocal(key, cloudData, Date.now(), true);
        try {
          return JSON.parse(cloudData) as T;
        } catch (err) {
          console.error('[HybridStorage] Parse cloud data failed:', err);
        }
      }
    }
    
    return defaultValue;
  }

  /**
   * 删除数据
   * @param key 存储键
   */
  public async deleteData(key: string): Promise<boolean> {
    // 1. 从本地删除
    const localSuccess = await this.deleteFromLocal(key);
    
    // 2. 同步删除到云端
    if (this.canSync()) {
      const syncSuccess = await this.syncToCloud(key, '', 'delete');
      if (!syncSuccess) {
        this.addToPendingQueue(key, '', 'delete');
      }
    } else {
      this.addToPendingQueue(key, '', 'delete');
    }
    
    return localSuccess;
  }

  /**
   * 检查数据是否存在
   */
  public async hasData(key: string): Promise<boolean> {
    if (this.localCache === null) {
      return false;
    }
    try {
      return await this.localCache.has(key);
    } catch (err) {
      return false;
    }
  }

  // ==================== 批量操作 ====================

  /**
   * 批量保存数据
   */
  public async saveDataBatch(items: Array<{ key: string; data: object }>): Promise<boolean> {
    let allSuccess = true;
    for (const item of items) {
      const success = await this.saveData(item.key, item.data);
      if (!success) {
        allSuccess = false;
      }
    }
    return allSuccess;
  }

  /**
   * 强制同步所有待同步数据
   */
  public async forceSync(): Promise<boolean> {
    if (!this.canSync()) {
      return false;
    }
    return await this.processPendingQueue();
  }

  // ==================== 本地存储操作 ====================

  private async saveToLocal(key: string, data: string, timestamp: number, synced: boolean): Promise<boolean> {
    if (this.localCache === null) {
      return false;
    }
    
    try {
      const cacheItem = new CacheItem(data, timestamp, synced);
      await this.localCache.put(key, JSON.stringify(cacheItem));
      await this.localCache.flush();
      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[HybridStorage] saveToLocal failed. Code: ${error.code}`);
      return false;
    }
  }

  private async getFromLocal(key: string): Promise<string | null> {
    if (this.localCache === null) {
      return null;
    }
    
    try {
      const value = await this.localCache.get(key, '') as string;
      return value === '' ? null : value;
    } catch (err) {
      return null;
    }
  }

  private async deleteFromLocal(key: string): Promise<boolean> {
    if (this.localCache === null) {
      return false;
    }
    
    try {
      await this.localCache.delete(key);
      await this.localCache.flush();
      return true;
    } catch (err) {
      return false;
    }
  }

  // ==================== 云端同步操作 ====================

  private canSync(): boolean {
    if (!this.networkService.getIsOnline()) {
      return false;
    }
    
    // 如果是计费网络且配置不允许，则不同步
    if (this.networkService.isMeteredNetwork() && !this.config.syncOnMetered) {
      return false;
    }
    
    return true;
  }

  private async syncToCloud(key: string, data: string, operation: 'upsert' | 'delete'): Promise<boolean> {
    // 根据 key 前缀判断数据类型，调用对应的 CloudDiaryService 方法
    try {
      console.info(`[HybridStorage] syncToCloud: ${operation} ${key}`);
      
      // 确保云服务已初始化
      await this.cloudDiaryService.initialize();
      
      // 日记数据同步（key 以 note_ 或 diary_ 开头）
      if (key.startsWith('note_') || key.startsWith('diary_')) {
        if (operation === 'upsert') {
          const noteItem: NoteItem = JSON.parse(data);
          return await this.cloudDiaryService.saveNote(noteItem);
        } else if (operation === 'delete') {
          return await this.cloudDiaryService.deleteNote(key);
        }
      }
      
      // 其他类型暂时只记录日志
      console.warn(`[HybridStorage] 未支持的数据类型: ${key}`);
      return true;
    } catch (err) {
      console.error('[HybridStorage] syncToCloud failed:', err);
      return false;
    }
  }

  private async fetchFromCloud(key: string): Promise<string | null> {
    try {
      console.info(`[HybridStorage] fetchFromCloud: ${key}`);
      
      // 确保云服务已初始化
      await this.cloudDiaryService.initialize();
      
      // 日记数据获取
      if (key.startsWith('note_') || key.startsWith('diary_')) {
        const notes = await this.cloudDiaryService.queryAllNotes();
        const note = notes.find((n: NoteItem) => n.id === key);
        if (note) {
          return JSON.stringify(note);
        }
      }
      
      return null;
    } catch (err) {
      console.error('[HybridStorage] fetchFromCloud failed:', err);
      return null;
    }
  }

  private async refreshFromCloud(key: string): Promise<void> {
    const cloudData = await this.fetchFromCloud(key);
    if (cloudData !== null) {
      await this.saveToLocal(key, cloudData, Date.now(), true);
    }
  }

  // ==================== 待同步队列管理 ====================

  private addToPendingQueue(key: string, data: string, operation: 'upsert' | 'delete'): void {
    // 检查是否已存在相同 key 的条目，如果有则更新
    const existingIndex = this.pendingQueue.findIndex((item: PendingSyncItem) => item.key === key);
    
    const newItem = new PendingSyncItem(key, data, operation, Date.now());
    
    if (existingIndex > -1) {
      this.pendingQueue[existingIndex] = newItem;
    } else {
      this.pendingQueue.push(newItem);
    }
    
    // 持久化待同步队列
    this.savePendingQueue();
  }

  private async processPendingQueue(): Promise<boolean> {
    if (this.isSyncing || this.pendingQueue.length === 0) {
      return true;
    }
    
    this.isSyncing = true;
    console.info(`[HybridStorage] Processing pending queue. Count: ${this.pendingQueue.length}`);
    
    const failedItems: PendingSyncItem[] = [];
    
    for (const item of this.pendingQueue) {
      const success = await this.syncToCloud(item.key, item.data, item.operation);
      if (!success) {
        failedItems.push(item);
      } else {
        // 更新本地同步状态
        if (item.operation === 'upsert') {
          await this.saveToLocal(item.key, item.data, Date.now(), true);
        }
      }
    }
    
    // 更新待同步队列为失败的条目
    this.pendingQueue = failedItems;
    await this.savePendingQueue();
    
    this.isSyncing = false;
    
    return failedItems.length === 0;
  }

  private async loadPendingQueue(): Promise<void> {
    if (this.localCache === null) {
      return;
    }
    
    try {
      const queueJson = await this.localCache.get(this.PENDING_QUEUE_KEY, '[]') as string;
      const queue = JSON.parse(queueJson) as Array<{
        key: string;
        data: string;
        operation: 'upsert' | 'delete';
        timestamp: number;
      }>;
      
      this.pendingQueue = queue.map((item) => {
        return new PendingSyncItem(item.key, item.data, item.operation, item.timestamp);
      });
      
      console.info(`[HybridStorage] Loaded pending queue. Count: ${this.pendingQueue.length}`);
    } catch (err) {
      this.pendingQueue = [];
    }
  }

  private async savePendingQueue(): Promise<void> {
    if (this.localCache === null) {
      return;
    }
    
    try {
      await this.localCache.put(this.PENDING_QUEUE_KEY, JSON.stringify(this.pendingQueue));
      await this.localCache.flush();
    } catch (err) {
      console.error('[HybridStorage] savePendingQueue failed:', err);
    }
  }

  // ==================== 状态查询 ====================

  /**
   * 获取待同步条目数量
   */
  public getPendingCount(): number {
    return this.pendingQueue.length;
  }

  /**
   * 获取网络状态
   */
  public isOnline(): boolean {
    return this.networkService.getIsOnline();
  }
}
