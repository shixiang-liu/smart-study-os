// 仪表盘 ViewModel - 统计学习数据和情绪变化
import { CloudDBService } from '../../common/services/CloudDBService'
import { Diary } from '../../diary/model/Diary'
import { GLMService } from '../../common/services/GLMService'
import { FocusRecordService } from '../../pomodoro/model/FocusRecordService'
import { common } from '@kit.AbilityKit'

// 专注记录数据（从日记推断或专门记录）
export interface FocusData {
  date: string      // 日期 MM-DD
  minutes: number   // 专注分钟数
}

// 情绪数据
export interface EmotionData {
  date: string
  score: number     // 情绪分数 1-5
  label: string     // 情绪标签
}

// 每日统计汇总
export interface DailyStats {
  date: string
  diaryCount: number
  focusMinutes: number
  mood: string
  moodScore: number
}

// 周统计数据
export interface WeeklyStats {
  totalMinutes: number
  averageMinutes: number
  streak: number
  diaryCount: number
}

// 内部数据结构
interface MoodScoreRecord {
  mood: string
  score: number
}

export class DashboardViewModel {
  private cloudDBService: CloudDBService
  private glmService: GLMService
  private focusRecordService: FocusRecordService
  private context: common.UIAbilityContext | null = null

  // 情绪标签到分数的映射
  private static readonly MOOD_SCORES: Map<string, number> = new Map([
    ['开心', 5], ['兴奋', 5], ['愉快', 5], ['喜悦', 5], ['感激', 5],
    ['满足', 4], ['平静', 4], ['轻松', 4], ['期待', 4], ['专注', 4],
    ['一般', 3], ['普通', 3], ['无聊', 3], ['平淡', 3],
    ['疲惫', 2], ['焦虑', 2], ['担忧', 2], ['紧张', 2], ['困倦', 2],
    ['难过', 1], ['沮丧', 1], ['愤怒', 1], ['烦躁', 1], ['失落', 1]
  ])

  constructor() {
    this.cloudDBService = CloudDBService.getInstance()
    this.glmService = GLMService.getInstance()
    this.focusRecordService = FocusRecordService.getInstance()
  }

  // 设置上下文（用于获取专注记录）
  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  // 获取情绪分数（从标签推断）
  private getMoodScore(mood: string): number {
    if (!mood) return 3
    
    // 检查映射表
    for (const entry of DashboardViewModel.MOOD_SCORES.entries()) {
      const label = entry[0]
      const score = entry[1]
      if (mood.includes(label)) {
        return score
      }
    }
    return 3 // 默认中等
  }

  // 获取过去 N 天的日期数组
  private getPastDays(days: number): string[] {
    const result: string[] = []
    const now = new Date()
    
    for (let i = days - 1; i >= 0; i--) {
      const date = new Date(now.getTime() - i * 24 * 60 * 60 * 1000)
      const month = String(date.getMonth() + 1).padStart(2, '0')
      const day = String(date.getDate()).padStart(2, '0')
      result.push(`${month}-${day}`)
    }
    
    return result
  }

  // 格式化日期为 MM-DD
  private formatDateToMMDD(timestamp: number): string {
    const date = new Date(timestamp)
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    return `${month}-${day}`
  }

  // 获取情绪数据（从日记）
  async getEmotionData(days: number = 7): Promise<EmotionData[]> {
    try {
      const diaries = await this.cloudDBService.getDiariesByTime()
      const now = Date.now()
      const cutoff = now - days * 24 * 60 * 60 * 1000
      
      // 按日期分组日记
      const dateMap: Map<string, MoodScoreRecord> = new Map()
      
      for (const diary of diaries) {
        const createTime = diary.create_time ?? 0
        if (createTime < cutoff) continue
        
        const dateStr = this.formatDateToMMDD(createTime)
        const mood = diary.mood ?? '平静'
        const score = this.getMoodScore(mood)
        
        // 如果该日期已有记录，取较高分数（乐观倾向）
        const existing = dateMap.get(dateStr)
        if (!existing || score > existing.score) {
          const record: MoodScoreRecord = { mood: mood, score: score }
          dateMap.set(dateStr, record)
        }
      }
      
      // 生成完整日期序列
      const pastDays = this.getPastDays(days)
      const result: EmotionData[] = []
      for (const date of pastDays) {
        const data = dateMap.get(date)
        const item: EmotionData = {
          date: date,
          score: data?.score ?? 3,
          label: data?.mood ?? '无记录'
        }
        result.push(item)
      }
      
      return result
    } catch (err) {
      console.error('[DashboardViewModel] 获取情绪数据失败:', err)
      const pastDays = this.getPastDays(days)
      const result: EmotionData[] = []
      for (const date of pastDays) {
        const item: EmotionData = {
          date: date,
          score: 3,
          label: '无记录'
        }
        result.push(item)
      }
      return result
    }
  }

  // 获取专注数据（使用真实的番茄钟记录）
  async getFocusData(days: number = 7): Promise<FocusData[]> {
    try {
      // 生成完整日期序列
      const pastDays = this.getPastDays(days)
      const result: FocusData[] = []

      // 优先使用真实的专注记录
      if (this.context) {
        const realRecords = await this.focusRecordService.getRecentRecords(this.context, days)
        console.info('[DashboardViewModel] getFocusData: 获取到', realRecords.length, '条记录')
        
        // 将真实记录转换为 Map，便于查询
        const recordMap = new Map<string, number>()
        for (const record of realRecords) {
          // FocusRecord.date 格式为 YYYY-MM-DD，需要转换为 MM-DD
          const dateStr = record.date.substring(5) // "2024-12-06" -> "12-06"
          recordMap.set(dateStr, record.focusMinutes)
          console.info('[DashboardViewModel] getFocusData: 日期', dateStr, '专注时长', record.focusMinutes, '分钟')
        }

        // 生成结果，确保所有日期都有数据（包括0）
        for (const date of pastDays) {
          const minutes = recordMap.get(date) ?? 0
          const item: FocusData = {
            date: date,
            minutes: minutes
          }
          result.push(item)
        }

        console.info('[DashboardViewModel] getFocusData: 生成', result.length, '条数据，总时长', result.reduce((sum, d) => sum + d.minutes, 0), '分钟')
        return result
      } else {
        console.warn('[DashboardViewModel] getFocusData: context 未设置，返回空数据')
      }

      // 如果没有 context，返回空数据
      for (const date of pastDays) {
        const item: FocusData = {
          date: date,
          minutes: 0
        }
        result.push(item)
      }
      
      return result
    } catch (err) {
      console.error('[DashboardViewModel] 获取专注数据失败:', err)
      const pastDays = this.getPastDays(days)
      const result: FocusData[] = []
      for (const date of pastDays) {
        const item: FocusData = {
          date: date,
          minutes: 0
        }
        result.push(item)
      }
      return result
    }
  }

  // 计算统计数据（本地优先策略 - 确保演示时数据及时更新）
  async getWeeklyStats(context?: common.UIAbilityContext): Promise<WeeklyStats> {
    try {
      const focusData = await this.getFocusData(7)
      const now = Date.now()
      const cutoff = now - 7 * 24 * 60 * 60 * 1000
      
      // 【本地优先】先从本地Preferences读取，确保演示时数据最新
      // 注意：报表显示的是"日记 X篇"，为了更好的用户体验，显示所有日记的总数量
      // 而不是仅统计最近7天的（因为用户可能期望看到总数量）
      let weekDiaryCount = 0
      let localCount = 0
      let cloudCount = 0
      
      // 步骤1: 从本地读取（主要数据源，DetailPage直接写入本地）
      // 优先使用传入的context，如果没有则使用实例的context
      const activeContext = context || this.context
      console.info('[DashboardViewModel] getWeeklyStats: context存在:', !!activeContext, '使用传入context:', !!context, '使用实例context:', !!this.context)
      if (activeContext) {
        try {
          console.info('[DashboardViewModel] 开始从本地加载日记...')
          const UtilModule = await import('../../common/utils/PreferencesUtil')
          const PreferencesUtil = UtilModule.PreferencesUtil
          const localNotes = await PreferencesUtil.loadNotes(activeContext)
          console.info('[DashboardViewModel] 本地日记总数:', localNotes.length)
          
          // 显示所有日记的总数量（而不是仅最近7天）
          // 这样可以更好地反映用户的日记使用情况
          if (Array.isArray(localNotes)) {
            localCount = localNotes.length
            weekDiaryCount = localCount
            console.info('[DashboardViewModel] 本地日记数量(全部):', localCount, ', 设置weekDiaryCount为:', weekDiaryCount)
          } else {
            console.warn('[DashboardViewModel] localNotes不是数组:', typeof localNotes)
            localCount = 0
          }
          
          // 如果需要统计最近7天的日记（用于其他用途），可以这样计算：
          if (Array.isArray(localNotes)) {
            const recentNotes = localNotes.filter(note => {
              const noteTime = note.createTime || note.lastModifiedTime || 0
              // 如果时间戳为0或不存在，说明是新创建的日记，包含进去
              if (noteTime === 0 || !noteTime) {
                return true
              }
              return noteTime >= cutoff
            })
            console.info('[DashboardViewModel] 最近7天日记数量:', recentNotes.length)
          }
        } catch (localErr) {
          console.error('[DashboardViewModel] 本地日记获取失败:', localErr)
          console.error('[DashboardViewModel] 错误类型:', typeof localErr)
          console.error('[DashboardViewModel] 错误消息:', (localErr as Error)?.message)
          console.error('[DashboardViewModel] 错误堆栈:', (localErr as Error)?.stack)
        }
      } else {
        console.warn('[DashboardViewModel] context 未设置，无法从本地读取日记')
      }
      
      // 步骤2: 尝试从CloudDB获取（作为补充数据源）
      // 注意：如果本地已经有数据，优先使用本地数据；只有当本地数据为0且云端有数据时，才使用云端数据
      try {
        const diaries = await this.cloudDBService.getDiariesByTime()
        cloudCount = diaries.length  // 显示所有日记，而不仅仅是最近7天的
        console.info('[DashboardViewModel] 云端日记总数:', cloudCount)
        
        // 如果本地没有数据（可能是因为context未设置），使用云端数据
        if (weekDiaryCount === 0 && cloudCount > 0) {
          weekDiaryCount = cloudCount
          console.info('[DashboardViewModel] 本地无数据，使用云端日记数量:', cloudCount)
        } else if (cloudCount > weekDiaryCount) {
          // 如果云端数据更多，使用云端数据（确保不遗漏）
          weekDiaryCount = cloudCount
          console.info('[DashboardViewModel] 云端数据更多，使用云端日记数量:', cloudCount)
        } else {
          console.info('[DashboardViewModel] 本地数据已存在，保持使用本地日记数量:', weekDiaryCount)
        }
      } catch (cloudErr) {
        console.warn('[DashboardViewModel] CloudDB获取日记失败，使用本地数据:', cloudErr)
        // 云端失败时保持使用本地数据，不影响功能
      }
      
      let totalMinutes = 0
      let activeDays = 0
      for (const d of focusData) {
        totalMinutes += d.minutes
        if (d.minutes > 0) activeDays++
      }
      const averageMinutes = activeDays > 0 ? Math.round(totalMinutes / activeDays) : 0
      
      // 计算连续天数
      let streak = 0
      for (let i = focusData.length - 1; i >= 0; i--) {
        if (focusData[i].minutes > 0) {
          streak++
        } else {
          break
        }
      }
      
      const stats: WeeklyStats = {
        totalMinutes: totalMinutes,
        averageMinutes: averageMinutes,
        streak: streak,
        diaryCount: weekDiaryCount
      }
      console.info('[DashboardViewModel] 最终统计结果:', JSON.stringify(stats))
      return stats
    } catch (err) {
      console.error('[DashboardViewModel] 获取周统计失败:', err)
      const defaultStats: WeeklyStats = {
        totalMinutes: 0,
        averageMinutes: 0,
        streak: 0,
        diaryCount: 0
      }
      return defaultStats
    }
  }

  // 使用 AI 生成周报洞察
  async generateWeeklyInsight(context?: common.UIAbilityContext): Promise<string> {
    try {
      const focusData = await this.getFocusData(7)
      const emotionData = await this.getEmotionData(7)
      const stats = await this.getWeeklyStats(context)
      
      if (stats.totalMinutes === 0) {
        return '本周还没有学习记录，开始记录你的第一篇日记吧！'
      }
      
      // 找到专注最长的日子
      let maxFocusDay = focusData[0]
      for (const d of focusData) {
        if (d.minutes > maxFocusDay.minutes) {
          maxFocusDay = d
        }
      }
      
      // 找到情绪最好的日子
      let bestMoodDay = emotionData[0]
      for (const d of emotionData) {
        if (d.score > bestMoodDay.score) {
          bestMoodDay = d
        }
      }
      
      // 计算平均情绪
      let moodSum = 0
      for (const d of emotionData) {
        moodSum += d.score
      }
      const avgMood = moodSum / emotionData.length
      
      let insight = ''
      
      if (maxFocusDay.minutes > 0) {
        insight += `你在 ${maxFocusDay.date} 专注时间最长（${maxFocusDay.minutes} 分钟），建议在这样的日子安排重要任务。`
      }
      
      if (avgMood >= 4) {
        insight += '本周情绪整体良好，继续保持！'
      } else if (avgMood >= 3) {
        insight += '本周情绪较为平稳，尝试在学习中加入一些休息。'
      } else {
        insight += '本周情绪偏低，建议适当放松，调整学习节奏。'
      }
      
      if (stats.streak >= 5) {
        insight += ` 已连续学习 ${stats.streak} 天，太棒了！`
      }
      
      return insight
    } catch (err) {
      console.error('[DashboardViewModel] 生成洞察失败:', err)
      return '暂无足够数据生成洞察，继续记录学习日记吧！'
    }
  }

  // 使用 GLM AI 生成更智能的洞察(问题22修复: 包含学习阻碍LLM总结)
  async generateAIInsight(context?: common.UIAbilityContext): Promise<string> {
    try {
      const focusData = await this.getFocusData(7)
      const emotionData = await this.getEmotionData(7)
      const stats = await this.getWeeklyStats(context)
      
      if (stats.totalMinutes === 0) {
        return '本周还没有学习记录，开始记录你的第一篇日记吧！'
      }
      
      const focusStrParts: string[] = []
      for (const d of focusData) {
        focusStrParts.push(`${d.date}:${d.minutes}分钟`)
      }
      const focusStr = focusStrParts.join(', ')
      
      const emotionStrParts: string[] = []
      for (const d of emotionData) {
        emotionStrParts.push(`${d.date}:${d.label}`)
      }
      const emotionStr = emotionStrParts.join(', ')
      
      // 问题22修复: 使用GLM分析学习阻碍
      let obstacleInsight = ''
      try {
        const diaries = await this.cloudDBService.getDiariesByTime()
        const now = Date.now()
        const cutoff = now - 7 * 24 * 60 * 60 * 1000
        const recentContents: string[] = []
        for (const diary of diaries) {
          if ((diary.create_time ?? 0) >= cutoff && diary.content) {
            recentContents.push(diary.content)
          }
        }
        
        if (recentContents.length > 0) {
          const obstacleResult = await this.glmService.analyzeObstacles(recentContents)
          if (obstacleResult.obstacles.length > 0) {
            obstacleInsight = `\n\n📌 学习阻碍: ${obstacleResult.obstacles.slice(0, 3).join('、')}`
          }
        }
      } catch (obstacleErr) {
        console.warn('[DashboardViewModel] 阻碍分析失败:', obstacleErr)
      }
      
      const prompt = `作为学习助手，请根据以下数据给出简短（50字以内）的学习建议：
      
本周专注数据：${focusStr}
本周情绪数据：${emotionStr}
总专注时长：${stats.totalMinutes}分钟
连续学习天数：${stats.streak}天

请给出一条具体、可执行的建议。`
      
      const response = await this.glmService.chat(prompt)
      return (response || await this.generateWeeklyInsight(context || undefined)) + obstacleInsight
    } catch (err) {
      console.error('[DashboardViewModel] AI 洞察生成失败:', err)
      return await this.generateWeeklyInsight(context || undefined)
    }
  }
}
