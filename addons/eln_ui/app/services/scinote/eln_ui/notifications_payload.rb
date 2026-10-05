# frozen_string_literal: true

module Scinote
  module ElnUi
    # 通知中心列表（REQ-NOTIF / SCN-DASH-7）：读当前用户原生通知，
    # 派生点开跳转的业务 URL。不造二开通知表 —— 复用 Noticed 的 Notification 模型，
    # 与 NotificationPublisher 写入的是同一张表（§5 第 5 项）。
    #
    # 🔴 V1.25：**去掉 `type='GeneralNotification'` 过滤** —— 口径改与宿主徽标同源。
    #   理由（生产实测 2026-10-06，全库 114 条通知）：
    #     · `type` 分布 = GeneralNotification 4 / ActivityNotification 110；
    #     · 但 ActivityNotification 全部带 `params.hide_in_app = true`
    #       （见 app/notifications/base_notification.rb:46），所以 `in_app` 一过就只剩 1 条未读；
    #     · 「in_app 未读」（1）与「GeneralNotification + in_app 未读」（1）当前相等。
    #   也就是说 type 过滤是**冗余**的，但它制造了一个隐性风险：宿主顶栏徽标走
    #   `current_user.notifications.in_app.where(read_at: nil).count`（app/controllers/navigations_controller.rb:103，
    #   **不筛 type**），一旦将来出现一种「in_app 可见但非 GeneralNotification」的通知，
    #   徽标就会比列表多 —— 又回到「徽标 3、点开 1」的老 bug。
    #   现在两边都走同一个 `scope_for`，数量**不可能**再分叉。
    class NotificationsPayload
      DATE_FMT = '%Y-%m-%d %H:%M'.freeze
      FALLBACK_URL = '/eln_res_center'.freeze
      # 列表条数上限（原型下拉面板的高度只放得下这么多）
      LIMIT = 20

      def initialize(user:)
        @user = user
      end

      def self.call(user:)
        new(user: user).call
      end

      # 🔴 V1.25：未读数的**唯一真源**（工作台铃铛徽标、通知中心列表头、宿主顶栏徽标
      #   三处必须是同一个数）。
      #   以前这里有两份写法：工作台用 `recipient_type/recipient_id` 明文条件且**不筛 type**，
      #   通知中心筛 type 又……两份必然漂 —— 徽标显示 3、点开列表显示 1。
      #
      # ⚠ `recipient: user` 是多态写法（Rails 自己展开 recipient_type/recipient_id），
      #   不要再写明文那两个列 —— 列名字面量写错会静默查空（本项目踩过）。
      # ⚠ `in_app` 是原生 scope（app/models/notification.rb:8），剔掉 `hide_in_app` 的通知；
      #   宿主顶栏徽标、ActionCable 广播（notification.rb:15）用的都是它 —— 同源。
      def self.scope_for(user)
        ::Notification.where(recipient: user).in_app
      end

      def self.unread_count_for(user)
        scope_for(user).where(read_at: nil).count
      end

      def call
        scope = self.class.scope_for(@user)
        items = scope.order(created_at: :desc).limit(LIMIT).map { |n| item(n) }
        unread = scope.where(read_at: nil).count
        { unread: unread, items: items }
      end

      private

      def item(n)
        {
          id: n.id,
          title: title_of(n),
          message: message_of(n),
          createdAt: n.created_at&.strftime(DATE_FMT),
          read: n.read_at.present?,
          url: subject_url(n)
        }
      end

      # Noticed 序列化走 ActiveJob::Arguments —— 反序列化后 params 键为符号，
      # 用 with_indifferent_access 兼容两种键。
      def title_of(n)
        n.params.with_indifferent_access['title'].to_s
      end

      def message_of(n)
        n.params.with_indifferent_access['message'].to_s
      end

      # 跳转目标：subject_class/subject_id 是 NotificationPublisher 落库时记录的
      # 业务对象（subject.class.name，见 notification_publisher.rb:27-29）。
      # 取不到业务对象 → 回资源中心兜底（**数据问题**，属于正常退化）。
      #
      # 🔴 V1.25 修了两个叠在一起的 bug（这就是「通知点不进去」的根因）：
      #   ① **URL 形状错**：原来是手写字符串 `"/experiments/#{mod.experiment_id}/eln_task_detail"`
      #      —— 少了 `/my_modules/:id`。真机点下去就是 404，生产日志实锤
      #      `No route matches [GET] "/experiments/1/1/eln_task_detail"`。
      #      而这条错 URL 当时**被写进了测试断言**，所以套件一直是绿的 ——
      #      「有用例覆盖」不等于「行为正确」（假绿第九层）。测试已同步修正。
      #   ② **helper 名错、且被静默吞掉**：资源申请分支写的是 `eln_res_apply_path`，
      #      而宿主真名是 `eln_res_apply_detail_path`（config/routes.rb:474-476）。
      #      整个方法裹着 `rescue StandardError → FALLBACK_URL`，于是这个 NoMethodError
      #      从没在日志里露过面，**所有**资源申请通知都静默落到资源中心。
      #
      # 🔴 所以现在**不再包一层全方法 rescue**：
      #   「查不到业务对象」用 `return FALLBACK_URL` 显式退化；
      #   而 path helper 写错是**程序问题**，必须当场抛（首个请求/首个用例就炸）。
      #   〔铁律〕前端不写死宿主路由，URL 由后端下发；后端也不能手写 path 字符串。
      def subject_url(n)
        p = n.params.with_indifferent_access
        klass = p['subject_class'].to_s
        sid = p['subject_id']
        return FALLBACK_URL if klass.blank? || sid.blank?

        case klass
        when 'MyModule'
          mod = ::MyModule.find_by(id: sid)
          return FALLBACK_URL unless mod&.experiment_id

          host_routes.eln_task_detail_path(mod.experiment_id, mod.id)
        when 'ResourceApplication', 'Scinote::ElnUi::ResourceApplication'
          app = ::Scinote::ElnUi::ResourceApplication.find_by(id: sid)
          return FALLBACK_URL unless app

          host_routes.eln_res_apply_detail_path(app.no)
        else
          FALLBACK_URL
        end
      end

      def host_routes
        ::Rails.application.routes.url_helpers
      end
    end
  end
end
