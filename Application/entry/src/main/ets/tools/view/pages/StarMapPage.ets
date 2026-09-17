// ============================================================================
// 知识星图页 - StarMapPage (Creamy UI Refactor)
// ============================================================================
// 风格：Creamy UI (Soft, Clean, Friendly)
// 核心：Canvas 动态浮球 + 柔光渐变 + 空气感交互
// ============================================================================

import { AppColors, AppSizes, AppShadows, AppAnimations, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'
import { IconPaths } from '../../../common/utils/IconPaths'
import { MemoryViewModel } from '../../../diary/viewmodel/MemoryViewModel'
import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

// ============================================================================
// 数据类型
// ============================================================================

interface StarNode {
  id: string
  keyword: string
  weight: number
  x: number
  y: number
  radius: number
  color: string
  vx: number
  vy: number
  opacity: number // 呼吸效果
  phase: number   // 动画相位
}

interface MockDataItem {
  keyword: string
  weight: number
}

interface BackgroundDot {
  x: number
  y: number
  r: number
  o: number
}

// ============================================================================
// 星图页面组件
// ============================================================================

@Entry
@Component
struct StarMapPage {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @State stars: StarNode[] = []
  @State selectedStar: StarNode | null = null
  @State showHint: boolean = true
  @State canvasWidth: number = 360
  @State canvasHeight: number = 640
  
  private memoryViewModel: MemoryViewModel = new MemoryViewModel()
  private canvasContext: CanvasRenderingContext2D | null = null
  private animationId: number = -1
  private hintTimer: number = -1
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private readonly maxNodes: number = 24 // 控制节点数量，避免拥挤与卡顿
  private backgroundDots: BackgroundDot[] = []

  // Creamy Palette for Bubbles
  private readonly bubbleColors: string[] = [
    '#FFD166', '#06D6A0', '#118AB2', '#EF476F', '#8338EC', '#FF9F1C',
    '#9D4EDD', '#4CC9F0', '#F15BB5', '#FEE440', '#5DD39E', '#8EA6E9'
  ]

  aboutToAppear() {
    if (!this.canvasContext) {
      this.canvasContext = new CanvasRenderingContext2D(this.canvasSettings)
    }
    if (this.backgroundDots.length === 0) {
      this.initBackgroundDots()
    }
    this.scheduleHintAutoHide()
    this.loadStarData()
  }

  aboutToDisappear() {
    if (this.animationId !== -1) {
      clearInterval(this.animationId)
    }
    if (this.hintTimer !== -1) {
      clearTimeout(this.hintTimer)
      this.hintTimer = -1
    }
  }

  private async loadStarData() {
    try {
      // 传递 context，以便从本地日记提取关键词（作为 CloudDB 的 fallback）
      const context = getContext(this) as common.UIAbilityContext
      const memories = await this.memoryViewModel.getStarMapData(context, true)
      // 如果云/本地都空，直接用内置 mock，保证有内容可见
      if (memories.length === 0) {
        this.stars = this.generateMockStars()
      } else {
        // 按权重排序截断，避免过多节点导致拥挤与卡顿
        const top = memories
          .sort((a, b) => b.weight - a.weight)
          .slice(0, this.maxNodes)
        this.stars = top.map((m, index) => this.createStarNode(m.keyword, m.weight, index))
      }
      this.layoutStars()
      console.info('[StarMapPage] final star node count:', this.stars.length)
      // 确保有数据后再启动动画
      if (this.stars.length > 0 && this.canvasContext) {
        this.startAnimation()
        this.drawStars()
      }
    } catch (err) {
      console.error('[StarMapPage] Load failed:', err)
      // 失败时使用模拟数据
      this.stars = this.generateMockStars()
      if (this.stars.length > 0 && this.canvasContext) {
        this.layoutStars()
        this.startAnimation()
      }
    }
  }

  private generateMockStars(): StarNode[] {
    const mockData: MockDataItem[] = [
      { keyword: '梦想', weight: 20 },
      { keyword: '坚持', weight: 18 },
      { keyword: '快乐', weight: 15 },
      { keyword: '焦虑', weight: 12 },
      { keyword: '旅行', weight: 10 },
      { keyword: '美食', weight: 8 },
      { keyword: '阅读', weight: 14 },
      { keyword: '运动', weight: 16 },
      { keyword: '早起', weight: 9 },
      { keyword: '冥想', weight: 7 }
    ]
    return mockData.map((d, i) => this.createStarNode(d.keyword, d.weight, i))
  }

  private createStarNode(keyword: string, weight: number, index: number): StarNode {
    const minRadius = 36
    const maxRadius = 78
    const normalizedWeight = Math.min(weight, 20) / 20
    const radius = minRadius + normalizedWeight * (maxRadius - minRadius)

    // Gentle floating speed
    const speed = 0.12
    const vx = (Math.random() - 0.5) * speed
    const vy = (Math.random() - 0.5) * speed

    return {
      id: `star_${index}`,
      keyword,
      weight,
      x: 0,
      y: 0,
      radius,
      color: this.bubbleColors[index % this.bubbleColors.length],
      vx,
      vy,
      opacity: 0.9,
      phase: Math.random() * Math.PI * 2
    }
  }

  // ==================== Animation System ====================

  private startAnimation() {
    if (this.animationId !== -1) return

    this.animationId = setInterval(() => {
      this.updatePhysics()
      this.drawStars()
    }, 33) // ~30 FPS，降低卡顿
  }

  private updatePhysics() {
    for (const star of this.stars) {
      // 1. Movement
      star.x += star.vx
      star.y += star.vy

      // 2. Wall Bounce (Soft)
      if (star.x - star.radius < 0 || star.x + star.radius > this.canvasWidth) {
        star.vx = -star.vx
        star.x = Math.max(star.radius, Math.min(this.canvasWidth - star.radius, star.x))
      }
      if (star.y - star.radius < 0 || star.y + star.radius > this.canvasHeight) {
        star.vy = -star.vy
        star.y = Math.max(star.radius, Math.min(this.canvasHeight - star.radius, star.y))
      }

      // 3. Breathing Effect
      star.phase += 0.02
      star.opacity = 0.85 + Math.sin(star.phase) * 0.15
    }
  }

  private drawStars() {
    if (!this.canvasContext) return
    const ctx = this.canvasContext
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    // 柔和渐变 + 暗纹星点背景
    ctx.save()
    const bgGradient = ctx.createLinearGradient(0, 0, 0, this.canvasHeight)
    if (this.isDarkMode) {
      bgGradient.addColorStop(0, '#0F1117')
      bgGradient.addColorStop(1, '#0A0C12')
    } else {
      bgGradient.addColorStop(0, '#F7F9FF')
      bgGradient.addColorStop(1, '#E7ECF7')
    }
    ctx.fillStyle = bgGradient
    ctx.fillRect(0, 0, this.canvasWidth, this.canvasHeight)

    // 中心光晕
    const glow = ctx.createRadialGradient(
      this.canvasWidth / 2, this.canvasHeight * 0.4, 0,
      this.canvasWidth / 2, this.canvasHeight * 0.4, this.canvasWidth * 0.8
    )
    if (this.isDarkMode) {
      glow.addColorStop(0, 'rgba(50,60,90,0.3)')
      glow.addColorStop(1, 'rgba(0,0,0,0)')
    } else {
      glow.addColorStop(0, 'rgba(255,255,255,0.9)')
      glow.addColorStop(1, 'rgba(255,255,255,0)')
    }
    ctx.fillStyle = glow
    ctx.fillRect(0, 0, this.canvasWidth, this.canvasHeight)

    // 背景星尘
    ctx.fillStyle = this.isDarkMode ? 'rgba(255,255,255,0.18)' : 'rgba(102,119,153,0.14)'
    for (const dot of this.backgroundDots) {
      ctx.beginPath()
      ctx.globalAlpha = dot.o
      ctx.arc(dot.x, dot.y, dot.r, 0, Math.PI * 2)
      ctx.fill()
    }
    ctx.globalAlpha = 1
    ctx.restore()

    // 连接线（最近距离）
    this.drawConnections(ctx)

    for (const star of this.stars) {
      // 1. Soft Shadow (Airy)
      ctx.beginPath()
      ctx.arc(star.x, star.y + 8, star.radius, 0, Math.PI * 2)
      ctx.fillStyle = 'rgba(0,0,0,0.05)'
      ctx.filter = 'blur(10px)'
      ctx.fill()
      ctx.filter = 'none'

      // 1.5 Outer Glow
      const glowG = ctx.createRadialGradient(
        star.x, star.y, star.radius * 0.6,
        star.x, star.y, star.radius * 1.35
      )
      glowG.addColorStop(0, this.hexToRgba(star.color, 0.26))
      glowG.addColorStop(1, 'rgba(255,255,255,0)')
      ctx.beginPath()
      ctx.arc(star.x, star.y, star.radius * 1.35, 0, Math.PI * 2)
      ctx.fillStyle = glowG
      ctx.fill()

      // 2. Bubble Body (Gradient)
      const gradient = ctx.createRadialGradient(
        star.x - star.radius * 0.3, star.y - star.radius * 0.3, 0,
        star.x, star.y, star.radius
      )
      gradient.addColorStop(0, this.hexToRgba(star.color, star.opacity))
      gradient.addColorStop(1, this.hexToRgba(star.color, star.opacity * 0.65))

      ctx.beginPath()
      ctx.arc(star.x, star.y, star.radius, 0, Math.PI * 2)
      ctx.fillStyle = gradient
      ctx.fill()
      // 细边线保持通透感
      ctx.lineWidth = 1.2
      ctx.strokeStyle = this.isDarkMode ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.12)'
      ctx.stroke()

      // 3. Highlight (Glossy)
      ctx.beginPath()
      ctx.ellipse(
        star.x - star.radius * 0.3, 
        star.y - star.radius * 0.3, 
        star.radius * 0.2, 
        star.radius * 0.1, 
        Math.PI / 4, 
        0, 
        Math.PI * 2
      )
      ctx.fillStyle = 'rgba(255,255,255,0.4)'
      ctx.fill()

      // 4. Text
      const fontSize = Math.max(20, star.radius / 2.4)
      const textColor = this.isDarkMode ? '#F2F5FF' : '#0B1220'
      ctx.fillStyle = textColor
      ctx.font = `600 ${fontSize}px "HarmonyOS Sans", sans-serif`
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      // 文字描边以提升可读性
      ctx.strokeStyle = this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(255,255,255,0.75)'
      ctx.lineWidth = 2
      ctx.strokeText(star.keyword, star.x, star.y)
      ctx.fillText(star.keyword, star.x, star.y)

      // 5. 小点缀 (pulse)
      ctx.beginPath()
      ctx.arc(star.x + star.radius * 0.35, star.y - star.radius * 0.2, 3, 0, Math.PI * 2)
      ctx.fillStyle = 'rgba(255,255,255,0.8)'
      ctx.fill()
    }
  }

  // 将节点按权重排序后分环排布，降低重叠
  private layoutStars() {
    if (this.stars.length === 0) return
    const sorted = [...this.stars].sort((a, b) => b.weight - a.weight)
    const centerX = this.canvasWidth / 2
    const centerY = this.canvasHeight / 2
    const ringGap = Math.min(this.canvasWidth, this.canvasHeight) / 4.2
    const baseRadius = Math.min(this.canvasWidth, this.canvasHeight) / 6.5
    const pad = 26

    // 环形分布：第一个放中心，其他按环排列
    if (sorted.length > 0) {
      sorted[0].x = centerX
      sorted[0].y = centerY
    }

    let idx = 1
    let ring = 1
    while (idx < sorted.length) {
      const ringRadius = baseRadius + ringGap * ring
      const countThisRing = Math.min(7 + ring * 3, sorted.length - idx)
      for (let i = 0; i < countThisRing && idx < sorted.length; i++, idx++) {
        const angle = (Math.PI * 2 * i) / countThisRing
        const r = ringRadius + pad
        sorted[idx].x = centerX + r * Math.cos(angle)
        sorted[idx].y = centerY + r * Math.sin(angle)
      }
      ring++
    }

    // 写回原数组
    for (const s of sorted) {
      const target = this.stars.find(st => st.id === s.id)
      if (target) {
        target.x = s.x
        target.y = s.y
      }
    }
  }

  private hexToRgba(hex: string, alpha: number): string {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex)
    return result ? 
      `rgba(${parseInt(result[1], 16)}, ${parseInt(result[2], 16)}, ${parseInt(result[3], 16)}, ${alpha})` : 
      `rgba(0,0,0,${alpha})`
  }

  // 统一根据深色/浅色模式获取色值
  private c(key: 'bgPrimary' | 'card' | 'textPrimary' | 'textSecondary' | 'textTertiary' | 'hintBg' | 'divider'): string {
    const dark = this.isDarkMode
    switch (key) {
      case 'bgPrimary': return dark ? AppColors.BG_DARK_PRIMARY : '#F7F8FB'
      case 'card': return dark ? AppColors.BG_DARK_SECONDARY : '#EEF1F7'
      case 'textPrimary': return dark ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY
      case 'textSecondary': return dark ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY
      case 'textTertiary': return dark ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY
      case 'hintBg': return dark ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.9)'
      case 'divider': return dark ? AppColors.DIVIDER_DARK : AppColors.DIVIDER
    }
  }

  private initBackgroundDots() {
    const count = 90
    this.backgroundDots = []
    for (let i = 0; i < count; i++) {
      this.backgroundDots.push({
        x: Math.random() * this.canvasWidth,
        y: Math.random() * this.canvasHeight,
        r: Math.random() * 1.4 + 0.4,
        o: Math.random() * 0.5 + 0.2
      })
    }
  }

  private drawConnections(ctx: CanvasRenderingContext2D) {
    const maxDist = Math.min(this.canvasWidth, this.canvasHeight) * 0.55
    ctx.save()
    ctx.lineWidth = 1
    for (let i = 0; i < this.stars.length; i++) {
      for (let j = i + 1; j < this.stars.length; j++) {
        const a = this.stars[i]
        const b = this.stars[j]
        const dx = a.x - b.x
        const dy = a.y - b.y
        const dist = Math.sqrt(dx * dx + dy * dy)
        if (dist > maxDist) continue
        const alphaBase = this.isDarkMode ? 0.22 : 0.14
        const alpha = alphaBase * (1 - dist / maxDist)
        const grad = ctx.createLinearGradient(a.x, a.y, b.x, b.y)
        grad.addColorStop(0, this.hexToRgba(a.color, alpha))
        grad.addColorStop(1, this.hexToRgba(b.color, alpha))
        ctx.strokeStyle = grad
        ctx.beginPath()
        ctx.moveTo(a.x, a.y)
        ctx.lineTo(b.x, b.y)
        ctx.stroke()
      }
    }
    ctx.restore()
  }

  private dismissHint() {
    this.showHint = false
    if (this.hintTimer !== -1) {
      clearTimeout(this.hintTimer)
      this.hintTimer = -1
    }
  }

  private scheduleHintAutoHide() {
    if (this.hintTimer !== -1) return
    this.hintTimer = setTimeout(() => {
      this.dismissHint()
    }, 3800)
  }

  private handleTouch(event: TouchEvent) {
    if (event.type !== TouchType.Down) return
    const touch = event.touches[0]
    
    // Find touched star (reverse order to hit top one first)
    for (let i = this.stars.length - 1; i >= 0; i--) {
      const star = this.stars[i]
      const dx = touch.x - star.x
      const dy = touch.y - star.y
      if (Math.sqrt(dx*dx + dy*dy) <= star.radius) {
        this.selectedStar = star
        return
      }
    }
    this.selectedStar = null
  }

  // ==================== UI Layout ====================

  build() {
    Stack() {
      // 1) 背景与主列
      Column() {
        // 顶部标题区
        Column() {
          Text('知识星图')
            .fontSize(AppSizes.FONT_2XL + 4)
            .fontWeight(FontWeight.Bolder)
            .fontColor(this.c('textPrimary'))
          Text('探索你的思维宇宙，聚焦真正重要的念头')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(this.c('textSecondary'))
            .opacity(0.9)
            .margin({ top: 6 })
          Row() {
            Text('动态浮动 · 关联连线 · 柔光渐变')
              .fontSize(AppSizes.FONT_XS)
              .fontColor(this.c('textTertiary'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)')
              .borderRadius(12)
            Blank()
          }
          .width('100%')
          .margin({ top: AppSizes.SPACE_SM })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          top: AppSizes.SPACE_4XL,
          left: AppSizes.SPACE_2XL,
          right: AppSizes.SPACE_2XL,
          bottom: AppSizes.SPACE_MD
        })

        // 画布区域容器：柔和圆角 + 阴影
        Stack() {
          Canvas(this.canvasContext)
            .width('100%')
            .height('100%') // 明确占满剩余区域
            .layoutWeight(1)
            .backgroundColor(this.c('card'))
            .constraintSize({ minHeight: 320 })
            .borderRadius(28)
            .shadow(AppShadows.SHADOW_MD)
            .clip(true)
            .onReady(() => {
              if (this.stars.length > 0) {
                this.startAnimation()
                this.drawStars() // 立即渲染一帧
              } else {
                this.loadStarData()
              }
            })
            .onAreaChange((_, newValue) => {
              this.canvasWidth = newValue.width as number
              this.canvasHeight = newValue.height as number
              console.info('[StarMapPage] canvas area:', this.canvasWidth, this.canvasHeight)
              this.initBackgroundDots()
              if (this.canvasContext && this.stars.length > 0) {
                this.layoutStars()
                this.drawStars()
              }
            })
            .onTouch((e) => this.handleTouch(e))
            .onClick(() => this.dismissHint())
          
          // 问题19修复：右上角小提示卡 - 使用position明确定位到顶部
          if (this.showHint) {
            Column() {
              Row() {
                Text('提示')
                  .fontSize(AppSizes.FONT_XS)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c('textPrimary'))
                Blank()
                Text('×')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(this.c('textSecondary'))
                  .onClick(() => this.dismissHint())
              }
              .width('100%')
              Text('点击节点查看详情，节点大小代表关注度')
                .fontSize(AppSizes.FONT_XS)
                .fontColor(this.c('textSecondary'))
                .lineHeight(18)
                .margin({ top: 4 })
            }
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.c('hintBg'))
            .borderRadius(14)
            .shadow(AppShadows.SHADOW_SM)
            .position({ x: '50%', y: 16 })  // 问题19修复：定位到顶部中央
            .translate({ x: '-50%' })
          }
        }
        .padding({ left: AppSizes.SPACE_2XL, right: AppSizes.SPACE_2XL, bottom: AppSizes.SPACE_3XL })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c('bgPrimary'))

      // 2) 详情弹层
      if (this.selectedStar) {
        this.DetailPopup()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DetailPopup() {
    Stack() {
      // Backdrop
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColors.OVERLAY_DARK)
        .onClick(() => {
          animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
            this.selectedStar = null
          })
        })

      // Card
      Column() {
        // Close Icon
        Row() {
          Blank()
          Text('×')
            .fontSize(28)
            .fontColor(AppColors.TEXT_TERTIARY)
            .onClick(() => this.selectedStar = null)
        }
        .width('100%')

        // Content
        Text(this.selectedStar?.keyword)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
          .margin({ top: AppSizes.SPACE_SM })

        Text(`出现频率: ${this.selectedStar?.weight}`)
          .fontSize(AppSizes.FONT_MD)
          .fontColor(AppColors.ACCENT)
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor(this.isDarkMode ? 'rgba(10,89,247,0.18)' : AppColors.ACCENT_BG)
          .borderRadius(12)
          .margin({ top: AppSizes.SPACE_MD })

        Text('这个关键词是你近期关注的重点，建议结合相关日记进行深度复盘。')
          .fontSize(AppSizes.FONT_MD)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_SECONDARY : AppColors.TEXT_SECONDARY)
          .lineHeight(24)
          .margin({ top: AppSizes.SPACE_LG })

        // Action Button
        Button('查看相关日记')
          .width('100%')
          .height(48)
          .backgroundColor(AppColors.ACCENT)
          .linearGradient(AppGradients.PRIMARY_BTN)
          .fontColor(AppColors.TEXT_WHITE)
          .fontSize(AppSizes.FONT_MD)
          .borderRadius(24)
          .shadow(AppShadows.SHADOW_MD)
          .margin({ top: AppSizes.SPACE_2XL })
          .onClick(() => {
            const keyword = this.selectedStar?.keyword || ''
            this.selectedStar = null
            router.pushUrl({
              url: 'diary/view/pages/DiaryListPage',
              params: { searchKeyword: keyword }
            })
          })
      }
      .width('85%')
      .padding(AppSizes.SPACE_2XL)
      .backgroundColor(this.isDarkMode ? 'rgba(30,30,34,0.92)' : 'rgba(255,255,255,0.95)') // Glass effect base
      .backdropBlur(20)
      .borderRadius(32)
      .shadow(AppShadows.SHADOW_LG)
      .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 100 } })
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
  }
}