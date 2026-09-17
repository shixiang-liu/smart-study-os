/**
 * @file ProfilePage.ets
 * @description 个人中心页面 - 用户信息、设置、数据管理
 * @features
 * - 用户信息展示
 * - 头像选择（从相册）
 * - 一键清空数据（开发调试用）
 * - 设置选项
 */

import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import window from '@ohos.window';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CloudDiaryService, CloudDataStats } from '../../../common/services/CloudDiaryService';
import { PreferencesUtil } from '../../../common/utils/PreferencesUtil';
import { AppColors, AppSizes, getCardShadow } from '../../../common/utils/AppTheme';
import common from '@ohos.app.ability.common';

@Entry
@Component
struct ProfilePage {
  /** 顶部安全区高度 */
  @State topSafeHeight: number = 0;
  /** 底部安全区高度 */
  @State bottomSafeHeight: number = 0;
  /** 是否正在清除数据 */
  @State isClearing: boolean = false;
  /** 是否正在加载云端状态 */
  @State isLoadingCloudStats: boolean = false;
  /** 用户昵称 */
  @State nickname: string = '用户';
  /** 本地日记数量 */
  @State diaryCount: number = 0;
  /** 云端数据统计 */
  @State cloudStats: CloudDataStats | null = null;
  /** 云端错误信息 */
  @State cloudError: string = '';
  /** 用户头像 PixelMap */
  @State avatarImage: PixelMap | undefined = undefined;
  /** 用户头像 URI（持久化保存） */
  @State avatarUri: string = '';

  aboutToAppear() {
    this.setFullScreen();
    this.loadUserInfo();
    this.loadCloudStats();
    this.loadAvatarFromStorage();
  }

  async setFullScreen() {
    try {
      const windowClass = await window.getLastWindow(getContext(this));
      await windowClass.setWindowLayoutFullScreen(true);
      const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topSafeHeight = px2vp(avoidArea.topRect.height);
      this.bottomSafeHeight = px2vp(avoidArea.bottomRect.height);
    } catch (e) {
      this.topSafeHeight = 44;
      this.bottomSafeHeight = 34;
    }
  }

  async loadUserInfo() {
    try {
      const context = getContext() as common.Context;
      const notes = await PreferencesUtil.loadNotes(context);
      this.diaryCount = notes.length;
    } catch (error) {
      console.error('加载用户信息失败:', error);
    }
  }

  // 从本地存储加载头像
  async loadAvatarFromStorage() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const avatarPath = context.filesDir + '/user_avatar.jpg';
      
      // 检查文件是否存在
      const exists = fileIo.accessSync(avatarPath);
      if (exists) {
        this.avatarUri = fileUri.getUriFromPath(avatarPath);
        await this.loadAvatarPixelMap();
        // 同步到全局存储
        AppStorage.setOrCreate('currentUserAvatar', this.avatarUri);
      }
    } catch (err) {
      console.info('[ProfilePage] 未找到已保存的头像');
    }
  }

  // 加载头像 PixelMap
  async loadAvatarPixelMap() {
    if (!this.avatarUri) return;
    
    try {
      const file = fileIo.openSync(this.avatarUri, fileIo.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      this.avatarImage = await imageSource.createPixelMap();
      fileIo.closeSync(file.fd);
    } catch (err) {
      console.error('[ProfilePage] 加载头像失败:', err);
    }
  }

  // 选择头像图片
  async pickAvatar() {
    try {
      // 配置图片选择器
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;

      // 打开图片选择器
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);

      if (result.photoUris.length === 0) {
        return;
      }

      const selectedUri = result.photoUris[0];
      console.info('[ProfilePage] 选择图片:', selectedUri);

      // 将图片拷贝到应用沙箱（持久化）
      const context = getContext(this) as common.UIAbilityContext;
      const avatarPath = context.filesDir + '/user_avatar.jpg';

      // 读取选中的图片
      const srcFile = fileIo.openSync(selectedUri, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(avatarPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile.fd);
      fileIo.closeSync(destFile.fd);

      // 更新 URI 并加载 PixelMap
      this.avatarUri = fileUri.getUriFromPath(avatarPath);
      await this.loadAvatarPixelMap();

      // 同步到全局存储
      AppStorage.setOrCreate('currentUserAvatar', this.avatarUri);

      promptAction.showToast({ message: '头像已更新', duration: 1500 });
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[ProfilePage] 选择头像失败: ${error.code} - ${error.message}`);
      promptAction.showToast({ message: '选择头像失败', duration: 1500 });
    }
  }

  /**
   * 加载云端数据统计
   */
  async loadCloudStats() {
    this.isLoadingCloudStats = true;
    this.cloudError = '';
    try {
      const cloudService = CloudDiaryService.getInstance();
      await cloudService.initialize();
      this.cloudStats = await cloudService.getCloudDataStats();
      
      // 检查连接状态和错误信息
      if (!this.cloudStats.isConnected) {
        this.cloudError = this.cloudStats.errorMessage || '云端连接失败';
      }
    } catch (error) {
      console.error('加载云端状态失败:', error);
      this.cloudStats = null;
      // 解析错误码
      const errorObj = error as Record<string, number | string>;
      if (errorObj && errorObj.code) {
        const code = Number(errorObj.code);
        switch (code) {
          case 2300006:
            this.cloudError = '网络错误: DNS解析失败，请检查网络';
            break;
          case 1008200002:
            this.cloudError = '服务器连接失败，请稍后重试';
            break;
          case 1008200003:
          case 1008232001:
            this.cloudError = '认证失败: 请先登录华为账号';
            break;
          default:
            this.cloudError = `连接失败 (${code}): ${errorObj.message || ''}`;
        }
      } else {
        this.cloudError = String(errorObj?.message || '未知错误，请检查网络');
      }
    } finally {
      this.isLoadingCloudStats = false;
    }
  }

  /**
   * 显示清空数据确认对话框
   */
  showClearDataDialog() {
    AlertDialog.show({
      title: '⚠️ 危险操作',
      message: '确定要清空所有数据吗？\n\n这将删除：\n• 所有日记 (Diary)\n• 所有目标 (Goal)\n• 所有记忆 (Memory)\n\n此操作不可恢复！',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        fontColor: AppColors.TEXT_SECONDARY,
        action: () => {}
      },
      secondaryButton: {
        value: '确认清空',
        fontColor: '#EF4444',
        action: () => {
          this.showSecondConfirmDialog();
        }
      }
    });
  }

  /**
   * 二次确认对话框
   */
  showSecondConfirmDialog() {
    AlertDialog.show({
      title: '最后确认',
      message: '真的要删除所有数据吗？\n请输入 "确认删除" 继续',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        fontColor: AppColors.TEXT_SECONDARY,
        action: () => {}
      },
      secondaryButton: {
        value: '我确定要删除',
        fontColor: '#EF4444',
        action: () => {
          this.clearAllData();
        }
      }
    });
  }

  /**
   * 执行清空数据操作
   */
  async clearAllData() {
    this.isClearing = true;
    
    try {
      // 1. 清空云端数据
      const cloudService = CloudDiaryService.getInstance();
      await cloudService.initialize();
      const cloudResult = await cloudService.clearAllData();
      
      // 2. 清空本地数据
      const context = getContext() as common.Context;
      await PreferencesUtil.clearAllData(context);
      
      // 3. 更新UI
      this.diaryCount = 0;
      
      promptAction.showToast({
        message: cloudResult ? '所有数据已清空' : '本地数据已清空，云端清空可能失败',
        duration: 2000
      });
      
    } catch (error) {
      console.error('清空数据失败:', error);
      promptAction.showToast({
        message: '清空数据失败，请重试',
        duration: 2000
      });
    } finally {
      this.isClearing = false;
    }
  }

  build() {
    Column() {
      // 顶部安全区
      Column()
        .width('100%')
        .height(this.topSafeHeight)
        .backgroundColor(AppColors.BG_PRIMARY)

      // 顶部导航栏
      Row() {
        Row() {
          Image($r('app.media.back'))
            .width(18)
            .height(18)
            .fillColor(AppColors.TEXT_PRIMARY)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.BG_SECONDARY)
        .borderRadius(20)
        .border({ width: 1, color: AppColors.BORDER })
        .onClick(() => {
          router.back();
        })

        Text('个人中心')
          .fontSize(AppSizes.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Column().width(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      // 内容区域
      Scroll() {
        Column({ space: 16 }) {
          // 用户信息卡片
          Column({ space: 16 }) {
            Row({ space: 16 }) {
              // 头像（可点击更换）
              Column() {
                if (this.avatarImage) {
                  Image(this.avatarImage)
                    .width(72)
                    .height(72)
                    .borderRadius(36)
                    .objectFit(ImageFit.Cover)
                } else {
                  Text('👤')
                    .fontSize(36)
                }
              }
              .width(72)
              .height(72)
              .backgroundColor(AppColors.BG_PRIMARY)
              .borderRadius(36)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.pickAvatar();
              })

              Column({ space: 4 }) {
                Text(this.nickname)
                  .fontSize(AppSizes.FONT_XL)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.TEXT_PRIMARY)

                Text(`已记录 ${this.diaryCount} 篇日记`)
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                
                Text('点击头像更换')
                  .fontSize(AppSizes.FONT_XS)
                  .fontColor(AppColors.ACCENT)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .backgroundColor(AppColors.BG_SECONDARY)
          .borderRadius(AppSizes.RADIUS_LG)
          .border({ width: 1, color: AppColors.BORDER })
          .shadow(getCardShadow())

          // 云端数据状态卡片
          Column({ space: 12 }) {
            Row() {
              Text('☁️ 云端数据状态')
                .fontSize(AppSizes.FONT_MD)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.TEXT_PRIMARY)
              
              Blank()
              
              if (this.isLoadingCloudStats) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(AppColors.ACCENT)
              } else {
                Text('刷新')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(AppColors.ACCENT)
                  .onClick(() => {
                    this.loadCloudStats();
                  })
              }
            }
            .width('100%')

            if (this.cloudStats !== null) {
              // 网络状态
              Row({ space: 8 }) {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(this.cloudStats.networkAvailable ? '#22C55E' : '#F59E0B')
                
                Text(this.cloudStats.networkAvailable ? '网络正常' : '网络异常')
                  .fontSize(AppSizes.FONT_XS)
                  .fontColor(this.cloudStats.networkAvailable ? '#22C55E' : '#F59E0B')
              }

              // 连接状态
              Row({ space: 8 }) {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(this.cloudStats.isConnected ? '#22C55E' : '#EF4444')
                
                Text(this.cloudStats.isConnected ? '云端已连接' : '云端未连接')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(this.cloudStats.isConnected ? '#22C55E' : '#EF4444')
              }

              // 认证状态
              Row({ space: 8 }) {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(this.cloudStats.isAuthenticated ? '#22C55E' : '#F59E0B')
                
                Text(this.cloudStats.isAuthenticated 
                  ? `已认证 (${this.cloudStats.userId.substring(0, 8)}...)` 
                  : '未认证 (匿名)')
                  .fontSize(AppSizes.FONT_XS)
                  .fontColor(this.cloudStats.isAuthenticated ? '#22C55E' : '#F59E0B')
              }

              // 如果有错误信息，显示
              if (this.cloudStats.errorMessage) {
                Text(this.cloudStats.errorMessage)
                  .fontSize(AppSizes.FONT_XS)
                  .fontColor('#EF4444')
                  .margin({ top: 4 })
              }

              // 数据统计 (仅在连接成功时显示)
              if (this.cloudStats.isConnected) {
                Row({ space: 16 }) {
                  this.CloudStatItem('📝', '日记', this.cloudStats.diaryCount)
                  this.CloudStatItem('🎯', '目标', this.cloudStats.goalCount)
                  this.CloudStatItem('💭', '记忆', this.cloudStats.memoryCount)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceAround)
                .margin({ top: 8 })
              }

              // 最后同步时间
              Text(`最后检查: ${this.formatTime(this.cloudStats.lastSyncTime)}`)
                .fontSize(AppSizes.FONT_XS)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ top: 8 })
            } else {
              // 显示错误或提示
              if (this.cloudError) {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    Circle()
                      .width(8)
                      .height(8)
                      .fill('#EF4444')
                    Text('连接失败')
                      .fontSize(AppSizes.FONT_SM)
                      .fontColor('#EF4444')
                  }
                  Text(this.cloudError)
                    .fontSize(AppSizes.FONT_XS)
                    .fontColor(AppColors.TEXT_HINT)
                    .textAlign(TextAlign.Center)
                }
              } else {
                Text('点击刷新查看云端数据状态')
                  .fontSize(AppSizes.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
              }
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(AppColors.BG_SECONDARY)
          .borderRadius(AppSizes.RADIUS_LG)
          .border({ width: 1, color: AppColors.BORDER })
          .shadow(getCardShadow())

          // 设置选项
          Column({ space: 0 }) {
            this.SettingItem('🔔', '通知设置', '管理推送通知')
            Divider().color(AppColors.BORDER).margin({ left: 48 })
            this.SettingItem('🎨', '主题设置', '深色/浅色模式')
            Divider().color(AppColors.BORDER).margin({ left: 48 })
            this.SettingItem('☁️', '云同步', '数据自动同步到云端')
            Divider().color(AppColors.BORDER).margin({ left: 48 })
            this.SettingItem('📤', '导出数据', '导出日记为文件')
          }
          .width('100%')
          .backgroundColor(AppColors.BG_SECONDARY)
          .borderRadius(AppSizes.RADIUS_LG)
          .border({ width: 1, color: AppColors.BORDER })
          .shadow(getCardShadow())

          // 开发者选项
          Column({ space: 0 }) {
            Row() {
              Text('🛠️ 开发者选项')
                .fontSize(AppSizes.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
            }
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 8 })

            // 一键清空数据
            Row() {
              Row({ space: 12 }) {
                Text('🗑️')
                  .fontSize(20)
                
                Column({ space: 2 }) {
                  Text('一键清空数据')
                    .fontSize(AppSizes.FONT_MD)
                    .fontColor('#EF4444')
                    .fontWeight(FontWeight.Medium)
                  
                  Text('删除 Diary、Goal、Memory 所有数据')
                    .fontSize(AppSizes.FONT_XS)
                    .fontColor(AppColors.TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .layoutWeight(1)

              if (this.isClearing) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color('#EF4444')
              } else {
                Image($r('app.media.back'))
                  .width(16)
                  .height(16)
                  .fillColor(AppColors.TEXT_HINT)
                  .rotate({ angle: 180 })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(AppColors.BG_SECONDARY)
            .onClick(() => {
              if (!this.isClearing) {
                this.showClearDataDialog();
              }
            })
          }
          .width('100%')
          .backgroundColor(AppColors.BG_SECONDARY)
          .borderRadius(AppSizes.RADIUS_LG)
          .border({ width: 1, color: '#FECACA' })
          .shadow(getCardShadow())

          // 版本信息
          Column({ space: 4 }) {
            Text('版本 1.0.0')
              .fontSize(AppSizes.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
            Text('智慧学习助手')
              .fontSize(AppSizes.FONT_XS)
              .fontColor(AppColors.TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })

          // 底部安全区
          Column().height(this.bottomSafeHeight + 20)
        }
        .padding({ left: 16, right: 16, top: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BG_PRIMARY)
  }

  @Builder
  SettingItem(icon: string, title: string, subtitle: string) {
    Row() {
      Row({ space: 12 }) {
        Text(icon)
          .fontSize(20)
        
        Column({ space: 2 }) {
          Text(title)
            .fontSize(AppSizes.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .fontWeight(FontWeight.Medium)
          
          Text(subtitle)
            .fontSize(AppSizes.FONT_XS)
            .fontColor(AppColors.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)

      Image($r('app.media.back'))
        .width(16)
        .height(16)
        .fillColor(AppColors.TEXT_HINT)
        .rotate({ angle: 180 })
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  CloudStatItem(icon: string, label: string, count: number) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text(icon)
          .fontSize(16)
        Text(count.toString())
          .fontSize(AppSizes.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
      }
      Text(label)
        .fontSize(AppSizes.FONT_XS)
        .fontColor(AppColors.TEXT_HINT)
    }
  }

  /**
   * 格式化时间戳
   */
  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }
}
