// 番茄钟 ViewModel - 情绪联动白噪音
// 使用智谱 GLM-4.5-Flash 进行智能白噪音推荐

import { EmotionAnalyzer, EmotionAnalysisResult, EMOTION_PRESETS } from '../../common/utils/EmotionAnalyzer'
import { PreferencesUtil } from '../../common/utils/PreferencesUtil'
import { GLMService } from '../../common/services/GLMService'

// 白噪音类型定义
export enum WhiteNoiseType {
  NONE = 'none',
  RAIN = 'rain',
  OCEAN = 'ocean',
  FOREST = 'forest',
  LIBRARY = 'library',  // 图书馆氛围
  FIRE = 'fire'         // 壁炉火焰
}

// 情绪-白噪音映射
interface EmotionNoiseMapping {
  emotionKey: string
  recommendedNoise: WhiteNoiseType
  reason: string  // 推荐理由
}

// 白噪音使用偏好记录
interface NoisePreferenceRecord {
  emotionKey: string
  noiseType: WhiteNoiseType
  useCount: number
  lastUsed: number
}

// 白噪音类型信息
export interface NoiseTypeInfo {
  type: WhiteNoiseType
  label: string
  icon: string
}

// 智能白噪音推荐结果
export interface SmartNoiseResult {
  noiseType: WhiteNoiseType
  reason: string
  isAI: boolean
}

// 白噪音推荐结果
export interface NoiseRecommendation {
  noiseType: WhiteNoiseType
  reason: string
  isLearned: boolean
}

export class PomodoroViewModel {
  private static instance: PomodoroViewModel | null = null
  private glmService: GLMService

  // 默认情绪-白噪音映射（作为备用）
  private readonly defaultMappings: EmotionNoiseMapping[] = [
    { emotionKey: 'anxious', recommendedNoise: WhiteNoiseType.RAIN, reason: '雨声帮助缓解焦虑' },
    { emotionKey: 'excited', recommendedNoise: WhiteNoiseType.LIBRARY, reason: '图书馆氛围帮助平静' },
    { emotionKey: 'sad', recommendedNoise: WhiteNoiseType.FIRE, reason: '温暖的火焰声抚慰心灵' },
    { emotionKey: 'angry', recommendedNoise: WhiteNoiseType.OCEAN, reason: '海浪声帮助释放情绪' },
    { emotionKey: 'calm', recommendedNoise: WhiteNoiseType.FOREST, reason: '森林声维持平静状态' },
    { emotionKey: 'happy', recommendedNoise: WhiteNoiseType.NONE, reason: '好心情不需要额外干预' },
    { emotionKey: 'grateful', recommendedNoise: WhiteNoiseType.NONE, reason: '感恩状态最适合专注' }
  ]

  // 用户偏好缓存
  private userPreferences: NoisePreferenceRecord[] = []

  private constructor() {
    this.glmService = GLMService.getInstance()
  }

  static getInstance(): PomodoroViewModel {
    if (!PomodoroViewModel.instance) {
      PomodoroViewModel.instance = new PomodoroViewModel()
    }
    return PomodoroViewModel.instance
  }

  // 情绪中英文映射
  private mapEmotionToKey(emotion: string): string {
    const emotionMap: Map<string, string> = new Map([
      ['焦虑', 'anxious'], ['anxious', 'anxious'],
      ['兴奋', 'excited'], ['excited', 'excited'],
      ['低落', 'sad'], ['sad', 'sad'], ['难过', 'sad'],
      ['愤怒', 'angry'], ['angry', 'angry'],
      ['平静', 'calm'], ['calm', 'calm'],
      ['开心', 'happy'], ['happy', 'happy'], ['快乐', 'happy'],
      ['感恩', 'grateful'], ['grateful', 'grateful'],
      ['专注', 'calm'], ['专注', 'calm']
    ])
    return emotionMap.get(emotion) || 'calm' // 默认使用平静
  }

  // 使用 GLM 智能推荐白噪音
  async getSmartNoiseRecommendation(emotion: string, activity?: string): Promise<SmartNoiseResult> {
    try {
      const emotionKey = this.mapEmotionToKey(emotion)
      const recommendation = await this.glmService.recommendNoise(emotionKey, activity)
      return {
        noiseType: recommendation.type as WhiteNoiseType,
        reason: recommendation.reason,
        isAI: true
      }
    } catch (err) {
      console.error('[PomodoroViewModel] GLM推荐失败，使用本地推荐:', err)
      const emotionKey = this.mapEmotionToKey(emotion)
      const localResult = await this.getRecommendedNoise({ emotionKey: emotionKey } as EmotionAnalysisResult)
      const result: SmartNoiseResult = {
        noiseType: localResult.noiseType,
        reason: localResult.reason,
        isAI: false
      }
      return result
    }
  }

  // 获取基于情绪的白噪音推荐
  async getRecommendedNoise(recentEmotion?: EmotionAnalysisResult | null): Promise<NoiseRecommendation> {
    // 无情绪数据时返回默认
    if (!recentEmotion) {
      const defaultResult: NoiseRecommendation = {
        noiseType: WhiteNoiseType.RAIN,
        reason: '默认推荐',
        isLearned: false
      }
      return defaultResult
    }

    const emotionKey = recentEmotion.emotionKey

    // 先检查用户学习到的偏好
    await this.loadUserPreferences()
    let userPref: NoisePreferenceRecord | undefined = undefined
    for (const p of this.userPreferences) {
      if (p.emotionKey === emotionKey) {
        userPref = p
        break
      }
    }
    if (userPref && userPref.useCount >= 3) {
      // 用户使用超过3次，认为是学习到的偏好
      const learnedResult: NoiseRecommendation = {
        noiseType: userPref.noiseType,
        reason: '根据您的使用习惯推荐',
        isLearned: true
      }
      return learnedResult
    }

    // 否则使用默认映射
    let mapping: EmotionNoiseMapping | undefined = undefined
    for (const m of this.defaultMappings) {
      if (m.emotionKey === emotionKey) {
        mapping = m
        break
      }
    }
    if (mapping) {
      const mappedResult: NoiseRecommendation = {
        noiseType: mapping.recommendedNoise,
        reason: mapping.reason,
        isLearned: false
      }
      return mappedResult
    }

    // 兜底返回雨声
    const fallbackResult: NoiseRecommendation = {
      noiseType: WhiteNoiseType.RAIN,
      reason: '舒缓专注',
      isLearned: false
    }
    return fallbackResult
  }

  // 记录用户白噪音选择，用于偏好学习
  async recordNoiseSelection(emotionKey: string, noiseType: WhiteNoiseType): Promise<void> {
    await this.loadUserPreferences()

    let existingIdx = -1
    for (let i = 0; i < this.userPreferences.length; i++) {
      if (this.userPreferences[i].emotionKey === emotionKey) {
        existingIdx = i
        break
      }
    }
    if (existingIdx >= 0) {
      const pref = this.userPreferences[existingIdx]
      if (pref.noiseType === noiseType) {
        // 同样的选择，增加计数
        pref.useCount++
        pref.lastUsed = Date.now()
      } else {
        // 不同选择，更新类型并重置计数
        pref.noiseType = noiseType
        pref.useCount = 1
        pref.lastUsed = Date.now()
      }
    } else {
      // 新增记录
      this.userPreferences.push({
        emotionKey,
        noiseType,
        useCount: 1,
        lastUsed: Date.now()
      })
    }

    await this.saveUserPreferences()
  }

  // 获取所有可用白噪音类型（带描述）
  getAvailableNoiseTypes(): NoiseTypeInfo[] {
    const types: NoiseTypeInfo[] = [
      { type: WhiteNoiseType.NONE, label: '无', icon: '' },
      { type: WhiteNoiseType.RAIN, label: '雨声', icon: '' },
      { type: WhiteNoiseType.OCEAN, label: '海浪', icon: '' },
      { type: WhiteNoiseType.FOREST, label: '森林', icon: '' },
      { type: WhiteNoiseType.LIBRARY, label: '图书馆', icon: '' },
      { type: WhiteNoiseType.FIRE, label: '壁炉', icon: '' }
    ]
    return types
  }

  // 加载用户偏好
  private async loadUserPreferences(): Promise<void> {
    try {
      const data = await PreferencesUtil.getObject<NoisePreferenceRecord[]>('noise_preferences', [])
      this.userPreferences = data
    } catch (err) {
      this.userPreferences = []
    }
  }

  // 保存用户偏好
  private async saveUserPreferences(): Promise<void> {
    try {
      await PreferencesUtil.putObject('noise_preferences', this.userPreferences)
    } catch (err) {
      console.error('保存白噪音偏好失败:', err)
    }
  }

  // 重置用户偏好学习
  async resetPreferences(): Promise<void> {
    this.userPreferences = []
    await PreferencesUtil.delete('noise_preferences')
  }
}
