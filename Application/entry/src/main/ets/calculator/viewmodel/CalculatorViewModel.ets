// 计算器 ViewModel - 历史记录持久化
// 将计算历史保存到本地存储

import { PreferencesUtil } from '../../common/utils/PreferencesUtil'

// 历史记录项
export interface CalcHistoryItem {
  id: number
  expression: string
  result: string
  timestamp: number
}

// 历史记录分组（按日期）
export interface CalcHistoryGroup {
  dateLabel: string
  items: CalcHistoryItem[]
}

export class CalculatorViewModel {
  private static instance: CalculatorViewModel | null = null
  private history: CalcHistoryItem[] = []
  private readonly maxHistorySize: number = 100  // 最多保存100条

  private constructor() {}

  static getInstance(): CalculatorViewModel {
    if (!CalculatorViewModel.instance) {
      CalculatorViewModel.instance = new CalculatorViewModel()
    }
    return CalculatorViewModel.instance
  }

  // 加载历史记录
  async loadHistory(): Promise<CalcHistoryItem[]> {
    try {
      const data: CalcHistoryItem[] = await PreferencesUtil.getObject<CalcHistoryItem[]>('calc_history', [])
      this.history = data
    } catch (err) {
      this.history = []
    }
    return this.history
  }

  // 添加历史记录
  async addHistory(expression: string, result: string): Promise<void> {
    const item: CalcHistoryItem = {
      id: Date.now(),
      expression,
      result,
      timestamp: Date.now()
    }

    this.history.unshift(item)

    // 限制历史数量
    if (this.history.length > this.maxHistorySize) {
      this.history = this.history.slice(0, this.maxHistorySize)
    }

    await this.saveHistory()
  }

  // 删除单条历史
  async deleteHistory(id: number): Promise<void> {
    this.history = this.history.filter(h => h.id !== id)
    await this.saveHistory()
  }

  // 清空所有历史
  async clearHistory(): Promise<void> {
    this.history = []
    await PreferencesUtil.delete('calc_history')
  }

  // 获取分组历史（按日期）
  getGroupedHistory(): CalcHistoryGroup[] {
    const groups: Map<string, CalcHistoryItem[]> = new Map()

    for (const item of this.history) {
      const dateLabel = this.formatDateLabel(item.timestamp)
      if (!groups.has(dateLabel)) {
        groups.set(dateLabel, [])
      }
      groups.get(dateLabel)!.push(item)
    }

    const result: CalcHistoryGroup[] = []
    groups.forEach((items, dateLabel) => {
      result.push({ dateLabel, items })
    })

    return result
  }

  // 从历史恢复计算（返回表达式）
  restoreFromHistory(id: number): CalcHistoryItem | null {
    return this.history.find(h => h.id === id) || null
  }

  // 保存历史到本地
  private async saveHistory(): Promise<void> {
    try {
      await PreferencesUtil.putObject('calc_history', this.history)
    } catch (err) {
      console.error('保存计算器历史失败:', err)
    }
  }

  // 格式化日期标签
  private formatDateLabel(timestamp: number): string {
    const date = new Date(timestamp)
    const today = new Date()
    const yesterday = new Date(today)
    yesterday.setDate(yesterday.getDate() - 1)

    const dateStr = this.formatDate(date)
    const todayStr = this.formatDate(today)
    const yesterdayStr = this.formatDate(yesterday)

    if (dateStr === todayStr) return '今天'
    if (dateStr === yesterdayStr) return '昨天'
    return dateStr
  }

  private formatDate(date: Date): string {
    const month = date.getMonth() + 1
    const day = date.getDate()
    return `${month}月${day}日`
  }
}
