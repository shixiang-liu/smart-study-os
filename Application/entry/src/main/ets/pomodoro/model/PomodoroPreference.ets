/**
 * 番茄钟偏好数据模型
 * 用于本地KV存储和云端数据库预留字段
 */
export interface PomodoroPreference {
  // 基础设置
  workDuration: number;        // 工作时长（分钟），默认25
  shortBreakDuration: number; // 短休息时长（分钟），默认5
  longBreakDuration: number;  // 长休息时长（分钟），默认15
  longBreakInterval: number;  // 长休息间隔（几个番茄钟后），默认4
  
  // 白噪音设置
  whiteNoiseEnabled: boolean; // 是否启用白噪音
  whiteNoiseType: string;     // 白噪音类型：'rain', 'ocean', 'forest', 'none'等
  
  // 音效设置
  soundEnabled: boolean;      // 是否启用音效
  startSoundEnabled: boolean;  // 开始音效
  endSoundEnabled: boolean;   // 结束音效
  tickSoundEnabled: boolean;  // 滴答声
  
  // 情绪联动（预留接口，等待A的AI结果）
  emotionLinkEnabled: boolean; // 是否启用情绪联动
  emotionRecommendation: string | undefined; // AI推荐的白噪音类型（由A提供）
  
  // 统计信息
  totalPomodoros: number;     // 总番茄钟数
  totalFocusTime: number;    // 总专注时长（分钟）
  
  // 应用白名单
  whitelistApps: string[];    // 白名单应用包名列表
  
  // 时间戳
  lastUpdated: number;       // 最后更新时间
}

export const DEFAULT_POMODORO_PREFERENCE: PomodoroPreference = {
  workDuration: 25,
  shortBreakDuration: 5,
  longBreakDuration: 15,
  longBreakInterval: 4,
  whiteNoiseEnabled: false,
  whiteNoiseType: 'none',
  soundEnabled: true,
  startSoundEnabled: true,
  endSoundEnabled: true,
  tickSoundEnabled: false,
  emotionLinkEnabled: false,
  emotionRecommendation: undefined,
  totalPomodoros: 0,
  totalFocusTime: 0,
  whitelistApps: [],
  lastUpdated: Date.now()
};

