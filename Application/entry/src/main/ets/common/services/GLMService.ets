// ============================================================================
// 智谱 GLM-4.5-Flash AI 服务
// ============================================================================
// 功能：意图识别、情绪分析、白噪音推荐
// 特性：强制 JSON 输出、正则兜底、401/429 重试
// ============================================================================
import http from '@ohos.net.http'
import { NetworkService } from './NetworkService'

// API 响应类型定义 - 与智谱官方文档保持一致

interface GLMChoice {
  index: number
  message: GLMMessage
  finish_reason: string
}

interface GLMMessage {
  role: string
  content: string
}

// 聊天消息类型 - 用于构建请求消息数组
interface GLMChatMessage {
  role: string
  content: string
}

interface GLMUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

interface GLMResponse {
  id: string
  created: number
  model: string
  choices: GLMChoice[]
  usage: GLMUsage
}

interface GLMThinkingConfig {
  type: string
}

// JSON 格式强制输出配置
interface GLMResponseFormat {
  type: string
}

// 阻碍分析结果接口
interface ObstacleAnalysisResult {
  obstacles: string[]
  report: string
}

// API 请求体类型
interface GLMRequestBody {
  model: string
  messages: GLMChatMessage[]
  max_tokens: number
  temperature: number
  thinking?: GLMThinkingConfig
  response_format?: GLMResponseFormat
}

interface GLMStreamDelta {
  content?: string
  role?: string
}

interface GLMStreamChoice {
  index: number
  delta: GLMStreamDelta
  finish_reason: string | null
}

interface GLMStreamResponse {
  id: string
  created: number
  model: string
  choices: GLMStreamChoice[]
}

// 业务层返回类型

export interface IntentResult {
  type: 'goal' | 'todo' | 'emotion' | 'question' | 'chat'
  content: string
  confidence: number
  extracted?: ExtractedInfo
  encouragement?: string  // AI 温馨鼓励语
}

export interface ExtractedInfo {
  goals?: string[]
  todos?: string[]
  keywords?: string[]
  emotion?: string
  emotionScore?: number // 1-5, 越高心情越好
}

export interface NoiseRecommendation {
  type: string
  reason: string
}

// 情绪分析结果
export interface EmotionAnalysisResult {
  emotion: string
  score: number
  emoji: string
}

// 默认返回结构（兜底用）
const DEFAULT_INTENT: IntentResult = {
  type: 'chat',
  content: '',
  confidence: 0,
  extracted: {
    goals: [],
    todos: [],
    keywords: [],
    emotion: '平静',
    emotionScore: 3
  }
}

const DEFAULT_EMOTION: EmotionAnalysisResult = {
  emotion: '平静',
  score: 3,
  emoji: '😐'
}

const DEFAULT_NOISE: NoiseRecommendation = {
  type: 'rain',
  reason: '舒缓的雨声帮助专注'
}

export class GLMService {
  private static instance: GLMService | null = null
  // 网络服务（用于检测联网状态）
  private networkService: NetworkService = NetworkService.getInstance()
  // 智谱开放平台的 API Key，format: {id}.{secret}
  private readonly apiKey: string = '' // 从本地配置注入，勿提交真实 Key；为空时该服务不可用
  private readonly baseUrl: string = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
  private readonly model: string = 'glm-4.5-flash' // 快速模型，适合实时交互
  // 请求频率限制：记录上次请求时间
  private lastRequestTime: number = 0
  private readonly minRequestInterval: number = 5000 // 最小请求间隔 5 秒，避免触发 429

  private constructor() {
  }

  static getInstance(): GLMService {
    if (!GLMService.instance) {
      GLMService.instance = new GLMService()
    }
    return GLMService.instance
  }

  // 通用聊天 - 其他方法的基础
  async chat(prompt: string, systemPrompt?: string, useJsonFormat: boolean = false): Promise<string> {
    const messages: GLMChatMessage[] = []

    if (systemPrompt) {
      messages.push({ role: 'system', content: systemPrompt })
    }
    messages.push({ role: 'user', content: prompt })

    try {
      const response = await this.callAPIWithRetry(messages, false, useJsonFormat)
      return response.choices[0]?.message?.content ?? ''
    } catch (err) {
      console.error('[GLMService] chat error:', err)
      return ''
    }
  }

  // 从日记中提取目标、待办、情绪等结构化信息
  async analyzeIntent(content: string): Promise<IntentResult> {
    const systemPrompt = `你是一个智能学习助手，负责分析用户的日记内容。
请从内容中识别：
1. 学习目标（如：我要考过四级、准备期末考试）
2. 待办事项（如：明天要交作业、下周复习）
3. 情绪状态（开心、焦虑、压力大、平静等）
4. 学习阻碍关键词（手机、游戏、熬夜、拖延等）

请严格以 JSON 格式返回，不要输出任何其他文字：
{
  "type": "goal|todo|emotion|chat",
  "goals": ["目标1", "目标2"],
  "todos": ["待办1", "待办2"],
  "keywords": ["关键词1", "关键词2"],
  "emotion": "情绪标签",
  "emotionScore": 3
}
emotionScore: 1=很差 2=不好 3=一般 4=不错 5=很好`

    try {
      // 使用 JSON 格式强制返回结构化数据
      const response = await this.chat(content, systemPrompt, true)
      return this.parseIntentResponse(response)
    } catch (err) {
      console.error('[GLMService] analyzeIntent error:', err)
      // 离线或失败时返回默认结果
      return DEFAULT_INTENT
    }
  }

  // 情绪分析 - 用于番茄钟根据心情推荐白噪音
  async analyzeEmotion(content: string): Promise<EmotionAnalysisResult> {
    const systemPrompt = `分析以下文本的情绪状态，严格返回 JSON 格式，不要输出任何其他文字：
{
  "emotion": "情绪标签（开心/平静/焦虑/难过/愤怒/兴奋）",
  "score": 情绪分数1-5,
  "emoji": "对应的emoji表情"
}`

    try {
      // 使用 JSON 格式强制返回
      const response = await this.chat(content, systemPrompt, true)
      const json = this.extractJSON(response)
      const result: EmotionAnalysisResult = {
        emotion: (json.emotion as string) ?? '平静',
        score: (json.score as number) ?? 3,
        emoji: (json.emoji as string) ?? '😐'
      }
      return result
    } catch (err) {
      console.error('[GLMService] analyzeEmotion error:', err)
      return DEFAULT_EMOTION
    }
  }

  // 基于情绪推荐白噪音类型，减少用户选择负担
  async recommendNoise(emotion: string, currentActivity?: string): Promise<NoiseRecommendation> {
    const systemPrompt = `你是一个专注力专家。根据用户当前的情绪状态推荐最合适的白噪音类型。
可选类型：rain(雨声)、ocean(海浪)、forest(森林)、library(图书馆)、fire(壁炉)、none(无)

严格返回 JSON 格式，不要输出任何其他文字：
{
  "type": "rain|ocean|forest|library|fire|none",
  "reason": "推荐理由（一句话）"
}`

    const prompt = `用户情绪：${emotion}${currentActivity ? `\n当前活动：${currentActivity}` : ''}`

    try {
      // 使用 JSON 格式强制返回
      const response = await this.chat(prompt, systemPrompt, true)
      const json = this.extractJSON(response)
      const result: NoiseRecommendation = {
        type: (json.type as string) ?? 'rain',
        reason: (json.reason as string) ?? '帮助你更好地专注'
      }
      return result
    } catch (err) {
      console.error('[GLMService] recommendNoise error:', err)
      return DEFAULT_NOISE
    }
  }

  // 分析日记中的学习阻碍（使用LLM真实分析而非关键词匹配）
  async analyzeObstacles(diaryContents: string[]): Promise<ObstacleAnalysisResult> {
    const emptyResult: ObstacleAnalysisResult = { obstacles: [], report: '暂无日记数据可分析' }
    if (diaryContents.length === 0) {
      return emptyResult
    }

    // 合并日记内容，限制长度避免token过多
    const combinedContent = diaryContents.map((c, i) => `[日记${i + 1}] ${c}`).join('\n').substring(0, 3000)

    const systemPrompt = `你是一个专业的学习行为分析师。请仔细阅读用户近期的日记内容，分析影响学习的真实阻碍因素。

注意事项：
1. 仔细理解语境，识别否定句。如"我没玩手机"说明用户没有玩手机，不应计为阻碍
2. 只提取真正影响学习的因素，不要误判
3. 分析要基于日记的实际内容，不要臆断

严格返回JSON格式：
{
  "obstacles": ["阻碍1", "阻碍2", "阻碍3"],
  "report": "一段50-100字的分析报告，说明主要阻碍因素和改进建议"
}`

    try {
      const response = await this.chat(combinedContent, systemPrompt, true)
      const json = this.extractJSON(response)
      const result: ObstacleAnalysisResult = {
        obstacles: (json.obstacles as string[]) ?? [],
        report: (json.report as string) ?? '分析完成'
      }
      return result
    } catch (err) {
      console.error('[GLMService] analyzeObstacles error:', err)
      const errorResult: ObstacleAnalysisResult = { obstacles: [], report: '分析失败，请稍后重试' }
      return errorResult
    }
  }

  // 根据阻碍和目标给出针对性建议
  async generateStudyAdvice(obstacles: string[], goals: string[]): Promise<string> {
    const systemPrompt = `你是一个学习教练，帮助学生提高学习效率。
请根据用户的学习阻碍和目标，给出简洁实用的建议。
建议要具体、可执行，不超过100字。`

    const prompt = `我的学习阻碍：${obstacles.join('、')}
我的目标：${goals.join('、')}
请给我一条建议。`

    try {
      return await this.chat(prompt, systemPrompt)
    } catch (err) {
      console.error('[GLMService] generateStudyAdvice error:', err)
      return '建议：合理规划时间，减少干扰，专注当下任务。'
    }
  }

  /**
   * 通过联网搜索获取目标的真实截止日期
   * GLM-4.5-Flash 支持联网搜索，可获取最新的考试日期
   * @param goalTitle 目标标题，如"考研"、"四级"、"六级"
   * @returns 截止日期时间戳，如果无法确定则返回 null
   */
  async searchGoalDeadline(goalTitle: string): Promise<number | null> {
    const currentYear = new Date().getFullYear()
    const currentMonth = new Date().getMonth() + 1

    const systemPrompt = `你是一个精准的考试日期查询助手。
请根据用户的目标，联网搜索并返回最近一次该考试/目标的具体日期。
当前日期：${currentYear}年${currentMonth}月

要求：
1. 搜索最新的官方公布的考试时间
2. 如果是考研，返回全国硕士研究生招生考试初试日期
3. 如果是四级/六级(CET)，返回最近一次考试日期
4. 如果是高考/中考等，返回对应的考试日期
5. 如果目标没有固定日期，返回 null

严格以 JSON 格式返回，不要输出任何其他文字：
{
  "found": true或false,
  "year": 年份数字,
  "month": 月份数字(1-12),
  "day": 日期数字,
  "examName": "具体考试名称",
  "source": "信息来源说明"
}`

    const prompt = `请帮我查询"${goalTitle}"的最近一次考试/截止日期是什么时候？`

    try {
      // 使用 JSON 格式强制返回结构化数据
      const response = await this.chat(prompt, systemPrompt, true)
      const json = this.extractJSON(response)

      if (json.found === true && json.year && json.month && json.day) {
        const year = json.year as number
        const month = (json.month as number) - 1 // JavaScript 月份从 0 开始
        const day = json.day as number

        const deadline = new Date(year, month, day)
        console.info(`[GLMService] 搜索到 "${goalTitle}" 截止日期: ${deadline.toLocaleDateString()}，来源: ${json.source}`)

        return deadline.getTime()
      }

      console.info(`[GLMService] 未找到 "${goalTitle}" 的具体截止日期`)
      return null
    } catch (err) {
      console.error('[GLMService] searchGoalDeadline error:', err)
      return null
    }
  }

  /**
   * 生成温暖的 AI 鼓励语
   * @param content 日记内容
   * @param emotion 情绪状态
   * @returns 鼓励语
   */
  async generateEncouragement(content: string, emotion: string): Promise<string> {
    const systemPrompt = `你是一个温暖贴心的学习伙伴。
请根据用户的日记内容和情绪状态，给出一句简短温暖的鼓励。
要求：
1. 语气亲切、像朋友一样
2. 针对具体内容给出鼓励
3. 不超过50字
4. 可以适当使用 emoji

直接返回鼓励语，不要任何前缀或解释。`

    const prompt = `用户情绪：${emotion}\n日记内容：${content.substring(0, 200)}`

    try {
      const response = await this.chat(prompt, systemPrompt)
      return response || '今天也要加油哦！💪'
    } catch (err) {
      console.error('[GLMService] generateEncouragement error:', err)
      return '继续保持，你做得很棒！✨'
    }
  }

  // 一句话总结日记，用于列表预览
  async summarizeDiary(content: string): Promise<string> {
    const systemPrompt = `请用一句话总结这篇日记的核心内容，不超过30字。`

    try {
      return await this.chat(content, systemPrompt)
    } catch (err) {
      console.error('[GLMService] summarizeDiary error:', err)
      return ''
    }
  }

  /* ==================== 内部方法 ==================== */

  // 带重试的 API 调用入口
  private async callAPIWithRetry(
    messages: GLMChatMessage[],
    enableThinking: boolean = false,
    useJsonFormat: boolean = false,
    maxRetries: number = 3
  ): Promise<GLMResponse> {
    let lastError: Error | null = null

    // 请求频率限制：确保与上次请求间隔足够
    const now = Date.now()
    const timeSinceLastRequest = now - this.lastRequestTime
    if (timeSinceLastRequest < this.minRequestInterval) {
      await this.sleep(this.minRequestInterval - timeSinceLastRequest)
    }

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        this.lastRequestTime = Date.now()
        return await this.callAPI(messages, enableThinking, useJsonFormat)
      } catch (err) {
        lastError = err as Error
        const errMsg = lastError.message ?? ''

        // 429 限流 - 需要更长的等待时间
        if (errMsg.includes('429')) {
          const delay = attempt * 3000 // 递增延迟: 3s, 6s, 9s（限流需要更长等待）
          console.warn(`[GLMService] 请求过于频繁(429)，第${attempt}次重试，等待${delay}ms...`)
          await this.sleep(delay)
          continue
        }
        // 401 认证失败 - 短延迟重试
        if (errMsg.includes('401')) {
          const delay = attempt * 1000
          console.warn(`[GLMService] 认证失败(401)，第${attempt}次重试，等待${delay}ms...`)
          await this.sleep(delay)
          continue
        }
        // 其他错误直接抛出
        throw new Error(lastError?.message || 'API调用失败')
      }
    }

    throw new Error(lastError?.message || 'API调用失败')
  }

  // 延迟工具方法
  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  // HTTP 请求封装 - 智谱 API 要求 Bearer token 认证
  private async callAPI(
    messages: GLMChatMessage[],
    enableThinking: boolean = false,
    useJsonFormat: boolean = false
  ): Promise<GLMResponse> {
    // 离线检测 - 无网络时返回空响应
    if (!this.networkService.getIsOnline()) {
      console.warn('[GLMService] 当前无网络连接')
      throw new Error('OFFLINE')
    }

    return new Promise((resolve, reject) => {
      const httpRequest = http.createHttp()

      const requestBody: GLMRequestBody = {
        model: this.model,
        messages: messages,
        max_tokens: 2048,
        temperature: 0.7
      }

      // 深度思考会消耗更多 token，非必要不启用
      if (enableThinking) {
        const thinkingEnabled: GLMThinkingConfig = { type: 'enabled' }
        requestBody.thinking = thinkingEnabled
      } else {
        const thinkingDisabled: GLMThinkingConfig = { type: 'disabled' }
        requestBody.thinking = thinkingDisabled
      }

      // 强制 JSON 响应格式 - 避免大模型输出非结构化文本
      if (useJsonFormat) {
        const jsonFormat: GLMResponseFormat = { type: 'json_object' }
        requestBody.response_format = jsonFormat
      }

      httpRequest.request(
        this.baseUrl,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.apiKey}`
          },
          extraData: JSON.stringify(requestBody),
          connectTimeout: 30000,
          readTimeout: 60000
        },
        (err, data) => {
          httpRequest.destroy()

          if (err) {
            console.error('[GLMService] HTTP error:', err)
            reject(err)
            return
          }

          if (data.responseCode !== 200) {
            console.error('[GLMService] API error:', data.responseCode, data.result)
            reject(new Error(`API error: ${data.responseCode}`))
            return
          }

          try {
            const result = JSON.parse(data.result as string) as GLMResponse
            resolve(result)
          } catch (parseErr) {
            console.error('[GLMService] Parse error:', parseErr)
            reject(parseErr)
          }
        }
      )
    })
  }

  // 解析 AI 回复，提取结构化数据
  private parseIntentResponse(response: string): IntentResult {
    try {
      const json = this.extractJSON(response)

      const extracted: ExtractedInfo = {
        goals: (json.goals as string[]) ?? [],
        todos: (json.todos as string[]) ?? [],
        keywords: (json.keywords as string[]) ?? [],
        emotion: (json.emotion as string) ?? '',
        emotionScore: (json.emotionScore as number) ?? 3
      }

      const result: IntentResult = {
        type: (json.type as 'goal' | 'todo' | 'emotion' | 'question' | 'chat') ?? 'chat',
        content: response,
        confidence: 0.8,
        extracted: extracted
      }
      return result
    } catch (err) {
      const fallbackResult: IntentResult = {
        type: 'chat',
        content: response,
        confidence: 0.5
      }
      return fallbackResult
    }
  }

  // AI 回复可能夹杂文字，需要提取 JSON 部分
  private extractJSON(text: string): Record<string, Object> {
    try {
      return JSON.parse(text)
    } catch {
      // 回复格式: "这是分析结果：{...}"，需要正则提取
      const jsonMatch = text.match(/\{[\s\S]*\}/)
      if (jsonMatch) {
        try {
          return JSON.parse(jsonMatch[0])
        } catch {
          return {}
        }
      }
      return {}
    }
  }
}