class CreateWechatUserBindings < ActiveRecord::Migration[7.2]
  def change
    create_table :wechat_user_bindings do |t|
      t.string :wechat_id,        null: false
      t.string :platform,         null: false # 'ilink' | 'wecom'
      t.bigint :scinote_user_id,  null: false
      t.string :status, default: 'active'
      t.timestamps
    end
    add_index :wechat_user_bindings, [:wechat_id, :platform], unique: true
  end
end
