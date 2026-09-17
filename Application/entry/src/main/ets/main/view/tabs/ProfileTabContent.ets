/**
 * @file ProfileTabContent.ets
 * @description 我的 Tab - 个人中心（从 MainPage 提取的独立组件）
 * @module main/view/tabs
 */

import { router, promptAction } from '@kit.ArkUI'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { ConfigurationConstant, common } from '@kit.AbilityKit'
import { AppColors, AppSizes, AppGradients, AppShadows, AppThemeManager } from '../../../common/utils/AppTheme'
import { CloudDBService } from '../../../common/services/CloudDBService'
import { PreferencesUtil } from '../../../common/utils/PreferencesUtil'
import { AuthViewModel } from '../../../auth/viewmodel/AuthViewModel'
import { User } from '../../../auth/model/User'
import fs from '@ohos.file.fs'
import { fileUri } from '@kit.CoreFileKit'

@Component
export struct ProfileTabContent {
  @StorageLink('currentUserId') userId: string = ''
  @StorageLink('currentUserNickname') nickname: string = ''
  @StorageLink('currentUserEmail') userEmail: string = ''
  @StorageLink('currentUserAvatar') userAvatar: string = ''
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @State showProfileSheet: boolean = false
  @State activeProfileSheet: 'nickname' | 'avatar' = 'nickname'
  @State newNickname: string = ''
  @State selectedAvatarIndex: number = -1

  // 默认头像列表
  private defaultAvatars: string[] = [
    '👤', '🧑‍🎓', '👨‍💻', '👩‍🔬', '🧑‍🎨', '👨‍🚀',
    '🦊', '🐱', '🐶', '🐼', '🦁', '🐨',
    '🌟', '🌈', '🌸', '🍀', '🎯', '💎'
  ]

  private getDefaultAvatar(): string {
    if (this.nickname && this.nickname.length > 0) {
      return this.nickname.charAt(0).toUpperCase()
    }
    return '👤'
  }

  private getAvatarBg(): string {
    // 返回字符串颜色，避免 Color 类型混用
    return this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.WHITE
  }

  private getAvatarBorder(): string {
    return this.isDarkMode ? AppColors.BORDER_DARK : AppColors.WHITE
  }

  private getAvatarTextColor(): string {
    return this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY
  }

  private cloudDBService = CloudDBService.getInstance()

  private async copyToSandbox(uri: string): Promise<string> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const filesDir = context.filesDir
      const timestamp = Date.now()
      const fileExt = 'jpg' //假设
      const fileName = `avatar_${timestamp}.${fileExt}`
      const destPath = `${filesDir}/${fileName}`
      
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.copyFileSync(file.fd, destFile.fd)
      fs.closeSync(file)
      fs.closeSync(destFile)
      
      return fileUri.getUriFromPath(destPath)
    } catch (e) {
      console.error('Copy avatar failed:', e)
      return uri
    }
  }

  build() {
    Column() {
      // 问题3修复：顶部背景 - 使用Swiss Spa风格渐变
      Column()
        .width('100%')
        .height(240)
        .linearGradient(this.isDarkMode ? {
          angle: 180,
          colors: [['#1C1C1E', 0], ['#2C2C2E', 1]]
        } : {
          angle: 180,
          colors: [['#E6F3F0', 0], ['#F7F5F2', 1]]  // Swiss Spa薄荷绿渐变
        })
        .borderRadius({ bottomLeft: 40, bottomRight: 40 })

      // 头像卡片 (悬浮) - 可点击更换头像
      Column() {
        Stack() {
          if (this.userAvatar && this.userAvatar.length <= 2) {
            // Emoji 头像
            Text(this.userAvatar)
              .fontSize(48)
              .width(80)
              .height(80)
              .textAlign(TextAlign.Center)
              .fontColor(this.getAvatarTextColor())
              .backgroundColor(this.getAvatarBg())
              .borderRadius(40)
              .border({ width: 4, color: this.getAvatarBorder() })
          } else if (this.userAvatar) {
            // 图片头像
            Image(this.userAvatar)
              .width(80)
              .height(80)
              .borderRadius(40)
              .backgroundColor(this.getAvatarBg())
              .border({ width: 4, color: this.getAvatarBorder() })
          } else {
          // 默认头像（昵称首字母或 emoji）
          Text(this.getDefaultAvatar())
            .fontSize(32)
            .fontWeight(FontWeight.Medium)
            .width(80)
            .height(80)
            .textAlign(TextAlign.Center)
            .fontColor(this.getAvatarTextColor())
            .backgroundColor(this.getAvatarBg())
            .borderRadius(40)
            .border({ width: 4, color: this.getAvatarBorder() })
          }
          // 编辑图标
          Text('📷')
            .fontSize(16)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .backgroundColor(AppColors.ACCENT)
            .borderRadius(14)
            .position({ x: 56, y: 56 })
        }
        .onClick(() => {
          this.activeProfileSheet = 'avatar'
          this.selectedAvatarIndex = -1
          this.showProfileSheet = true
        })

        Text(this.nickname || '学习者')
          .fontSize(AppSizes.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_PRIMARY : AppColors.TEXT_PRIMARY)
          .margin({ top: AppSizes.SPACE_MD })

        Text(this.userEmail ? `邮箱: ${this.userEmail.replace(/(.{3}).*(@.*)/, '$1***$2')}` : '')
          .fontSize(AppSizes.FONT_SM)
          .fontColor(this.isDarkMode ? AppColors.TEXT_DARK_TERTIARY : AppColors.TEXT_TERTIARY)
          .margin({ top: AppSizes.SPACE_XS })
      }
      .margin({ top: -60 })

      // 设置列表
      Column({ space: AppSizes.SPACE_MD }) {
        // 修改昵称
        this.SettingItem('👤', '修改昵称', () => {
          this.newNickname = this.nickname || ''
          this.activeProfileSheet = 'nickname'
          this.showProfileSheet = true
        })

        // 深色模式开关
        Row() {
          Text('🌓').fontSize(20)
          Text('深色模式')
            .fontSize(AppSizes.FONT_MD)
            .margin({ left: AppSizes.SPACE_MD })
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.isDarkMode })
            .selectedColor(AppColors.ACCENT)
            .onChange(async (isOn: boolean) => {
              this.isDarkMode = isOn
              AppStorage.setOrCreate('isDarkMode', isOn)
              AppThemeManager.setIsDarkMode(isOn)
              // 持久化设置
              try {
                await PreferencesUtil.put('isDarkMode', isOn)
              } catch (e) {
                console.error('保存深色模式设置失败:', e)
              }
              // 即时切换系统颜色模式
              try {
                const appContext: common.ApplicationContext = getContext(this).getApplicationContext() as common.ApplicationContext
                const colorMode = isOn
                  ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                  : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
                appContext.setColorMode(colorMode)
                console.info(`[MainPage] 已切换系统颜色模式: ${isOn ? 'DARK' : 'LIGHT'}`)
              } catch (e) {
                console.error('[MainPage] 切换系统颜色模式失败:', e)
              }
              promptAction.showToast({ message: isOn ? '已切换深色模式' : '已切换浅色模式' })
            })
        }
        .width('100%')
        .padding(AppSizes.SPACE_LG)
        .backgroundColor(this.isDarkMode ? AppColors.BG_DARK_SECONDARY : AppColors.BG_SECONDARY)
        .borderRadius(AppSizes.RADIUS_LG)
        .shadow(AppShadows.SHADOW_SM)

        // 清空数据（测试功能）
        this.SettingItem('🗑️', '清空数据（测试）', () => {
          AlertDialog.show({
            title: '警告',
            message: '确定要清空所有本地数据吗？此操作不可恢复！',
            primaryButton: {
              value: '取消',
              action: () => {}
            },
            secondaryButton: {
              value: '确定清空',
              fontColor: AppColors.ERROR,
              action: async () => {
                try {
                  promptAction.showToast({ message: '正在清空数据...' })
                  
                  // 1. AGConnect 退出登录（重要！清空数据前必须退出）
                  try {
                    const agconnect = await import('@hw-agconnect/api-ohos')
                    await agconnect.default.auth().signOut()
                    console.info('[MainPage] AGConnect 已退出登录')
                  } catch (e) {
                    console.warn('[MainPage] AGConnect 退出登录失败（可能未登录）:', e)
                  }
                  
                  // 2. 清空云端数据
                  const cloudDB = CloudDBService.getInstance()
                  try {
                    await cloudDB.clearAllData()
                    console.info('[MainPage] 云端数据已清空')
                  } catch (e) {
                    console.error('[MainPage] 清空云端数据失败:', e)
                  }
                  
                  // 3. 清空 Preferences 存储（使用 UIAbilityContext 保持与日记加载一致）
                  const abilityContext = getContext(this) as common.UIAbilityContext
                  await PreferencesUtil.clearAllData(abilityContext)
                  
                  // 4. 清空 AppStorage（包括暗色模式）
                  AppStorage.setOrCreate('isLoggedIn', false)
                  AppStorage.setOrCreate('currentUserId', '')
                  AppStorage.setOrCreate('currentUserEmail', '')
                  AppStorage.setOrCreate('currentUserNickname', '')
                  AppStorage.setOrCreate('currentUserAvatar', '')
                  AppStorage.setOrCreate('goalUpdatedAt', 0)
                  AppStorage.setOrCreate('shouldShowAIDialog', false)
                  AppStorage.setOrCreate('pendingAIGoals', '[]')
                  AppStorage.setOrCreate('pendingAITodos', '[]')
                  AppStorage.setOrCreate('isDarkMode', false)  // 重置暗色模式
                  this.isDarkMode = false  // 立即生效
                  
                  promptAction.showToast({ message: '本地和云端数据已全部清空' })
                  
                  // 5. 跳转到登录页
                  setTimeout(() => {
                    router.replaceUrl({ url: 'auth/view/pages/LoginPage' })
                  }, 800)
                } catch (e) {
                  console.error('[MainPage] 清空数据失败:', e)
                  promptAction.showToast({ message: '清空失败，请重试' })
                }
              }
            }
          })
        })

        // 退出登录
        this.SettingItem('🚪', '退出登录', () => {
          AlertDialog.show({
            title: '提示',
            message: '确定要退出登录吗？',
            primaryButton: {
              value: '取消',
              action: () => {}
            },
            secondaryButton: {
              value: '退出',
              fontColor: AppColors.ERROR,
              action: async () => {
                // 使用 AuthViewModel 退出登录（包含 AGConnect signOut）
                const authVM = new AuthViewModel()
                await authVM.logout()
                
                promptAction.showToast({ message: '已退出登录' })
                router.replaceUrl({ url: 'auth/view/pages/LoginPage' })
              }
            }
          })
        })
      }
      .padding(AppSizes.SPACE_XL)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .bindSheet(
      $$this.showProfileSheet,
      this.activeProfileSheet === 'nickname'
        ? this.EditNicknameSheet()
        : this.AvatarPickerSheet(),
      {
        height: this.activeProfileSheet === 'nickname' ? 500 : 700,
        showClose: true,
        dragBar: true,
        title: { title: this.activeProfileSheet === 'nickname' ? '修改昵称' : '选择头像' }
      }
    )
  }

  @Builder
  EditNicknameSheet() {
    Column({ space: AppSizes.SPACE_LG }) {
      TextInput({ placeholder: '请输入新昵称', text: this.newNickname })
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.BG_TERTIARY)
        .borderRadius(AppSizes.RADIUS_MD)
        .padding({ left: AppSizes.SPACE_LG, right: AppSizes.SPACE_LG })
        .onChange((value: string) => {
          this.newNickname = value
        })

      Button('保存')
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.ACCENT)
        .borderRadius(24)
        .onClick(async () => {
          const trimmedNickname = this.newNickname.trim()
          if (trimmedNickname) {
            // 更新 AppStorage
            AppStorage.setOrCreate('currentUserNickname', trimmedNickname)
            // 持久化到 Preferences
            try {
              await PreferencesUtil.put('currentUserNickname', trimmedNickname)
            } catch (e) {
              console.error('保存昵称到Preferences失败:', e)
            }
            // 同步到云端用户数据 - 优先使用 userId，如果没有则尝试 email
            try {
              let user: User | null = null
              if (this.userId) {
                user = await this.cloudDBService.getUser(this.userId)
              }
              if (!user && this.userEmail) {
                user = await this.cloudDBService.getUserByEmail(this.userEmail)
              }
              if (user) {
                user.nickname = trimmedNickname
                await this.cloudDBService.upsertUser(user)
                console.info('昵称已同步到云端:', trimmedNickname)
              }
            } catch (e) {
              console.error('同步昵称到云端失败:', e)
            }
            this.showProfileSheet = false
            promptAction.showToast({ message: '昵称修改成功' })
          } else {
            promptAction.showToast({ message: '昵称不能为空' })
          }
        })
    }
    .width('100%')
    .padding(AppSizes.SPACE_XL)
  }

  @Builder
  AvatarPickerSheet() {
    Column({ space: AppSizes.SPACE_LG }) {
      Text('选择默认头像')
        .fontSize(AppSizes.FONT_MD)
        .fontColor(AppColors.TEXT_SECONDARY)
        .width('100%')

      // 默认头像网格
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.defaultAvatars, (avatar: string, index: number) => {
          Column() {
            Text(avatar)
              .fontSize(32)
          }
          .width(56)
          .height(56)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.selectedAvatarIndex === index ? AppColors.ACCENT_BG : AppColors.BG_TERTIARY)
          .borderRadius(28)
          .border({
            width: this.selectedAvatarIndex === index ? 2 : 0,
            color: AppColors.ACCENT
          })
          .margin(6)
          .onClick(() => {
            this.selectedAvatarIndex = index
          })
        })
      }
      .width('100%')

      // 从相册选择
      Button('从相册选择')
        .width('100%')
        .height(44)
        .backgroundColor(AppColors.BG_TERTIARY)
        .fontColor(AppColors.TEXT_PRIMARY)
        .borderRadius(22)
        .onClick(async () => {
          try {
            const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
            photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
            photoSelectOptions.maxSelectNumber = 1
            const photoPicker = new photoAccessHelper.PhotoViewPicker()
            const result = await photoPicker.select(photoSelectOptions)
            if (result.photoUris && result.photoUris.length > 0) {
              const uri = result.photoUris[0]
              const sandboxUri = await this.copyToSandbox(uri)
              await this.saveAvatar(sandboxUri)
              this.showProfileSheet = false
            }
          } catch (e) {
            console.error('选择照片失败:', e)
            promptAction.showToast({ message: '选择照片失败' })
          }
        })

      // 确认选择默认头像
      Button('确认')
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.ACCENT)
        .borderRadius(24)
        .onClick(async () => {
          if (this.selectedAvatarIndex >= 0) {
            const avatar = this.defaultAvatars[this.selectedAvatarIndex]
            await this.saveAvatar(avatar)
            this.showProfileSheet = false
            this.selectedAvatarIndex = -1
          } else {
            promptAction.showToast({ message: '请选择一个头像' })
          }
        })
    }
    .width('100%')
    .padding(AppSizes.SPACE_XL)
  }

  private async saveAvatar(avatar: string): Promise<void> {
    // 更新 AppStorage
    AppStorage.setOrCreate('currentUserAvatar', avatar)
    this.userAvatar = avatar
    // 持久化到 Preferences
    try {
      await PreferencesUtil.put('currentUserAvatar', avatar)
    } catch (e) {
      console.error('保存头像到Preferences失败:', e)
    }
    // 同步到云端用户数据 - 优先使用 userId，如果没有则尝试 email
    try {
      let user: User | null = null
      if (this.userId) {
        user = await this.cloudDBService.getUser(this.userId)
      }
      if (!user && this.userEmail) {
        user = await this.cloudDBService.getUserByEmail(this.userEmail)
      }
      if (user) {
        user.avatar = avatar
        await this.cloudDBService.upsertUser(user)
        console.info('头像已同步到云端:', avatar)
      }
    } catch (e) {
      console.error('同步头像到云端失败:', e)
    }
    promptAction.showToast({ message: '头像已更新' })
  }

  @Builder
  SettingItem(icon: string, title: string, action: () => void) {
    Row() {
      Text(icon).fontSize(20)
      Text(title)
        .fontSize(AppSizes.FONT_MD)
        .margin({ left: AppSizes.SPACE_MD })
        .layoutWeight(1)
      Text('›').fontColor(AppColors.TEXT_TERTIARY)
    }
    .width('100%')
    .padding(AppSizes.SPACE_LG)
    .backgroundColor(AppColors.BG_SECONDARY)
    .borderRadius(AppSizes.RADIUS_LG)
    .shadow(AppShadows.SHADOW_SM)
    .onClick(() => {
      // 确保点击必定触发
      try {
        action()
      } catch (e) {
        console.error('SettingItem click error:', e)
        promptAction.showToast({ message: '操作失败，请重试' })
      }
    })
  }
}
