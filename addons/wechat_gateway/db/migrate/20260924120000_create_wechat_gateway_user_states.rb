# 用户级长期状态：默认项目（跨消息/跨通道持久化）+ 待选项目 pending。
# 主键直接取 scinote_user_id：同一 SciNote 用户在 iLink / 企业微信两个通道共享同一份状态
# （绑定表 wechat_user_bindings 的唯一键是 [wechat_id, platform]，同一用户会有两行，
#  因此状态不能挂在绑定行上）。
class CreateWechatGatewayUserStates < ActiveRecord::Migration[7.2]
  def change
    create_table :wechat_gateway_user_states, id: false do |t|
      t.bigint  :scinote_user_id,    null: false, primary_key: true
      t.bigint  :default_project_id                       # 长期记住的「当前项目」
      t.string  :pending_action                           # 'select_project' | nil
      t.jsonb   :pending_payload,    null: false, default: {} # 候选项目 + 暂存标题/日期/文本
      t.datetime :pending_expires_at                      # 待选超时（默认 15 分钟）
      t.timestamps
    end

    add_index :wechat_gateway_user_states, :default_project_id
  end
end
