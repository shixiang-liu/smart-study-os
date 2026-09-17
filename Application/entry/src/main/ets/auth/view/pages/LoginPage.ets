// 登录页面 - 支持密码登录和验证码登录双模式
// Swiss Spa 极简设计风格
import { promptAction, router } from '@kit.ArkUI'
import { AuthViewModel } from '../../../auth/viewmodel/AuthViewModel'
import window from '@ohos.window'
import { common } from '@kit.AbilityKit'
import { AuthInput, AuthButton, CodeInput, TextLink } from '../../../common/components/AuthComponents'
import { AppColors, AppSizes, AppAnimations, AppGradients, LinearGradient } from '../../../common/utils/AppTheme'

@Entry
@Component
struct LoginPage {
  // 登录模式：0=密码登录, 1=验证码登录
  @State loginType: number = 0
  @State email: string = ''
  @State password: string = ''
  @State verificationCode: string = ''
  @State rememberPassword: boolean = false
  @State isLoading: boolean = false
  @State isSendingCode: boolean = false
  @State countdown: number = 0
  @State pageOpacity: number = 0

  private viewModel: AuthViewModel = new AuthViewModel()

  private timerId: number = -1
  @State topSafeHeight: number = 0

  aboutToAppear() {
    this.initWindow()
    // 页面渐入动画
    setTimeout(() => {
      this.pageOpacity = 1
    }, 50)

    // 加载记住的密码和上次登录的邮箱
    this.loadRememberedData()
  }

  aboutToDisappear() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private async initWindow() {
    try {
      const win = await window.getLastWindow(getContext(this))
      const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      this.topSafeHeight = px2vp(avoidArea.topRect.height)
    } catch (e) {
      this.topSafeHeight = 0
    }
  }

  async loadRememberedData() {
    // 首先尝试获取记住的密码
    const savedInfo = await this.viewModel.getRememberedUser()
    if (savedInfo) {
      this.email = savedInfo.email
      this.password = savedInfo.password
      this.rememberPassword = savedInfo.remember
    } else {
      // 如果没有记住密码，至少回填上次登录的邮箱
      const lastEmail = await this.viewModel.getLastLoginEmail()
      if (lastEmail) {
        this.email = lastEmail
      }
    }
  }

  startCountdown() {
    this.countdown = 60
    this.timerId = setInterval(() => {
      if (this.countdown > 1) {
        this.countdown--
      } else {
        this.countdown = 0
        clearInterval(this.timerId)
        this.timerId = -1
      }
    }, 1000)
  }

  async handleSendCode() {
    if (!this.email.trim()) {
      promptAction.showToast({ message: '请输入邮箱' })
      return
    }

    this.isSendingCode = true
    const result = await this.viewModel.sendVerificationCode(this.email)
    this.isSendingCode = false

    if (result.success) {
      this.startCountdown()
    }
    promptAction.showToast({ message: result.message })
  }

  async handleLogin() {
    if (this.loginType === 0) {
      // 密码登录
      if (!this.email.trim() || !this.password.trim()) {
        promptAction.showToast({ message: '请输入邮箱和密码' })
        return
      }

      this.isLoading = true
      const result = await this.viewModel.loginWithPassword(this.email, this.password)
      this.isLoading = false

      if (result.success) {
        // 保存记住密码
        if (this.rememberPassword) {
          await this.viewModel.saveRememberedUser({
            email: this.email,
            password: this.password,
            remember: true
          })
        } else {
          await this.viewModel.clearRememberedUser()
        }

        promptAction.showToast({ message: '登录成功' })
        setTimeout(() => {
          router.replaceUrl({ url: 'main/view/pages/MainPage' })
        }, 500)
      } else {
        promptAction.showToast({ message: result.message })
      }
    } else {
      // 验证码登录
      if (!this.email.trim() || !this.verificationCode.trim()) {
        promptAction.showToast({ message: '请输入邮箱和验证码' })
        return
      }

      this.isLoading = true
      const result = await this.viewModel.loginWithCode(this.email, this.verificationCode)
      this.isLoading = false

      if (result.success) {
        promptAction.showToast({ message: '登录成功' })
        setTimeout(() => {
          router.replaceUrl({ url: 'main/view/pages/MainPage' })
        }, 500)
      } else {
        promptAction.showToast({ message: result.message })
      }
    }
  }

  @Builder
  PasswordLoginForm() {
    Column() {
      AuthInput({
        label: '邮箱',
        placeholder: '请输入邮箱地址',
        text: $email
      })

      AuthInput({
        label: '密码',
        placeholder: '请输入密码',
        text: $password,
        inputType: InputType.Password
      })

      // 记住密码和忘记密码
      Row() {
        Row() {
          Checkbox()
            .select(this.rememberPassword)
            .selectedColor(AppColors.ACCENT)
            .width(18)
            .height(18)
            .onChange((value: boolean) => {
              this.rememberPassword = value
            })

          Text('记住密码')
            .fontSize(AppSizes.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .margin({ left: AppSizes.SPACE_SM })
        }

        TextLink({
          text: '忘记密码？',
          action: () => {
            router.pushUrl({ url: 'auth/view/pages/ForgotPasswordPage' })
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: AppSizes.SPACE_3XL })
    }
    .width('100%')
  }

  @Builder
  CodeLoginForm() {
    Column() {
      AuthInput({
        label: '邮箱',
        placeholder: '请输入邮箱地址',
        text: $email
      })

      CodeInput({
        label: '验证码',
        placeholder: '请输入验证码',
        text: $verificationCode,
        countdown: this.countdown,
        isSending: this.isSendingCode,
        onSendCode: () => {
          this.handleSendCode()
        }
      })
    }
    .width('100%')
    .margin({ bottom: AppSizes.SPACE_2XL })
  }

  build() {
    Stack() {
      // 顶部装饰渐变圆
      Column()
        .width(300)
        .height(300)
        .linearGradient(AppGradients.SPA_LAVENDER)
        .borderRadius(150)
        .position({ x: -100, y: -150 })
        .opacity(0.6)
      
      Column()
        .width(200)
        .height(200)
        .linearGradient(AppGradients.SPA_PEACH)
        .borderRadius(100)
        .position({ x: 250, y: -80 })
        .opacity(0.5)
      
      Scroll() {
        Column() {
          // 顶部留白 (适配状态栏)
          Blank().height(60 + this.topSafeHeight)

          // APP Logo + 名称
          Column() {
            Image($r('app.media.app_logo'))
              .width(88)
              .height(88)
              .objectFit(ImageFit.Contain)
            Text('智学 OS')
              .fontSize(AppSizes.FONT_LG)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_SECONDARY)
              .margin({ top: AppSizes.SPACE_SM })
          }
          .alignItems(HorizontalAlign.Center)
          .margin({ bottom: AppSizes.SPACE_4XL })

      // 登录方式切换
      Row() {
        Text('密码登录')
          .fontSize(AppSizes.FONT_MD)
          .fontWeight(this.loginType === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.loginType === 0 ? AppColors.TEXT_PRIMARY : AppColors.TEXT_TERTIARY)
          .padding({ bottom: AppSizes.SPACE_SM })
          .border({
            width: { bottom: this.loginType === 0 ? 2 : 0 },
            color: AppColors.TEXT_PRIMARY
          })
          .onClick(() => {
            this.loginType = 0
          })

        Text('验证码登录')
          .fontSize(AppSizes.FONT_MD)
          .fontWeight(this.loginType === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.loginType === 1 ? AppColors.TEXT_PRIMARY : AppColors.TEXT_TERTIARY)
          .margin({ left: AppSizes.SPACE_3XL })
          .padding({ bottom: AppSizes.SPACE_SM })
          .border({
            width: { bottom: this.loginType === 1 ? 2 : 0 },
            color: AppColors.TEXT_PRIMARY
          })
          .onClick(() => {
            this.loginType = 1
          })
      }
      .width('100%')
      .margin({ bottom: AppSizes.SPACE_3XL })

      // 表单区域
      if (this.loginType === 0) {
        this.PasswordLoginForm()
      } else {
        this.CodeLoginForm()
      }

      // 登录按钮
      AuthButton({
        label: '登录',
        isLoading: this.isLoading,
        isEnabled: this.email.length > 0,
        action: () => {
          this.handleLogin()
        }
      })

      // 注册入口
      Row() {
        Text('还没有账户？')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_TERTIARY)

        Text('立即注册')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(AppColors.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)
          .margin({ left: AppSizes.SPACE_XS })
          .onClick(() => {
            router.pushUrl({ url: 'auth/view/pages/RegisterPage' })
          })
      }
      .margin({ top: AppSizes.SPACE_2XL })

      // 底部留白，确保滚动时内容不被遮挡
        Blank().height(60)
      }
      .width('100%')
      .padding({ left: AppSizes.SPACE_3XL, right: AppSizes.SPACE_3XL })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BG_PRIMARY)
    .opacity(this.pageOpacity)
    .animation({ duration: AppAnimations.DURATION_SLOW, curve: Curve.EaseOut })
  }
}