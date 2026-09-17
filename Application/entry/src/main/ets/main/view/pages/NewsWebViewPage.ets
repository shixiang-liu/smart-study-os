// ============================================================================
// 新闻WebView页面 - 用于显示新闻原文
// ============================================================================

import { AppColors, AppSizes } from '../../../common/utils/AppTheme'
import { router, promptAction } from '@kit.ArkUI'
import webview from '@ohos.web.webview'
import { common, Want } from '@kit.AbilityKit'
import { NoteItem, LinkItem, LinkBlock } from '../../../diary/model/NoteItem'
import { PreferencesUtil } from '../../../common/utils/PreferencesUtil'
import { CloudDBService } from '../../../common/services/CloudDBService'
import { NewsCollection } from '../../../common/model/NewsCollection'

// 定义事件类型接口
interface PageEndEvent {
  url: string
}

// Web资源错误接口
interface WebResourceError {
  code?: number
  reason?: string
  description?: string
}

// HTTP响应接口
interface HttpResponse {
  statusCode?: number
  status?: number
  responseUrl?: string
  url?: string
}

@Entry
@Component
struct NewsWebViewPage {
  @State url: string = ''
  @State title: string = '新闻原文'
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  controller: webview.WebviewController = new webview.WebviewController()
  
  // 日记选择器状态
  @State showDiaryPicker: boolean = false
  @State diaryList: NoteItem[] = []
  
  // 加载和错误状态
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State errorMessage: string = ''
  private errorCheckTimer: number = -1
  private pageLoaded: boolean = false
  
  // 新闻收藏 - 选择日记插入链接并同步到云端
  private async saveToNote(): Promise<void> {
    if (!this.url || !this.title) {
      promptAction.showToast({ message: '无法保存，链接或标题缺失' })
      return
    }
    
    // 弹窗选择：新建日记或插入已有日记
    promptAction.showDialog({
      title: '收藏到日记',
      message: '选择如何保存这篇新闻',
      buttons: [
        { text: '取消', color: AppColors.TEXT_SECONDARY },
        { text: '新建日记', color: AppColors.ACCENT },
        { text: '插入已有', color: AppColors.ACCENT }
      ]
    }).then(async result => {
      if (result.index === 1) {
        // 新建日记（传递链接信息用于插入超链接）
        await this.syncNewsToCloud('')  // 先保存收藏记录
        router.pushUrl({
          url: 'diary/view/pages/DetailPage',
          params: {
            initialTitle: `📰 ${this.title}`,
            initialContent: '我的感想：',
            initialLink: { title: `📰 ${this.title}`, url: this.url }  // 传递链接信息
          }
        })
      } else if (result.index === 2) {
        // 插入已有日记 - 打开日记选择器
        const context = getContext(this) as common.UIAbilityContext
        this.diaryList = await PreferencesUtil.loadNotes(context)
        this.showDiaryPicker = true
      }
    }).catch(() => {})
  }
  
  // 同步新闻收藏到CloudDB
  private async syncNewsToCloud(linkedDiaryId: string): Promise<void> {
    try {
      const userId = AppStorage.get<string>('currentUserId') || ''
      if (!userId) return
      
      const collection = NewsCollection.create(userId, this.title, this.url)
      if (linkedDiaryId) {
        collection.linkToDiary(linkedDiaryId)
      }
      
      const cloudService = CloudDBService.getInstance()
      await cloudService.upsertNewsCollection(collection)
      console.info('[NewsWebView] 新闻收藏已同步到云端')
    } catch (err) {
      console.warn('[NewsWebView] 云端同步失败:', err)
      // 不影响本地操作
    }
  }
  
  // 插入到选中的日记并同步到云端（问题5修复：使用超链接格式）
  private async insertToSelectedDiary(noteId: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext
    const notes = await PreferencesUtil.loadNotes(context)
    const note = notes.find(n => n.id === noteId)
    
    if (note) {
      // 使用超链接格式，只显示标题但可点击跳转
      // 创建LinkItem对象
      const linkItem = new LinkItem()
      linkItem.id = Date.now().toString()
      linkItem.title = `📰 ${this.title}`
      linkItem.url = this.url
      
      // 添加到日记的links数组
      if (!note.links) {
        note.links = []
      }
      note.links.push(linkItem)
      
      // 同时更新contentBlocks（用于RichEditor恢复）
      if (!note.contentBlocks) {
        note.contentBlocks = []
      }
      note.contentBlocks.push(new LinkBlock(linkItem.title, linkItem.url))
      
      // 更新richEditorSpans（用于编辑器恢复）
      try {
        interface SpanData {
          type: string
          value?: string
          linkTitle?: string
          linkUrl?: string
          src?: string
        }
        let spans: SpanData[] = []
        
        // 如果richEditorSpans存在且不为空，解析它
        if (note.richEditorSpans && note.richEditorSpans !== '[]') {
          try {
            spans = JSON.parse(note.richEditorSpans) as SpanData[]
          } catch (parseError) {
            console.warn('[NewsWebView] 解析richEditorSpans失败，将重建:', parseError)
            spans = []
          }
        }
        
        // 如果spans为空但note.content存在，从content恢复文本内容
        if (spans.length === 0 && note.content && note.content.trim() !== '') {
          spans.push({
            type: 'text',
            value: note.content
          })
          console.info('[NewsWebView] 从note.content恢复文本内容到richEditorSpans，长度:', note.content.length)
        }
        
        // 检查是否已存在相同的链接（避免重复）
        const linkExists = spans.some(s => s.type === 'link' && s.linkUrl === linkItem.url)
        if (!linkExists) {
          // 添加新的链接span
          const newSpan: SpanData = { 
            type: 'link', 
            linkTitle: linkItem.title, 
            linkUrl: linkItem.url 
          }
          spans.push(newSpan)
          console.info('[NewsWebView] 添加链接到richEditorSpans:', linkItem.title)
        } else {
          console.info('[NewsWebView] 链接已存在，跳过:', linkItem.url)
        }
        
        // 更新richEditorSpans
        note.richEditorSpans = JSON.stringify(spans)
        console.info('[NewsWebView] 更新richEditorSpans完成，包含', spans.length, '个元素')
      } catch (e) {
        console.error('[NewsWebView] 更新richEditorSpans失败:', e)
        // 失败时至少确保链接被添加到links数组和contentBlocks
      }
      
      note.lastModifiedTime = Date.now()
      
      await PreferencesUtil.saveNote(context, note)
      await this.syncNewsToCloud(noteId)  // 同步到云端并关联日记
      this.showDiaryPicker = false
      
      promptAction.showToast({ message: '已插入超链接到日记' })
      // 导航到该日记
      setTimeout(() => {
        router.pushUrl({
          url: 'diary/view/pages/DetailPage',
          params: { noteId: noteId }
        })
      }, 300)
    }
  }

  // 规范化URL，确保包含协议
  private normalizeUrl(url: string): string {
    if (!url || url.trim() === '') {
      return ''
    }
    const trimmedUrl = url.trim()
    // 如果URL已经包含协议，直接返回
    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
      return trimmedUrl
    }
    // 否则添加 https://
    return `https://${trimmedUrl}`
  }
  
  aboutToAppear() {
    // 重置状态
    this.pageLoaded = false
    this.hasError = false
    this.errorMessage = ''
    this.isLoading = true
    
    // 从路由参数获取URL
    const params = router.getParams() as Record<string, string>
    console.info('[NewsWebView] 接收到的路由参数:', JSON.stringify(params))
    
    if (params && params['url']) {
      const rawUrl = params['url'] as string
      // 规范化URL
      this.url = this.normalizeUrl(rawUrl)
      console.info('[NewsWebView] 原始URL:', rawUrl, '规范化后URL:', this.url)
    } else {
      console.warn('[NewsWebView] 未找到URL参数')
      this.hasError = true
      this.errorMessage = '未找到链接地址'
      this.isLoading = false
    }
    
    if (params && params['title']) {
      this.title = params['title'] as string
    }
  }
  
  aboutToDisappear() {
    // 清理定时器
    if (this.errorCheckTimer !== -1) {
      clearTimeout(this.errorCheckTimer)
      this.errorCheckTimer = -1
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('←')
            .fontSize(20)
            .fontColor(AppColors.TEXT_PRIMARY)
            .onClick(() => {
              router.back()
            })
          Blank()
          Text(this.title)
            .fontSize(AppSizes.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          
          // 问题23修复: 插入日记按钮
          Text('📝')
            .fontSize(22)
            .fontColor(AppColors.ACCENT)
            .margin({ right: 12 })
            .onClick(() => {
              this.saveToNote()
            })
          
          Text('···')
            .fontSize(20)
            .fontColor(AppColors.TEXT_PRIMARY)
            .onClick(() => {
              this.openInBrowser()
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: AppSizes.SPACE_MD, right: AppSizes.SPACE_MD })
        .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)

        if (this.url && this.url !== '') {
          Stack() {
            // WebView组件
            Web({ src: this.url, controller: this.controller })
              .width('100%')
              .layoutWeight(1)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .fileAccess(true)
              .imageAccess(true)
              .mixedMode(MixedMode.All)
              .onTitleReceive((event: OnTitleReceiveEvent) => {
                if (event && event.title) {
                  this.title = event.title
                  this.isLoading = false
                  this.hasError = false
                  console.info('[NewsWebView] 页面标题:', event.title)
                }
              })
              .onPageEnd((event: PageEndEvent) => {
                if (event) {
                  this.pageLoaded = true
                  this.isLoading = false
                  // 页面加载成功，清除错误状态
                  this.hasError = false
                  this.errorMessage = ''
                  // 清除错误检查定时器
                  if (this.errorCheckTimer !== -1) {
                    clearTimeout(this.errorCheckTimer)
                    this.errorCheckTimer = -1
                  }
                  console.info('[NewsWebView] 页面加载完成:', event.url)
                }
              })
              .onErrorReceive((event: OnErrorReceiveEvent) => {
                if (!event || !event.request || !event.error) {
                  return
                }

                // 直接使用事件对象的方法
                const isMainFrame: boolean = event.request.isMainFrame()
                const url: string = event.request.getRequestUrl()
                const errorCode: number = event.error.getErrorCode()
                const errorInfo: string = event.error.getErrorInfo()
                
                console.error(`[NewsWebView] 页面加载错误: code=${errorCode}, info=${errorInfo}, isMainFrame=${isMainFrame}, url=${url}`)
                
                // 只有主页面的错误才显示错误页
                if (isMainFrame) {
                  console.warn('[NewsWebView] 主框架加载失败，延迟检查页面状态')
                  
                  if (this.errorCheckTimer !== -1) {
                    clearTimeout(this.errorCheckTimer)
                  }
                  
                  this.errorCheckTimer = setTimeout(() => {
                    if (!this.pageLoaded) {
                      this.isLoading = false
                      this.hasError = true
                      
                      let errorMsg = '页面加载失败'
                      
                      // 常见错误码处理
                      switch (errorCode) {
                        case -2:
                          errorMsg = '网络解析失败(DNS)，请检查网络'
                          break
                        case -5:
                          errorMsg = '连接服务器失败'
                          break
                        case -6:
                          errorMsg = 'SSL证书验证失败'
                          break
                        case -10:
                        case -11:
                          errorMsg = '网络连接超时'
                          break
                        default:
                          errorMsg = errorInfo || `加载失败 (码:${errorCode})`
                      }
                      this.errorMessage = errorMsg
                    }
                    this.errorCheckTimer = -1
                  }, 2500) as number
                }
              })
              .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
                if (!event || !event.request || !event.response) {
                  return
                }
                
                // 直接使用事件对象的方法
                const isMainFrame: boolean = event.request.isMainFrame()
                const requestUrl: string = event.request.getRequestUrl()
                const statusCode: number = event.response.getResponseCode()
                
                console.error(`[NewsWebView] HTTP错误: status=${statusCode}, isMainFrame=${isMainFrame}, url=${requestUrl}`)
                
                if (isMainFrame && statusCode >= 400) {
                  this.errorMessage = `HTTP加载错误: ${statusCode}`
                  this.hasError = true
                  this.isLoading = false
                }
              })
            
            // 加载中提示
            if (this.isLoading && !this.hasError) {
              Column({ space: 12 }) {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color(AppColors.ACCENT)
                Text('正在加载...')
                  .fontSize(AppSizes.FONT_MD)
                  .fontColor(AppColors.TEXT_SECONDARY)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .backgroundColor('rgba(255, 255, 255, 0.9)')
            }
            
            // 错误提示
            if (this.hasError) {
              Column({ space: 16 }) {
                Text('⚠️')
                  .fontSize(48)
                Text(this.errorMessage || '页面加载失败')
                  .fontSize(AppSizes.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .textAlign(TextAlign.Center)
                  .padding({ left: 32, right: 32 })
                
                Row({ space: 12 }) {
                  Button('重试')
                    .fontSize(AppSizes.FONT_SM)
                    .backgroundColor(AppColors.ACCENT)
                    .fontColor('#FFFFFF')
                    .onClick(() => {
                      console.info('[NewsWebView] 用户点击重试，URL:', this.url)
                      this.isLoading = true
                      this.hasError = false
                      this.errorMessage = ''
                      // 重新加载页面 - 先刷新，如果失败则重新加载URL
                      try {
                        this.controller.refresh()
                        // 如果refresh失败，尝试重新加载URL
                        setTimeout(() => {
                          if (this.hasError) {
                            console.warn('[NewsWebView] refresh失败，尝试重新加载URL')
                            this.controller.loadUrl(this.url)
                          }
                        }, 1000)
                      } catch (e) {
                        console.error('[NewsWebView] 重试失败:', e)
                        // 如果refresh失败，直接重新加载URL
                        this.controller.loadUrl(this.url)
                      }
                    })
                  
                  Button('在浏览器中打开')
                    .fontSize(AppSizes.FONT_SM)
                    .backgroundColor(AppColors.BG_SECONDARY)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .onClick(() => {
                      this.openInBrowser()
                    })
                }
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY)
            }
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          // 如果没有URL，显示提示
          Column({ space: AppSizes.SPACE_MD }) {
            Text('⚠️')
              .fontSize(48)
            Text('暂无新闻链接')
              .fontSize(AppSizes.FONT_LG)
              .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_PRIMARY : AppColors.BG_PRIMARY)
      
      // 日记选择器弹窗
      if (this.showDiaryPicker) {
        this.DiaryPickerDialog()
      }
    }
    .width('100%')
    .height('100%')
  }
  
  // 日记选择器对话框
  @Builder DiaryPickerDialog() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {
          this.showDiaryPicker = false
        })
      
      // 对话框
      Column({ space: 16 }) {
        Text('选择日记')
          .fontSize(AppSizes.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        
        // 日记列表
        if (this.diaryList.length === 0) {
          Column({ space: 8 }) {
            Text('暂无日记')
              .fontSize(AppSizes.FONT_MD)
              .fontColor(AppColors.TEXT_SECONDARY)
            Text('请先新建一条日记')
              .fontSize(AppSizes.FONT_SM)
              .fontColor(AppColors.TEXT_TERTIARY)
          }
          .width('100%')
          .padding(32)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.diaryList.slice(0, 10), (note: NoteItem) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text(note.emotionEmoji || '📝')
                    .fontSize(24)
                  
                  Column({ space: 4 }) {
                    Text(note.title || '无标题')
                      .fontSize(AppSizes.FONT_MD)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColors.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    
                    Text(this.formatDate(note.createTime))
                      .fontSize(AppSizes.FONT_XS)
                      .fontColor(AppColors.TEXT_TERTIARY)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  
                  Text('选择')
                    .fontSize(AppSizes.FONT_SM)
                    .fontColor(AppColors.ACCENT)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(AppColors.BG_TERTIARY)
                    .borderRadius(AppSizes.RADIUS_SM)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(AppColors.BG_SECONDARY)
                .borderRadius(AppSizes.RADIUS_MD)
                .onClick(() => {
                  this.insertToSelectedDiary(note.id)
                })
              }
            }, (note: NoteItem) => note.id)
          }
          .width('100%')
          .height(300)
        }
        
        // 关闭按钮
        Button('取消')
          .width('100%')
          .height(44)
          .fontSize(AppSizes.FONT_MD)
          .backgroundColor(AppColors.BG_TERTIARY)
          .fontColor(AppColors.TEXT_PRIMARY)
          .borderRadius(AppSizes.RADIUS_MD)
          .onClick(() => {
            this.showDiaryPicker = false
          })
      }
      .width('85%')
      .padding(20)
      .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_PRIMARY)
      .borderRadius(AppSizes.RADIUS_LG)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.3)', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
  
  // 格式化日期
  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = date.getMonth() + 1
    const day = date.getDate()
    return `${month}月${day}日`
  }

  // 在系统浏览器中打开
  private async openInBrowser(): Promise<void> {
    if (!this.url || this.url.trim() === '') {
      promptAction.showToast({ message: '暂无链接', duration: 2000 })
      return
    }

    try {
      const context = getContext(this) as common.UIAbilityContext
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: this.url,
        type: 'text/html'
      }
      await context.startAbility(want)
    } catch (err) {
      console.error('[NewsWebView] 打开浏览器失败:', err)
      promptAction.showToast({ message: '无法打开浏览器', duration: 2000 })
    }
  }
}
