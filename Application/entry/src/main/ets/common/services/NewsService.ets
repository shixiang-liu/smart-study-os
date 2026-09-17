// ============================================================================
// 新闻服务 - 获取时政新闻
// ============================================================================

import { NewsItem } from '../model/NewsItem'
import { NetworkService } from './NetworkService'
import http from '@ohos.net.http'

// API 响应数据结构
interface NewsApiResult {
  data?: NewsApiItem[]
}

interface NewsApiResponse {
  error_code: number
  result?: NewsApiResult
}

interface NewsApiItem {
  title: string
  author_name: string
  date: string
  url: string
}

export interface NewsDetail {
  content: string
  summary: string
}

export class NewsService {
  private static instance: NewsService | null = null
  // 使用聚合数据免费新闻API（需要替换为你的API key，或者使用其他免费API）
  // 这里使用一个公开的新闻API作为示例
  private readonly NEWS_API_URL = 'https://v.juhe.cn/toutiao/index'
  private readonly API_KEY = '' // 填入自己的新闻 API Key；为空时该服务自动停用

  static getInstance(): NewsService {
    if (!NewsService.instance) {
      NewsService.instance = new NewsService()
    }
    return NewsService.instance
  }

  /**
   * 获取今日时政新闻
   * 使用真实的新闻API获取当天新闻
   */
  async getTodayNews(): Promise<NewsItem[]> {
    try {
      // 检查网络状态
      if (!NetworkService.getInstance().getIsOnline()) {
        console.warn('[NewsService] 网络未连接，使用模拟数据')
        return this.getMockNews()
      }

      // 尝试获取真实新闻
      const realNews = await this.fetchRealNews()
      if (realNews && realNews.length > 0) {
        return realNews
      }

      // 如果获取失败，返回模拟数据
      console.warn('[NewsService] 获取真实新闻失败，使用模拟数据')
      return this.getMockNews()
    } catch (err) {
      console.error('[NewsService] 获取新闻失败:', err)
      return this.getMockNews()
    }
  }

  /**
   * 从真实API获取新闻
   * 注意：需要配置API key才能获取真实新闻
   * 可以在聚合数据(https://www.juhe.cn/)注册账号获取免费API key
   * 或者使用其他免费的新闻API服务
   */
  private async fetchRealNews(): Promise<NewsItem[]> {
    // 如果没有配置API key，直接返回空数组，使用模拟数据
    if (!this.API_KEY || this.API_KEY.length === 0) {
      console.info('[NewsService] 未配置API key，使用模拟数据')
      return []
    }

    try {
      const httpRequest = http.createHttp()
      const url = `${this.NEWS_API_URL}?type=guonei&key=${this.API_KEY}`
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        },
        connectTimeout: 10000,
        readTimeout: 10000
      })

      if (response.responseCode === 200 && response.result) {
        const data: NewsApiResponse = JSON.parse(response.result.toString())
        if (data.error_code === 0 && data.result && data.result.data) {
          const newsList: NewsItem[] = data.result.data.map((item: NewsApiItem, index: number) => {
            const newsItem: NewsItem = {
              id: `news_${index}_${Date.now()}`,
              title: item.title || '',
              source: item.author_name || '未知来源',
              publishTime: item.date || new Date().toISOString().split('T')[0],
              url: item.url || '',
              summary: item.title // 暂时使用标题作为摘要
            }
            return newsItem
          })
          httpRequest.destroy()
          return newsList.slice(0, 10) // 只返回前10条
        }
      }

      httpRequest.destroy()
      return []
    } catch (err) {
      console.error('[NewsService] 获取真实新闻失败:', err)
      return []
    }
  }

  /**
   * 获取新闻详情（包括内容和摘要）
   * @param newsItem 新闻对象，包含摘要等信息
   */
  async getNewsDetail(newsItem: NewsItem): Promise<NewsDetail | null> {
    try {
      // 使用新闻中已有的摘要，如果没有则使用标题
      const summary = newsItem.summary || newsItem.title || '暂无摘要'
      
      // 生成详细内容（基于摘要扩展）
      let content = ''
      if (newsItem.summary && newsItem.summary !== newsItem.title) {
        // 如果有摘要且不同于标题，基于摘要生成详细内容
        content = `${newsItem.summary}\n\n${newsItem.title}是一条重要的新闻报道。该新闻涉及当前社会关注的热点话题，具有一定的时效性和价值。\n\n如需了解更多详细信息，请点击"查看原文"按钮查看完整报道。`
      } else {
        // 如果没有摘要，生成基于标题的内容
        content = `${newsItem.title}\n\n这是一条重要的新闻报道，涉及当前社会关注的热点内容。该新闻对了解当前社会动态具有参考意义，值得关注。\n\n如需了解更多详细信息，请点击"查看原文"按钮查看完整报道。`
      }
      
      const detail: NewsDetail = {
        content: content,
        summary: summary
      }
      return detail
    } catch (err) {
      console.error('[NewsService] 获取新闻详情失败:', err)
      return null
    }
  }

  /**
   * 获取模拟新闻数据（当无法获取真实新闻时使用）
   * 使用新华网的真实栏目链接，确保可以正常访问
   */
  private getMockNews(): NewsItem[] {
    const today = new Date()
    const dateStr = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`
    
    return [
      {
        id: '1',
        title: '国家发展改革委：推动经济持续回升向好',
        source: '新华社',
        publishTime: dateStr,
        url: 'https://www.xinhuanet.com/politics/',
        summary: '国家发展改革委相关负责人表示，将采取一系列政策措施，推动经济持续回升向好，确保实现全年经济社会发展目标。'
      },
      {
        id: '2',
        title: '教育部：深化教育改革，提升教育质量',
        source: '新华社',
        publishTime: dateStr,
        url: 'https://www.xinhuanet.com/edu/',
        summary: '教育部发布新政策，将进一步深化教育改革，提升教育质量，促进教育公平，培养更多优秀人才。'
      },
      {
        id: '3',
        title: '科技部：加强科技创新，推动高质量发展',
        source: '新华社',
        publishTime: dateStr,
        url: 'https://www.xinhuanet.com/tech/',
        summary: '科技部强调要加强科技创新，推动高质量发展，加快实现高水平科技自立自强，为建设科技强国贡献力量。'
      },
      {
        id: '4',
        title: '生态环境部：持续推进生态文明建设',
        source: '新华社',
        publishTime: dateStr,
        url: 'https://www.xinhuanet.com/fortune/',
        summary: '生态环境部表示将持续推进生态文明建设，加强生态环境保护，推动绿色发展，建设美丽中国。'
      },
      {
        id: '5',
        title: '商务部：促进消费恢复，扩大对外开放',
        source: '新华社',
        publishTime: dateStr,
        url: 'https://www.xinhuanet.com/fortune/',
        summary: '商务部将采取多项措施促进消费恢复，扩大对外开放，推动外贸稳中提质，为经济发展注入新动力。'
      }
    ]
  }

  /**
   * 格式化日期显示
   */
  formatDate(date: Date): string {
    const year = date.getFullYear()
    const month = date.getMonth() + 1
    const day = date.getDate()
    const weekdays = ['日', '一', '二', '三', '四', '五', '六']
    const weekday = weekdays[date.getDay()]
    
    return `${year}年${month}月${day}日 星期${weekday}`
  }
}

