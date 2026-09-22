Scinote::WechatGateway::Engine.routes.draw do
  # 企微自建应用回调：GET 校验 URL，POST 收消息
  post '/wecom/callback',  to: 'wecom#callback'
  get  '/wecom/callback',  to: 'wecom#callback'
  # iLink 私聊 DM 回调（长轮询拉到消息后由桥接层转发，或 iLink webhook）
  post '/ilink/callback', to: 'ilink#callback'
  # 绑定码确认（也可走私聊 /bind <码>，此处保留 HTTP 入口备用）
  get  '/bind/:code',     to: 'bind#confirm'
end
