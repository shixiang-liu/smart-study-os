// 持久化存储工具类 - 基于 Preferences 实现本地数据存储

import { preferences } from '@kit.ArkData'
import { NoteItem } from '../../diary/model/NoteItem'
import common from '@ohos.app.ability.common'
import { CloudDiaryService } from '../services/CloudDiaryService'
import { TaskStorageService } from '../../goal/model/TaskStorageService'
import { FocusRecordService } from '../../pomodoro/model/FocusRecordService'

// 通用偏好设置存储名
const COMMON_PREFERENCES_NAME = 'app_preferences'
// 日记专用存储名
const NOTES_PREFERENCES_NAME = 'myNotesData'
const NOTES_KEY = 'notesList'

// 全局上下文引用
let globalContext: common.Context | null = null

// 日记数据持久化工具类
export class PreferencesUtil {

  // 初始化上下文（应用启动时调用）
  static initContext(context: common.Context): void {
    globalContext = context
  }

  // 获取上下文
  private static getContext(): common.Context {
    if (!globalContext) {
      throw new Error('PreferencesUtil 未初始化，请先调用 initContext')
    }
    return globalContext
  }

  // ==================== 通用键值存储 ====================

  // 存储任意值
  static async put(key: string, value: string | number | boolean): Promise<void> {
    const context = PreferencesUtil.getContext()
    const pref = await preferences.getPreferences(context, COMMON_PREFERENCES_NAME)
    await pref.put(key, value)
    await pref.flush()
  }

  // 获取值
  static async get<T>(key: string, defaultValue: T): Promise<T> {
    const context = PreferencesUtil.getContext()
    const pref = await preferences.getPreferences(context, COMMON_PREFERENCES_NAME)
    const result = await pref.get(key, defaultValue as preferences.ValueType)
    return result as T
  }

  // 删除指定键
  static async delete(key: string): Promise<void> {
    const context = PreferencesUtil.getContext()
    const pref = await preferences.getPreferences(context, COMMON_PREFERENCES_NAME)
    await pref.delete(key)
    await pref.flush()
  }

  // 获取对象（JSON反序列化）
  static async getObject<T>(key: string, defaultValue: T): Promise<T> {
    const jsonStr = await PreferencesUtil.get<string>(key, '')
    if (!jsonStr) {
      return defaultValue
    }
    return JSON.parse(jsonStr) as T
  }

  // 存储对象（JSON序列化）
  static async putObject<T>(key: string, value: T): Promise<void> {
    await PreferencesUtil.put(key, JSON.stringify(value))
  }

  // ==================== 日记专用方法 ====================

  // 加载日记列表
  static async loadNotes(context: common.Context): Promise<NoteItem[]> {
    try {
      console.info('[PreferencesUtil] 开始加载日记，context存在:', !!context)
      const pref = await preferences.getPreferences(context, NOTES_PREFERENCES_NAME)
      console.info('[PreferencesUtil] Preferences对象已获取')
      const notesJson: string = await pref.get(NOTES_KEY, '[]') as string
      console.info('[PreferencesUtil] 读取到JSON字符串，长度:', notesJson.length, '前100字符:', notesJson.substring(0, 100))
      const notes: NoteItem[] = JSON.parse(notesJson)
      console.info('[PreferencesUtil] 解析完成，日记数量:', notes.length)
      if (notes.length > 0) {
        console.info('[PreferencesUtil] 第一条日记ID:', notes[0].id, '标题:', notes[0].title, 'createTime:', notes[0].createTime)
      }
      return notes
    } catch (err) {
      console.error('[PreferencesUtil] 加载日记失败:', err)
      console.error('[PreferencesUtil] 错误详情:', JSON.stringify(err))
      return []
    }
  }

  // 保存日记列表（本地 + 云端同步）
  static async saveNotes(context: common.Context, notes: NoteItem[], key?: string): Promise<void> {
    try {
      console.info('[PreferencesUtil] 开始保存日记列表，数量:', notes.length, 'context存在:', !!context)
      // 保存到本地
      const pref = await preferences.getPreferences(context, NOTES_PREFERENCES_NAME)
      const saveKey = key || NOTES_KEY
      const jsonStr = JSON.stringify(notes)
      console.info('[PreferencesUtil] JSON字符串长度:', jsonStr.length, '前200字符:', jsonStr.substring(0, 200))
      await pref.put(saveKey, jsonStr)
      await pref.flush()
      console.info('[PreferencesUtil] 本地保存完成，日记数量:', notes.length)
      
      // 验证保存是否成功
      const verifyJson: string = await pref.get(saveKey, '[]') as string
      const verifyNotes: NoteItem[] = JSON.parse(verifyJson)
      console.info('[PreferencesUtil] 验证保存结果，读取到的数量:', verifyNotes.length)
      if (verifyNotes.length !== notes.length) {
        console.error('[PreferencesUtil] 警告：保存后验证数量不匹配！期望:', notes.length, '实际:', verifyNotes.length)
      }

      // 异步同步到云端
      PreferencesUtil.syncToCloud(notes)
    } catch (err) {
      console.error('[PreferencesUtil] 保存日记列表失败:', err)
      console.error('[PreferencesUtil] 错误详情:', JSON.stringify(err))
      throw err instanceof Error ? err : new Error(String(err))
    }
  }

  // 同步日记到云端
  private static async syncToCloud(notes: NoteItem[]): Promise<void> {
    const cloudService = CloudDiaryService.getInstance()
    const initialized = await cloudService.initialize()
    if (!initialized) {
      console.warn('[PreferencesUtil] CloudDB 未初始化，跳过云端同步')
      return
    }
    const success = await cloudService.saveNotes(notes)
    if (success) {
      console.info('[PreferencesUtil] 云端同步成功')
    }
  }

  // 保存单条日记
  static async saveNote(context: common.Context, note: NoteItem): Promise<void> {
    try {
      console.info('[PreferencesUtil] 开始保存单条日记，ID:', note.id, '标题:', note.title)
      const notes = await PreferencesUtil.loadNotes(context)
      console.info('[PreferencesUtil] 当前日记列表数量:', notes.length)
      const index = notes.findIndex(n => n.id === note.id)
      if (index >= 0) {
        notes[index] = note
        console.info('[PreferencesUtil] 更新已存在的日记，索引:', index)
      } else {
        notes.unshift(note)
        console.info('[PreferencesUtil] 添加新日记，新列表数量:', notes.length)
      }
      await PreferencesUtil.saveNotes(context, notes)
      console.info('[PreferencesUtil] 单条日记保存完成，最终列表数量:', notes.length)
    } catch (err) {
      console.error('[PreferencesUtil] 保存单条日记失败:', err)
      console.error('[PreferencesUtil] 错误详情:', JSON.stringify(err))
      throw err instanceof Error ? err : new Error(String(err))
    }
  }

  // 清除所有数据（云端+本地）
  static async clearAllData(context: common.Context): Promise<void> {
    // 1. 清除日记本地存储
    try {
      const notesPref = await preferences.getPreferences(context, NOTES_PREFERENCES_NAME)
      await notesPref.clear()
      await notesPref.flush()
      console.info('[PreferencesUtil] 日记数据已清除')
    } catch (e) {
      console.warn('[PreferencesUtil] 清除日记存储失败:', e)
    }
    
    // 2. 清除通用设置存储
    try {
      const commonPref = await preferences.getPreferences(context, COMMON_PREFERENCES_NAME)
      await commonPref.clear()
      await commonPref.flush()
      console.info('[PreferencesUtil] 通用设置已清除')
    } catch (e) {
      console.warn('[PreferencesUtil] 清除通用设置失败:', e)
    }

    // 3. 清除任务和专注记录
    try {
      const taskService = TaskStorageService.getInstance()
      await taskService.clearAllTasks(context)
      console.info('[PreferencesUtil] 任务数据已清除')
    } catch (e) {
      console.warn('[PreferencesUtil] 清除任务数据失败:', e)
    }

    try {
      const focusService = FocusRecordService.getInstance()
      await focusService.clearAllRecords(context)
      console.info('[PreferencesUtil] 专注记录已清除')
    } catch (e) {
      console.warn('[PreferencesUtil] 清除专注记录失败:', e)
    }

    // 4. 清除云端数据
    const cloudService = CloudDiaryService.getInstance()
    const initialized = await cloudService.initialize()
    if (initialized) {
      await cloudService.clearAllData()
      console.info('[PreferencesUtil] 云端数据已清除')
    }
  }
}
