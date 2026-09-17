// ============================================================================
// 悬浮窗番茄钟 - FloatPomodoro
// ============================================================================
// 功能：紧凑型番茄钟计时器，支持拖拽移动
// 用途：全局悬浮窗模式下使用
// 依赖：FloatWindowService
// ============================================================================

import { window } from '@kit.ArkUI';
import { IconPaths, IconSize } from '../../../common/utils/IconPaths';
import { AppColors, AppSizes, AppShadows } from '../../../common/utils/AppTheme';

// ============================================================================
// 计时器状态
// ============================================================================
enum TimerState {
  IDLE,      // 空闲
  RUNNING,   // 运行中
  PAUSED     // 已暂停
}

// ============================================================================
// 拖拽位置类型
// ============================================================================
class DragPosition {
  x: number = 0;
  y: number = 0;
}

// ============================================================================
// 悬浮窗番茄钟组件
// ============================================================================
@Entry
@Component
struct FloatPomodoro {
  // ==================== 状态变量 ====================
  
  // 剩余秒数（默认 25 分钟）
  @State private remainingSeconds: number = 25 * 60;
  
  // 计时器状态
  @State private timerState: TimerState = TimerState.IDLE;
  
  // 是否为工作时段（否则为休息时段）
  @State private isWorkSession: boolean = true;
  
  // 拖拽位置
  @State private dragPosition: DragPosition = new DragPosition();
  
  // 悬浮窗实例
  private floatWindow: window.Window | null = null;
  
  // 计时器 ID
  private timerId: number = -1;
  
  // 拖拽手势配置
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.All });

  // ==================== 生命周期 ====================

  aboutToAppear() {
    // 获取悬浮窗实例
    try {
      this.floatWindow = window.findWindow('floatPomodoro');
    } catch (err) {
      console.error('[FloatPomodoro] findWindow failed:', err);
    }
  }

  aboutToDisappear() {
    // 清理计时器
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
    }
  }

  // ==================== 窗口操作 ====================

  // 移动悬浮窗
  private moveWindow(offsetX: number, offsetY: number): void {
    if (this.floatWindow) {
      this.dragPosition.x += offsetX;
      this.dragPosition.y += offsetY;
      this.floatWindow.moveWindowTo(this.dragPosition.x, this.dragPosition.y);
    }
  }

  // 关闭悬浮窗
  private closeWindow(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
    }
    if (this.floatWindow) {
      this.floatWindow.destroyWindow();
    }
  }

  // ==================== 计时器逻辑 ====================

  // 开始/继续计时
  private startTimer(): void {
    if (this.timerState === TimerState.RUNNING) {
      return;
    }
    
    this.timerState = TimerState.RUNNING;
    this.timerId = setInterval(() => {
      if (this.remainingSeconds > 0) {
        this.remainingSeconds--;
      } else {
        this.onTimerComplete();
      }
    }, 1000);
  }

  // 暂停计时
  private pauseTimer(): void {
    if (this.timerState !== TimerState.RUNNING) {
      return;
    }
    
    this.timerState = TimerState.PAUSED;
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // 重置计时
  private resetTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    
    this.timerState = TimerState.IDLE;
    this.remainingSeconds = this.isWorkSession ? 25 * 60 : 5 * 60;
  }

  // 计时完成
  private onTimerComplete(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    
    this.timerState = TimerState.IDLE;
    
    // 切换工作/休息模式
    this.isWorkSession = !this.isWorkSession;
    this.remainingSeconds = this.isWorkSession ? 25 * 60 : 5 * 60;
    
    // TODO: 播放提示音
  }

  // 格式化时间显示
  private formatTime(): string {
    const minutes = Math.floor(this.remainingSeconds / 60);
    const seconds = this.remainingSeconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  // 计算进度（0-1）
  private getProgress(): number {
    const total = this.isWorkSession ? 25 * 60 : 5 * 60;
    return (total - this.remainingSeconds) / total;
  }

  // ==================== UI 构建 ====================

  build() {
    Column() {
      // 标题栏（可拖拽）
      Row() {
        // 拖拽手柄图标
        Shape() {
          Path().commands(IconPaths.MENU)
        }
        .width(IconSize.SM)
        .height(IconSize.SM)
        .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        .fill('#78716C')
        
        Text(this.isWorkSession ? '专注中' : '休息中')
          .fontSize(14)
          .fontColor('#1C1917')
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: 8 })
        
        // 关闭按钮
        Button({ type: ButtonType.Circle }) {
          Shape() {
            Path().commands(IconPaths.CLOSE)
          }
          .width(IconSize.SM)
          .height(IconSize.SM)
          .viewPort({ x: 0, y: 0, width: 24, height: 24 })
          .fill('#78716C')
        }
        .width(28)
        .height(28)
        .backgroundColor('#F5F5F4')
        .onClick(() => this.closeWindow())
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 8 })
      .backgroundColor('#FAFAF9')
      .borderRadius({ topLeft: 12, topRight: 12 })
      .gesture(
        PanGesture(this.panOption)
          .onActionUpdate((event: GestureEvent) => {
            this.moveWindow(event.offsetX, event.offsetY);
          })
      )

      // 计时器显示区
      Column({ space: 12 }) {
        // 进度环
        Stack() {
          // 背景圆环
          Circle()
            .width(100)
            .height(100)
            .fill('none')
            .stroke('#E7E5E4')
            .strokeWidth(6)
          
          // 进度圆环
          Circle()
            .width(100)
            .height(100)
            .fill('none')
            .stroke(this.isWorkSession ? '#1C1917' : '#4ADE80')
            .strokeWidth(6)
            .strokeDashArray([Math.PI * 100 * this.getProgress(), Math.PI * 100])
            .rotate({ angle: -90, centerX: '50%', centerY: '50%' })
          
          // 时间文字
          Text(this.formatTime())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1917')
        }

        // 控制按钮
        Row({ space: 16 }) {
          // 重置按钮
          Button({ type: ButtonType.Circle }) {
            Shape() {
              Path().commands(IconPaths.REFRESH)
            }
            .width(IconSize.MD)
            .height(IconSize.MD)
            .viewPort({ x: 0, y: 0, width: 24, height: 24 })
            .fill('#78716C')
          }
          .width(40)
          .height(40)
          .backgroundColor('#E7E5E4')
          .onClick(() => this.resetTimer())
          
          // 开始/暂停按钮
          Button({ type: ButtonType.Circle }) {
            Shape() {
              Path().commands(
                this.timerState === TimerState.RUNNING ? IconPaths.PAUSE : IconPaths.PLAY
              )
            }
            .width(IconSize.LG)
            .height(IconSize.LG)
            .viewPort({ x: 0, y: 0, width: 24, height: 24 })
            .fill('#FFFFFF')
          }
          .width(56)
          .height(56)
          .backgroundColor('#1C1917')
          .onClick(() => {
            if (this.timerState === TimerState.RUNNING) {
              this.pauseTimer();
            } else {
              this.startTimer();
            }
          })
          
          // 跳过按钮
          Button({ type: ButtonType.Circle }) {
            Shape() {
              Path().commands(IconPaths.SKIP_NEXT)
            }
            .width(IconSize.MD)
            .height(IconSize.MD)
            .viewPort({ x: 0, y: 0, width: 24, height: 24 })
            .fill('#78716C')
          }
          .width(40)
          .height(40)
          .backgroundColor('#E7E5E4')
          .onClick(() => this.onTimerComplete())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding(16)
      .backgroundColor('#FAFAF9')
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAF9')
    .borderRadius(12)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.15)',
      offsetX: 0,
      offsetY: 4
    })
  }
}
