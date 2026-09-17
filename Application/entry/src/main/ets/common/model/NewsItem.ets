// ============================================================================
// 新闻数据模型
// ============================================================================

export interface NewsItem {
  id: string
  title: string
  source: string
  publishTime: string
  url?: string
  content?: string  // 新闻内容
  summary?: string  // 新闻摘要
}

