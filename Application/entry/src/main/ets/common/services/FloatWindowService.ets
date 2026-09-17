// ============================================================================
// 悬浮窗服务 - FloatWindowService
// ============================================================================
// 功能：创建、管理、销毁全局悬浮窗
// 权限：ohos.permission.SYSTEM_FLOAT_WINDOW
// 用途：计算器、番茄钟等工具的小窗模式
// ============================================================================

import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

// ============================================================================
// 悬浮窗配置
// ============================================================================
export class FloatWindowConfig {
  // 窗口名称（唯一标识）
  name: string;
  
  // 加载的页面路径
  contentPath: string;
  
  // 初始位置
  x: number = 100;
  y: number = 100;
  
  // 初始尺寸
  width: number = 300;
  height: number = 400;

  constructor(name: string, contentPath: string, x?: number, y?: number, width?: number, height?: number) {
    this.name = name;
    this.contentPath = contentPath;
    if (x !== undefined) {
      this.x = x;
    }
    if (y !== undefined) {
      this.y = y;
    }
    if (width !== undefined) {
      this.width = width;
    }
    if (height !== undefined) {
      this.height = height;
    }
  }
}

// ============================================================================
// 悬浮窗管理条目
// ============================================================================
class FloatWindowEntry {
  name: string;
  windowInstance: window.Window;
  config: FloatWindowConfig;

  constructor(name: string, windowInstance: window.Window, config: FloatWindowConfig) {
    this.name = name;
    this.windowInstance = windowInstance;
    this.config = config;
  }
}

// ============================================================================
// 悬浮窗服务 - 单例模式
// ============================================================================
export class FloatWindowService {
  private static instance: FloatWindowService;
  
  // 管理的悬浮窗映射表
  private floatWindows: Map<string, FloatWindowEntry> = new Map();
  
  // 上下文
  private context: common.UIAbilityContext | null = null;

  private constructor() {}

  // ==================== 单例入口 ====================
  public static getInstance(): FloatWindowService {
    if (!FloatWindowService.instance) {
      FloatWindowService.instance = new FloatWindowService();
    }
    return FloatWindowService.instance;
  }

  // ==================== 初始化 ====================

  /**
   * 初始化服务
   * @param context UIAbility 上下文
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
    console.info('[FloatWindowService] Init success.');
  }

  // ==================== 悬浮窗操作 ====================

  /**
   * 创建悬浮窗
   * @param config 悬浮窗配置
   * @returns Promise<boolean> 是否创建成功
   */
  public async createFloatWindow(config: FloatWindowConfig): Promise<boolean> {
    if (this.context === null) {
      console.error('[FloatWindowService] Context not initialized.');
      return false;
    }

    // 检查是否已存在
    if (this.floatWindows.has(config.name)) {
      console.warn(`[FloatWindowService] Window "${config.name}" already exists.`);
      return this.showFloatWindow(config.name);
    }

    try {
      // 悬浮窗配置
      const windowConfig: window.Configuration = {
        name: config.name,
        windowType: window.WindowType.TYPE_FLOAT,
        ctx: this.context
      };

      // 创建悬浮窗
      const floatWindow = await window.createWindow(windowConfig);
      console.info(`[FloatWindowService] Window "${config.name}" created.`);

      // 设置位置
      await floatWindow.moveWindowTo(config.x, config.y);
      console.info(`[FloatWindowService] Window moved to (${config.x}, ${config.y}).`);

      // 设置尺寸
      await floatWindow.resize(config.width, config.height);
      console.info(`[FloatWindowService] Window resized to ${config.width}x${config.height}.`);

      // 加载页面内容
      await floatWindow.setUIContent(config.contentPath);
      console.info(`[FloatWindowService] Window content loaded: ${config.contentPath}`);

      // 显示悬浮窗
      await floatWindow.showWindow();
      console.info(`[FloatWindowService] Window "${config.name}" shown.`);

      // 保存到管理映射表
      const entry = new FloatWindowEntry(config.name, floatWindow, config);
      this.floatWindows.set(config.name, entry);

      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FloatWindowService] createFloatWindow failed. Code: ${error.code}, Message: ${error.message}`);
      return false;
    }
  }

  /**
   * 显示悬浮窗
   * @param name 窗口名称
   * @description 恢复窗口到原始位置并显示
   */
  public async showFloatWindow(name: string): Promise<boolean> {
    const entry = this.floatWindows.get(name);
    if (!entry) {
      console.warn(`[FloatWindowService] Window "${name}" not found.`);
      return false;
    }

    try {
      // 恢复到原始位置
      await entry.windowInstance.moveWindowTo(entry.config.x, entry.config.y);
      await entry.windowInstance.showWindow();
      console.info(`[FloatWindowService] Window "${name}" shown at (${entry.config.x}, ${entry.config.y}).`);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FloatWindowService] showFloatWindow failed. Code: ${error.code}`);
      return false;
    }
  }

  /**
   * 隐藏悬浮窗
   * @param name 窗口名称
   * @description hide() 是系统 API，普通应用无法使用，
   *              使用移动窗口到屏幕外的方式模拟隐藏
   */
  public async hideFloatWindow(name: string): Promise<boolean> {
    const entry = this.floatWindows.get(name);
    if (!entry) {
      console.warn(`[FloatWindowService] Window "${name}" not found.`);
      return false;
    }

    try {
      // hide() 是系统 API，普通应用使用 moveWindowTo 将窗口移出屏幕
      await entry.windowInstance.moveWindowTo(-9999, -9999);
      console.info(`[FloatWindowService] Window "${name}" hidden (moved off screen).`);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FloatWindowService] hideFloatWindow failed. Code: ${error.code}`);
      return false;
    }
  }

  /**
   * 销毁悬浮窗
   * @param name 窗口名称
   */
  public async destroyFloatWindow(name: string): Promise<boolean> {
    const entry = this.floatWindows.get(name);
    if (!entry) {
      console.warn(`[FloatWindowService] Window "${name}" not found.`);
      return true; // 不存在也算成功
    }

    try {
      await entry.windowInstance.destroyWindow();
      this.floatWindows.delete(name);
      console.info(`[FloatWindowService] Window "${name}" destroyed.`);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[FloatWindowService] destroyFloatWindow failed. Code: ${error.code}`);
      return false;
    }
  }

  /**
   * 销毁所有悬浮窗
   */
  public async destroyAllFloatWindows(): Promise<void> {
    const names = Array.from(this.floatWindows.keys());
    for (const name of names) {
      await this.destroyFloatWindow(name);
    }
  }

  // ==================== 窗口属性操作 ====================

  /**
   * 移动悬浮窗位置
   */
  public async moveFloatWindow(name: string, x: number, y: number): Promise<boolean> {
    const entry = this.floatWindows.get(name);
    if (!entry) {
      return false;
    }

    try {
      await entry.windowInstance.moveWindowTo(x, y);
      entry.config.x = x;
      entry.config.y = y;
      return true;
    } catch (err) {
      return false;
    }
  }

  /**
   * 调整悬浮窗尺寸
   */
  public async resizeFloatWindow(name: string, width: number, height: number): Promise<boolean> {
    const entry = this.floatWindows.get(name);
    if (!entry) {
      return false;
    }

    try {
      await entry.windowInstance.resize(width, height);
      entry.config.width = width;
      entry.config.height = height;
      return true;
    } catch (err) {
      return false;
    }
  }

  // ==================== 状态查询 ====================

  /**
   * 检查悬浮窗是否存在
   */
  public hasFloatWindow(name: string): boolean {
    return this.floatWindows.has(name);
  }

  /**
   * 获取悬浮窗实例（用于高级操作）
   */
  public getFloatWindow(name: string): window.Window | null {
    const entry = this.floatWindows.get(name);
    return entry ? entry.windowInstance : null;
  }

  /**
   * 通过名称查找悬浮窗（静态方法，供悬浮窗内部使用）
   */
  public static findWindow(name: string): window.Window | null {
    try {
      return window.findWindow(name);
    } catch (err) {
      return null;
    }
  }
}

// ============================================================================
// 预定义的悬浮窗配置
// ============================================================================
export class FloatWindowPresets {
  // 计算器悬浮窗
  static readonly CALCULATOR = new FloatWindowConfig(
    'floatCalculator',
    'calculator/view/float/FloatCalculator',
    100, 100, 280, 380
  );

  // 番茄钟悬浮窗
  static readonly POMODORO = new FloatWindowConfig(
    'floatPomodoro',
    'calculator/view/float/FloatPomodoro',
    100, 100, 200, 240
  );
}
