/**
 * 任务数据模型
 */
export interface Task {
  id: string;
  title: string;
  description?: string;
  estimatedPomodoros: number; // 预计番茄数
  completedPomodoros: number;  // 已完成番茄数
  isCompleted: boolean;
  priority: TaskPriority;      // 优先级
  tag?: string;                // 标签
  createdAt: number;           // 创建时间
  completedAt?: number;        // 完成时间
  plannedMinutes?: number;     // 计划总时长（可选）
}

export enum TaskPriority {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2
}

export const DEFAULT_TASK: Task = {
  id: '',
  title: '',
  description: '',
  estimatedPomodoros: 1,
  completedPomodoros: 0,
  isCompleted: false,
  priority: TaskPriority.MEDIUM,
  tag: '',
  createdAt: Date.now()
};

