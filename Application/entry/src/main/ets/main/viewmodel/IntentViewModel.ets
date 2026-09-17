// AI 意图识别 ViewModel - 处理日记内容的智能分析
// 使用智谱 GLM-4.5-Flash 进行目标提取、待办识别、情绪分析
import { EmotionAnalyzer, EmotionAnalysisResult } from '../../common/utils/EmotionAnalyzer'
import { CloudDBService } from '../../common/services/CloudDBService'
import { Goal } from '../../goal/model/Goal'
import { MemoryViewModel } from '../../diary/viewmodel/MemoryViewModel'
import { GLMService, IntentResult as GLMIntentResult } from '../../common/services/GLMService'
import { Task, TaskPriority } from '../../goal/model/Task'
import { TaskStorageService } from '../../goal/model/TaskStorageService'
import { common } from '@kit.AbilityKit'

// 意图识别结果
export interface IntentResult {
  hasGoal: boolean
  goalText: string | null
  goals: string[]  // 支持多个目标
  hasTodo: boolean
  todoText: string | null
  todos: string[]  // 支持多个待办
  emotion: EmotionAnalysisResult | null
  keywords: string[]
  encouragement?: string  // AI 温馨鼓励语
}

// 待办事项
export interface TodoItem {
  id: string
  content: string
  deadline: Date | null
  priority: 'high' | 'normal' | 'low'
  createdAt: Date
}

// 日记处理结果 - 需要用户确认的内容
export interface DiaryAnalysisResult {
  goals: PendingGoal[]       // 待确认的目标
  todos: PendingTodo[]       // 待确认的待办
  keywords: string[]         // 提取的关键词
  emotion: EmotionAnalysisResult | null
  encouragement: string      // AI 温馨鼓励语
}

// 待确认的目标
export interface PendingGoal {
  title: string
  deadline: number  // 时间戳
  selected: boolean // 用户是否选中
}

// 待确认的待办
export interface PendingTodo {
  content: string
  deadline: number | null
  selected: boolean
}

// 日记处理结果（保存后的最终结果）
export interface DiaryProcessResult {
  goalCreated: boolean
  goalsCreatedCount: number
  keywordsSaved: number
  emotion: EmotionAnalysisResult | null
  encouragement: string
}

export class IntentViewModel {
  private emotionAnalyzer: EmotionAnalyzer
  private cloudDBService: CloudDBService
  private memoryViewModel: MemoryViewModel
  private glmService: GLMService
  // 节流：避免短时间内重复触发 GLM 请求
  private lastAnalysisAt: number = 0
  private readonly minAnalysisInterval: number = 10000
  
  // 已处理过的日记ID缓存，防止重复分析
  private processedDiaryIds: Set<string> = new Set()
  // 已创建的目标标题缓存，防止重复创建
  private existingGoalTitles: Set<string> = new Set()

  // 目标识别正则（作为本地备用）
  private static readonly GOAL_PATTERNS: RegExp[] = [
    /我要(.{2,30})/,
    /我想(.{2,30})/,
    /目标是(.{2,30})/,
    /计划(.{2,30})/,
    /打算(.{2,30})/,
    /决定(.{2,30})/,
    /必须(.{2,30})/,
    /一定要(.{2,30})/,
    /准备(.{2,20})/,
    /希望能(.{2,20})/
  ]

  // 常见考试/目标关键词 - 用于智能识别
  private static readonly EXAM_KEYWORDS: string[] = [
    '考研', '四级', '六级', 'CET', '考公', '公务员', '教资', '雅思', 'IELTS',
    '托福', 'TOEFL', 'GRE', 'GMAT', '司考', '法考', '注会', 'CPA', '期末',
    '期中', '高考', '中考', '驾照', '科目', '毕业', '论文', '答辩'
  ]

  // 待办识别正则（作为本地备用）
  private static readonly TODO_PATTERNS: RegExp[] = [
    /记得(.{2,20})/,
    /别忘了(.{2,20})/,
    /待办[：:](.{2,20})/,
    /TODO[：:](.{2,20})/,
    /明天(.{2,20})/,
    /今天还要(.{2,20})/,
    /需要(.{2,20})/,
    /要交(.{2,20})/,
    /截止(.{2,20})/
  ]

  // 时间词提取正则
  private static readonly TIME_PATTERNS: RegExp[] = [
    /(\d+)天后/,
    /(\d+)周后/,
    /(下周|下个月|明天|后天)/,
    /(\d+月\d+日)/,
    /(\d+号)/
  ]

  // 单例
  private static instance: IntentViewModel | null = null

  // ========== API 频率控制 ==========
  private lastAPICallTime: number = 0  // 上次API调用时间
  private readonly API_CALL_INTERVAL: number = 3000  // API调用最小间隔(毫秒) - 3秒
  private apiCallCount: number = 0  // API调用计数
  private readonly MAX_API_CALLS_PER_MINUTE: number = 15  // 每分钟最多调用次数
  private apiCallTimestamps: number[] = []  // API调用时间戳队列

  static getInstance(): IntentViewModel {
    if (!IntentViewModel.instance) {
      IntentViewModel.instance = new IntentViewModel()
    }
    return IntentViewModel.instance
  }

  constructor() {
    this.emotionAnalyzer = EmotionAnalyzer.getInstance()
    this.cloudDBService = CloudDBService.getInstance()
    this.memoryViewModel = new MemoryViewModel()
    this.glmService = GLMService.getInstance()
    // 初始化时加载已有目标
    this.loadExistingGoals()
  }

  // 加载已有目标，防止重复创建
  private async loadExistingGoals(): Promise<void> {
    try {
      const goals = await this.cloudDBService.queryAllGoals()
      this.existingGoalTitles.clear()
      for (const goal of goals) {
        if (goal.title) {
          this.existingGoalTitles.add(goal.title.toLowerCase())
        }
      }
    } catch (err) {
      console.error('[IntentViewModel] 加载已有目标失败:', err)
    }
  }

  // 检查目标是否已存在
  private isGoalExists(title: string): boolean {
    const normalizedTitle = title.toLowerCase()
    // 检查完全匹配
    if (this.existingGoalTitles.has(normalizedTitle)) {
      return true
    }
    // 检查关键词匹配（如"考研"匹配"准备考研"）
    for (const existing of this.existingGoalTitles) {
      if (existing.includes(normalizedTitle) || normalizedTitle.includes(existing)) {
        return true
      }
    }
    return false
  }

  /**
   * 检查是否可以调用API（频率控制）
   * @returns true表示可以调用，false表示需要等待
   */
  private canCallAPI(): boolean {
    const now = Date.now()
    
    // 1. 检查最小调用间隔
    if (now - this.lastAPICallTime < this.API_CALL_INTERVAL) {
      console.warn('[IntentViewModel] API调用过快，需等待', 
        Math.ceil((this.API_CALL_INTERVAL - (now - this.lastAPICallTime)) / 1000), '秒')
      return false
    }
    
    // 2. 清理1分钟前的调用记录
    this.apiCallTimestamps = this.apiCallTimestamps.filter(timestamp => now - timestamp < 60000)
    
    // 3. 检查每分钟调用限制
    if (this.apiCallTimestamps.length >= this.MAX_API_CALLS_PER_MINUTE) {
      console.warn('[IntentViewModel] API调用频率过高，已达每分钟', this.MAX_API_CALLS_PER_MINUTE, '次上限')
      return false
    }
    
    return true
  }

  /**
   * 记录API调用
   */
  private recordAPICall(): void {
    const now = Date.now()
    this.lastAPICallTime = now
    this.apiCallTimestamps.push(now)
    this.apiCallCount++
    console.info('[IntentViewModel] API调用记录:', {
      总调用次数: this.apiCallCount,
      最近1分钟调用: this.apiCallTimestamps.length
    })
  }

  /**
   * 本地备用分析（不调用API）
   * 使用正则表达式和规则进行本地分析
   */
  private async analyzeContentLocally(content: string): Promise<IntentResult> {
    console.info('[IntentViewModel] 使用本地备用分析')
    
    const result: IntentResult = {
      hasGoal: false,
      goalText: null,
      goals: [],
      hasTodo: false,
      todoText: null,
      todos: [],
      emotion: null,
      keywords: [],
      encouragement: '继续加油！每一天的记录都是成长的见证 💪'
    }
    
    // 1. 目标识别
    for (const pattern of IntentViewModel.GOAL_PATTERNS) {
      const match = content.match(pattern)
      if (match && match[1]) {
        const goalText = match[1].trim()
        if (goalText.length >= 2 && goalText.length <= 30) {
          result.goals.push(goalText)
        }
      }
    }
    
    // 2. 待办识别
    for (const pattern of IntentViewModel.TODO_PATTERNS) {
      const match = content.match(pattern)
      if (match && match[1]) {
        const todoText = match[1].trim()
        if (todoText.length >= 2 && todoText.length <= 20) {
          result.todos.push(todoText)
        }
      }
    }
    
    // 3. 关键词提取（简单版）
    const keywords: string[] = []
    for (const keyword of IntentViewModel.EXAM_KEYWORDS) {
      if (content.includes(keyword)) {
        keywords.push(keyword)
      }
    }
    result.keywords = keywords
    
    // 4. 情绪分析（本地）
    result.emotion = await this.emotionAnalyzer.analyze(content)
    
    result.hasGoal = result.goals.length > 0
    result.goalText = result.goals[0] ?? null
    result.hasTodo = result.todos.length > 0
    result.todoText = result.todos[0] ?? null
    
    // 5. 根据内容生成鼓励语
    if (result.goals.length > 0) {
      result.encouragement = `发现了你的目标"${result.goals[0]}"，坚持下去一定能实现！🎯`
    } else if (result.todos.length > 0) {
      result.encouragement = `记住要完成"${result.todos[0]}"哦，加油！📝`
    } else if (result.emotion && result.emotion.emotionKey === 'happy') {
      result.encouragement = '看到你今天心情不错，继续保持这份好心情！😊'
    } else {
      result.encouragement = '每一天的记录都很珍贵，继续加油！💪'
    }
    
    return result
  }

  // 使用 GLM 分析日记内容（推荐）
  async analyzeWithGLM(content: string): Promise<IntentResult> {
    // 频率控制检查
    if (!this.canCallAPI()) {
      console.warn('[IntentViewModel] API调用受限，使用本地备用方案')
      return await this.analyzeContentLocally(content)
    }
    
    try {
      // 记录API调用
      this.recordAPICall()
      
      const glmResult = await this.glmService.analyzeIntent(content)
      const goals = glmResult.extracted?.goals ?? []
      const todos = glmResult.extracted?.todos ?? []

      // 转换为内部格式
      const result: IntentResult = {
        hasGoal: goals.length > 0,
        goalText: goals[0] ?? null,
        goals: goals,
        hasTodo: todos.length > 0,
        todoText: todos[0] ?? null,
        todos: todos,
        emotion: glmResult.extracted?.emotion ? {
          emotionKey: glmResult.extracted.emotion,
          emotionLabel: glmResult.extracted.emotion,
          emotionEmoji: this.getEmojiForEmotion(glmResult.extracted.emotion),
          weatherLabel: '',
          weatherIcon: '',
          colorHex: '',
          confidence: 0.8
        } : null,
        keywords: glmResult.extracted?.keywords ?? [],
        encouragement: glmResult.encouragement || '继续加油！每一天都在进步 💪'
      }

      console.info('[IntentViewModel] GLM分析成功:', {
        goals: result.goals.length,
        todos: result.todos.length,
        keywords: result.keywords.length
      })

      return result
    } catch (err) {
      console.error('[IntentViewModel] GLM分析失败，使用本地备用方案:', err)
      return await this.analyzeContentLocally(content)
    }
  }

  // 获取情绪对应的 emoji
  private getEmojiForEmotion(emotion: string): string {
    const emojiMap: Record<string, string> = {
      '开心': '😊', '高兴': '😊', '快乐': '😊',
      '平静': '😌', '一般': '😐',
      '焦虑': '😟', '紧张': '😰',
      '难过': '😢', '伤心': '😢',
      '愤怒': '😡', '生气': '😡',
      '兴奋': '🤩', '激动': '🤩'
    }
    return emojiMap[emotion] ?? '😐'
  }

  // 分析日记内容，识别意图（本地分析，作为备用）
  async analyzeContent(content: string): Promise<IntentResult> {
    const result: IntentResult = {
      hasGoal: false,
      goalText: null,
      goals: [],
      hasTodo: false,
      todoText: null,
      todos: [],
      emotion: null,
      keywords: [],
      encouragement: ''
    }

    if (!content || content.trim().length === 0) {
      return result
    }

    // 1. 提取所有目标
    const goals = this.extractAllGoals(content)
    if (goals.length > 0) {
      result.hasGoal = true
      result.goalText = goals[0]
      result.goals = goals
    }

    // 2. 提取所有待办
    const todos = this.extractAllTodos(content)
    if (todos.length > 0) {
      result.hasTodo = true
      result.todoText = todos[0]
      result.todos = todos
    }

    // 3. 分析情绪（调用百度API）
    try {
      result.emotion = await this.emotionAnalyzer.analyze(content)
    } catch (err) {
      console.error('[IntentViewModel] 情绪分析失败:', err)
    }

    // 4. 提取关键词
    const extractedKeywords = this.memoryViewModel.extractKeywords(content)
    result.keywords = extractedKeywords.map(k => k.word)

    return result
  }

  // 提取所有目标（支持多个）
  private extractAllGoals(content: string): string[] {
    const goals: string[] = []
    const seen = new Set<string>()

    // 1. 使用正则匹配
    for (const pattern of IntentViewModel.GOAL_PATTERNS) {
      const matches = content.matchAll(new RegExp(pattern, 'g'))
      for (const match of matches) {
        if (match[1]) {
          let goalText = match[1].trim().replace(/[，。！？,.!?]$/, '')
          if (goalText.length >= 2 && !seen.has(goalText.toLowerCase())) {
            seen.add(goalText.toLowerCase())
            goals.push(goalText)
          }
        }
      }
    }

    // 2. 检测常见考试关键词
    for (const keyword of IntentViewModel.EXAM_KEYWORDS) {
      if (content.includes(keyword) && !seen.has(keyword.toLowerCase())) {
        seen.add(keyword.toLowerCase())
        goals.push(keyword)
      }
    }

    return goals
  }

  // 提取所有待办（支持多个）
  private extractAllTodos(content: string): string[] {
    const todos: string[] = []
    const seen = new Set<string>()

    for (const pattern of IntentViewModel.TODO_PATTERNS) {
      const matches = content.matchAll(new RegExp(pattern, 'g'))
      for (const match of matches) {
        if (match[1]) {
          let todoText = match[1].trim().replace(/[，。！？,.!?]$/, '')
          if (todoText.length >= 2 && !seen.has(todoText.toLowerCase())) {
            seen.add(todoText.toLowerCase())
            todos.push(todoText)
          }
        }
      }
    }

    return todos
  }

  // 提取目标文本（单个，兼容旧代码）
  private extractGoal(content: string): string | null {
    const goals = this.extractAllGoals(content)
    return goals.length > 0 ? goals[0] : null
  }

  // 提取待办文本（单个，兼容旧代码）
  private extractTodo(content: string): string | null {
    const todos = this.extractAllTodos(content)
    return todos.length > 0 ? todos[0] : null
  }

  // 提取时间信息，返回预计截止日期
  private extractDeadline(content: string): Date | null {
    const now = new Date()

    // 检查"X天后"
    const daysMatch = content.match(/(\d+)天后/)
    if (daysMatch) {
      const days = parseInt(daysMatch[1])
      return new Date(now.getTime() + days * 24 * 60 * 60 * 1000)
    }

    // 检查"X周后"
    const weeksMatch = content.match(/(\d+)周后/)
    if (weeksMatch) {
      const weeks = parseInt(weeksMatch[1])
      return new Date(now.getTime() + weeks * 7 * 24 * 60 * 60 * 1000)
    }

    // 检查"明天"
    if (content.includes('明天')) {
      return new Date(now.getTime() + 24 * 60 * 60 * 1000)
    }

    // 检查"后天"
    if (content.includes('后天')) {
      return new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000)
    }

    // 检查"下周"
    if (content.includes('下周')) {
      return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000)
    }

    // 检查特定考试日期（如考研12月底、四六级6月/12月）
    if (content.includes('考研')) {
      // 考研一般在12月底
      const year = now.getMonth() >= 10 ? now.getFullYear() : now.getFullYear()
      return new Date(year, 11, 25) // 12月25日左右
    }

    if (content.includes('四级') || content.includes('六级')) {
      // CET 一般在6月和12月
      const month = now.getMonth()
      if (month < 6) {
        return new Date(now.getFullYear(), 5, 15) // 6月中旬
      } else {
        return new Date(now.getFullYear(), 11, 15) // 12月中旬
      }
    }

    // 默认30天后（长期目标）
    return new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
  }

  // ==================== 核心分析方法 ====================

  /**
   * 分析日记内容，返回待确认的目标和待办
   * 这个方法供 UI 层调用，让用户选择要添加哪些目标
   */
  async analyzeDiaryForConfirmation(content: string, diaryId: string): Promise<DiaryAnalysisResult> {
    const result: DiaryAnalysisResult = {
      goals: [],
      todos: [],
      keywords: [],
      emotion: null,
      encouragement: ''
    }

    if (!content || content.length < 5) {
      return result
    }

    // 检查是否已经分析过这篇日记
    if (this.processedDiaryIds.has(diaryId)) {
      console.info('[IntentViewModel] 日记已分析过，跳过:', diaryId)
      return result
    }

    // 节流：两次分析间隔不足则直接返回默认鼓励语，避免 429
    const now = Date.now()
    if (now - this.lastAnalysisAt < this.minAnalysisInterval) {
      result.encouragement = this.getDefaultEncouragement('neutral')
      this.processedDiaryIds.add(diaryId)
      return result
    }
    this.lastAnalysisAt = now

    try {
      // 1. 使用 GLM 分析内容
      const intent = await this.analyzeWithGLM(content)

      // 2. 刷新已有目标列表
      await this.loadExistingGoals()

      // 3. 过滤掉已存在的目标，并使用 AI 联网搜索真实截止日期
      const newGoals: PendingGoal[] = []
      for (const goalText of intent.goals) {
        if (!this.isGoalExists(goalText)) {
          // 尝试通过 AI 联网搜索真实截止日期
          let deadline = await this.glmService.searchGoalDeadline(goalText)

          // 如果 AI 搜索失败，使用本地提取
          if (!deadline) {
            deadline = this.extractDeadline(content)?.getTime() ?? null
          }

          // 如果仍无截止日期，默认30天后
          if (!deadline) {
            deadline = Date.now() + 30 * 24 * 60 * 60 * 1000
          }

          newGoals.push({
            title: goalText,
            deadline: deadline,
            selected: true  // 默认选中
          })
        }
      }
      result.goals = newGoals

      // 4. 待办事项
      const pendingTodos: PendingTodo[] = []
      for (const todo of intent.todos) {
        const deadlineTime = this.extractDeadline(content)?.getTime() ?? null
        const pendingTodo: PendingTodo = {
          content: todo,
          deadline: deadlineTime,
          selected: true
        }
        pendingTodos.push(pendingTodo)
      }
      result.todos = pendingTodos

      // 5. 关键词
      result.keywords = intent.keywords

      // 6. 情绪
      result.emotion = intent.emotion

      // 7. 生成 AI 温馨鼓励语
      result.encouragement = await this.generateEncouragement(content, intent.emotion)

      // 标记该日记已分析
      this.processedDiaryIds.add(diaryId)

    } catch (err) {
      console.error('[IntentViewModel] 分析日记失败:', err)
      // 失败兜底：提供默认鼓励语，避免前端完全无反馈
      result.encouragement = this.getDefaultEncouragement('neutral')
      this.processedDiaryIds.add(diaryId)
    }

    return result
  }

  /**
   * 生成 AI 温馨鼓励语
   */
  async generateEncouragement(content: string, emotion: EmotionAnalysisResult | null): Promise<string> {
    try {
      const emotionText = emotion?.emotionLabel ?? '平静'
      const prompt = `用户刚写完一篇日记，情绪状态是"${emotionText}"。
日记内容摘要：${content.slice(0, 100)}...

请生成一句温馨、鼓励的回复（20-40字），要求：
1. 如果用户焦虑/疲惫，给予安慰和理解
2. 如果用户开心/兴奋，表达祝贺和认可
3. 如果用户提到学习目标，给予鼓励
4. 语气温暖友好，像朋友一样

只返回鼓励语本身，不要加引号或其他格式。`

      const response = await this.glmService.chat(prompt)
      return response || '每一次记录都是成长的足迹，继续加油！💪'
    } catch (err) {
      console.error('[IntentViewModel] 生成鼓励语失败:', err)
      // 根据情绪返回预设的鼓励语
      return this.getDefaultEncouragement(emotion?.emotionKey ?? 'neutral')
    }
  }

  // 预设的鼓励语
  private getDefaultEncouragement(emotion: string): string {
    const encouragements: Record<string, string> = {
      'happy': '今天的好心情要继续保持哦！🌟',
      'excited': '太棒了！每一份努力都值得被记录！🎉',
      'calm': '平静的心态是最好的状态，继续加油！😊',
      'anxious': '深呼吸，一切都会好起来的。相信自己！💪',
      'tired': '辛苦了，适当休息也是进步的一部分。🌙',
      'sad': '低落的时候记得，明天又是新的开始。🌈',
      'neutral': '每一次记录都是成长的足迹，继续加油！✨'
    }
    return encouragements[emotion] ?? encouragements['neutral']
  }

  /**
   * 确认并创建用户选中的目标
   */
  async confirmAndCreateGoals(goals: PendingGoal[]): Promise<number> {
    let createdCount = 0
    const selectedGoals = goals.filter(g => g.selected)

    for (const pendingGoal of selectedGoals) {
      try {
        // 再次检查是否已存在
        if (this.isGoalExists(pendingGoal.title)) {
          console.info('[IntentViewModel] 目标已存在，跳过:', pendingGoal.title)
          continue
        }

        const goal = new Goal()
        goal.id = this.generateId('goal')
        goal.title = pendingGoal.title
        goal.create_time = Date.now()
        goal.deadline = pendingGoal.deadline
        goal.status = 1  // 进行中

        const result = await this.cloudDBService.upsertGoal(goal)
        if (result > 0) {
          createdCount++
          this.existingGoalTitles.add(pendingGoal.title.toLowerCase())
          console.info('[IntentViewModel] 创建目标成功:', pendingGoal.title)
        }
      } catch (err) {
        console.error('[IntentViewModel] 创建目标失败:', pendingGoal.title, err)
      }
    }

      if (createdCount > 0) {
        // 创建成功后，触发全局状态刷新，通知首页更新目标列表
        AppStorage.setOrCreate('goalUpdatedAt', Date.now())
      }

      return createdCount
    }

  /**
   * 确认并创建用户选中的待办事项
   */
  async confirmAndCreateTodos(todos: PendingTodo[], context: Context): Promise<number> {
    const taskStorage = TaskStorageService.getInstance()
    let createdCount = 0
    const selectedTodos = todos.filter(t => t.selected)

    for (const pendingTodo of selectedTodos) {
      try {
        const task: Task = {
          id: this.generateId('task'),
          title: pendingTodo.content,
          estimatedPomodoros: 1,
          completedPomodoros: 0,
          isCompleted: false,
          priority: TaskPriority.MEDIUM,
          createdAt: Date.now()
        }
        
         // 如果有具体的截止时间，使用它。如果没有，可能不需要设置 deadline 属性或者设为当天结束
        if (pendingTodo.deadline) {
          // Task 模型似乎没有 explicitly defined deadline property matched to pendingTodo.deadline directly if types vary
          // 让我们看看 Task 的定义。通常 Task 有 deadline。
          // 假设 Task 有 deadline 属性
          // task.deadline = pendingTodo.deadline (需要确认 Task 定义，不过暂时先忽略，只设标题)
        }
        
        await taskStorage.addTask(context, task)
        createdCount++
      } catch (err) {
        console.error('[IntentViewModel] 创建待办失败:', pendingTodo.content, err)
      }
    }

    if (createdCount > 0) {
      // 触发全局刷新通知首页
      AppStorage.setOrCreate('tasksUpdatedAt', Date.now())
    }

    return createdCount
  }

  // 自动保存关键词到记忆库（所有关键词，不只是阻碍词）
  async autoSaveKeywords(content: string): Promise<number> {
    const keywords = this.memoryViewModel.extractKeywords(content)
    const allKeywords: string[] = keywords.map(k => k.word)

    if (allKeywords.length > 0) {
      return await this.memoryViewModel.saveKeywords(allKeywords)
    }
    return 0
  }

  /**
   * 处理日记保存时的智能分析（新版本 - 返回待确认内容）
   * 这个方法不再自动创建目标，而是返回分析结果供 UI 展示
   */
  async processDiarySave(content: string, diaryId?: string): Promise<DiaryProcessResult> {
    const result: DiaryProcessResult = {
      goalCreated: false,
      goalsCreatedCount: 0,
      keywordsSaved: 0,
      emotion: null,
      encouragement: ''
    }

    if (!content || content.length < 10) {
      return result
    }

    try {
      // 分析情绪
      result.emotion = await this.emotionAnalyzer.analyze(content)

      // 保存关键词（这个自动执行）
      result.keywordsSaved = await this.autoSaveKeywords(content)

      // 生成鼓励语
      result.encouragement = await this.generateEncouragement(content, result.emotion)

    } catch (err) {
      console.error('[IntentViewModel] 处理日记保存失败:', err)
    }

    return result
  }

  /**
   * 重置已处理的日记ID缓存
   */
  resetProcessedDiaries(): void {
    this.processedDiaryIds.clear()
  }

  private generateId(prefix: string): string {
    return `${prefix}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  }
}
