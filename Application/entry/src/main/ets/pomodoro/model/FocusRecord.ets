/**
 * 专注记录数据模型
 * 用于记录每日的专注时间和番茄钟数
 */
export interface FocusRecord {
  date: string;              // 日期 YYYY-MM-DD
  focusMinutes: number;      // 专注时长（分钟）
  pomodoros: number;         // 番茄钟数
  records: FocusSession[];   // 详细的专注会话记录
}

export interface FocusSession {
  id: string;                // 会话ID
  startTime: number;         // 开始时间戳
  endTime: number;           // 结束时间戳
  duration: number;          // 时长（分钟）
  taskId?: string;           // 关联的任务ID
  taskTitle?: string;         // 任务标题
}

export const DEFAULT_FOCUS_RECORD: FocusRecord = {
  date: '',
  focusMinutes: 0,
  pomodoros: 0,
  records: []
};

