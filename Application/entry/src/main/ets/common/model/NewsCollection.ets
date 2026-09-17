// ============================================================================
// 新闻收藏数据模型 - 用于CloudDB同步
// ============================================================================
import { cloudDatabase } from '@kit.CloudFoundationKit'

@Observed
export class NewsCollection extends cloudDatabase.DatabaseObject {
  id: string = ''
  user_id: string = ''
  news_title: string = ''
  news_url: string = ''
  news_summary: string = ''
  news_image: string = ''
  linked_diary_id: string = ''
  collect_time: number = 0
  sync_status: string = 'synced'

  // 创建新收藏
  static create(userId: string, title: string, url: string, summary?: string): NewsCollection {
    const collection = new NewsCollection()
    collection.id = `news_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`
    collection.user_id = userId
    collection.news_title = title
    collection.news_url = url
    collection.news_summary = summary || ''
    collection.collect_time = Date.now()
    collection.sync_status = 'synced'
    return collection
  }

  // 关联到日记
  linkToDiary(diaryId: string): void {
    this.linked_diary_id = diaryId
  }

  // CloudDB要求的方法
  naturalbase_ClassName(): string {
    return 'NewsCollection'
  }

  // 获取主键字段
  primaryKeys(): string[] {
    return ['id']
  }

  // 获取所有字段索引
  indexes(): string[] {
    return ['user_id', 'collect_time']
  }
}
