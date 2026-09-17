// 认证服务 - 邮箱验证码登录/注册/密码重置
// 用户数据通过 CloudDBService 同步到云端
// AGConnect Auth 集成：邮箱验证码服务
import { CloudDBService } from '../../common/services/CloudDBService'
import { NotificationService } from '../../common/services/NotificationService'
import { User } from '../model/User'
import { promptAction } from '@kit.ArkUI'
import http from '@ohos.net.http'
import { PreferencesUtil } from '../../common/utils/PreferencesUtil'
import { BusinessError } from '@kit.BasicServicesKit'
// AGConnect Auth SDK
import agconnect from '@hw-agconnect/api-ohos'
import { EmailAuthProvider, EmailUserBuilder, VerifyCodeAction, VerifyCodeSettingBuilder, AGConnectUser } from '@hw-agconnect/auth-ohos'
import { hilog } from '@kit.PerformanceAnalysisKit'
// 导入 SDK 初始化状态检查
import { waitForAGCInit, isAGCInitialized } from '../../entryability/EntryAbility'

// 云函数发送验证码的响应接口
interface SendCodeResponse {
  code: number
  message: string
}

export interface AuthResult {
  success: boolean
  message: string
  user?: User
}

export interface UserCredentials {
  email?: string
  password?: string
  code?: string
  nickname?: string
}

export interface RememberedInfo {
  email: string
  password: string
  remember: boolean
}

// 密码验证结果
export interface ValidationResult {
  valid: boolean
  message: string
}

export class AuthViewModel {
  private cloudDBService: CloudDBService
  private codeEmail: string = ''
  private codeExpireTime: number = 0
  // ========== 模拟验证码测试模式 ==========
  // 当邮箱服务未就绪时，启用此模式进行测试
  // 设置为 false 可切换到真实邮箱验证
  private static MOCK_MODE: boolean = false
  private mockCode: string = ''

  // ========================================

  constructor() {
    this.cloudDBService = CloudDBService.getInstance()
  }

  // 生成6位随机验证码（测试模式用）
  private generateMockCode(): string {
    return Math.floor(100000 + Math.random() * 900000).toString()
  }

  // 密码强度 0-3，用于 UI 进度条
  calculatePasswordStrength(password: string): number {
    if (!password) {
      return 0
    }
    let strength = 0
    if (password.length >= 6) {
      strength++
    }
    if (password.length >= 10) {
      strength++
    }
    if (/[a-z]/.test(password) && /[A-Z]/.test(password)) {
      strength++
    }
    if (/\d/.test(password) && /[!@#$%^&*(),.?":{}|<>]/.test(password)) {
      strength++
    }
    return Math.min(strength, 3)
  }

  // 邮箱格式验证
  validateEmail(email: string): boolean {
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    return emailRegex.test(email)
  }

  // 密码 8-26 位，包含字母和数字（符合 AGConnect 要求）
  validatePassword(password: string): ValidationResult {
    if (!password || password.length < 8) {
      const result: ValidationResult = { valid: false, message: '密码至少需要8位' }
      return result
    }
    if (password.length > 26) {
      const result: ValidationResult = { valid: false, message: '密码最多26位' }
      return result
    }
    if (!/[a-zA-Z]/.test(password)) {
      const result: ValidationResult = { valid: false, message: '密码需要包含字母' }
      return result
    }
    if (!/\d/.test(password)) {
      const result: ValidationResult = { valid: false, message: '密码需要包含数字' }
      return result
    }
    const result: ValidationResult = { valid: true, message: '' }
    return result
  }

  // 发送邮箱验证码（测试模式会显示弹窗，正式模式调用 AGConnect）
  async sendVerificationCode(email: string, actionType: string = 'login'): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      return { success: false, message: '请输入正确的邮箱地址' }
    }

    // ========== 模拟验证码模式 ==========
    if (AuthViewModel.MOCK_MODE) {
      this.mockCode = this.generateMockCode()
      this.codeEmail = email
      this.codeExpireTime = Date.now() + 5 * 60 * 1000 // 5分钟有效期

      console.info(`[AuthViewModel][MOCK] 模拟验证码: ${this.mockCode} 邮箱: ${email}`)

      // 问题10修复: 发送本地通知模拟短信验证码
      const notificationService = NotificationService.getInstance()
      const notificationSent = await notificationService.sendVerificationCodeNotification(this.mockCode)
      
      if (notificationSent) {
        // 通知发送成功
        promptAction.showToast({ 
          message: '验证码已发送到通知栏',
          duration: 2000
        })
      } else {
        // 通知权限未授予，使用弹窗作为备用显示
        promptAction.showDialog({
          title: '验证码',
          message: `您的验证码是：\n\n${this.mockCode}\n\n有效期5分钟`,
          buttons: [{ text: '确定', color: '#1C1917' }]
        })
      }

      return { success: true, message: `验证码已发送` }
    }
    // ====================================

    try {
      // 等待 AGConnect SDK 初始化完成
      hilog.info(0x0000, 'AuthViewModel', 'Waiting for AGConnect SDK initialization...')
      await waitForAGCInit()
      hilog.info(0x0000, 'AuthViewModel', 'AGConnect SDK is ready, sending verification code...')

      // 构建验证码配置（官方推荐用 VerifyCodeSettingBuilder）
      const settings = new VerifyCodeSettingBuilder()
        .setAction(actionType === 'reset' ? VerifyCodeAction.RESET_PASSWORD : VerifyCodeAction.REGISTER_LOGIN)
        .setLang('zh_CN')
        .setSendInterval(60)
        .build()

      // 调用 AGConnect Auth 发送邮箱验证码（带重试机制）
      let lastError: BusinessError | null = null
      for (let attempt = 1; attempt <= 2; attempt++) {
        try {
          hilog.info(0x0000, 'AuthViewModel', `Attempt ${attempt}: Calling requestEmailVerifyCode for ${email}`)
          
          const result = await agconnect.auth().requestEmailVerifyCode(email, settings)
          
          hilog.info(0x0000, 'AuthViewModel', `requestEmailVerifyCode succeeded, interval: ${result.getShortestInterval()}`)
          
          // 记录当前验证邮箱
          this.codeEmail = email
          this.codeExpireTime = Date.now() + 5 * 60 * 1000

          console.info(`[AuthViewModel] 邮箱验证码已发送至: ${email}`)
          return { success: true, message: '验证码已发送，请查收邮件' }
        } catch (e) {
          lastError = e as BusinessError
          hilog.error(0x0000, 'AuthViewModel', `Attempt ${attempt} failed - Code: ${lastError.code}, Message: ${lastError.message}`)
          if (attempt < 2) {
            // 等待 1.5 秒后重试
            await new Promise<void>(resolve => setTimeout(resolve, 1500))
          }
        }
      }      // 所有重试都失败
      const error = lastError!
      console.error('[AuthViewModel] 发送邮箱验证码失败:', JSON.stringify(error))

      // 根据错误码返回友好提示
      const errorCode = error.code || 0
      if (errorCode === 203818048) {
        return { success: false, message: '发送过于频繁，请稍后再试' }
      } else if (errorCode === 203818049) {
        return { success: false, message: '今日发送次数已达上限' }
      } else if (errorCode === 10002 || String(error.message).includes('AGCInstance not inited')) {
        // SDK 初始化失败的特殊处理（通常是网络问题）
        return { success: false, message: '网络不可用，请检查网络连接' }
      }
      return { success: false, message: `发送失败: ${error.message || '未知错误'}` }
    } catch (e) {
      const error = e as BusinessError
      console.error('[AuthViewModel] AGConnect SDK 初始化或验证码发送失败:', JSON.stringify(error))
      return { success: false, message: '网络连接失败，请检查网络' }
    }
  }

  // 发送重置密码验证码
  async sendCodeForReset(email: string): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      return { success: false, message: '请输入正确的邮箱地址' }
    }

    try {
      // 按邮箱检查用户是否存在
      const existingUser = await this.cloudDBService.getUserByEmail(email)
      if (!existingUser) {
        return { success: false, message: '该邮箱未注册' }
      }
    } catch (err) {
      console.error('[AuthViewModel] 检查用户失败:', err)
    }

    return await this.sendVerificationCode(email, 'reset')
  }

  // 注册时发送验证码（会检查邮箱是否已注册）
  async sendCodeForRegister(email: string): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      return { success: false, message: '请输入正确的邮箱地址' }
    }

    try {
      // 按邮箱检查用户是否已存在
      const existingUser = await this.cloudDBService.getUserByEmail(email)
      if (existingUser) {
        return { success: false, message: '该邮箱已注册，如忘记密码请去忘记密码页面重置' }
      }
    } catch (err) {
      console.error('[AuthViewModel] 检查用户失败:', err)
    }

    return await this.sendVerificationCode(email, 'register')
  }

  // 验证邮箱验证码（不退出登录，用于注册流程）
  async verifyEmailCode(email: string, code: string): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      return { success: false, message: '请输入正确的邮箱地址' }
    }
    if (!code || code.length !== 6) {
      return { success: false, message: '请输入6位验证码' }
    }

    // 模拟模式验证
    if (AuthViewModel.MOCK_MODE) {
      if (Date.now() > this.codeExpireTime) {
        return { success: false, message: '验证码已过期，请重新获取' }
      }
      if (email !== this.codeEmail) {
        return { success: false, message: '邮箱与获取验证码时不一致' }
      }
      if (code !== this.mockCode) {
        return { success: false, message: '验证码错误' }
      }
      return { success: true, message: '验证成功' }
    }

    // AGConnect验证 - 使用登录验证验证码，不退出
    try {
      await waitForAGCInit()
      const credential = EmailAuthProvider.credentialWithVerifyCode(email, code)
      await agconnect.auth().signIn(credential)
      // 验证成功，保持登录状态，供后续register方法使用
      console.info('[AuthViewModel] 验证码验证成功，已登录AGConnect')
      return { success: true, message: '验证成功' }
    } catch (err) {
      const error = err as BusinessError
      const errorCode = error.code || 0
      if (errorCode === 203818130) {
        return { success: false, message: '验证码错误' }
      } else if (errorCode === 203818129) {
        return { success: false, message: '验证码已过期' }
      }
      return { success: false, message: '验证失败，请稍后重试' }
    }
  }

  async loginWithPassword(email: string, password: string): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      return { success: false, message: '请输入正确的邮箱地址' }
    }
    if (!password) {
      return { success: false, message: '请输入密码' }
    }

    try {
      // 按邮箱查询用户
      const user = await this.cloudDBService.getUserByEmail(email)
      if (!user) {
        return { success: false, message: '用户不存在' }
      }

      // 简化实现，实际应用哈希比对
      if (user.password_hash !== this.hashPassword(password)) {
        return { success: false, message: '密码错误' }
      }

      await this.saveLoginState(user)

      return { success: true, message: '登录成功', user: user }
    } catch (err) {
      console.error('[AuthViewModel] 登录失败:', err)
      return { success: false, message: '登录失败，请稍后重试' }
    }
  }

  // 验证码登录（用户不存在会自动注册）
  async loginWithCode(email: string, code: string): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      return { success: false, message: '请输入正确的邮箱地址' }
    }
    if (!code || code.length !== 6) {
      return { success: false, message: '请输入6位验证码' }
    }

    // ========== 模拟验证码模式 ==========
    if (AuthViewModel.MOCK_MODE) {
      // 检查验证码是否过期
      if (Date.now() > this.codeExpireTime) {
        return { success: false, message: '验证码已过期，请重新获取' }
      }
      // 检查邮箱是否匹配
      if (email !== this.codeEmail) {
        return { success: false, message: '邮箱与获取验证码时不一致' }
      }
      // 验证模拟验证码
      if (code !== this.mockCode) {
        console.warn(`[AuthViewModel][MOCK] 验证码错误: 输入=${code}, 正确=${this.mockCode}`)
        return { success: false, message: '验证码错误' }
      }

      console.info(`[AuthViewModel][MOCK] 模拟验证码验证成功: ${email}`)

      // 查找或创建本地用户（模拟模式不调用 AGConnect Auth）
      try {
        let user = await this.cloudDBService.getUserByEmail(email)
        if (!user) {
          user = new User()
          user.uid = `mock_${email.split('@')[0]}_${Date.now()}`
          user.email = email
          user.phone = ''
          user.nickname = `用户${email.split('@')[0].slice(-4)}`
          user.avatar = ''
          user.password_hash = ''
          await this.cloudDBService.upsertUser(user)
          console.info('[AuthViewModel][MOCK] 新用户已创建:', email)
        }

        await this.saveLoginState(user)
        // 清除已使用的验证码
        this.mockCode = ''
        this.codeEmail = ''

        return { success: true, message: '登录成功（测试模式）', user: user }
      } catch (err) {
        console.error('[AuthViewModel][MOCK] 用户操作失败:', err)
        return { success: false, message: '登录失败，请稍后重试' }
      }
    }
    // ====================================

    try {
      // 等待 AGConnect SDK 初始化完成
      hilog.info(0x0000, 'AuthViewModel', 'Waiting for AGConnect SDK for code login...')
      await waitForAGCInit()

      // 使用 EmailAuthProvider 创建凭证并登录
      const credential = EmailAuthProvider.credentialWithVerifyCode(email, code)
      const signInResult = await agconnect.auth().signIn(credential)

      // 获取 AGConnect 用户信息
      const agcUser = signInResult.getUser()
      const agcUid: string = agcUser ? agcUser.getUid() : email

      // 查找或创建本地用户
      let user = await this.cloudDBService.getUserByEmail(email)
      if (!user) {
        // 用户不存在，自动注册并同步到云端
        user = new User()
        user.uid = agcUid
        user.email = email
        user.phone = ''
        user.nickname = `用户${email.split('@')[0].slice(-4)}`
        user.avatar = ''
        user.password_hash = ''
        user.create_time = Date.now()
        
        // 同步到云数据库
        await this.cloudDBService.upsertUser(user)
        console.info('[AuthViewModel] AGConnect 验证码登录 - 新用户已创建并同步到云:', email)
      } else {
        console.info('[AuthViewModel] AGConnect 验证码登录 - 用户已存在:', email)
      }

      await this.saveLoginState(user)
      console.info('[AuthViewModel] AGConnect 验证码登录成功:', email)

      return { success: true, message: '登录成功', user: user }
    } catch (err) {
      const error = err as BusinessError
      console.error('[AuthViewModel] AGConnect 验证码登录失败:', JSON.stringify(error))

      // 根据 AGConnect 错误码返回友好提示
      const errorCode = error.code || 0
      if (errorCode === 203818130) {
        return { success: false, message: '验证码错误' }
      } else if (errorCode === 203818129) {
        return { success: false, message: '验证码已过期' }
      } else if (errorCode === 10002 || String(error.message).includes('AGCInstance not inited')) {
        return { success: false, message: '网络不可用，请检查网络连接' }
      }
      return { success: false, message: '登录失败，请稍后重试' }
    }
  }

  // 用户注册（验证码验证后创建用户）
  async register(credentials: UserCredentials): Promise<AuthResult> {
    const email = credentials.email
    const password = credentials.password
    const code = credentials.code
    const nickname = credentials.nickname

    if (!email || !this.validateEmail(email)) {
      const result: AuthResult = { success: false, message: '请输入正确的邮箱地址' }
      return result
    }

    const passwordCheck = this.validatePassword(password || '')
    if (!passwordCheck.valid) {
      const result: AuthResult = { success: false, message: passwordCheck.message }
      return result
    }

    if (!code || code.length !== 6) {
      const result: AuthResult = { success: false, message: '请输入6位验证码' }
      return result
    }

    // ========== 模拟验证码模式 ==========
    if (AuthViewModel.MOCK_MODE) {
      // 检查验证码是否过期
      if (Date.now() > this.codeExpireTime) {
        return { success: false, message: '验证码已过期，请重新获取' }
      }
      // 检查邮箱是否匹配
      if (email !== this.codeEmail) {
        return { success: false, message: '邮箱与获取验证码时不一致' }
      }
      // 验证模拟验证码
      if (code !== this.mockCode) {
        console.warn(`[AuthViewModel][MOCK] 注册验证码错误: 输入=${code}, 正确=${this.mockCode}`)
        return { success: false, message: '验证码错误' }
      }

      try {
        // 检查本地是否已有用户（按邮箱查询）
        const existingUser = await this.cloudDBService.getUserByEmail(email)
        if (existingUser) {
          return { success: false, message: '该邮箱已注册' }
        }

        // 创建本地用户记录（模拟模式不调用 AGConnect Auth）
        // uid 统一使用邮箱前缀，确保查询一致性
        const user = new User()
        user.uid = email.split('@')[0]
        user.email = email
        user.phone = ''
        user.nickname = nickname || `用户${email.split('@')[0].slice(-4)}`
        user.avatar = ''
        user.password_hash = this.hashPassword(password!)
        user.create_time = Date.now()

        await this.cloudDBService.upsertUser(user)
        console.info('[AuthViewModel][MOCK] 模拟注册成功:', email)

        // 清除已使用的验证码
        this.mockCode = ''
        this.codeEmail = ''

        // 注册成功后自动登录
        await this.saveLoginState(user)
        // 保存邮箱供下次登录使用
        await this.saveLastLoginEmail(email)

        return { success: true, message: '注册成功', user: user }
      } catch (err) {
        console.error('[AuthViewModel][MOCK] 注册操作失败:', err)
        return { success: false, message: '注册失败，请稍后重试' }
      }
    }
    // ====================================

    try {
      // 检查AGConnect是否已登录（verifyEmailCode已经登录了）
      const currentUser: AGConnectUser | null = await agconnect.auth().getCurrentUser()
      
      if (currentUser) {
        // 已登录，说明验证码已验证，直接创建本地用户记录
        console.info('[AuthViewModel] 检测到AGConnect已登录，直接完善用户信息')
        const agcUid: string = currentUser.getUid()
        
        // 检查本地是否已有用户
        let existingUser = await this.cloudDBService.getUserByEmail(email)
        if (existingUser) {
          // 更新密码和昵称
          existingUser.password_hash = this.hashPassword(password!)
          existingUser.nickname = nickname || existingUser.nickname
          await this.cloudDBService.upsertUser(existingUser)
          await this.saveLoginState(existingUser)
          await this.saveLastLoginEmail(email)
          return { success: true, message: '注册成功', user: existingUser }
        }
        
        // 创建新用户
        const user = new User()
        user.uid = agcUid
        user.email = email
        user.phone = ''
        user.nickname = nickname || `用户${email.split('@')[0].slice(-4)}`
        user.avatar = ''
        user.password_hash = this.hashPassword(password!)
        user.create_time = Date.now()
        await this.cloudDBService.upsertUser(user)
        await this.saveLoginState(user)
        await this.saveLastLoginEmail(email)
        console.info('[AuthViewModel] 注册成功（基于已登录状态）:', email)
        return { success: true, message: '注册成功', user: user }
      }

      // 未登录，使用传统方式创建用户（不应该走到这里）
      console.warn('[AuthViewModel] AGConnect未登录，使用createEmailUser方式注册')
      
      // 检查本地是否已有用户（按邮箱查询）
      let existingUser = await this.cloudDBService.getUserByEmail(email)
      if (existingUser) {
        console.info('[AuthViewModel] 用户已存在，更新密码并完善信息:', email)
        existingUser.password_hash = this.hashPassword(password!)
        existingUser.nickname = nickname || existingUser.nickname
        await this.cloudDBService.upsertUser(existingUser)
        await this.saveLoginState(existingUser)
        await this.saveLastLoginEmail(email)
        return { success: true, message: '账户信息已完善', user: existingUser }
      }

      // 使用 EmailUserBuilder 构建用户并创建
      const emailUser = new EmailUserBuilder()
        .setEmail(email)
        .setVerifyCode(code)
        .setPassword(password!)
        .build()
      await agconnect.auth().createEmailUser(emailUser)

      // 创建本地用户记录
      const user = new User()
      user.uid = email.split('@')[0]
      user.email = email
      user.phone = ''
      user.nickname = nickname || `用户${email.split('@')[0].slice(-4)}`
      user.avatar = ''
      user.password_hash = this.hashPassword(password!)
      user.create_time = Date.now()

      await this.cloudDBService.upsertUser(user)
      console.info('[AuthViewModel] AGConnect 用户注册成功:', email)

      // 注册成功后自动登录
      await this.saveLoginState(user)
      // 保存邮箱供下次登录使用
      await this.saveLastLoginEmail(email)

      return { success: true, message: '注册成功', user: user }
    } catch (err) {
      const error = err as BusinessError
      console.error('[AuthViewModel] AGConnect 注册失败:', JSON.stringify(error))

      const errorCode = error.code || 0
      if (errorCode === 203818130) {
        return { success: false, message: '验证码错误' }
      } else if (errorCode === 203818129) {
        return { success: false, message: '验证码已过期' }
      } else if (errorCode === 203818037) {
        return { success: false, message: '该邮箱已注册' }
      }
      return { success: false, message: '注册失败，请稍后重试' }
    }
  }

  // 重置密码
  async resetPassword(email: string, code: string, newPassword: string): Promise<AuthResult> {
    if (!this.validateEmail(email)) {
      const result: AuthResult = { success: false, message: '请输入正确的邮箱地址' }
      return result
    }

    if (!code || code.length !== 6) {
      const result: AuthResult = { success: false, message: '请输入6位验证码' }
      return result
    }

    const passwordCheck = this.validatePassword(newPassword)
    if (!passwordCheck.valid) {
      const result: AuthResult = { success: false, message: passwordCheck.message }
      return result
    }

    // ========== 模拟验证码模式 ==========
    if (AuthViewModel.MOCK_MODE) {
      // 检查验证码是否过期
      if (Date.now() > this.codeExpireTime) {
        return { success: false, message: '验证码已过期，请重新获取' }
      }
      // 检查邮箱是否匹配
      if (email !== this.codeEmail) {
        return { success: false, message: '邮箱与获取验证码时不一致' }
      }
      // 验证模拟验证码
      if (code !== this.mockCode) {
        console.warn(`[AuthViewModel][MOCK] 重置密码验证码错误: 输入=${code}, 正确=${this.mockCode}`)
        return { success: false, message: '验证码错误' }
      }

      try {
        // 更新本地用户密码（模拟模式不调用 AGConnect Auth）
        const user = await this.cloudDBService.getUserByEmail(email)
        if (!user) {
          return { success: false, message: '用户不存在' }
        }

        user.password_hash = this.hashPassword(newPassword)
        await this.cloudDBService.upsertUser(user)

        console.info('[AuthViewModel][MOCK] 模拟密码重置成功:', email)

        // 清除已使用的验证码
        this.mockCode = ''
        this.codeEmail = ''

        return { success: true, message: '密码重置成功（测试模式）' }
      } catch (err) {
        console.error('[AuthViewModel][MOCK] 重置密码操作失败:', err)
        return { success: false, message: '重置密码失败，请稍后重试' }
      }
    }
    // ====================================

    try {
      // 使用 AGConnect Auth 重置密码
      await agconnect.auth().resetPasswordByEmail(email, newPassword, code)

      // 同步更新本地用户密码
      const user = await this.cloudDBService.getUserByEmail(email)
      if (user) {
        user.password_hash = this.hashPassword(newPassword)
        await this.cloudDBService.upsertUser(user)
      }

      console.info('[AuthViewModel] AGConnect 密码重置成功:', email)
      return { success: true, message: '密码重置成功' }
    } catch (err) {
      const error = err as BusinessError
      console.error('[AuthViewModel] AGConnect 重置密码失败:', JSON.stringify(error))

      const errorCode = error.code || 0
      if (errorCode === 203818130) {
        return { success: false, message: '验证码错误' }
      } else if (errorCode === 203818129) {
        return { success: false, message: '验证码已过期' }
      }
      return { success: false, message: '重置失败，请稍后重试' }
    }
  }

  // 简化哈希，生产环境应使用 bcrypt/PBKDF2
  private hashPassword(password: string): string {
    let hash = 0
    for (let i = 0; i < password.length; i++) {
      const char = password.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return `hash_${Math.abs(hash).toString(16)}`
  }

  // 登录后存储用户信息到 AppStorage，供全局访问
  private async saveLoginState(user: User): Promise<void> {
    try {
      AppStorage.setOrCreate('isLoggedIn', true)
      AppStorage.setOrCreate('currentUserId', user.uid)
      AppStorage.setOrCreate('currentUserEmail', user.email || '')
      AppStorage.setOrCreate('currentUserPhone', user.phone || '')
      AppStorage.setOrCreate('currentUserNickname', user.nickname)
      AppStorage.setOrCreate('currentUserAvatar', user.avatar)

      // 持久化到 Preferences（包含所有关键信息）
      await PreferencesUtil.put('isLoggedIn', true)
      await PreferencesUtil.put('currentUserId', user.uid)
      await PreferencesUtil.put('currentUserEmail', user.email || '')
      await PreferencesUtil.put('currentUserPhone', user.phone || '')
      await PreferencesUtil.put('currentUserNickname', user.nickname)
      await PreferencesUtil.put('currentUserAvatar', user.avatar || '')

      // 保存最后登录的邮箱（无论是否勾选记住密码）
      if (user.email) {
        await this.saveLastLoginEmail(user.email)
      }

      console.info('[AuthViewModel] 登录状态已保存:', user.email || user.uid)
    } catch (err) {
      console.error('[AuthViewModel] 保存登录状态失败:', err)
    }
  }

  // 保存最后登录的邮箱（始终保存，与记住密码无关）
  async saveLastLoginEmail(email: string): Promise<void> {
    try {
      await PreferencesUtil.put('last_login_email', email)
    } catch (err) {
      console.error('[AuthViewModel] 保存邮箱失败:', err)
    }
  }

  // 获取最后登录的邮箱
  async getLastLoginEmail(): Promise<string> {
    try {
      const email = await PreferencesUtil.get<string>('last_login_email', '')
      return email || ''
    } catch (err) {
      return ''
    }
  }

  async logout(): Promise<void> {
    try {
      // AGConnect 退出登录（使用官方 API）
      try {
        await agconnect.auth().signOut()
      } catch (e) {
        // 忽略 AGConnect 退出错误（可能未登录）
      }

      AppStorage.setOrCreate('isLoggedIn', false)
      AppStorage.setOrCreate('currentUserId', '')
      AppStorage.setOrCreate('currentUserEmail', '')
      AppStorage.setOrCreate('currentUserPhone', '')
      AppStorage.setOrCreate('currentUserNickname', '')
      AppStorage.setOrCreate('currentUserAvatar', '')

      await PreferencesUtil.put('isLoggedIn', false)
      await PreferencesUtil.put('currentUserId', '')
      await PreferencesUtil.put('currentUserEmail', '')
      await PreferencesUtil.put('currentUserPhone', '')
      // 注意：不清除 last_login_email，保留邮箱供下次登录
      console.info('[AuthViewModel] 已退出登录')
    } catch (err) {
      console.error('[AuthViewModel] 退出登录失败:', err)
    }
  }

  // "记住密码"功能 - 存储到本地 Preferences
  async saveRememberedUser(info: RememberedInfo): Promise<void> {
    try {
      await PreferencesUtil.put('remembered_email', info.email)
      await PreferencesUtil.put('remembered_password', info.password)
      await PreferencesUtil.put('remember_password', info.remember)
    } catch (err) {
      console.error('[AuthViewModel] 保存记住密码失败:', err)
    }
  }

  async getRememberedUser(): Promise<RememberedInfo | null> {
    try {
      const remember = await PreferencesUtil.get<boolean>('remember_password', false)
      if (!remember) {
        return null
      }

      const email = await PreferencesUtil.get<string>('remembered_email', '')
      const password = await PreferencesUtil.get<string>('remembered_password', '')

      if (email && password) {
        const result: RememberedInfo = { email, password, remember }
        return result
      }
      return null
    } catch (err) {
      console.error('[AuthViewModel] 获取记住密码失败:', err)
      return null
    }
  }

  async clearRememberedUser(): Promise<void> {
    try {
      await PreferencesUtil.delete('remembered_email')
      await PreferencesUtil.delete('remembered_password')
      await PreferencesUtil.put('remember_password', false)
    } catch (err) {
      console.error('[AuthViewModel] 清除记住密码失败:', err)
    }
  }

  // 启动时检查是否已登录，并恢复AppStorage状态
  async checkLoginState(): Promise<boolean> {
    try {
      const isLoggedIn = await PreferencesUtil.get<boolean>('isLoggedIn', false)
      if (isLoggedIn) {
        // 从Preferences恢复数据到AppStorage
        const userId = await PreferencesUtil.get<string>('currentUserId', '')
        const email = await PreferencesUtil.get<string>('currentUserEmail', '')
        const phone = await PreferencesUtil.get<string>('currentUserPhone', '')
        const nickname = await PreferencesUtil.get<string>('currentUserNickname', '')
        const avatar = await PreferencesUtil.get<string>('currentUserAvatar', '')

        AppStorage.setOrCreate('isLoggedIn', true)
        AppStorage.setOrCreate('currentUserId', userId)
        AppStorage.setOrCreate('currentUserEmail', email)
        AppStorage.setOrCreate('currentUserPhone', phone)
        AppStorage.setOrCreate('currentUserNickname', nickname)
        AppStorage.setOrCreate('currentUserAvatar', avatar)

        console.info('[AuthViewModel] 已恢复登录状态:', email || userId)
        return true
      }
      return false
    } catch (err) {
      console.error('[AuthViewModel] 检查登录状态失败:', err)
      return false
    }
  }

  async getCurrentUser(): Promise<User | null> {
    try {
      const userId = await PreferencesUtil.get<string>('currentUserId', '')
      if (!userId || userId === '') {
        return null
      }
      return await this.cloudDBService.getUser(userId)
    } catch (err) {
      console.error('[AuthViewModel] 获取当前用户失败:', err)
      return null
    }
  }
}
