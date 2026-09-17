
import { NoteItem, ChecklistItem, LinkItem, ContentBlock, TextBlock, ImageBlock, VideoBlock, LinkBlock } from '../../model/NoteItem'
import { RecordingItem } from '../../model/RecordingItem'
import { AudioRecordItem } from './AudioRecordItem'
import { AppColors, AppSizes, AppShadows, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'
import { IconPaths } from '../../../common/utils/IconPaths'
import { promptAction, router } from '@kit.ArkUI'
import common from '@ohos.app.ability.common'

/** 用于保存 Span 信息的辅助类 (用于JSON序列化恢复) */
class SpanInfo {
  type: string
  value: string
  src: string
  start: number
  end: number
  linkTitle?: string
  linkUrl?: string

  constructor(type: string, value: string, src: string, start: number, end: number) {
    this.type = type
    this.value = value
    this.src = src
    this.start = start
    this.end = end
  }
}

/** Span数据接口（用于解析richEditorSpans） */
interface ParsedSpanData {
  type: string
  value?: string
  src?: string
  linkTitle?: string
  linkUrl?: string
}

/** Note 编辑器控制器，用于外部调用（如插入图片） */
export class NoteEditController {
  insertImage: (path: string) => void = () => {}
  insertVideo: (path: string) => void = () => {}
  insertLink: (title: string, url: string) => void = () => {}
  insertChecklist: (text: string) => void = () => {}
  insertText: (text: string) => void = () => {}
  undo: () => void = () => {}
  redo: () => void = () => {}
}

@Component
export struct NoteEditView {
  @Link note: NoteItem
  @Link titleText: string
  @Link contentText: string
  
  // 附件列表（与 Note 同步）
  @Link recordings: RecordingItem[]
  @Link checklistItems: ChecklistItem[]
  
  // 播放状态
  @Link currentPlayingId: string
  @Link playbackProgress: number
  
  // 撤销/重做状态通知
  @Link canUndo: boolean
  @Link canRedo: boolean
  
  // 控制器 - 由外部传入，用于调用编辑器方法（如 insertText）
  controller: NoteEditController = new NoteEditController()

  // 内部状态
  private richEditorController: RichEditorController = new RichEditorController()
  private richEditorOptions: RichEditorOptions = { controller: this.richEditorController }
  @State isRichEditorReady: boolean = false
  
  // 记录上次初始化的note ID，用于检测note对象是否变化
  private lastInitializedNoteId: string = ''
  private hasInitializedContent: boolean = false
  
  // 附件缓存（用于编辑时快速访问）
  @State imageAttachments: string[] = []
  @State videoAttachments: string[] = []
  @State linkItems: LinkItem[] = []
  
  // 图片尺寸缓存
  private imageSizeMap: Map<string, number[]> = new Map()
  
  // 历史记录栈
  private historyStack: string[] = []
  private historyIndex: number = -1
  private isUndoing: boolean = false
  
  // 防抖计时器（优化长文本性能）
  private syncDebounceTimer: number = -1
  
  // 回调
  onEmotionAnalysisTrigger: () => void = () => {}
  onPlayRecording: (item: RecordingItem) => void = () => {}
  onDeleteRecording: (item: RecordingItem) => void = () => {}
  onChecklistItemUpdate: (item: ChecklistItem) => void = () => {}
  onContentChange: () => void = () => {}
  onEditorReady: () => void = () => {}  // 修复：编辑器准备好时的回调
  onBeforeSave: () => void = () => {}  // 修复：保存前的回调，用于强制同步内容

  aboutToAppear() {
    // 初始化内部状态
    this.imageAttachments = this.note.images || []
    this.videoAttachments = this.note.videos || []
    // 修复：确保linkItems从note.links正确初始化
    this.linkItems = this.note.links ? [...this.note.links] : []
    this.checklistItems = this.note.checklist || []
    
    // 修复：如果contentText为空但note.content有内容，同步contentText
    if ((!this.contentText || this.contentText.trim() === '') && this.note.content && this.note.content.trim() !== '') {
      this.contentText = this.note.content
      console.info('[NoteEditView] aboutToAppear: 从note.content同步contentText，长度:', this.contentText.length)
    }
    
    // 修复：调试信息
    console.info('[NoteEditView] aboutToAppear，note.id:', this.note.id, 'note.content长度:', this.note.content?.length || 0, 'contentText长度:', this.contentText?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0, 'links数量:', this.linkItems.length, 'note.links数量:', this.note.links?.length || 0)
    
    // 【关键修复】在组件初始化时立即绑定控制器方法
    // 这样外部（DetailPage）就可以通过 noteEditController 调用这些方法
    this.bindControllerMethods()
  }
  
  // 修复：当note对象更新时，如果RichEditor已准备好，重新初始化内容
  aboutToUpdate() {
    // 检查note对象是否变化（通过ID判断）或者内容是否已加载
    const noteIdChanged = this.note.id && this.note.id !== this.lastInitializedNoteId
    const hasContentButNotInitialized = this.note.content && this.note.content.trim() !== '' && !this.hasInitializedContent
    const hasRichEditorSpansButNotInitialized = this.note.richEditorSpans && this.note.richEditorSpans !== '[]' && !this.hasInitializedContent
    
    if (noteIdChanged || hasContentButNotInitialized || hasRichEditorSpansButNotInitialized) {
      console.info('[NoteEditView] aboutToUpdate: 检测到note对象变化或内容需要初始化，ID:', this.note.id, 'lastInitializedNoteId:', this.lastInitializedNoteId, 'hasInitializedContent:', this.hasInitializedContent)
      
      // 更新内部状态
      this.imageAttachments = this.note.images || []
      this.videoAttachments = this.note.videos || []
      this.linkItems = this.note.links ? [...this.note.links] : []
      this.checklistItems = this.note.checklist || []
      
      // 同步contentText
      if (this.note.content && this.note.content.trim() !== '') {
        this.contentText = this.note.content
        console.info('[NoteEditView] aboutToUpdate: 同步contentText，长度:', this.contentText.length)
      }
      
      // 如果RichEditor已经准备好，重新初始化内容
      if (this.isRichEditorReady) {
        console.info('[NoteEditView] aboutToUpdate: RichEditor已准备好，准备重新初始化内容')
        setTimeout(() => {
          this.initRichEditorContent()
          this.lastInitializedNoteId = this.note.id
          this.hasInitializedContent = true
          console.info('[NoteEditView] aboutToUpdate: 内容初始化完成')
        }, 100)
      } else {
        console.info('[NoteEditView] aboutToUpdate: RichEditor尚未准备好，等待onReady')
      }
    } 

    // 绑定控制器方法（每次更新时重新绑定，确保方法可用）
    this.bindControllerMethods()
    
    // 修复：绑定保存前回调，强制同步内容
    this.onBeforeSave = (): void => {
      if (this.isRichEditorReady) {
        this.syncContentFromRichEditor()
      }
    }
  }
  
  // 【关键修复】绑定控制器方法 - 使外部能够调用编辑器功能
  private bindControllerMethods(): void {
    this.controller.insertImage = (path: string): void => { this.insertImageSpanInline(path) }
    this.controller.insertVideo = (path: string): void => {
      this.videoAttachments.push(path)
      this.addVideoBuilderSpan(path)
      this.syncContentFromRichEditor()
    }
    this.controller.insertLink = (title: string, url: string): void => {
      const link = new LinkItem()
      link.id = Date.now().toString()
      link.title = title
      link.url = url
      this.linkItems.push(link)
      this.addLinkBuilderSpan(title, url)
      this.syncContentFromRichEditor()
    }
    this.controller.insertChecklist = (text: string): void => {
      const item = new ChecklistItem()
      item.id = Date.now().toString()
      item.text = text
      item.checked = false
      
      const newList = [...this.checklistItems, item]
      this.checklistItems = newList
      this.note.checklist = newList
    }
    this.controller.insertText = (text: string): void => {
       if (this.richEditorController && text) {
          this.richEditorController.addTextSpan(text, { style: { fontColor: AppColors.TEXT_PRIMARY, fontSize: 16 } })
          this.syncContentFromRichEditor()
       }
    }
    this.controller.undo = (): void => { this.undo() }
    this.controller.redo = (): void => { this.redo() }
  }

  build() {
    Column() {
      // 标题输入
      TextInput({ text: this.titleText, placeholder: '标题' })
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .placeholderColor(AppColors.TEXT_HINT)
        .backgroundColor(Color.Transparent)
        .height(56)
        .margin({ top: 8, bottom: 8 })
        .padding({ left: 24, right: 24 })
        .onChange((value: string) => {
          this.titleText = value
          this.note.title = value
        })

      // RichEditor 编辑区
      RichEditor(this.richEditorOptions)
        .width('100%')
        .constraintSize({ minHeight: 300 })
        .padding({
          left: 24,
          right: 24,
          top: 16,
          bottom: 16
        })
        .backgroundColor(Color.Transparent)
        .placeholder('开始记录你的想法...', {
          fontColor: AppColors.TEXT_HINT,
          font: { size: 16 }
        })
        .caretColor(AppColors.ACCENT)
        .onReady(() => {
          console.info('[NoteEditView] RichEditor onReady 触发，准备初始化内容，note.id:', this.note.id, 'note.content长度:', this.note.content?.length || 0, 'contentText长度:', this.contentText?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0)
          this.isRichEditorReady = true
          
          // 修复：延迟初始化内容，确保数据已经完全加载
          // 因为onReady可能在DetailPage的loadNote完成之前触发
          // 使用轮询方式检查数据是否已加载，最多等待1秒
          let checkCount = 0
          const maxChecks = 10  // 最多检查10次，每次100ms，总共1秒
          const checkDataLoaded = () => {
            checkCount++
            const hasData = (this.note.content && this.note.content.trim() !== '') || 
                           (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') ||
                           (this.note.links && this.note.links.length > 0)
            
            if (hasData || checkCount >= maxChecks) {
              // 修复：在RichEditor ready时，再次确保数据同步
              // 因为此时note对象可能已经被DetailPage更新了
              if (this.note.links && this.note.links.length > 0 && (!this.linkItems || this.linkItems.length === 0)) {
                this.linkItems = [...this.note.links]
                console.info('[NoteEditView] onReady: 从note.links恢复linkItems，数量:', this.linkItems.length)
              }
              
              // 修复：确保contentText从note.content同步
              if ((!this.contentText || this.contentText.trim() === '') && this.note.content && this.note.content.trim() !== '') {
                this.contentText = this.note.content
                console.info('[NoteEditView] onReady: 从note.content同步contentText，长度:', this.contentText.length)
              }
              
              console.info('[NoteEditView] onReady: 开始初始化内容，note.content长度:', this.note.content?.length || 0, 'contentText长度:', this.contentText?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0)
              
              // 初始化内容
              this.initRichEditorContent()
              this.saveToHistory()
              
              // 记录已初始化
              this.lastInitializedNoteId = this.note.id
              this.hasInitializedContent = true
              
              // 修复：通知编辑器已准备好
              this.onEditorReady()
            } else {
              // 数据还未加载完成，继续等待
              setTimeout(checkDataLoaded, 100)
            }
          }
          
          // 开始检查
          setTimeout(checkDataLoaded, 100)
        })
        .onIMEInputComplete(() => {
          this.syncContentFromRichEditor()
          this.saveToHistory()
        })
        .onDidChange(() => {
           this.syncContentDebounced()
        })
        .aboutToDelete((value: RichEditorDeleteValue) => {
          this.handleBuilderSpanDelete(value)
          return true
        })
        .onDeleteComplete(() => {
          this.syncContentFromRichEditor()
          this.saveToHistory()
        })
        .onPaste(() => {
          setTimeout(() => {
             this.syncContentFromRichEditor()
             this.saveToHistory()
          }, 100)
        })

      // 录音卡片列表
      if (this.recordings.length > 0) {
        Column({ space: 8 }) {
          Text('录音')
            .fontSize(13)
            .fontColor(AppColors.TEXT_HINT)
            .padding({ left: 24, top: 16 })

          ForEach(this.recordings, (recording: RecordingItem) => {
            AudioRecordItem({
               recording: recording, 
               currentPlayingId: this.currentPlayingId,
               playbackProgress: this.playbackProgress,
               onPlay: (item) => this.onPlayRecording(item),
               onDelete: (item) => this.onDeleteRecording(item),
               onRename: (id, name) => {
                  const idx = this.recordings.findIndex(r => r.id === id)
                  if (idx !== -1) {
                     this.recordings[idx].name = name
                     this.recordings = [...this.recordings] // Trigger update
                     this.onContentChange()
                  }
               }
            })
          }, (recording: RecordingItem) => recording.id)
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
      }

      // 清单列表
      if (this.checklistItems.length > 0) {
          Column({ space: 8 }) {
            Text('清单')
              .fontSize(13)
              .fontColor(AppColors.TEXT_HINT)
              .padding({ left: 24, top: 16 })

            ForEach(this.checklistItems, (item: ChecklistItem) => {
              this.ChecklistItemCard(item)
            }, (item: ChecklistItem) => `${item.id}_${item.checked}`)
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
      }
      
      // 底部留白
      Column().height(180)
    }
  }

  // ==================== RichEditor Logic ====================

  private initRichEditorContent(): void {
    if (!this.isRichEditorReady) {
      console.warn('[NoteEditView] RichEditor未准备好，无法初始化内容')
      return
    }

    console.info('[NoteEditView] initRichEditorContent 开始，note.id:', this.note.id, 'note.content长度:', this.note.content?.length || 0, 'contentText长度:', this.contentText?.length || 0, 'richEditorSpans长度:', this.note.richEditorSpans?.length || 0, 'linkItems数量:', this.linkItems.length, 'note.links数量:', this.note.links?.length || 0)
    
    // 修复：先清空编辑器
    try {
      this.richEditorController.deleteSpans()
      console.info('[NoteEditView] deleteSpans 执行完成')
    } catch (e) {
      console.error('[NoteEditView] deleteSpans 失败:', e)
    }
    
    // 尝试从 richEditorSpans 恢复
    if (this.note.richEditorSpans && this.note.richEditorSpans !== '[]') {
      try {
        const spanDataList: ParsedSpanData[] = JSON.parse(this.note.richEditorSpans) as ParsedSpanData[]
        console.info('[NoteEditView] 开始从richEditorSpans恢复内容，包含', spanDataList.length, '个元素')
        let hasContent = false
        let extractedText = ''
        // 修复：在恢复链接时，同时添加到linkItems数组，确保后续syncContentFromRichEditor能正确工作
        for (const spanData of spanDataList) {
           if (spanData.type === 'text' && spanData.value) {
             this.richEditorController.addTextSpan(spanData.value, { style: { fontColor: AppColors.TEXT_PRIMARY, fontSize: 16 } })
             extractedText += spanData.value
             hasContent = true
           } else if (spanData.type === 'image' && spanData.src) {
             const size = this.imageSizeMap.get(spanData.src) || [120, 90]
             this.richEditorController.addImageSpan(spanData.src, {
               imageStyle: { size: [`${size[0]}vp`, `${size[1]}vp`], verticalAlign: ImageSpanAlignment.CENTER, objectFit: ImageFit.Cover }
             })
             hasContent = true
           } else if (spanData.type === 'video' && spanData.src) {
             this.addVideoBuilderSpan(spanData.src)
             hasContent = true
           } else if (spanData.type === 'link' && spanData.linkTitle && spanData.linkUrl) {
             // 修复：确保链接也被添加到linkItems数组
             const linkExists = this.linkItems.some(l => l.url === spanData.linkUrl)
             if (!linkExists) {
               const linkItem = new LinkItem()
               linkItem.id = Date.now().toString() + Math.random().toString(36).substring(2, 8)
               linkItem.title = spanData.linkTitle
               linkItem.url = spanData.linkUrl
               this.linkItems.push(linkItem)
               console.info('[NoteEditView] 从richEditorSpans恢复链接并添加到linkItems:', spanData.linkTitle)
             }
             // 添加到编辑器
             this.addLinkBuilderSpan(spanData.linkTitle, spanData.linkUrl)
             hasContent = true
           }
        }
        // 修复：如果从richEditorSpans恢复了内容，同步到contentText和note.content
        if (hasContent) {
          // 修复：如果没有从richEditorSpans提取到文本，但note.content有内容，也要显示文本
          if (extractedText) {
            this.contentText = extractedText
            this.note.content = extractedText
            console.info('[NoteEditView] 从richEditorSpans恢复内容成功，文本长度:', extractedText.length)
          } else {
            // 如果没有文本但note.content有内容，使用note.content作为文本内容
            const textFromNote = this.note.content || this.contentText || ''
            if (textFromNote && textFromNote.trim() !== '') {
              this.richEditorController.addTextSpan(textFromNote, { style: { fontColor: AppColors.TEXT_PRIMARY, fontSize: 16 } })
              this.contentText = textFromNote
              this.note.content = textFromNote
              console.info('[NoteEditView] 从richEditorSpans恢复链接，从note.content恢复文本，长度:', textFromNote.length)
            } else {
              console.info('[NoteEditView] 从richEditorSpans恢复内容成功（无文本，只有媒体/链接）')
            }
          }
          // 修复：确保恢复的链接也同步到note.links数组
          if (this.linkItems.length > 0) {
            this.note.links = [...this.linkItems]
            console.info('[NoteEditView] 已同步', this.linkItems.length, '个链接到note.links')
          }
          return
        } else {
          console.warn('[NoteEditView] richEditorSpans解析成功但没有有效内容，将使用fallback逻辑')
        }
      } catch (e) {
        console.error('[NoteEditView] Failed to parse spans:', e, 'richEditorSpans:', this.note.richEditorSpans?.substring(0, 100))
      }
    }
    
    // Fallback logic: 如果richEditorSpans不存在或解析失败，使用contentText和links
    console.info('[NoteEditView] 使用fallback逻辑恢复内容，contentText长度:', this.contentText?.length || 0, 'links数量:', this.linkItems.length, 'note.content长度:', this.note.content?.length || 0, 'note.links数量:', this.note.links?.length || 0)
    
    // 修复：如果linkItems为空但note.links有内容，从note.links恢复
    if ((!this.linkItems || this.linkItems.length === 0) && this.note.links && this.note.links.length > 0) {
      this.linkItems = [...this.note.links]
      console.info('[NoteEditView] fallback: 从note.links恢复链接，数量:', this.linkItems.length)
    }
    
    // 修复：优先使用note.content，如果为空再使用contentText
    // 重要：需要检查所有可能的内容来源
    let textToDisplay = ''
    if (this.note.content && this.note.content.trim() !== '') {
      textToDisplay = this.note.content
    } else if (this.contentText && this.contentText.trim() !== '') {
      textToDisplay = this.contentText
    }
    
    console.info('[NoteEditView] fallback: 准备显示内容，textToDisplay长度:', textToDisplay.length, 'note.content长度:', this.note.content?.length || 0, 'contentText长度:', this.contentText?.length || 0)
    
    if (textToDisplay && textToDisplay.trim() !== '') {
       console.info('[NoteEditView] fallback: 添加文本内容到编辑器，长度:', textToDisplay.length, '内容预览:', textToDisplay.substring(0, 100))
       try {
         this.richEditorController.addTextSpan(textToDisplay, { style: { fontColor: AppColors.TEXT_PRIMARY, fontSize: 16 } })
         // 同步到contentText和note.content
         this.contentText = textToDisplay
         this.note.content = textToDisplay
         console.info('[NoteEditView] fallback: ✅ 文本内容已成功添加到RichEditor')
       } catch (e) {
         console.error('[NoteEditView] fallback: ❌ 添加文本内容失败:', e)
         // 如果失败，尝试延迟添加
         setTimeout(() => {
           try {
             this.richEditorController.addTextSpan(textToDisplay, { style: { fontColor: AppColors.TEXT_PRIMARY, fontSize: 16 } })
             this.contentText = textToDisplay
             this.note.content = textToDisplay
             console.info('[NoteEditView] fallback: ✅ 文本内容已成功添加到RichEditor（延迟重试）')
           } catch (retryE) {
             console.error('[NoteEditView] fallback: ❌ 延迟重试也失败:', retryE)
           }
         }, 100)
       }
    } else {
      console.warn('[NoteEditView] fallback: ⚠️ 没有文本内容可以显示')
      console.warn('[NoteEditView] fallback: note.content类型:', typeof this.note.content, '值:', this.note.content?.substring(0, 50) || '(空或undefined)')
      console.warn('[NoteEditView] fallback: contentText类型:', typeof this.contentText, '值:', this.contentText?.substring(0, 50) || '(空或undefined)')
    }
    
    // Add attachments
    this.videoAttachments.forEach(v => this.addVideoBuilderSpan(v))
    
    // 修复：确保链接被添加到编辑器（即使没有文本内容）
    if (this.linkItems && this.linkItems.length > 0) {
      console.info('[NoteEditView] fallback: 准备添加', this.linkItems.length, '个链接到编辑器')
      this.linkItems.forEach(l => {
        console.info('[NoteEditView] fallback: 添加链接到编辑器:', l.title, l.url)
        this.addLinkBuilderSpan(l.title, l.url)
      })
    } else {
      console.warn('[NoteEditView] fallback: 没有链接可以显示')
    }
    
    console.info('[NoteEditView] fallback逻辑执行完成')
  }

  // 防抖版本的同步方法（优化长文本性能）
  private syncContentDebounced(): void {
    if (this.syncDebounceTimer !== -1) {
      clearTimeout(this.syncDebounceTimer)
    }
    this.syncDebounceTimer = setTimeout(() => {
      this.syncContentFromRichEditor()
      this.syncDebounceTimer = -1
    }, 150) as number
  }
  
  private syncContentFromRichEditor(): void {
    if (!this.isRichEditorReady || this.isUndoing) return

    const spans = this.richEditorController.getSpans()
    let text = ''
    const spanInfos: SpanInfo[] = []
    
    // 修复：从RichEditor获取的spans可能不包含BuilderSpan（链接使用BuilderSpan）
    // 所以我们需要先收集已有的链接URL，避免重复添加
    const existingLinkUrls = new Set<string>()
    
    spans.forEach(span => {
       if ((span as RichEditorTextSpanResult).value) {
          const s = span as RichEditorTextSpanResult
          text += s.value
          spanInfos.push(new SpanInfo('text', s.value, '', 0, 0))
       } else if ((span as RichEditorImageSpanResult).imageStyle) {
          const s = span as RichEditorImageSpanResult
          const src = s.valueResourceStr as string
          if (src && src.length > 1) {
             spanInfos.push(new SpanInfo('image', '', src, 0, 0))
          }
       }
       // 注意：BuilderSpan（用于链接）可能不会被getSpans()返回
       // 所以我们总是从linkItems数组添加链接
    })
    
    this.contentText = text
    this.note.content = text // update note
    
    // 修复：同步链接到note对象（重要：先同步linkItems，确保最新状态）
    // 如果linkItems为空但note.links有内容，恢复linkItems
    if ((!this.linkItems || this.linkItems.length === 0) && this.note.links && this.note.links.length > 0) {
      this.linkItems = [...this.note.links]
      console.info('[NoteEditView] syncContentFromRichEditor: 从note.links恢复linkItems，数量:', this.linkItems.length)
    }
    this.note.links = [...this.linkItems]
    
    this.onContentChange()
    
    // Append attachments（注意：这里要确保所有附件都被包含）
    this.videoAttachments.forEach(v => spanInfos.push(new SpanInfo('video', '', v, 0, 0)))
    
    // 修复：确保所有链接都被添加到spanInfos（这是关键！）
    // 因为BuilderSpan可能不会被getSpans()返回，所以必须从linkItems手动添加
    if (this.linkItems && this.linkItems.length > 0) {
      this.linkItems.forEach(l => {
        // 检查是否已经添加过（避免重复）
        const alreadyAdded = spanInfos.some(s => s.type === 'link' && s.linkUrl === l.url)
        if (!alreadyAdded) {
          const info = new SpanInfo('link', '', '', 0, 0)
          info.linkTitle = l.title
          info.linkUrl = l.url
          spanInfos.push(info)
          console.info('[NoteEditView] syncContentFromRichEditor: 添加链接到spanInfos:', l.title)
        }
      })
    } else {
      console.warn('[NoteEditView] syncContentFromRichEditor: linkItems为空，可能导致链接丢失')
    }

    this.note.richEditorSpans = JSON.stringify(spanInfos)
    console.info('[NoteEditView] syncContentFromRichEditor: 更新richEditorSpans，包含', spanInfos.length, '个元素，其中链接:', spanInfos.filter(s => s.type === 'link').length)
    
    // Sync ContentBlocks for preview/list view compatibility
    const newBlocks: ContentBlock[] = []
    spanInfos.forEach(span => {
       if (span.type === 'text') {
          newBlocks.push(new TextBlock(span.value))
       } else if (span.type === 'image') {
          newBlocks.push(new ImageBlock(span.src))
       } else if (span.type === 'video') {
          newBlocks.push(new VideoBlock(span.src))
       } else if (span.type === 'link') {
          newBlocks.push(new LinkBlock(span.linkTitle || '', span.linkUrl || ''))
       }
    })
    this.note.contentBlocks = newBlocks
    
    if (text.length > 5) {
       this.onEmotionAnalysisTrigger()
    }
  }

  private insertImageSpanInline(path: string): void {
     if (!this.richEditorController) return
     this.richEditorController.addImageSpan(path, {
        imageStyle: { size: ['120vp', '90vp'], verticalAlign: ImageSpanAlignment.CENTER, objectFit: ImageFit.Cover }
     })
     this.imageAttachments.push(path)
     this.note.images = this.imageAttachments
     this.syncContentFromRichEditor()
  }

  private addVideoBuilderSpan(path: string): void {
    this.richEditorController.addBuilderSpan(() => {
       this.VideoCard(path)
    })
  }

  private addLinkBuilderSpan(title: string, url: string): void {
    this.richEditorController.addBuilderSpan(() => {
       this.LinkCard(title, url)
    })
  }
  
  private handleBuilderSpanDelete(value: RichEditorDeleteValue): void {
     // Placeholder
  }

  // ==================== Builders ====================
  
  @Builder
  VideoCard(path: string) {
     Stack() {
       Video({ src: path, controller: new VideoController() })
         .width(200).height(150).controls(true)
       // Delete button
       Text('x').onClick(() => {
          const idx = this.videoAttachments.indexOf(path)
          if (idx !== -1) {
             this.videoAttachments.splice(idx, 1)
             this.note.videos = this.videoAttachments
             this.initRichEditorContent() 
          }
       })
     }
  }

  @Builder
  LinkCard(title: string, url: string) {
     Text(`[${title}]`)
       .fontColor(AppColors.ACCENT)
       .decoration({ type: TextDecorationType.Underline })
       .onClick(() => {
          if (url && url.length > 0) {
              try {
                  // 跳转到新闻WebView页面
                  router.pushUrl({
                      url: 'main/view/pages/NewsWebViewPage',
                      params: {
                          url: url,
                          title: title || '新闻原文'
                      }
                  }).catch((e: Error) => {
                      console.error('[NoteEditView] 跳转到NewsWebViewPage失败:', e)
                      promptAction.showToast({ message: '无法打开链接: ' + e.message })
                  })
              } catch (e) {
                  console.error('[NoteEditView] 打开链接失败:', e)
                  promptAction.showToast({ message: '无法打开链接' })
              }
          }
       })
  }

  @Builder
  ChecklistItemCard(item: ChecklistItem) {
    Row({ space: 12 }) {
      Checkbox({ name: item.id, group: 'checklist' })
        .select(item.checked)
        .onChange((val) => {
           item.checked = val
           this.onChecklistItemUpdate(item)
        })
      Text(item.text).fontSize(16).decoration({ type: item.checked ? TextDecorationType.LineThrough : TextDecorationType.None })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(8)
  }

  // ==================== History (Undo/Redo) ====================
  
  private saveToHistory(): void {
     const current = this.note.richEditorSpans
     if (this.historyStack[this.historyIndex] !== current) {
        this.historyIndex++
        this.historyStack = this.historyStack.slice(0, this.historyIndex)
        this.historyStack.push(current)
        this.updateUndoRedoState()
     }
  }
  
  private undo(): void {
     if (this.historyIndex > 0) {
        this.isUndoing = true
        this.historyIndex--
        const prev = this.historyStack[this.historyIndex]
        this.note.richEditorSpans = prev
        this.initRichEditorContent()
        this.isUndoing = false
        this.updateUndoRedoState()
     }
  }
  
  private redo(): void {
     if (this.historyIndex < this.historyStack.length - 1) {
        this.isUndoing = true
        this.historyIndex++
        const next = this.historyStack[this.historyIndex]
        this.note.richEditorSpans = next
        this.initRichEditorContent()
        this.isUndoing = false
        this.updateUndoRedoState()
     }
  }
  
  private updateUndoRedoState(): void {
     this.canUndo = this.historyIndex > 0
     this.canRedo = this.historyIndex < this.historyStack.length - 1
  }
}
