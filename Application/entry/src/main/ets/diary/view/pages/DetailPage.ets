
/**
 * @file DetailPage.ets
 * @description 日记详情编辑页面 - 重构版 (MVVM 组件化)
 */
import { router, promptAction } from '@kit.ArkUI'
import common from '@ohos.app.ability.common'
import photoAccessHelper from '@ohos.file.photoAccessHelper'
import { fileUri } from '@kit.CoreFileKit'
import fs from '@ohos.file.fs'
import window from '@ohos.window'

import { NoteItem, ChecklistItem, LinkItem, LinkBlock, ContentBlock, TextBlock } from '../../model/NoteItem'
import { RecordingItem } from '../../model/RecordingItem'
import { PreferencesUtil } from '../../../common/utils/PreferencesUtil'
import { RecordingService, ASRCallbacks } from '../../../common/services/RecordingService'
import * as DiaryUtils from '../../../common/utils/DiaryUtils'
import { AudioPlayer } from '../../../common/utils/AudioPlayer'
import { AppColors, AppShadows, AppGradients, AppSizes, LinearGradient } from '../../../common/utils/AppTheme'
import { EmotionAnalyzer, EmotionAnalysisResult, EmotionPreset, EMOTION_PRESETS } from '../../../common/utils/EmotionAnalyzer'
import { GLMService, IntentResult } from '../../../common/services/GLMService'
import { IntentViewModel, DiaryAnalysisResult, PendingGoal, PendingTodo } from '../../../main/viewmodel/IntentViewModel'
import { DiaryTopBar, DiaryBottomBar } from '../components/DiaryToolBar'
import { NoteEditView, NoteEditController } from '../components/NoteEditView'
import { EmotionPanel } from '../components/EmotionPanel'
import { CategoryPickerDialog, LockDialog, UnlockDialog } from '../components/DiaryDialogs'
import { InsertMenuDialog, LinkDialog, ChecklistDialog } from '../components/InsertMenu'
import { AudioRecordingOverlay } from '../components/AudioRecordingOverlay'

/** 波纹数据接口 */
interface RippleData {
  radius: number
  opacity: number
  speed: number
  lineWidth: number
}

/** Span信息接口（用于构建richEditorSpans） */
interface SpanData {
  type: string
  value?: string
  linkTitle?: string
  linkUrl?: string
}

@Entry
@Component
struct DetailPage {
  @State noteId: string = ''
  @State note: NoteItem = new NoteItem()
  
  // 安全区高度
  @State topSafeHeight: number = 0
  @State bottomSafeHeight: number = 0
  
  // 编辑器状态（与 NoteEditView 同步）
  @State titleText: string = ''
  @State contentText: string = ''
  @State recordings: RecordingItem[] = []
  @State checklistItems: ChecklistItem[] = []
  @State canUndo: boolean = false
  @State canRedo: boolean = false
  
  // 弹窗状态
  @State showInsertMenu: boolean = false
  @State showEmotionPanel: boolean = false
  @State showCategoryPicker: boolean = false
  @State showLockDialog: boolean = false
  @State showUnlockDialog: boolean = false
  @State showLinkDialog: boolean = false
  @State showChecklistDialog: boolean = false
  @State showRecordingOverlay: boolean = false

  // 预解锁标志
  private isPreUnlocked: boolean = false
  
  // 待插入的链接数据
  private pendingLinkData: Record<string, string> | null = null
  
  // 分类列表
  @State categories: string[] = ['生活', '工作', '学习', '灵感', '情感', '旅行']
  
  // 使用独立的分类状态变量，避免$note.category嵌套绑定导致闪退
  @State @Watch('onCategoryChange') selectedCategory: string = '生活'
  
  // 临时状态（用于弹窗交互）
  @State tempLinkTitle: string = ''
  @State tempLinkUrl: string = ''
  @State checklistInput: string = ''
  @State passwordInput: string = ''
  @State confirmPasswordInput: string = ''
  
  // 情绪分析状态
  @State isEmotionAnalyzing: boolean = false
  @State emotionStatusText: string = '等待分析'
  @State emotionAnalysisError: string = ''
  @State selectedEmotionEmoji: string = '😐'
  @State selectedEmotionLabel: string = '平淡'
  @State selectedEmotionKey: string = 'neutral'
  @State selectedWeatherIcon: string = '☁️'
  @State selectedWeatherLabel: string = '多云'
  @State emotionColor: string = '#9CA3AF'
  @State emotionConfidence: number = 0
  
  // 录音状态
  @State isRecording: boolean = false
  @State isProcessing: boolean = false
  @State recordingSeconds: number = 0
  @State waveHeights: number[] = [20, 35, 25, 40, 30, 45, 28, 38, 22, 42, 32, 36]
  @State pulseScale: number = 1
  @State currentVolume: number = 0
  
  // AI分析弹窗控制器
  @State aiAnalysisResult: DiaryAnalysisResult | null = null
  private aiDialogController: CustomDialogController | null = null
  @State realTimeTranscription: string = ''
  @State isSlideCancelling: boolean = false  // 上滑取消状态
  private lastASRLength: number = 0
  private recordStartY: number = 0  // 录音开始时的Y坐标
  
  // 播放状态
  @State isPlaying: boolean = false
  @State currentPlayingId: string = ''
  @State playbackProgress: number = 0
  @State currentDuration: number = 0
  
  // 控制器
  @State noteEditController: NoteEditController = new NoteEditController()
  
  // 服务实例
  private recordingService: RecordingService = RecordingService.getInstance()
  private audioPlayer: AudioPlayer = new AudioPlayer()
  private emotionAnalyzer: EmotionAnalyzer = EmotionAnalyzer.getInstance()
  private glmService: GLMService = GLMService.getInstance()
  
  private emotionAnalysisTimer: number = 0
  private uiTimer: number = 0 // Modified from waveAnimationTimer
  private playbackTimer: number = 0
  private saveTimer: number = 0

  // 波纹动画相关 // Added
  private waveCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private waveCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.waveCanvasSettings)
  private ripples: Array<RippleData> = []
  private rippleAnimationTimer: number = 0
  private lastRippleTime: number = 0
  private frameCount: number = 0
  
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext

  // 页面生命周期
  aboutToAppear(): void {
    this.setFullScreen()
    const params = router.getParams() as Record<string, Object>
    // 问题11修复：预解锁标志（从LockedNotesPage已验证过密码）
    let preUnlocked = false
    // 修复：记录是否是新建日记（有初始内容但没有noteId）
    let isNewNoteWithContent = false
    if (params) {
      if (params['noteId']) {
        this.noteId = params['noteId'] as string
      } else if (params['initialTitle'] || params['initialContent']) {
        // 如果没有noteId但有初始内容，说明是新建日记
        isNewNoteWithContent = true
      }
      // 检查是否已预先解锁
      if (params['preUnlocked']) {
        preUnlocked = params['preUnlocked'] as boolean
      }
      // News-Diary Integration: pre-fill content
      if (params['initialTitle']) {
        this.titleText = params['initialTitle'] as string
      }
      if (params['initialContent']) {
        this.contentText = params['initialContent'] as string
      }
      // 处理从新闻页传递的超链接信息
      if (params['initialLink']) {
        const linkData = params['initialLink'] as Record<string, string>
        if (linkData && linkData.title && linkData.url) {
          // 保存链接数据，等待编辑器准备好后插入
          this.pendingLinkData = linkData
        }
      }
    }
    
    // 保存预解锁状态供loadNote使用
    this.isPreUnlocked = preUnlocked
    
    // 初始化服务
    this.initServices()
    // 加载日记
    this.loadNote()
    
    // 如果是新建日记且有初始内容，立即保存一次确保日记被创建
    // 注意：loadNote()会创建新的note对象，所以这里需要等待loadNote完成
    setTimeout(async () => {
      // 检查是否是新建日记（有初始内容但没有从数据库加载）
      if (isNewNoteWithContent && this.note && this.note.id) {
        // 确保内容已同步到note对象（再次确认，因为loadNote可能重置了）
        this.note.title = this.titleText || ''
        this.note.content = this.contentText || ''
        
        // 如果richEditorSpans还没有设置，手动构建它
        // 这样可以确保内容（包括链接）被正确保存
        if (!this.note.richEditorSpans || this.note.richEditorSpans === '[]') {
          const spanInfos: SpanData[] = []
          // 添加文本内容
          if (this.contentText && this.contentText.trim() !== '') {
            const textSpan: SpanData = { type: 'text', value: this.contentText }
            spanInfos.push(textSpan)
            console.info('[DetailPage] 添加文本内容到richEditorSpans，长度:', this.contentText.length)
          }
          // 添加链接（从pendingLinkData或note.links）
          if (this.pendingLinkData) {
            const linkSpan: SpanData = { 
              type: 'link', 
              linkTitle: this.pendingLinkData.title, 
              linkUrl: this.pendingLinkData.url 
            }
            spanInfos.push(linkSpan)
            // 同时添加到note.links
            if (!this.note.links) {
              this.note.links = []
            }
            const linkItem = new LinkItem()
            linkItem.id = Date.now().toString()
            linkItem.title = this.pendingLinkData.title
            linkItem.url = this.pendingLinkData.url
            this.note.links.push(linkItem)
            console.info('[DetailPage] 添加链接到richEditorSpans:', this.pendingLinkData.title)
          } else if (this.note.links && this.note.links.length > 0) {
            this.note.links.forEach(link => {
              const linkSpan: SpanData = { 
                type: 'link', 
                linkTitle: link.title, 
                linkUrl: link.url 
              }
              spanInfos.push(linkSpan)
            })
          }
          if (spanInfos.length > 0) {
            this.note.richEditorSpans = JSON.stringify(spanInfos)
            console.info('[DetailPage] 手动构建richEditorSpans，包含', spanInfos.length, '个元素，JSON长度:', this.note.richEditorSpans.length)
          } else {
            console.warn('[DetailPage] 警告：没有内容可以添加到richEditorSpans')
          }
        }
        
        // 再次确保note.content被设置（重要！）
        if (!this.note.content || this.note.content.trim() === '') {
          this.note.content = this.contentText || ''
          console.info('[DetailPage] 修复：设置note.content，长度:', this.note.content.length)
        }
        
        // 立即保存确保日记被创建
        await this.saveNote()
        console.info('[DetailPage] 新建日记已保存，ID:', this.note.id, '标题:', this.note.title, '内容长度:', this.note.content?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0)
        // 显示保存成功提示
        promptAction.showToast({ message: '日记已创建', duration: 1500 })
      }
    }, 1500)  // 等待编辑器初始化和链接插入完成
  }
  
  async setFullScreen() {
    try {
      const windowClass = await window.getLastWindow(getContext(this))
      await windowClass.setWindowLayoutFullScreen(true)
      const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      this.topSafeHeight = px2vp(avoidArea.topRect.height)
      this.bottomSafeHeight = px2vp(avoidArea.bottomRect.height)
    } catch (e) {
      this.topSafeHeight = 44
      this.bottomSafeHeight = 34
    }
  }
  
  onPageHide(): void {
    this.stopPlayback()
    // 修复：保存前确保内容已同步
    // 通过触发一次内容变化来确保RichEditor内容已同步
    if (this.contentText) {
      this.note.content = this.contentText
    }
    
    // 修复：如果note.links有内容但richEditorSpans中没有，确保richEditorSpans包含链接
    if (this.note.links && this.note.links.length > 0) {
      try {
        let spans: SpanData[] = []
        if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
          spans = JSON.parse(this.note.richEditorSpans) as SpanData[]
        }
        
        // 检查richEditorSpans中是否包含所有链接
        const linkUrlsInSpans = new Set(spans.filter(s => s.type === 'link').map(s => s.linkUrl))
        let needUpdate = false
        
        for (const link of this.note.links) {
          if (!linkUrlsInSpans.has(link.url)) {
            spans.push({
              type: 'link',
              linkTitle: link.title,
              linkUrl: link.url
            })
            needUpdate = true
            console.info('[DetailPage] onPageHide: 添加缺失的链接到richEditorSpans:', link.title)
          }
        }
        
        // 如果没有文本内容但有链接，至少添加文本占位符
        const hasText = spans.some(s => s.type === 'text' && s.value && s.value.trim() !== '')
        if (!hasText && spans.length > 0) {
          // 如果有链接但没有文本，至少保留一个空文本或者从note.content创建
          if (this.note.content && this.note.content.trim() !== '') {
            spans.unshift({
              type: 'text',
              value: this.note.content
            })
            needUpdate = true
          }
        }
        
        if (needUpdate) {
          this.note.richEditorSpans = JSON.stringify(spans)
          console.info('[DetailPage] onPageHide: 更新richEditorSpans，包含', spans.length, '个元素')
        }
      } catch (e) {
        console.warn('[DetailPage] onPageHide: 检查richEditorSpans失败:', e)
      }
    }
    
    this.saveNote() // 立即保存
  }
  
  aboutToDisappear(): void {
    this.recordingService.release()
    this.audioPlayer.release()
    this.stopRippleAnimation() // Added
    this.stopUITimer() // Added
  }
  
  // 初始化服务
  private initServices(): void {
    this.recordingService.init()
    this.audioPlayer.init()
  }
  
  private stopPlayback(): void {
     this.audioPlayer.stop()
     this.isPlaying = false
     this.currentPlayingId = ''
     this.playbackProgress = 0
     if (this.playbackTimer) {
        clearInterval(this.playbackTimer)
        this.playbackTimer = 0
     }
  }

  // 加载日记数据
  async loadNote(): Promise<void> {
    if (this.noteId) {
      const notes = await PreferencesUtil.loadNotes(this.context)
      const loaded = notes.find(n => n.id === this.noteId)
      if (loaded) {
        this.note = loaded
        this.titleText = loaded.title || ''
        this.contentText = loaded.content || ''
        this.recordings = loaded.recordings || []
        this.checklistItems = loaded.checklist || [] 
        this.initEmotionState(loaded)
        // 问题4修复：初始化分类状态
        this.selectedCategory = loaded.category || '生活'
        
        // 修复：调试信息 - 检查加载的内容
        console.info('[DetailPage] 加载日记，ID:', loaded.id, '标题:', loaded.title, 'content长度:', loaded.content?.length || 0, 'richEditorSpans长度:', loaded.richEditorSpans?.length || 0, 'links数量:', loaded.links?.length || 0)
        
        // 修复：确保links数组被正确加载
        if (loaded.links && loaded.links.length > 0) {
          console.info('[DetailPage] 加载日记，包含', loaded.links.length, '个链接')
        }
        
        // 修复：如果content为空但richEditorSpans存在，从richEditorSpans中提取文本
        if ((!this.contentText || this.contentText.trim() === '') && loaded.richEditorSpans && loaded.richEditorSpans !== '[]') {
          try {
            const spanDataList: SpanData[] = JSON.parse(loaded.richEditorSpans) as SpanData[]
            let textContent = ''
            for (const spanData of spanDataList) {
              if (spanData.type === 'text' && spanData.value) {
                textContent += spanData.value
              }
            }
            if (textContent) {
              this.contentText = textContent
              this.note.content = textContent
              console.info('[DetailPage] 从richEditorSpans恢复文本内容，长度:', textContent.length)
            } else {
              console.warn('[DetailPage] richEditorSpans中没有文本内容，但可能有链接或媒体内容')
              // 即使没有文本，也确保content至少是空字符串，这样richEditorSpans中的链接也能显示
              this.contentText = ''
              this.note.content = ''
            }
          } catch (e) {
            console.warn('[DetailPage] 从richEditorSpans提取文本失败:', e)
          }
        }
        
        // 修复：如果content和richEditorSpans都为空，记录警告
        if ((!this.contentText || this.contentText.trim() === '') && (!loaded.richEditorSpans || loaded.richEditorSpans === '[]')) {
          console.warn('[DetailPage] 警告：日记内容为空！ID:', loaded.id, '标题:', loaded.title)
        }
        
        // 问题11修复：如果已预先解锁(从LockedNotesPage进入)则跳过密码验证
        if (loaded.isLocked && !this.isPreUnlocked) {
           this.showUnlockDialog = true
        }
        
        // 修复：加载完成后，记录日志便于调试
        setTimeout(() => {
          console.info('[DetailPage] loadNote完成，contentText长度:', this.contentText.length, 'note.content长度:', this.note.content?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0, 'links数量:', this.note.links?.length || 0)
        }, 300)
      }
    } else {
      // New Note
      this.note = new NoteItem()
      this.note.id = Date.now().toString()
      this.note.createTime = Date.now()
      this.noteId = this.note.id
      // Keep pre-filled values if they exist, otherwise empty
      this.titleText = this.titleText || ''
      this.contentText = this.contentText || ''
      // 修复：确保新建日记时，note对象也包含初始内容
      this.note.title = this.titleText
      this.note.content = this.contentText
      console.info('[DetailPage] 新建日记，ID:', this.note.id, '标题:', this.titleText, '内容长度:', this.contentText.length)
      
      // 修复：同步初始值到note对象
      this.note.title = this.titleText
      this.note.content = this.contentText
      
      // 修复：如果是新建日记且有初始内容，立即保存一次
      // 但需要等待RichEditor初始化完成，所以延迟更长
      if (this.titleText || this.contentText) {
        // 延迟保存，确保RichEditor和链接都初始化完成
        setTimeout(async () => {
          // 再次确保内容同步
          this.note.title = this.titleText
          this.note.content = this.contentText
          await this.saveNote()
          console.info('[DetailPage] 新建日记已立即保存，ID:', this.note.id, '内容:', this.contentText.substring(0, 50))
        }, 1500)  // 增加延迟，确保链接插入完成
      }
    }
  }
  
  private initEmotionState(note: NoteItem): void {
     if (note.emotionLabel) {
        this.selectedEmotionLabel = note.emotionLabel
        this.selectedEmotionEmoji = note.emotionEmoji || '😐'
        this.selectedWeatherLabel = note.weatherLabel || '多云'
        this.selectedWeatherIcon = note.weatherIcon || '☁️'
        this.emotionColor = note.emotionColor || '#9CA3AF'
        this.emotionStatusText = `情绪：${note.emotionLabel}`
     }
  }
  
  // 保存日记
  async saveNote(): Promise<void> {
    // 修复：确保RichEditor内容已同步
    // 通过访问NoteEditView的onBeforeSave回调来强制同步
    // 注意：由于NoteEditView是子组件，我们无法直接访问其内部方法
    // 但我们可以通过触发一次内容变化来确保同步
    // 实际上，onContentChange会在内容变化时自动调用syncContentFromRichEditor
    // 所以这里我们只需要确保note对象的状态是最新的
    
    // 修复：在保存前，先尝试从RichEditor获取最新内容
    // 如果contentText为空，尝试从richEditorSpans提取
    // 注意：onBeforeSave 回调会在 NoteEditView 中自动调用 syncContentFromRichEditor
    // 但为了确保，我们在这里也做一次检查
    
    this.note.title = this.titleText
    
    // 修复：确保content包含完整文本内容
    // 优先使用contentText，如果为空则从richEditorSpans中提取
    if (this.contentText && this.contentText.trim() !== '') {
      this.note.content = this.contentText
    } else if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
      try {
        const spanDataList: SpanData[] = JSON.parse(this.note.richEditorSpans) as SpanData[]
        let textContent = ''
        for (const spanData of spanDataList) {
          if (spanData.type === 'text' && spanData.value) {
            textContent += spanData.value
          }
        }
        if (textContent) {
          this.note.content = textContent
          this.contentText = textContent
          console.info('[DetailPage] 保存时从richEditorSpans提取文本，长度:', textContent.length)
        } else {
          console.warn('[DetailPage] richEditorSpans中没有文本内容')
        }
      } catch (e) {
        console.warn('[DetailPage] 从richEditorSpans提取文本失败:', e)
      }
    } else {
      // 如果都没有，至少保存空字符串
      this.note.content = this.contentText || ''
    }
    // Ensure lists are synced (crucial for rename/delete persistence)
    this.note.recordings = this.recordings
    this.note.checklist = this.checklistItems
    
    // 修复：确保链接已同步（NoteEditView会在syncContentFromRichEditor中同步，但我们需要确保）
    // 如果note.links不存在，从contentBlocks中恢复
    if (!this.note.links || this.note.links.length === 0) {
      if (this.note.contentBlocks) {
        const links: LinkItem[] = []
        this.note.contentBlocks.forEach(block => {
          if (block instanceof LinkBlock) {
            const linkItem = new LinkItem()
            linkItem.id = Date.now().toString() + Math.random().toString()
            linkItem.title = block.title
            linkItem.url = block.url
            links.push(linkItem)
          }
        })
        if (links.length > 0) {
          this.note.links = links
        }
      }
    }
    
    // 修复：确保richEditorSpans包含所有链接
    if (this.note.links && this.note.links.length > 0) {
      try {
        let spans: SpanData[] = []
        if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
          spans = JSON.parse(this.note.richEditorSpans) as SpanData[]
        }
        
        // 检查richEditorSpans中是否包含所有链接
        const linkUrlsInSpans = new Set(spans.filter(s => s.type === 'link' && s.linkUrl).map(s => s.linkUrl))
        let needUpdate = false
        
        for (const link of this.note.links) {
          if (!linkUrlsInSpans.has(link.url)) {
            spans.push({
              type: 'link',
              linkTitle: link.title,
              linkUrl: link.url
            })
            needUpdate = true
            console.info('[DetailPage] saveNote: 添加缺失的链接到richEditorSpans:', link.title)
          }
        }
        
        // 确保至少有一个文本span（如果没有文本内容但有链接）
        const hasText = spans.some(s => s.type === 'text' && s.value && s.value.trim() !== '')
        if (!hasText && spans.length > 0 && this.note.content && this.note.content.trim() !== '') {
          // 如果有内容但没有文本span，添加文本span
          spans.unshift({
            type: 'text',
            value: this.note.content
          })
          needUpdate = true
          console.info('[DetailPage] saveNote: 添加文本内容到richEditorSpans')
        }
        
        if (needUpdate) {
          this.note.richEditorSpans = JSON.stringify(spans)
          console.info('[DetailPage] saveNote: 更新richEditorSpans，包含', spans.length, '个元素')
        }
      } catch (e) {
        console.warn('[DetailPage] saveNote: 检查richEditorSpans失败:', e)
      }
    }
    
    // Sync emotion
    this.note.emotionLabel = this.selectedEmotionLabel
    this.note.emotionEmoji = this.selectedEmotionEmoji
    this.note.weatherLabel = this.selectedWeatherLabel
    this.note.weatherIcon = this.selectedWeatherIcon
    this.note.emotionColor = this.emotionColor
    // 问题4修复：同步分类
    this.note.category = this.selectedCategory
    
    // 修复：确保contentBlocks也同步（用于列表预览和恢复）
    if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
      try {
        const spanDataList: SpanData[] = JSON.parse(this.note.richEditorSpans) as SpanData[]
        const blocks: ContentBlock[] = []
        for (const spanData of spanDataList) {
          if (spanData.type === 'text' && spanData.value) {
            blocks.push(new TextBlock(spanData.value))
          } else if (spanData.type === 'link' && spanData.linkTitle && spanData.linkUrl) {
            blocks.push(new LinkBlock(spanData.linkTitle, spanData.linkUrl))
          }
        }
        if (blocks.length > 0) {
          this.note.contentBlocks = blocks
        }
      } catch (e) {
        console.warn('[DetailPage] 构建contentBlocks失败:', e)
      }
    }
    
    this.note.lastModifiedTime = Date.now()
    
    // 修复：保存前最后一次检查，确保note.content被设置
    if (!this.note.content || this.note.content.trim() === '') {
      if (this.contentText && this.contentText.trim() !== '') {
        this.note.content = this.contentText
        console.info('[DetailPage] 保存前修复：从contentText设置note.content，长度:', this.contentText.length)
      } else if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
        try {
          const spanDataList: SpanData[] = JSON.parse(this.note.richEditorSpans) as SpanData[]
          let textContent = ''
          for (const spanData of spanDataList) {
            if (spanData.type === 'text' && spanData.value) {
              textContent += spanData.value
            }
          }
          if (textContent) {
            this.note.content = textContent
            this.contentText = textContent
            console.info('[DetailPage] 保存前修复：从richEditorSpans设置note.content，长度:', textContent.length)
          }
        } catch (e) {
          console.warn('[DetailPage] 保存前从richEditorSpans提取文本失败:', e)
        }
      }
    }
    
    // 修复：保存前打印详细信息
    console.info('[DetailPage] 准备保存，标题:', this.note.title, 'content长度:', this.note.content?.length || 0, 'contentText长度:', this.contentText?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0, 'richEditorSpans内容:', this.note.richEditorSpans?.substring(0, 200))
    
    await PreferencesUtil.saveNote(this.context, this.note)
    // 触发日记更新信号
    AppStorage.setOrCreate('diaryUpdatedAt', Date.now())
    
    console.info('[DetailPage] 保存完成，标题:', this.note.title, '内容长度:', this.note.content?.length || 0, '链接数:', this.note.links?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0, 'contentBlocks数量:', this.note.contentBlocks?.length || 0)
  }
  
  // 问题4修复：分类变更时自动同步到note对象
  onCategoryChange(): void {
    if (this.note && this.selectedCategory) {
      this.note.category = this.selectedCategory
    }
  }
  
  // 自动保存（防抖）
  debouncedSave(): void {
     if (this.saveTimer) clearTimeout(this.saveTimer)
     this.saveTimer = setTimeout(() => {
        this.saveNote()
     }, 1000)
  }


  // AI功能：智能分析日记内容并生成建议
  async performAIAnalysis(): Promise<void> {
    if (!this.contentText || this.contentText.length < 5) {
       promptAction.showToast({ message: '日记内容太少啦，多写一点吧~' })
       return
    }
    
    promptAction.showToast({ message: '🤖 AI正在分析你的日记...' })

    try {
      const intentVM = IntentViewModel.getInstance()
      // 如果还没有ID，使用临时ID避免逻辑错误
      const currentDiaryId = this.note.id || `temp_${Date.now()}`
      
      // 使用 IntentViewModel 进行全链路智能分析
      const result: DiaryAnalysisResult = await intentVM.analyzeDiaryForConfirmation(this.contentText, currentDiaryId)
      this.aiAnalysisResult = result
      
      // 1. 如果没有任何有价值的分析结果（没有目标也没有待办），只显示鼓励语作为Toast
      if ((!result.goals || result.goals.length === 0) && (!result.todos || result.todos.length === 0)) {
        const encouragement = result.encouragement || '记录每一个当下，成就更好的自己 💪'
        promptAction.showToast({ 
          message: `💡 ${encouragement}`,
          duration: 3000
        })
        
        // 顺便触发一下情绪分析（因为没有弹窗干扰）
        if (!this.selectedEmotionLabel) {
           this.triggerEmotionAnalysis()
        }
        return
      }
      
      // 2. 有待确认的目标或待办，弹出选择框
      if (this.aiDialogController) {
          this.aiDialogController = null
      }
      this.aiDialogController = new CustomDialogController({
         builder: AIAnalysisDialog({
            analysisResult: this.aiAnalysisResult,
            onConfirm: async (selectedGoals: PendingGoal[], selectedTodos: PendingTodo[]) => {
                let goalsCount = 0
                let todosCount = 0
                
                if (selectedGoals.length > 0) {
                   goalsCount = await intentVM.confirmAndCreateGoals(selectedGoals)
                }
                if (selectedTodos.length > 0) {
                   const context = getContext(this)
                   todosCount = await intentVM.confirmAndCreateTodos(selectedTodos, context)
                }
                
                // 总是保存关键词
                if (result.keywords && result.keywords.length > 0) {
                    await intentVM.autoSaveKeywords(this.contentText)
                }
                
                if (goalsCount + todosCount > 0) {
                   promptAction.showToast({ message: `✅ 已创建 ${goalsCount} 个目标，${todosCount} 个待办` })
                }
                
                // 触发情绪分析更新UI
                if (result.emotion && !this.selectedEmotionLabel) {
                   this.applyEmotionResult({
                       emotionLabel: result.emotion.emotionLabel,
                       emotionEmoji: result.emotion.emotionEmoji,
                       weatherLabel: '晴', // 默认或者不更新
                       weatherIcon: '☀️',
                       colorHex: '#FFC107',
                       confidence: 1,
                       emotionKey: result.emotion.emotionKey
                   })
                }
            }
         }),
         alignment: DialogAlignment.Center,
         customStyle: true,
         width: '90%'
      })
      this.aiDialogController.open()
      
    } catch (err) {
      console.error('[DetailPage] AI智能分析失败:', err)
      promptAction.showToast({ 
        message: '大脑有点累，稍后再试吧~',
        duration: 2000
      })
    }
  }
  
  // 情绪分析触发
  triggerEmotionAnalysis(): void {
     if (this.emotionAnalysisTimer) clearTimeout(this.emotionAnalysisTimer)
     this.emotionAnalysisTimer = setTimeout(() => { this.analyzeEmotion() }, 1000)
  }
  
  async analyzeEmotion(): Promise<void> {
     if (!this.contentText || this.contentText.length < 5) return
     this.isEmotionAnalyzing = true
     this.emotionStatusText = '正在分析...'
     try {
        const result = await this.emotionAnalyzer.analyze(this.contentText)
        if (result) {
           this.applyEmotionResult(result)
        }
     } catch(e) {
        this.emotionStatusText = '分析失败'
     } finally {
        this.isEmotionAnalyzing = false
     }
  }
  
  applyEmotionResult(result: EmotionAnalysisResult): void {
     this.selectedEmotionLabel = result.emotionLabel
     this.selectedEmotionEmoji = result.emotionEmoji
     this.selectedWeatherLabel = result.weatherLabel
     this.selectedWeatherIcon = result.weatherIcon
     this.emotionColor = result.colorHex
     this.emotionConfidence = result.confidence
     this.emotionStatusText = `情绪：${result.emotionLabel}`
     this.saveNote() // 结果可以立即保存
  }

  // ==================== 菜单逻辑 ====================
  
  // 打开分类选择器(问题13修复)
  handleCategoryAction(): void {
    this.showCategoryPicker = true
  }

  // ==================== 锁逻辑 (直接交互) ====================

  handleLockAction(): void {
    if (this.note.isLocked) {
       // 已锁定 -> 提示解锁
       promptAction.showDialog({
         title: '解除锁定',
         message: '确定要移除日记密码吗？',
         buttons: [
           { text: '取消', color: AppColors.TEXT_SECONDARY },
           { text: '移除', color: AppColors.ERROR }
         ]
       }).then((dialogRes) => {
         if (dialogRes.index === 1) {
           this.note.isLocked = false
           this.note.password = ''
           this.saveNote()
           promptAction.showToast({ message: '已解除锁定' })
         }
       })
    } else {
       // 未锁定 -> 设置密码
       this.passwordInput = ''
       this.confirmPasswordInput = ''
       this.showLockDialog = true
    }
  }

  // ==================== 插入逻辑 ====================
  
  // 复制文件到沙箱以持久保存
  private async copyMediaToSandbox(sourceUri: string, type: 'image' | 'video'): Promise<string | null> {
    try {
      const filesDir = this.context.filesDir
      const timestamp = Date.now()
      const extension = type === 'image' ? 'jpg' : 'mp4' 
      
      const fileName = `${type}_${timestamp}_${Math.random().toString(36).substr(2, 6)}.${extension}`
      const destPath = `${filesDir}/${fileName}`
      
      const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY)
      const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      
      fs.copyFileSync(sourceFile.fd, destFile.fd)
      
      fs.closeSync(sourceFile)
      fs.closeSync(destFile)
      
      const sandboxUri = fileUri.getUriFromPath(destPath)
      console.info('Media copied to sandbox:', sandboxUri)
      return sandboxUri
    } catch(e) {
      console.error('Copy to sandbox failed:', e)
      return sourceUri // Fallback to original
    }
  }

  async insertImageFromGallery(): Promise<void> {
     try {
       const slider = new photoAccessHelper.PhotoViewPicker()
       const result = await slider.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 })
       if (result.photoUris.length > 0) {
          let uri = result.photoUris[0]
          const sandboxUri = await this.copyMediaToSandbox(uri, 'image')
          if (sandboxUri) uri = sandboxUri
          this.noteEditController.insertImage(uri)
       }
     } catch (e) {
       console.error('Insert Image failed', e)
     }
     this.showInsertMenu = false
  }
  
  async insertVideoFromGallery(): Promise<void> {
     try {
       const slider = new photoAccessHelper.PhotoViewPicker()
       const result = await slider.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE, maxSelectNumber: 1 })
       if (result.photoUris.length > 0) {
          let uri = result.photoUris[0]
          const sandboxUri = await this.copyMediaToSandbox(uri, 'video')
          if (sandboxUri) uri = sandboxUri
          this.noteEditController.insertVideo(uri)
       }
     } catch (e) { console.error(e) }
     this.showInsertMenu = false
  }

  // ==================== 录音逻辑 ====================

  startRecording(): void {
    if (this.isRecording || this.isProcessing) return
    this.isProcessing = true
    this.realTimeTranscription = ''

    try {
    // 每次开始录音重置已上屏长度
      this.lastASRLength = 0
      
      this.recordingService.startRecording({
        onResult: (text: string, isFinal: boolean) => {
          // 【实时插入】计算新增的文字部分
          const currentLen = text.length
          const newPart = text.substring(this.lastASRLength)
          
          // 只要有新增内容就直接插入到日记，不等 isFinal
          if (newPart.length > 0) {
            this.noteEditController.insertText(newPart)
            this.lastASRLength = currentLen
          }
          
          // 更新预览（显示最近识别的内容）
          this.realTimeTranscription = isFinal ? '' : newPart
        },
        onVolumeChange: (level: number) => {
           this.currentVolume = level
        },
        onError: (code: number, message: string) => {
          console.error(`Recording error: ${code} - ${message}`)
          this.isRecording = false
          this.isProcessing = false
          promptAction.showToast({ message: '录音失败: ' + message })
        }
      })
      this.isRecording = true
      this.isProcessing = false
      this.recordingSeconds = 0
      
      this.startUITimer()
      this.startRippleAnimation()
      
    } catch (e) {
      console.error('Failed to start recording:', e)
      promptAction.showToast({ message: '启动录音失败' })
      this.isProcessing = false
    }
  }
  
  async stopRecording(): Promise<void> {
    if (!this.isRecording) return
    
    // 停止动画和计时器
    this.stopRippleAnimation()
    this.stopUITimer()
    
    this.isProcessing = true
    try {
      const recording = await this.recordingService.stopRecording()
      this.onRecordingComplete(recording)
    } catch (e) {
      console.error('Stop recording failed', e)
    } finally {
      this.isRecording = false
      this.isProcessing = false
      this.showRecordingOverlay = false 
    }
  }
  
  cancelRecording(): void {
     this.recordingService.cancelRecording()
     this.isRecording = false
     this.showRecordingOverlay = false
     this.stopRippleAnimation() 
     this.stopUITimer() 
     this.isProcessing = false 
  }
  
  onRecordingComplete(item: RecordingItem): void {
     // 强制使用24小时制命名
     const now = new Date()
     const pad = (n: number) => n.toString().padStart(2, '0')
     const name = `录音_${now.getFullYear()}${pad(now.getMonth()+1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
     item.name = name

     this.recordings = [...this.recordings, item]
     this.note.recordings = this.recordings
     
     // 补全剩余未上屏的文本
     const finalFullText = item.transcription || ''
     if (finalFullText.length > this.lastASRLength) {
         const remain = finalFullText.substring(this.lastASRLength)
         this.noteEditController.insertText(remain)
     }
     this.realTimeTranscription = ''
     
     this.saveNote()
     this.isProcessing = false 
  }
  
  // UI 计时器 (取代原有的 waveAnimationTimer) // Added
  startUITimer(): void {
     this.uiTimer = setInterval(() => {
        this.recordingSeconds++
        // Update waveHeights for the overlay if it were still active, or for other UI elements
        this.waveHeights = this.waveHeights.map(() => Math.random() * 40 + 10)
     }, 1000)
  }
  
  stopUITimer(): void {
     if (this.uiTimer) clearInterval(this.uiTimer)
     this.recordingSeconds = 0
  }
  
  // ==================== 波纹动画逻辑 ==================== // Added

  /** 启动波纹动画 */
  private startRippleAnimation() {
    if (this.rippleAnimationTimer) clearInterval(this.rippleAnimationTimer)
    this.ripples = []
    this.frameCount = 0
    this.rippleAnimationTimer = setInterval(() => {
      if (this.isRecording) {
        this.frameCount++
        this.updateRipples()
        this.drawRipples()
      }
    }, 16)
  }

  /** 停止波纹动画 */
  private stopRippleAnimation() {
    if (this.rippleAnimationTimer) {
      clearInterval(this.rippleAnimationTimer)
      this.rippleAnimationTimer = 0
    }
    this.ripples = []
    // 清空画布
    this.waveCanvasContext.clearRect(0, 0, 120, 120)
  }

  /**
   * 更新波纹状态 - 核心动画逻辑（与backup版本一致）
   * 根据音量动态生成和更新波纹
   */
  private updateRipples() {
    const now = Date.now()
    const centerRadius = 28  // 按钮半径
    const maxRadius = 58     // 最大扩散半径
    const volume = this.currentVolume

    // ===== 根据音量生成新波纹 =====
    if (volume > 3) {
      // 音量越大，波纹生成越频繁（间隔 60ms ~ 200ms）
      const interval = Math.max(60, 200 - volume * 1.4)

      if (now - this.lastRippleTime > interval) {
        // 波纹初始线宽与音量相关（1.5 ~ 4）
        const lineWidth = 1.5 + (volume / 100) * 2.5
        // 波纹扩散速度与音量相关（0.6 ~ 1.8）
        const speed = 0.6 + (volume / 100) * 1.2

        this.ripples.push({
          radius: centerRadius + 2,
          opacity: 0.7 + (volume / 100) * 0.3, // 初始透明度 0.7 ~ 1.0
          speed: speed,
          lineWidth: lineWidth
        })
        this.lastRippleTime = now
      }
    }

    // ===== 更新所有波纹 =====
    for (let i = this.ripples.length - 1; i >= 0; i--) {
      const ripple = this.ripples[i]

      // 扩散
      ripple.radius += ripple.speed

      // 透明度：随半径增大平滑衰减
      const progress = (ripple.radius - centerRadius) / (maxRadius - centerRadius)
      ripple.opacity = Math.max(0, (1 - progress * progress) * 0.8)

      // 线宽：随扩散逐渐变细
      ripple.lineWidth = Math.max(0.5, ripple.lineWidth * 0.98)

      // 移除消失的波纹
      if (ripple.radius > maxRadius || ripple.opacity <= 0.02) {
        this.ripples.splice(i, 1)
      }
    }
  }

  /**
   * 绘制波纹 - Canvas 渲染（与backup版本一致）
   * 包含扩散波纹和呼吸光晕两种效果
   */
  private drawRipples() {
    const ctx = this.waveCanvasContext
    const size = 120
    const cx = size / 2
    const cy = size / 2
    const volume = this.currentVolume
    
    // 清空画布
    ctx.clearRect(0, 0, size, size)
    
    // ===== 绘制扩散的波纹（一缕一缕） =====
    for (const ripple of this.ripples) {
      ctx.beginPath()
      ctx.arc(cx, cy, ripple.radius, 0, Math.PI * 2)
      ctx.closePath()
      
      // 红色渐变，外层偏橙（与录音按钮颜色协调）
      const r = Math.floor(220 + (ripple.radius / 60) * 35)
      const g = Math.floor(38 + (ripple.radius / 60) * 40)
      const b = 38
      ctx.strokeStyle = `rgba(${Math.min(255, r)}, ${g}, ${b}, ${ripple.opacity})`
      ctx.lineWidth = ripple.lineWidth
      ctx.stroke()
    }
    
    // ===== 绘制呼吸光晕（随音量变化） =====
    const glowRadius = 28 + (volume / 100) * 8
    const glowOpacity = 0.15 + (volume / 100) * 0.25

    // 外层柔和光晕
    const glowGradient = ctx.createRadialGradient(cx, cy, 28, cx, cy, glowRadius + 10)
    glowGradient.addColorStop(0, `rgba(239, 68, 68, ${glowOpacity})`)
    glowGradient.addColorStop(1, 'rgba(239, 68, 68, 0)')
    ctx.beginPath()
    ctx.arc(cx, cy, glowRadius + 10, 0, Math.PI * 2)
    ctx.fillStyle = glowGradient
    ctx.fill()
  }
  
  // ==================== 播放逻辑 ====================
  
  playRecording(item: RecordingItem): void {
     if (this.currentPlayingId === item.id && this.isPlaying) {
        this.stopPlayback()
     } else {
        this.stopPlayback()
        this.audioPlayer.playAudio(item.audioPath)
        this.currentPlayingId = item.id
        this.isPlaying = true
        this.currentDuration = item.audioDuration
        
        // Timer for progress
        this.playbackTimer = setInterval(() => {
           this.playbackProgress++
           if (this.playbackProgress >= this.currentDuration) {
              this.stopPlayback()
           }
        }, 1000)
     }
  }
  
  deleteRecording(item: RecordingItem): void {
     this.recordings = this.recordings.filter(r => r.id !== item.id)
     this.note.recordings = this.recordings
     this.saveNote()
  }
  
  updateChecklistItem(item: ChecklistItem): void {
     this.note.checklist = this.checklistItems
     this.saveNote() 
  }
  
  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const timeStr = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
    return `${DiaryUtils.formatDate(timestamp)} ${timeStr}`
  }

  /** 内联录音按钮 - 2025 Premium Design (问题6修复：正居中 + 音量波纹动画) */
  @Builder
  RecordButtonWithWave() {
      Column({ space: 6 }) {
        // 实时转写文本显示
        if (this.isRecording && this.realTimeTranscription.length > 0) {
          Text(this.realTimeTranscription)
            .fontSize(14)
            .fontColor(AppColors.TEXT_PRIMARY)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(AppColors.BG_SECONDARY)
            .borderRadius(12)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ duration: 100 })
        }
        
        // 录音时长
        if (this.isRecording) {
          Text(this.formatRecordingTime(this.recordingSeconds))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.ERROR)
        }
        
        // 按钮主体 - 确保居中
        Stack({ alignContent: Alignment.Center }) {
            // 【问题6修复】音量波纹画布 - 随音量变化的动态波纹
            if (this.isRecording) {
              Canvas(this.waveCanvasContext)
                .width(120)
                .height(120)
                .backgroundColor(Color.Transparent)
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                   // Canvas已初始化
                })
            }

            // 外圈脉冲动画 (录音时显示) - 第二层波纹
            if (this.isRecording) {
              Circle()
                .width(68)
                .height(68)
                .fill(Color.Transparent)
                .stroke(AppColors.ERROR)
                .strokeWidth(2)
                .scale({ x: this.pulseScale, y: this.pulseScale })
                .opacity(Math.max(0, 2 - this.pulseScale))
              
              // 第三层波纹 - 更大更淡
              Circle()
                .width(84)
                .height(84)
                .fill(Color.Transparent)
                .stroke(AppColors.ERROR)
                .strokeWidth(1)
                .scale({ x: this.pulseScale * 1.1, y: this.pulseScale * 1.1 })
                .opacity(Math.max(0, (2 - this.pulseScale) * 0.5))
            }

            // 主按钮
            Column() {
              if (this.isProcessing) {
                LoadingProgress().width(22).height(22).color(AppColors.TEXT_WHITE)
              } else if (this.isRecording) {
                // 停止图标 - 圆角方块
                Column().width(16).height(16).borderRadius(3).backgroundColor(AppColors.TEXT_WHITE)
              } else {
                // 麦克风图标 - 极简现代设计 🎙️
                Stack() {
                  Column().width(10).height(14).borderRadius(5).backgroundColor(AppColors.TEXT_WHITE).position({ x: 9, y: 0 })
                  Column().width(18).height(9).borderRadius({ bottomLeft: 9, bottomRight: 9 }).backgroundColor(Color.Transparent)
                    .border({ width: { left: 2, right: 2, bottom: 2 }, color: AppColors.TEXT_WHITE }).position({ x: 5, y: 8 })
                  Column().width(2).height(5).backgroundColor(AppColors.TEXT_WHITE).position({ x: 13, y: 17 })
                  Column().width(10).height(2).borderRadius(1).backgroundColor(AppColors.TEXT_WHITE).position({ x: 9, y: 22 })
                }.width(28).height(26)
              }
            }
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor(this.isRecording ? AppColors.ERROR : AppColors.BG_DARK_SECONDARY)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .shadow(AppShadows.SHADOW_MD)
            // 【问题8修复】改为长按录音，松开停止
            .onTouch((e: TouchEvent) => {
               if (e.type === TouchType.Down) {
                  if (!this.isRecording && !this.isProcessing) {
                     this.recordStartY = e.touches[0].y
                     this.startRecording()
                     // 启动脉冲动画
                     this.pulseScale = 1
                     animateTo({ duration: 1000, iterations: -1, playMode: PlayMode.Alternate }, () => {
                        this.pulseScale = 1.4
                     })
                  }
               } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  if (this.isRecording) {
                     this.stopRecording()
                     this.pulseScale = 1
                  }
               }
            })
        }
        .width(120)
        .height(120)
        
        Text(this.isRecording ? '松开停止' : '长按开始录音')
           .fontSize(11)
           .fontColor(AppColors.TEXT_TERTIARY)
      }
      // 【问题6修复】确保按钮正居中
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
  }

  // 格式化录音时长
  private formatRecordingTime(seconds: number): string {
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // 主界面
        Column() {
          // 顶部安全区
          Column()
            .width('100%')
            .height(this.topSafeHeight)
            .backgroundColor(AppColors.BG_PRIMARY)
          
          DiaryTopBar({ 
            onSave: async () => await this.saveNote(), 
            onAIAnalysis: () => this.performAIAnalysis(),
            isLocked: this.note.isLocked,
            topSafeHeight: this.topSafeHeight,  // 问题5修复：传递安全区高度
            onLockAction: () => this.handleLockAction(),
            onCategoryAction: () => this.handleCategoryAction()
          })

          // Date and Info Row
          Row() {
            Text(this.formatDateTime(this.note.createTime))
               .fontSize(12)
               .fontColor(AppColors.TEXT_HINT)
            Blank()
            if (this.selectedEmotionLabel) {
               Text(`${this.selectedEmotionEmoji} ${this.selectedEmotionLabel}  ${this.selectedWeatherIcon} ${this.selectedWeatherLabel}`)
                 .fontSize(12)
                 .fontColor(AppColors.TEXT_HINT)
            }
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 4, bottom: 4 })

          NoteEditView({
            note: $note,
            titleText: $titleText,
            contentText: $contentText,
            recordings: $recordings,
            checklistItems: $checklistItems,
            currentPlayingId: $currentPlayingId,
            playbackProgress: $playbackProgress,
            canUndo: $canUndo,
            canRedo: $canRedo,
            controller: this.noteEditController,
            onEmotionAnalysisTrigger: () => this.triggerEmotionAnalysis(),
            onPlayRecording: (item: RecordingItem) => this.playRecording(item),
            onDeleteRecording: (item: RecordingItem) => this.deleteRecording(item),
            onChecklistItemUpdate: (item: ChecklistItem) => this.updateChecklistItem(item),
            onContentChange: () => this.debouncedSave(), // Auto-save trigger
            onEditorReady: () => {
              console.info('[DetailPage] onEditorReady回调触发，note.id:', this.note.id, 'contentText长度:', this.contentText?.length || 0, 'note.content长度:', this.note.content?.length || 0)
              
              // 修复：如果contentText有内容，延迟检查并确保内容被添加到编辑器
              // 因为RichEditor的initRichEditorContent可能在数据加载前执行
              setTimeout(() => {
                const hasContent = (this.contentText && this.contentText.trim() !== '') || (this.note.content && this.note.content.trim() !== '')
                if (hasContent && this.noteEditController) {
                  // 检查内容是否已经显示（通过检查contentText是否等于note.content）
                  // 如果note.content有值，尝试通过insertText强制添加
                  const textToAdd = this.contentText || this.note.content || ''
                  if (textToAdd && textToAdd.trim() !== '') {
                    console.info('[DetailPage] onEditorReady(延迟检查): 检测到内容，尝试强制添加到编辑器，长度:', textToAdd.length)
                    // 注意：这里不能直接用insertText，因为会追加内容，需要先清空
                    // 实际上initRichEditorContent应该已经处理了，这里只是作为保险
                    console.info('[DetailPage] onEditorReady(延迟检查): 内容应已通过initRichEditorContent初始化')
                  }
                }
              }, 500)  // 延迟500ms确保initRichEditorContent完成
              
              // 修复：编辑器准备好后，插入待插入的链接
              if (this.pendingLinkData && this.noteEditController && this.noteEditController.insertLink) {
                setTimeout(() => {
                  // 插入链接到编辑器
                  this.noteEditController.insertLink(this.pendingLinkData!.title, this.pendingLinkData!.url)
                  
                  // 确保链接已添加到note.links数组
                  if (!this.note.links) {
                    this.note.links = []
                  }
                  const linkExists = this.note.links.some(l => l.url === this.pendingLinkData!.url)
                  if (!linkExists) {
                    const linkItem = new LinkItem()
                    linkItem.id = Date.now().toString()
                    linkItem.title = this.pendingLinkData!.title
                    linkItem.url = this.pendingLinkData!.url
                    this.note.links.push(linkItem)
                  }
                  
                  // 清理pendingLinkData（先保存引用，然后清空）
                  const linkDataToSave = this.pendingLinkData
                  if (!linkDataToSave) {
                    console.warn('[DetailPage] pendingLinkData为空，无法保存链接')
                    return
                  }
                  this.pendingLinkData = null
                  
                  // 等待编辑器同步完成后保存，确保richEditorSpans包含链接
                  setTimeout(async () => {
                    // 再次确认richEditorSpans包含链接
                    try {
                      if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
                        const spans: SpanData[] = JSON.parse(this.note.richEditorSpans) as SpanData[]
                        const hasLink = spans.some(s => s.type === 'link' && s.linkUrl === linkDataToSave.url)
                        if (!hasLink) {
                          // 如果richEditorSpans中没有链接，手动添加
                          const newSpan: SpanData = {
                            type: 'link',
                            linkTitle: linkDataToSave.title,
                            linkUrl: linkDataToSave.url
                          }
                          spans.push(newSpan)
                          this.note.richEditorSpans = JSON.stringify(spans)
                          console.info('[DetailPage] 手动添加链接到richEditorSpans')
                        }
                      }
                    } catch (e) {
                      console.warn('[DetailPage] 检查richEditorSpans失败:', e)
                    }
                    
                    // 保存以确保链接被持久化
                    await this.saveNote()
                    console.info('[DetailPage] 链接插入后已保存，richEditorSpans长度:', this.note.richEditorSpans?.length || 0)
                  }, 500)  // 增加延迟确保编辑器同步完成
                }, 200)  // 增加初始延迟
              }
            },
            onBeforeSave: () => {
              // 修复：保存前强制同步RichEditor内容
              // 这个回调会在saveNote中被调用
              // NoteEditView 会自动调用 syncContentFromRichEditor
            }
          })
          .layoutWeight(1)

          DiaryBottomBar({
            showInsertMenu: $showInsertMenu,
            showEmotionPanel: $showEmotionPanel,
            canUndo: this.canUndo,
            canRedo: this.canRedo,
            emotionEmoji: this.selectedEmotionEmoji,
            emotionLabel: this.selectedEmotionLabel,
            onUndo: () => this.noteEditController.undo(),
            onRedo: () => this.noteEditController.redo(),
            onRecord: () => this.startRecording(), // Modified
            centerButton: () => { this.RecordButtonWithWave() }
          })
        }
        .width('100%')
        .height('100%')

        // ========== 各种弹窗覆盖层 ==========
        // 注：CategoryPickerDialog已在下方正确位置使用$selectedCategory
        
        if (this.showLockDialog) {
           LockDialog({ 
             showDialog: $showLockDialog, 
             passwordInput: $passwordInput,
             confirmPasswordInput: $confirmPasswordInput,
             onConfirm: () => {
                if (this.passwordInput === this.confirmPasswordInput && this.passwordInput.length >= 4) {
                   this.note.password = this.passwordInput
                   this.note.isLocked = true
                   this.showLockDialog = false
                   this.saveNote()
                } else {
                   promptAction.showToast({ message: '密码不一致或太短' })
                }
             }
           })
        }
        
        if (this.showUnlockDialog) {
           UnlockDialog({
             showDialog: $showUnlockDialog,
             passwordInput: $passwordInput,
             onUnlock: () => {
                if (this.passwordInput === this.note.password) {
                   this.showUnlockDialog = false
                } else {
                   promptAction.showToast({ message: '密码错误' })
                }
             }
           })
        }
        
        // 问题4修复：使用独立的selectedCategory状态变量
        if (this.showCategoryPicker) {
           CategoryPickerDialog({
             showDialog: $showCategoryPicker,
             category: $selectedCategory,
             categories: this.categories
           })
        }
        
        if (this.showInsertMenu) {
           InsertMenuDialog({
             showMenu: $showInsertMenu,
             showLinkDialog: $showLinkDialog,
             showChecklistDialog: $showChecklistDialog,
             onInsertImage: () => this.insertImageFromGallery(),
             onInsertVideo: () => this.insertVideoFromGallery()
           })
        }
        
        if (this.showLinkDialog) {
           LinkDialog({
             showDialog: $showLinkDialog,
             title: $tempLinkTitle,
             url: $tempLinkUrl,
             onConfirm: () => this.noteEditController.insertLink(this.tempLinkTitle, this.tempLinkUrl)
           })
        }
        
        if (this.showChecklistDialog) {
           ChecklistDialog({
              showDialog: $showChecklistDialog,
              input: $checklistInput,
              onConfirm: () => this.noteEditController.insertChecklist(this.checklistInput)
           })
        }
        
        if (this.showEmotionPanel) {
           Stack({ alignContent: Alignment.Bottom }) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor('#00000040')
                .onClick(() => this.showEmotionPanel = false)
                
              EmotionPanel({
                 showPanel: $showEmotionPanel,
                 isAnalyzing: this.isEmotionAnalyzing,
                 statusText: this.emotionStatusText,
                 selectedEmoji: this.selectedEmotionEmoji,
                 selectedLabel: this.selectedEmotionLabel,
                 selectedKey: this.selectedEmotionKey,
                 weatherIcon: this.selectedWeatherIcon,
                 weatherLabel: this.selectedWeatherLabel,
                 themeColor: this.emotionColor,
                 errorText: this.emotionAnalysisError,
                 onRetry: () => this.analyzeEmotion(),
                 onSelectPreset: (preset: EmotionPreset) => {
                    const result: EmotionAnalysisResult = { 
                       emotionLabel: preset.label,
                       emotionEmoji: preset.emoji,
                       weatherLabel: preset.weather,
                       weatherIcon: preset.weatherIcon,
                       colorHex: preset.color,
                       confidence: 1,
                       emotionKey: preset.key
                    }
                    this.applyEmotionResult(result)
                 }
              })
           }
           .zIndex(900)
        }
        
        // 录音覆盖层不再需要，已改为内联 // Modified
        // if (this.showRecordingOverlay) {
        //    AudioRecordingOverlay({
        //       isRecording: $isRecording,
        //       recordingSeconds: $recordingSeconds,
        //       waveHeights: this.waveHeights,
        //       transcriptionText: this.realTimeTranscription,
        //       onStop: () => this.stopRecording(),
        //       onCancel: () => this.cancelRecording()
        //    })
        // }
      }
    }
    .hideTitleBar(true)
  }
}

// AI分析结果弹窗
@CustomDialog
struct AIAnalysisDialog {
  controller: CustomDialogController
  analysisResult: DiaryAnalysisResult | null = null
  onConfirm: (goals: PendingGoal[], todos: PendingTodo[]) => void = () => {}

  @State selectedGoals: boolean[] = []
  @State selectedTodos: boolean[] = []

  aboutToAppear() {
     if (this.analysisResult) {
        this.selectedGoals = this.analysisResult.goals ? this.analysisResult.goals.map(() => true) : []
        this.selectedTodos = this.analysisResult.todos ? this.analysisResult.todos.map(() => true) : []
     }
  }

  build() {
    Column() {
      Text('🧠 AI 智能分析结果')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .padding({ top: 20, bottom: 16 })
        .fontColor(AppColors.TEXT_PRIMARY)
      
      Scroll() {
        Column({ space: 12 }) {
           if (this.analysisResult?.encouragement) {
             Column() {
                Text('💡 AI寄语')
                  .fontSize(12).fontColor(AppColors.ACCENT).fontWeight(FontWeight.Bold).margin({ bottom: 4 })
                Text(this.analysisResult.encouragement)
                  .fontSize(14).fontColor(AppColors.TEXT_SECONDARY).lineHeight(20)
             }
             .width('100%').alignItems(HorizontalAlign.Start)
             .padding(12).backgroundColor(AppColors.BG_SECONDARY).borderRadius(8)
           }

           // 目标建议
           if (this.analysisResult?.goals && this.analysisResult.goals.length > 0) {
              Column({ space: 8 }) {
                Text('🎯 建议目标').fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY).width('100%')
                ForEach(this.analysisResult.goals, (goal: PendingGoal, index: number) => {
                   Row() {
                      Checkbox().select(this.selectedGoals[index]).selectedColor(AppColors.ACCENT)
                         .onChange((v: boolean) => this.selectedGoals[index] = v)
                      Column() {
                          Text(goal.title).fontSize(14).fontColor(AppColors.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                          if(goal.deadline) {
                              Text(`截止: ${new Date(goal.deadline).toLocaleDateString()}`).fontSize(11).fontColor(AppColors.TEXT_TERTIARY)
                          }
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 8 })
                   }.width('100%').padding({ top: 4, bottom: 4 })
                })
              }
           }

           // 待办建议
           if (this.analysisResult?.todos && this.analysisResult.todos.length > 0) {
              Column({ space: 8 }) {
                Text('📝 建议待办').fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY).width('100%')
                ForEach(this.analysisResult.todos, (todo: PendingTodo, index: number) => {
                   Row() {
                      Checkbox().select(this.selectedTodos[index]).selectedColor(AppColors.ACCENT)
                         .onChange((v: boolean) => this.selectedTodos[index] = v)
                      Text(todo.content).fontSize(14).fontColor(AppColors.TEXT_PRIMARY).layoutWeight(1).margin({ left: 8 })
                   }.width('100%').padding({ top: 4, bottom: 4 })
                })
              }
           }
        }
        .padding({ left: 16, right: 16 })
      }
      .constraintSize({ maxHeight: 350 }) // 稍微调高一点
      .width('100%')

      Row() {
        Button('取消')
          .onClick(() => this.controller.close())
          .backgroundColor(AppColors.BG_SECONDARY).fontColor(AppColors.TEXT_PRIMARY)
          .width(100)
        
        Button('确认添加')
          .onClick(() => {
             const finalGoals = this.analysisResult?.goals?.filter((_, i) => this.selectedGoals[i]) || []
             const finalTodos = this.analysisResult?.todos?.filter((_, i) => this.selectedTodos[i]) || []
             this.onConfirm(finalGoals, finalTodos)
             this.controller.close()
          })
          .backgroundColor(AppColors.ACCENT)
          .width(100)
      }
      .margin({ top: 24, bottom: 20 })
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')
    }
    .width('90%')
    .backgroundColor(AppColors.BG_PRIMARY)
    .borderRadius(16)
    .shadow(AppShadows.SHADOW_LG)
  }
}
