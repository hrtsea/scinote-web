# frozen_string_literal: true

# 资源申请单（eln_ui_resource_applications）
#
# 业务语义见迁移文件 SCN-RES-APPROVE-1~5。这里只做 ORM 形状 + 状态机 +
# items JSON 的便利访问，不在这里写校验/审批流（属于 service 层）。
#
# ⚠ class_name 一律带 `::`（避开宿主 Scinote::User / Scinote::Project 常量遮蔽，
#   与 model 铁律 #10 同源坑）。
# ⚠ 表名显式 self.table_name，否则 Rails 推不出 eln_ui_resource_application → 单复数歧义。
module Scinote
  module ElnUi
    class ResourceApplication < ActiveRecord::Base
      self.table_name = 'eln_ui_resource_applications'

      # ---- 关联 ----
      belongs_to :project,         class_name: '::Project', inverse_of: false
      belongs_to :requestor,       class_name: '::User',   inverse_of: false
      belongs_to :group_reviewer,  class_name: '::User',   optional: true, inverse_of: false
      belongs_to :project_reviewer, class_name: '::User',  optional: true, inverse_of: false
      # 服务执行挂在哪个任务下 —— 「欠交结果」闸门要靠它反查（ServiceStrikeBook#for_task）。
      # ⚠ optional: true 是**有意**的：物资申请不需要挂任务，只有服务类申请才必填
      #   （必填校验在 workflow 层做，因为要连「任务属不属于该项目」一起判）。
      belongs_to :my_module,       class_name: '::MyModule', optional: true, inverse_of: false

      # ---- 状态枚举（迁移里 default 'draft'）----
      # ⚠🔴 2026-10-05：试过换成 `enum :status, %w[...]`，**实测不能用，已回退**。
      #   现象：enum 自动生成的 `draft?` / `submitted?` 全返回 false，17 failures + 6 errors。
      #   根因在宿主这一层，不在调用姿势：本宿主里 enum 作用在 **string 列**上，
      #   会把值序列化成「整数下标」再 cast 成字符串 —— 探针实测
      #   `cr.new(kind:'material').send(:kind_for_database)` => **"0"**（字符串），
      #   于是 enum 的谓词实际在比 `("0" == 0)`，恒 false。
      #   真要上 enum，得先把列改成 integer（一条迁移 + 存储语义变更），那是独立决策。
      #   在此之前：常量 + validates inclusion + 下面几个显式谓词，老实用。
      STATUSES = %w[
        draft
        submitted
        group_approved
        project_approved
        rejected
        completed
      ].freeze
      validates :status, inclusion: { in: STATUSES }

      # ---- 业务编号格式校验：SQ-YYYY-NNNN ----
      validates :no, presence: true,
                     format: { with: /\ASQ-\d{4}-\d{4}\z/,
                               message: 'must match SQ-YYYY-NNNN' }

      # ---- items JSON 便利访问 ----
      # 读：始终返回 Array（DB 里可能 null/缺省）
      #
      # 🔴 2026-10-05 真 bug：这里原本是 symbolize_keys，而写侧（下面）是 stringify_keys
      #    —— 写进 jsonb 的是字符串键，读回来却被转成符号键，消费端无论用哪一种键都不稳：
      #    只写字符串键的取值点（res_center_payload 的 ['name'] / ['unit']）直接取到 nil，
      #    列表里「材料 · 」后面是空的（生产库实测 item_list.first['name'] == nil）。
      #    改成 with_indifferent_access：与写侧对称，'name' / :name 两种写法都通，
      #    既补上漏的取值点，也不动消费端已有的 `it['x'] || it[:x]` 防御写法。
      def item_list
        (items || []).map(&:with_indifferent_access)
      end

      # 写：覆盖 items 列
      def item_list=(arr)
        self.items = Array(arr).map(&:stringify_keys)
      end

      # ---- 状态机查询谓词（service 层用，view 层不用）----
      # ⚠ 这套手写谓词别换成 enum：见上面 STATUSES 那段的宿主 enum 地雷。
      def draft?;            status == 'draft';            end
      def submitted?;        status == 'submitted';        end
      def group_approved?;   status == 'group_approved';   end
      def project_approved?; status == 'project_approved'; end
      def rejected?;         status == 'rejected';         end
      def completed?;        status == 'completed';        end

      # 材料类申请的目标库（写入 items[0].repository_id）——请购语义，见 ADR-0030。
      # 服务类不适用，恒 nil。
      def repository_id
        item_dig(:repository_id)
      end

      # 入库后由 MaterialReceiptPosting 写回的实际条目 id（用于详情页精确溯源）。
      # 入库前恒 nil。
      def received_repository_row_id
        item_dig(:received_repository_row_id)
      end

      # items[0] 上取一个键，symbol / string 两种写法都认
      # （写侧 stringify_keys、读侧 with_indifferent_access，别只认一种）。
      def item_dig(key)
        first = item_list.first
        return nil if first.nil?

        first[key] || first[key.to_s]
      end

      # 材料类 = 请购单（ADR-0030）。审批后走「到货验收入库」，不是出库确认。
      def material?
        item_dig(:kind).to_s == 'material'
      end

      # 到货验收入库成功后，把**实际落库的条目 id** 写回 items[0]。
      # 详情页据此精确溯源（条目 → Stock → 任务消耗 Ledger），不必再靠「申请时绑定的条目」
      # ——请购语义下申请时**根本还没有条目**，它是在入库那一刻才被找到或创建的。
      def record_receipt!(repository_row_id)
        list = item_list.map(&:to_h)
        return if list.empty?

        list[0]['received_repository_row_id'] = repository_row_id
        self.item_list = list
        save!
      end

      # 是否「进入审批流」= 已提交 / 任一通过 / 已驳回 / 已完成
      # ⚠ 这个判定没有任何调用方（grep 确认全仓无引用）。按「接口只留被用得到的」先删了；
      #   将来要按阶段批量查，就写
      #   scope :in_review, -> { where(status: %w[submitted group_approved project_approved rejected]) }
      #   —— 注意别再用 enum 生成的同名 scope 顶替，理由同上。

      # 列表查询 scope
      scope :for_team, ->(team) {
        joins(:project).where(projects: { team_id: team.id })
      }
      scope :ordered, -> { order(submitted_at: :desc, id: :desc) }
    end
  end
end
