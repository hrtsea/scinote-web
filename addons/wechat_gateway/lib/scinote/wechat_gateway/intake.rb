# frozen_string_literal: true

require 'date'

module Scinote
  module WechatGateway
    # 写入层核心：消息指令路由 + 用户级草稿管理。
    # 忠实复刻 Python intake.py 的行为与指令协议，后端无关（通过 backend 注入）。
    #
    # 指令：
    #   /newexp [标题] [@起始 ~截止]  新建实验草稿（可选标题与起止日期，日期 YYYY-MM-DD）
    #                                 未设默认项目时先列可建实验的项目并等待选编号（两阶段引导）
    #   /newproject <名称> [| 描述]  在当前团队下新建项目（并设为默认项目）
    #   /newtask <实验ID> [任务名] [~截止]  在指定实验下新建任务（MyModule）
    #   /setexp <实验ID>  设置当前实验（并把它的所属项目设为默认项目；清空当前任务）
    #   /getexp        查看当前实验
    #   /settask <任务ID> 设置当前任务（后续文本/附件落到任务正文；同时切到所属实验）
    #   /gettask       查看当前任务
    #   #<实验ID> 文本   消息级指定：本条直接挂到对应实验（不改变「当前」）
    #   /done           收尾实验：写真实 done_at（状态=已完成，可列表筛选）+ 正文留痕
    #                   （任务状态流转不在网关推进，一律回 Web 端）
    #   /cancel         放弃当前草稿（保留实验/任务，仅清本地索引）
    #   /listexp [n]    列出最近实验
    #   /listproject [n|all] 列出可建实验的项目（all = 全部可读）
    #   /listtask [实验ID] [n] 列出任务；省略实验ID 时用当前实验
    #   /setproject <项目ID> 设置/切换长期默认项目（持久化到 DB）
    #   /getproject     查看当前默认项目
    #   /search <词>    关键词搜索实验
    #   纯文本/媒体       追加到当前落点：有当前任务 -> 任务正文，否则实验正文
    #
    # 落库作者用真实用户身份（backend 内部处理），不落 bot 名下，保证审计链。
    #
    # 项目作用域：实验必须挂在某个 Project 下。默认项目存在 UserStateStore（DB，
    # 按 scinote_user_id 主键，跨通道共享）；未设置或失效时走「列候选 → 回复编号」
    # 的两阶段引导，标题/日期/本条文本会暂存在 pending 里，选完直接建，不重打。
    class Intake
      DONE = '/done'
      CANCEL = '/cancel'
      SEARCH = '/search'
      CONFIRM = '/confirm'
      UNLOCK = '/unlock'
      ADMIN = '/admin'
      BOOK = '/book'
      HELP = '/help'
      NEWEXP = '/newexp'
      NEWPROJECT = '/newproject'
      NEWTASK = '/newtask'
      LISTPROJECT = '/listproject'
      LISTEXP = '/listexp'
      LISTTASK = '/listtask'
      SETPROJECT = '/setproject'
      GETPROJECT = '/getproject'
      SETEXP = '/setexp'
      GETEXP = '/getexp'
      SETTASK = '/settask'
      GETTASK = '/gettask'
      TITLE_PREFIX = '微信记录'
      # 待选项目的动作名 / 候选条数上限 / 有效期（秒）
      PENDING_SELECT_PROJECT = 'select_project'
      SELECTION_LIMIT = 10
      PENDING_TTL = 15 * 60
      SETPROJECT_USAGE = '⚠️ 用法：/setproject <项目ID>（发 /listproject 查看可建实验的项目）'
      SETEXP_USAGE = '⚠️ 用法：/setexp <实验ID>（发 /listexp 查看可用实验）'
      SETTASK_USAGE = '⚠️ 用法：/settask <任务ID>（发 /listtask 查看当前实验的任务）'
      # /newexp 日期片段匹配：@ 或 ~ 后必须紧跟本格式才视为日期，避免误伤群 @ 提及。
      DATE_FORMAT_RE = /(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2})?)/

      def initialize(backend:, store:, title_prefix: TITLE_PREFIX, ai_llm: nil,
                     mention_resolver: nil, vision_describer: nil, state_store: nil)
        @backend = backend
        @store = store
        @title_prefix = title_prefix
        @ai_llm = ai_llm
        # mention_resolver: (wechat_id, platform) -> scinote_user_id | nil（群 @ 指派用）
        @mention_resolver = mention_resolver
        # vision_describer: (media_descriptor) -> String | nil（图片识别，Ticket 05）
        @vision_describer = vision_describer
        # state_store: 长期状态（默认项目 + 待选 pending）。默认 UserStateStore（DB 持久化）
        @state_store = state_store || UserStateStore.new
        reset_notices
      end

      # 统一入口：message 为统一 Message 结构。
      def handle(user_id, message)
        reset_notices
        text = (message.text || '').to_s.strip

        # ① 待选项目优先：只有「纯数字且落在候选内」才算选择；其余一律取消 pending
        #    并按普通消息处理（不吞用户输入）。
        if (reply = intercept_pending(user_id, text))
          return reply
        end

        # ② 指令
        if (reply = route_command(user_id, text))
          return with_notices(reply)
        end

        # ③ 普通录入：没有当前草稿、也没有可用默认项目 -> 先引导选项目
        #    （本条文本暂存进 pending，选完自动写入，不丢内容）
        #    若本条已经取消过一次 pending，就不再重复弹选择列表（避免「一直问」的死循环）。
        if @store.get(user_id).nil? && resolve_default_project_id(user_id).nil?
          reply = @pending_cancelled ? no_project_guidance : start_project_selection(user_id, note: text.presence)
          return with_notices(reply)
        end

        parts = []
        parts << append_text(user_id, text) unless text.empty?
        parts << handle_media(user_id, message) if media?(message)
        parts << assign_mentions(user_id, message) if @mention_resolver && message.mentions.any?
        with_notices(parts.compact.join("\n"))
      end

      # 附加提示（如「已取消待选项目」），统一拼在回复前面。
      def reset_notices
        @notices = []
        @invalid_project_id = nil
        @pending_cancelled = false
      end

      def with_notices(reply)
        return reply if @notices.empty?

        [@notices.join("\n"), reply].reject { |s| s.to_s.empty? }.join("\n")
      end

      # 解锁辅助：已锁定草稿的新增内容一律拒收（/newexp 会开新草稿解除）
      def locked_reply
        '⚠️ 当前草稿已锁定（/confirm），新内容不会写入。发 /newexp 开新草稿，或 /done 收尾。'
      end

      # ---- 指令路由（复刻 Python handle_text）----
      def route_command(user_id, text)
        return nil if text.empty?

        # 消息级指定：#<实验ID> [备注]
        if (m = text.match(/\A#(\d+)\s*(.*)\z/m))
          exp_id = m[1].to_i
          rest = m[2].strip
          reply = set_experiment(user_id, exp_id)
          return rest.empty? ? reply : reply + "\n" + append_text(user_id, rest)
        end

        case text
        when NEWEXP then new_draft(user_id, '')
        when NEWPROJECT then new_project(user_id, '')
        when NEWTASK then new_task(user_id, '')
        when LISTPROJECT then list_projects(user_id, '')
        when LISTEXP then list_experiments(user_id, limit: 5)
        when LISTTASK then list_tasks(user_id, '')
        when GETPROJECT then show_project(user_id)
        when SETPROJECT then SETPROJECT_USAGE
        when GETEXP then show_experiment(user_id)
        when SETEXP then SETEXP_USAGE
        when GETTASK then show_task(user_id)
        when SETTASK then SETTASK_USAGE
        when DONE then done(user_id)
        when CANCEL then cancel(user_id)
        when CONFIRM then confirm(user_id)
        when UNLOCK then unlock(user_id)
        when HELP then help
        else
          if text.start_with?(LISTEXP)
            list_experiments(user_id, limit: parse_cmd_limit(text, LISTEXP))
          elsif text.start_with?(LISTPROJECT + ' ')
            list_projects(user_id, text[LISTPROJECT.length..].to_s.strip)
          elsif text.start_with?(LISTTASK + ' ')
            list_tasks(user_id, text[LISTTASK.length..].to_s.strip)
          elsif text.start_with?(NEWEXP + ' ')
            new_draft(user_id, text[NEWEXP.length..].to_s.strip)
          elsif text.start_with?(SEARCH)
            q = text[SEARCH.length..].to_s.strip
            return "⚠️ 用法：/search <关键词>" if q.empty?

            list_experiments(user_id, q: q, limit: 10)
          elsif text.start_with?(NEWPROJECT + ' ')
            new_project(user_id, text[NEWPROJECT.length..].to_s.strip)
          elsif text.start_with?(NEWTASK + ' ')
            new_task(user_id, text[NEWTASK.length..].to_s.strip)
          elsif (m = text.match(%r{\A/setproject\s+(\d+)\s*\z}))
            set_project(user_id, m[1].to_i)
          elsif text.start_with?(SETPROJECT)
            SETPROJECT_USAGE
          elsif text.start_with?(SETEXP + ' ')
            parts = text.split
            if parts.length == 2 && parts[1] =~ /\A\d+\z/
              set_experiment(user_id, parts[1].to_i)
            else
              SETEXP_USAGE
            end
          elsif text.start_with?(SETEXP)
            SETEXP_USAGE
          elsif (m = text.match(%r{\A/settask\s+(\d+)\s*\z}))
            set_task(user_id, m[1].to_i)
          elsif text.start_with?(SETTASK)
            SETTASK_USAGE
          elsif text.start_with?(HELP)
            help
          elsif text == ADMIN || text.start_with?(ADMIN + ' ')
            admin_query(user_id, text[ADMIN.length..].to_s.strip)
          elsif text == BOOK || text.start_with?(BOOK + ' ')
            book_equipment(user_id, text.split)
          else
            nil
          end
        end
      end

      # ---- 写入落点（task 优先于 experiment）----
      # 「当前落点」= 最近一次 /settask 指定的任务；没有则落到当前实验。
      # 返回 [kind, id]，kind ∈ :task | :experiment，供回复文案使用。
      def append_block(user_id, draft, block)
        return write_to_task(draft, block) if draft[:task_id]

        @backend.append_note(draft[:exp_id], block)
        [:experiment, draft[:exp_id]]
      end

      def write_to_task(draft, block)
        @backend.append_task_note(draft[:task_id], block)
        [:task, draft[:task_id]]
      end

      def append_media(user_id, draft, path, caption)
        return @backend.upload_task(draft[:task_id], path, caption) if draft[:task_id]

        @backend.upload(draft[:exp_id], path, caption)
      end

      def target_label(kind, id)
        kind == :task ? "任务 ##{id}" : "实验 ##{id}"
      end

      # ---- 文本/媒体处理（复刻 Python _append / handle_image 等）----
      def append_text(user_id, text)
        return locked_reply if @store.locked?(user_id)

        draft = ensure_draft(user_id)

        # AI 结构化（F12）：原文完整保留 + 标需人工审核；抽取失败降级为原文落库
        if @ai_llm && (record = ai_extract(text))
          kind, id = append_block(user_id, draft, AiProcessor.format_body(text, record))
          persist_formulation(record, draft[:exp_id])
          return "📝 已 AI 整理并写入#{target_label(kind, id)}（草稿，需人工审核）。"
        end

        ts = Time.now.strftime('%H:%M')
        block = "[#{ts} · 文本] #{text}"
        kind, id = append_block(user_id, draft, block)
        "📝 已记录到#{target_label(kind, id)}（草稿，未锁定）。"
      end

      # 调用注入的 LLM 抽取；异常返回 nil（降级为原文落库，不阻塞录入）
      def ai_extract(text)
        @ai_llm.call(text)
      rescue StandardError
        nil
      end

      def persist_formulation(record, exp_id)
        @backend.persist_formulation(record, exp_id)
      rescue StandardError
        nil
      end

      def handle_media(user_id, message)
        return locked_reply if @store.locked?(user_id)

        draft = ensure_draft(user_id)
        exp_id = draft[:exp_id]
        target_label_s = draft[:task_id] ? "任务 ##{draft[:task_id]}" : "实验 ##{exp_id}"
        message.media.map do |m|
          media_label = media_kind_label(m[:kind])
          caption = m[:text].presence || m[:file_name].presence || "微信#{media_label}"
          path = m[:full_url] || m[:url] || m[:file_name].to_s
          append_media(user_id, draft, path, caption)
          # 图片：尝试视觉识别（Ticket 05），成功则把识别文本写入正文；失败降级为仅附件
          desc = m[:kind] == :image ? describe_image(m) : nil
          if desc.present?
            append_block(user_id, draft, "图片识别：#{desc}")
            "🖼️ #{media_label}已归档到#{target_label_s}（#{caption}），识别文本已写入正文。"
          else
            "📎 #{media_label}已作为附件挂到#{target_label_s}（#{caption}）。"
          end
        end.join("\n")
      end

      # 图片识别（失败/未配置返回 nil，不阻塞录入）
      def describe_image(descriptor)
        return nil unless @vision_describer

        @vision_describer.call(descriptor)
      rescue StandardError
        nil
      end

      # 群 @ 指派（F6）：把被 @ 的微信用户（解析为 SciNote 用户）指派到当前草稿实验。
      def assign_mentions(user_id, message)
        return locked_reply if @store.locked?(user_id)

        exp_id = ensure_draft(user_id)[:exp_id]
        message.mentions.map do |wid|
          target = @mention_resolver.call(wid, message.platform)
          if target.nil?
            next "⚠️ @#{wid} 未绑定 SciNote，无法指派。"
          end

          begin
            @backend.assign_user(exp_id, target)
            "👤 已指派 #{wid}（SciNote 用户 ##{target}）到实验 ##{exp_id}。"
          rescue StandardError => e
            "⚠️ 指派 #{wid} 失败：#{e.message}"
          end
        end.join("\n")
      end

      # ---- 指令实现 ----
      # /newexp [标题] [@起始 ~截止]：解析可选标题与起止日期后建草稿。
      # args 为已去掉命令前缀的余串（如「PP配方A @2026-09-24 ~2026-10-01」）。
      # 无可用默认项目时不建实验，转为「列候选项目 → 等待选编号」（标题/日期暂存）。
      def new_draft(user_id, args = '')
        parsed = parse_new_args(args)
        project_id = resolve_default_project_id(user_id)
        return start_project_selection(user_id, parsed) if project_id.nil?

        prev = @store.get(user_id)
        exp_id = create_draft(user_id, project_id: project_id, title: parsed[:title],
                                      start_date: parsed[:start_date],
                                      due_date: parsed[:due_date])
        draft_created_reply(user_id, exp_id, parsed, prev)
      end

      # 建草稿成功的统一回复（/newexp 直建 与 选完项目后补建 共用）。
      def draft_created_reply(user_id, exp_id, parsed, prev)
        title_note = parsed[:title] ? "「#{parsed[:title]}」" : ''
        date_parts = []
        date_parts << "起始 #{parsed[:start_date]}" if parsed[:start_date]
        date_parts << "截止 #{parsed[:due_date]}" if parsed[:due_date]
        date_str = date_parts.empty? ? '' : "（#{date_parts.join('，')}）"
        if prev && !@store.locked?(user_id)
          # 存在未收尾的开放草稿：提示旧草稿仍开放，避免被静默孤立
          "🆕 已开新实验草稿 ##{exp_id}#{title_note}#{date_str}。\n" \
          "⚠️ 你还有未收尾的草稿 ##{prev[:exp_id]}（仍开放），记得发 /done 收尾。\n" \
          "后续消息将追加到 ##{exp_id}；发 /done 收尾。"
        else
          "🆕 已开新实验草稿 ##{exp_id}#{title_note}#{date_str}，继续发消息会被追加；发 /done 收尾。"
        end
      end

      # ---- 项目作用域：默认项目 + 两阶段选择 ----
      # 取当前可用的默认项目 id；不可用返回 nil（并把已失效的预设清掉，Q9 预校验）。
      def resolve_default_project_id(user_id)
        pid = @state_store.default_project_id(user_id)
        if pid
          return pid if @backend.project_available?(pid)

          @state_store.clear_default_project(user_id)
          @invalid_project_id = pid
          return nil
        end
        # 无用户级预设时回落实例级配置（WECHAT_GATEWAY_PROJECT_ID）
        env_pid = configured_project_id
        return nil if env_pid.nil?
        return env_pid if @backend.project_available?(env_pid)

        nil
      rescue StandardError
        nil # 后端查询异常不阻断录入：按「无预设」走引导
      end

      def configured_project_id
        cfg = Scinote::WechatGateway.configuration
        pid = cfg&.default_project_id
        pid.present? ? pid.to_i : nil
      rescue StandardError
        nil
      end

      # 发起「选项目」：列可建实验的项目并等待用户回复编号。
      # parsed: { title:, start_date:, due_date: }（来自 /newexp，可为 {}）
      # note:   普通文本录入触发时暂存的正文，选完自动写入新实验。
      def start_project_selection(user_id, parsed = {}, note: nil)
        payload = parsed.is_a?(Hash) ? parsed : {}
        projects = @backend.list_projects(limit: SELECTION_LIMIT, scope: :creatable)
        if projects.empty?
          return "⚠️ 你目前没有任何可新建实验的项目（需要对项目有「创建实验」权限）。\n" \
                 '请联系管理员授权，或先在 Web 端/SciNote 里新建一个项目，再发 /newexp。'
        end

        @state_store.set_pending(user_id, PENDING_SELECT_PROJECT, {
                                   'candidates' => projects.map { |p| p[:id].to_i },
                                   'title' => payload[:title],
                                   'start_date' => payload[:start_date]&.to_s,
                                   'due_date' => payload[:due_date]&.to_s,
                                   'note' => note || payload[:note]
                                 }, ttl: PENDING_TTL)

        lines = []
        if @invalid_project_id
          lines << "⚠️ 原默认项目 ##{@invalid_project_id} 已不可用（无「创建实验」权限或已归档），已清除。"
        end
        lines << "📁 实验必须挂在某个项目下，请先选一个（回复项目编号，#{PENDING_TTL / 60} 分钟内有效）："
        projects.each { |p| lines << "##{p[:id]} #{p[:title]}" }
        kept = []
        kept << "标题「#{payload[:title]}」" if payload[:title].present?
        kept << "起始 #{payload[:start_date]}" if payload[:start_date]
        kept << "截止 #{payload[:due_date]}" if payload[:due_date]
        kept << '你刚发的内容' if note.present? && payload[:title].blank?
        lines << ''
        lines << if kept.empty?
                   '回复编号后立即建实验；回复 0 取消。'
                 else
                   "回复编号后沿用 #{kept.join('、')} 并立即建实验；回复 0 取消。"
                 end
        lines << '（该选择会被记住，下次 /newexp 直接用；换项目发 /setproject <编号>）'
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 查询可选项目失败：#{e.message}"
      end

      # 待选拦截：返回非 nil 表示这条消息已被当作「选择」消费掉。
      def intercept_pending(user_id, text)
        pending = @state_store.pending(user_id)
        return nil unless pending && pending[:action] == PENDING_SELECT_PROJECT

        payload = pending[:payload] || {}
        candidates = Array(payload['candidates']).map(&:to_i)

        if text == '0'
          @state_store.clear_pending(user_id)
          return '🗑️ 已取消本次新建实验（未创建任何记录）。'
        end

        if text =~ /\A\d+\z/ && candidates.include?(text.to_i)
          project_id = text.to_i
          @state_store.clear_pending(user_id)
          @state_store.set_default_project(user_id, project_id) # 选过即记住（Q2 持久化）
          return create_from_pending(user_id, project_id, payload)
        end

        # 不是选择 -> 取消 pending，按普通消息继续处理（内容绝不吞掉）
        @state_store.clear_pending(user_id)
        @pending_cancelled = true
        @notices << '⚠️ 已取消上一条「选择项目」等待，本条按普通消息处理。' unless text.empty?
        nil
      end

      # 已问过一轮仍没项目：给出可执行的下一步，不再重复弹列表。
      def no_project_guidance
        ['⚠️ 还没有可用的默认项目，这条内容暂时无处安放。',
         '发 /listproject 查看可建实验的项目，再发 /setproject <编号> 设定后重发本条内容。'].join("\n")
      end

      # 选完项目后补建实验：沿用暂存的标题/日期，并把暂存的正文写进去。
      def create_from_pending(user_id, project_id, payload)
        title = payload['title'].presence
        start_date = parse_date(payload['start_date'])
        due_date = parse_date(payload['due_date'])
        note = payload['note'].presence

        prev = @store.get(user_id)
        exp_id = create_draft(user_id, project_id: project_id, title: title,
                                      start_date: start_date, due_date: due_date)
        @backend.append_note(exp_id, note) if note
        head = "✅ 默认项目已设为 #{project_label(project_id)}。"
        [head,
         draft_created_reply(user_id, exp_id,
                             { title: title, start_date: start_date, due_date: due_date }, prev)].join("\n")
      rescue StandardError => e
        "⚠️ 建实验失败：#{e.message}"
      end

      def project_label(project_id)
        p = @backend.get_project(project_id)
        "##{project_id}「#{p[:title]}」"
      rescue StandardError
        "##{project_id}"
      end

      # /setproject <项目ID>：显式设置长期默认项目（校验可建实验权限）。
      def set_project(user_id, project_id)
        unless @backend.project_available?(project_id)
          return "⚠️ 项目 ##{project_id} 不可用（不存在、已归档，或你没有「创建实验」权限）。\n" \
                 '发 /listproject 查看可建实验的项目列表。'
        end

        @state_store.set_default_project(user_id, project_id)
        "✅ 默认项目已设为 #{project_label(project_id)}；后续 /newexp 直接建在该项目下。\n" \
        '换项目：/setproject <编号>；看当前：/getproject。'
      end

      # /getproject：查看当前默认项目。
      def show_project(user_id)
        pid = @state_store.default_project_id(user_id) || configured_project_id
        return "📁 当前未设置默认项目。发 /listproject 查看可建实验的项目，再发 /setproject <编号> 设定。" if pid.nil?

        available = begin
          @backend.project_available?(pid)
        rescue StandardError
          false
        end
        "📁 当前默认项目：#{project_label(pid)}#{available ? '' : '（⚠️ 该项目当前不可建实验，/newexp 时会要求重选）'}。\n" \
        '新建实验：/newexp；换项目：/setproject <编号>。'
      end

      # /getexp：查看当前实验（对应 /setexp 的只读形态，同 /getproject 之于 /setproject）。
      def show_experiment(user_id)
        draft = @store.get(user_id)
        return '当前未指定实验，发 /newexp 新建草稿，或 /setexp <实验ID> 指定已有实验。' unless draft

        head = "🎯 当前实验：##{draft[:exp_id]}；发 /setexp <实验ID> 切换，/done 结束。"
        return head unless draft[:task_id]

        "#{head}\n📦 落点已下探到任务 ##{draft[:task_id]}（文本/附件写进任务正文）；/cancel 或 /setexp 退回实验级。"
      end

      def set_experiment(user_id, exp_id)
        e = @backend.get_experiment(exp_id)
        prev_task = @store.get(user_id)&.fetch(:task_id, nil)
        # put 不带 task_id：切实验即退出当前任务（否则文本会落进另一个实验里的旧任务）
        @store.put(user_id, exp_id, '')
        # 切到某实验 = 切到它所属的项目（Q5）：后续 /newexp 落在该项目下
        note = nil
        if e[:project_id]
          if @backend.project_available?(e[:project_id])
            @state_store.set_default_project(user_id, e[:project_id])
          else
            note = "⚠️ 该实验所属项目 ##{e[:project_id]} 你没有「创建实验」权限，/newexp 时会要求重选项目。"
          end
        end
        title = e[:title] || "实验##{exp_id}"
        lines = ["🎯 当前实验已设为 ##{exp_id}「#{title}」，后续消息/附件将挂到这里；发 /newexp 或 /done 结束。"]
        lines << "↩️ 已退出任务 ##{prev_task}，文本改为追加到实验正文（要回到任务级发 /settask）。" if prev_task
        lines << note if note
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 实验 ##{exp_id} 不存在或无权访问：#{e.message}"
      end

      # /settask <任务ID>：把当前录入落点设到某任务（Task 级 = set 动作）。
      # 语义对齐 /setexp：设为当前 + 同步上层作用域（所属实验 -> 当前实验、所属项目 -> 默认项目）。
      # 准入：存在 + 未归档 + 可读 + 有「编辑描述」写权限（可读 ≠ 可写）。
      def set_task(user_id, mm_id)
        unless @backend.my_module_available?(mm_id)
          return "⚠️ 任务 ##{mm_id} 不可用（不存在、已归档，或你只有读权限、不能写正文）。\n" \
                 '发 /listtask 查看当前实验的任务列表。'
        end

        meta = @backend.get_my_module(mm_id)
        @store.put(user_id, meta[:experiment_id], '') # 先把当前实验切到任务的父实验
        @store.set_task(user_id, mm_id)
        note = nil
        if meta[:project_id] && @backend.project_available?(meta[:project_id])
          @state_store.set_default_project(user_id, meta[:project_id])
        elsif meta[:project_id]
          note = "⚠️ 该任务所属项目 ##{meta[:project_id]} 你没有「创建实验」权限，/newexp 时会要求重选项目。"
        end
        lines = ["📦 当前任务已设为 ##{mm_id}「#{meta[:title]}」（实验 ##{meta[:experiment_id]}），" \
                 '后续消息/附件将挂到这个任务的正文；/done 只收尾所属实验，/cancel 退出到实验级。']
        lines << note if note
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 任务 ##{mm_id} 不存在或无权访问：#{e.message}"
      end

      # /gettask：查看当前任务（/settask 的只读形态）。
      def show_task(user_id)
        task_id = @store.get(user_id)&.fetch(:task_id, nil)
        if task_id.nil?
          draft = @store.get(user_id)
          return '当前未指定任务（文本会追加到实验级）。发 /newexp 新建草稿，或 /setexp <实验ID> 指定已有实验。' unless draft

          return "📦 当前未指定任务，文本会追加到实验 ##{draft[:exp_id]}。\n" \
                 '发 /listtask 看任务列表，再发 /settask <任务ID> 进入任务级录入。'
        end

        draft = @store.get(user_id)
        begin
          meta = @backend.get_my_module(task_id)
          title = meta[:title] ? "「#{meta[:title]}」" : ''
        rescue StandardError
          title = ''
        end
        "📦 当前任务：##{task_id}#{title}（实验 ##{draft[:exp_id]}）；文本/附件会追加到任务正文。\n" \
        '发 /settask <任务ID> 切换，/cancel 或 /setexp 退出到实验级。'
      end

      def task_label(mm_id)
        m = @backend.get_my_module(mm_id)
        "##{mm_id}「#{m[:title]}」"
      rescue StandardError
        "##{mm_id}"
      end

      def list_experiments(user_id, q: nil, limit: 5)
        results = @backend.list_experiments(q: q, limit: limit)
        return "📭 你还没有实验，发 /newexp 新建一个。" if results.empty? && q.nil?

        heading = q ? "「#{q}」的搜索结果" : '最近的实验'
        lines = ["📋 #{heading}（#{results.size}）："]
        results.each do |e|
          eid = e[:id] || '?'
          title = e[:title] || '(无标题)'
          date_s = e[:date] || ''
          lines << "##{eid} #{title}" + (date_s.empty? ? '' : " [#{date_s}]")
        end
        lines << ''
        lines << '回复 #编号 即可把后续消息/附件挂到该实验。'
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 查询失败：#{e.message}"
      end

      # /newproject <名称> [| 描述] [@起始 ~截止]：在当前团队下新建项目（Project）。
      # 名称必填；「|」后可附描述。
      # start_date **默认为当前指令日期**（与原生「Create new project」弹窗行为一致：
      # 打开弹窗时起始日期预填今天）；可用 @YYYY-MM-DD 显式覆盖。
      # ~YYYY-MM-DD 写 due_date（可选）。
      def new_project(user_id, raw_text)
        rest = raw_text.to_s.strip
        return '⚠️ 用法：/newproject <项目名称> [| 描述] [@起始 ~截止]' if rest.empty?

        # 先剥离日期片段，剩余部分再按「|」拆名称与描述
        due_m = rest.match(/~#{DATE_FORMAT_RE}/)
        due_date = due_m ? parse_date(due_m[1]) : nil
        start_m = rest.match(/@#{DATE_FORMAT_RE}/)
        start_date = start_m ? parse_date(start_m[1]) : nil
        rest = rest.gsub(/~#{DATE_FORMAT_RE}/, '').gsub(/@#{DATE_FORMAT_RE}/, '').strip

        if (sep = rest.index('|'))
          name = rest[0...sep].strip
          desc = rest[sep + 1..].strip.presence
        else
          name = rest
          desc = nil
        end
        return '⚠️ 项目名称不能为空。' if name.empty?

        # 未显式给起始日期时，用当前指令日期自动填充
        start_date ||= current_date
        pid = @backend.create_project(name, desc, start_date: start_date, due_date: due_date)
        # 新建的项目顺手设为该用户的默认项目（建完马上要在里面建实验是主路径）
        begin
          @state_store.set_default_project(user_id, pid)
          default_note = '已设为你的默认项目，/newexp 会直接建在这里'
        rescue StandardError
          default_note = '可用 /setproject <编号> 把它设为默认项目'
        end
        date_note = "（起始 #{start_date}#{due_date ? "，截止 #{due_date}" : ''}）"
        "🆕 已新建项目 ##{pid}「#{name}」#{date_note}（建在当前团队下）。\n" \
          "#{default_note}；/listproject 查看项目列表。"
      rescue StandardError => e
        "⚠️ 新建项目失败：#{e.message}"
      end

      # /newtask <实验ID> [任务名] [~截止日期]：在指定实验下新建任务（MyModule）。
      # MyModule 仅有截止日期（due_date），无起始日期；~ 后日期写 due_date。
      # 建完后把当前草稿切到该实验，方便后续文本追加到同一实验。
      def new_task(user_id, raw_text)
        rest = raw_text.to_s.strip
        return '⚠️ 用法：/newtask <实验ID> [任务名] [~截止日期]' if rest.empty?

        first = rest.split.first
        unless first =~ /\A\d+\z/
          return '⚠️ 用法：/newtask <实验ID> [任务名] [~截止日期]（实验ID 须为整数）'
        end

        exp_id = first.to_i
        body = rest[first.length..].to_s.strip
        due_m = body.match(/~#{DATE_FORMAT_RE}/)
        due_date = due_m ? parse_date(due_m[1]) : nil
        name = body.gsub(/~#{DATE_FORMAT_RE}/, '').strip.presence

        mid = @backend.create_mymodule(exp_id, name, nil, due_date: due_date)
        @store.put(user_id, exp_id, '') # 后续消息追加到该实验（不清现有任务落点以外的东西）
        due_note = due_date ? "（截止 #{due_date}）" : ''
        "🆕 已在实验 ##{exp_id} 下新建任务 ##{mid}「#{name || '未命名任务'}」#{due_note}。\n" \
          "当前草稿已切到 ##{exp_id}，后续消息将追加到实验正文；\n" \
          "要专门往这个任务里记，发 /settask #{mid}。"
      rescue StandardError => e
        "⚠️ 新建任务失败：#{e.message}"
      end

      # /listproject [n|all]：列出项目（Q4）。
      #   默认只列「可建实验」的项目 —— 列出来就是为了建实验，列不能建的是噪音。
      #   all -> 列全部可读项目（含只读），用于查找/核对。
      def list_projects(user_id, raw_text)
        scope, limit = parse_list_project_args(raw_text)
        results = @backend.list_projects(limit: limit, scope: scope)
        if results.empty?
          return scope == :creatable ? "📭 你还没有可新建实验的项目（需项目的「创建实验」权限）。\n" \
                                       '可发 /listproject all 查看全部可读项目。'
                                     : '📭 你还没有可见的项目。'
        end

        heading = scope == :creatable ? '可新建实验的项目' : '可见项目（含只读）'
        lines = ["📁 #{heading}（#{results.size}）："]
        results.each { |p| lines << "##{p[:id]} #{p[:title]}" }
        lines << ''
        lines << if scope == :creatable
                   '设为默认项目：/setproject <编号>；看全部可读项目：/listproject all。'
                 else
                   '（只读项目不能建实验；可建实验的清单请发 /listproject）'
                 end
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 查询失败：#{e.message}"
      end

      # 解析 /listproject 余串：出现 all -> :readable；纯数字 -> limit（默认 5）。
      def parse_list_project_args(raw_text)
        scope = :creatable
        limit = 5
        raw_text.to_s.strip.split.each do |tok|
          if tok.casecmp('all').zero?
            scope = :readable
          elsif tok =~ /\A\d+\z/
            limit = tok.to_i
          end
        end
        [scope, limit]
      end

      # /listtask [实验ID] [n]：列出任务（MyModule）。
      # 省略实验ID 时用当前实验——与 /listproject 不必带参数同源理（上下文已知就不该让用户再打一遍）。
      def list_tasks(user_id, raw_text)
        parts = raw_text.to_s.strip.split
        exp_id, rest = resolve_list_task_target(user_id, parts)
        return exp_id if exp_id.is_a?(String) # 错误文案直接返回

        limit = (rest[0] =~ /\A\d+\z/ ? rest[0].to_i : 5)
        results = @backend.list_mymodules(exp_id, limit: limit)
        if results.empty?
          return "📭 实验 ##{exp_id} 下还没有任务。发 /newtask <实验ID> <任务名> 建一个。"
        end

        lines = ["📦 实验 ##{exp_id} 的任务（#{results.size}）："]
        results.each { |m| lines << "##{m[:id]} #{m[:title]}" }
        lines << ''
        lines << '把某个任务设为录入落点：/settask <任务ID>；看当前任务：/gettask。'
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 查询失败：#{e.message}"
      end

      # 决定 /listtask 查哪个实验：[exp_id, 剩余参数] 或错误信息字符串。
      def resolve_list_task_target(user_id, parts)
        if parts.empty? || parts[0] !~ /\A\d+\z/
          draft = @store.get(user_id)
          return ['⚠️ 用法：/listtask [实验ID] [n]（省略实验ID 时用当前实验，但你还没有当前实验）。', []] unless draft

          return [draft[:exp_id], parts] # 首参不是数字 -> 整个参数串当作 [...] 余串
        end

        [parts[0].to_i, parts[1..]]
      end

      # 从「命令余串」中解析末尾整数作为 limit（默认 5）。
      def parse_limit_from(raw_text)
        rest = raw_text.to_s.strip
        m = rest.match(/\A(\d+)\z/)
        m ? m[1].to_i : 5
      end

      # 从「完整指令文本」中解析命令前缀后的整数 limit（默认 5）。
      def parse_cmd_limit(text, prefix)
        parse_limit_from(text[prefix.length..])
      end

      def done(user_id)
        draft = @store.pop(user_id)
        return '当前没有进行中的草稿。' unless draft

        exp_id = draft[:exp_id]
        @backend.append_note(exp_id, "✅ 收尾于 #{Time.now.strftime('%Y-%m-%d %H:%M')}（状态置为已完成）")
        @backend.complete_experiment(exp_id)
        lines = ["🔒 实验 ##{exp_id} 已收尾：状态置为「已完成」（done_at 已写入，可在实验列表按状态筛选）。"]
        # 任务不是 TimeTrackable：收尾=推进 status flow，且该动作不可逆 -> 一律回 Web 端（ADR 0027）
        lines << "ℹ️ 任务 ##{draft[:task_id]} 未被收尾：任务状态流转请在 Web 端完成（网关不提供）。" if draft[:task_id]
        lines.join("\n")
      rescue StandardError => e
        "实验 ##{exp_id} 已记录，但收尾失败：#{e.message}"
      end

      def cancel(user_id)
        draft = @store.pop(user_id)
        return '当前没有进行中的草稿。' unless draft

        extra = draft[:task_id] ? "（含任务级落点 ##{draft[:task_id]}）" : ''
        "🗑️ 草稿 ##{draft[:exp_id]}#{extra} 保留但不再追加，请到 Web 端继续编辑或删除。\n" \
        '⚠️ 实验与任务都仍存在于 SciNote，网关不提供删除（ADR 0027）。'
      end

      # /confirm：草稿级软锁。阻止后续追加（真实 SciNote 只读强锁见 Ticket 05/08）。
      def confirm(user_id)
        draft = @store.get(user_id)
        return '当前没有进行中的草稿，无法锁定。' unless draft
        return '该草稿已锁定。' if @store.locked?(user_id)

        @store.mark_locked(user_id)
        kind, id = append_block(user_id, draft, "✅ 已确认 #{Time.now.strftime('%Y-%m-%d %H:%M')}")
        target = target_label(kind, id)
        "🔒 #{target} 已软锁定：后续追加会被拒绝。\n" \
        "说明：/confirm 只冻结「本地草稿索引」（拒绝新内容），记录在 SciNote 仍开放；\n" \
        "发 /done 才打可信时间戳并收尾，或发 /unlock 解除锁定继续追加。"
      rescue StandardError => e
        "⚠️ 锁定失败：#{e.message}"
      end

      # /unlock：解除 /confirm 建立的软锁，恢复追加能力。
      def unlock(user_id)
        draft = @store.get(user_id)
        return '当前没有进行中的草稿。' unless draft
        return '该草稿未锁定，无需解锁。' unless @store.locked?(user_id)

        @store.mark_unlocked(user_id)
        kind, id = append_block(user_id, draft, "🔓 已解锁 #{Time.now.strftime('%Y-%m-%d %H:%M')}")
        "🔓 #{target_label(kind, id)} 已解除锁定，可继续追加；发 /confirm 重新锁定或 /done 收尾。"
      rescue StandardError => e
        "⚠️ 解锁失败：#{e.message}"
      end

      # /help：列出全部指令与用法（指令发现入口）。
      HELP_TEXT = <<~HELP
        📖 微信录入指令一览：
        /newexp [标题] [@起始 ~截止] 新建实验（未设默认项目时先选项目）
        /newproject <名称> [| 描述] [@起始 ~截止] 新建项目（起始日期默认填今天，并设为默认项目）
        /newtask <实验ID> [任务名] [~截止] 在指定实验下新建任务
        /setproject <项目ID> 设置长期默认项目（/newexp 落在它下面）
        /getproject 查看当前默认项目
        /setexp <实验ID> 设置当前实验（并把它的项目设为默认项目，同时退出任务级）
        /getexp 查看当前实验
        /settask <任务ID> 设置当前任务（后续文本/附件写进任务正文）
        /gettask 查看当前任务
        /listtask [实验ID] [n] 列出任务（省略实验ID 用当前实验）
        #<实验ID> 文本 本条消息直接挂到指定实验
        /done 收尾所属实验：状态置为「已完成」（done_at 已写入，可列表筛选）并清草稿索引
        /cancel 退出当前草稿（实验/任务保留在 SciNote，网关不删除）
        /confirm 软锁定当前草稿（拒绝后续追加）
        /unlock 解除 /confirm 软锁定
        /listexp [n] 列出最近 n 条实验（默认 5）
        /listproject [n|all] 列出可建实验的项目（all = 全部可读）
        /listtask <实验ID> [n] 列出指定实验下的任务
        /search <关键词> 按标题/正文搜索实验
        /bind <绑定码> 绑定 SciNote 账号（先在设置页获取绑定码）
        /admin [关键词] 管理员跨用户查询（需实例管理员权限）
        /book <设备ID> <开始ISO> <结束ISO> 预约设备
        直接发 文本/图片/文件 追加到当前草稿（无草稿自动新建）
      HELP

      def help
        HELP_TEXT
      end

      # /admin [关键词]：管理员跨用户查询实验（F9）
      def admin_query(_user_id, query)
        results = @backend.admin_experiments(query: query.presence, limit: 10)
        return '📭 没有可展示的实验。' if results.empty?

        lines = ["📋 管理员查询（#{results.size}）："]
        results.each do |e|
          lines << "##{e[:id]} #{e[:title]}#{e[:date] ? " [#{e[:date]}]" : ''}"
        end
        lines.join("\n")
      rescue StandardError => e
        "⚠️ 查询失败：#{e.message}"
      end

      # /book <设备ID> <开始ISO> <结束ISO>：设备预约（F10）
      def book_equipment(_user_id, parts)
        unless parts.length == 4
          return '⚠️ 用法：/book <设备ID> <开始ISO> <结束ISO>（如 /book 12 2026-09-24T14:00 2026-09-24T16:00）'
        end

        start_t = parse_time(parts[2])
        end_t = parse_time(parts[3])
        return '⚠️ 时间格式无效，请用 ISO8601（如 2026-09-24T14:00）。' if start_t.nil? || end_t.nil?

        res = @backend.book_equipment(parts[1].to_i, start_time: start_t, end_time: end_t)
        "📅 已预约设备 #{parts[1]}（#{parts[2]} ~ #{parts[3]}），预约号 ##{res[:id]}。"
      rescue StandardError => e
        "⚠️ 预约失败：#{e.message}"
      end

      def parse_time(str)
        t = (Time.zone || Time).parse(str)
        t
      rescue ArgumentError, TypeError
        nil
      end

      # 解析 /newexp 后的参数：标题可选；@起始 ~截止 日期可选。
      # 语法：/newexp [标题] [@YYYY-MM-DD[ HH:MM]] [~YYYY-MM-DD[ HH:MM]]
      # @/~ 后须紧跟日期才解析，否则 @ 视为标题正文（防误伤群消息 @提及）。
      def parse_new_args(rest)
        start_m = rest.match(/@#{DATE_FORMAT_RE}/)
        due_m = rest.match(/~#{DATE_FORMAT_RE}/)
        title = rest.gsub(/@#{DATE_FORMAT_RE}/, '').gsub(/~#{DATE_FORMAT_RE}/, '').strip
        title = nil if title.empty?
        {
          title: title,
          start_date: start_m ? parse_date(start_m[1]) : nil,
          due_date: due_m ? parse_date(due_m[1]) : nil
        }
      end

      # 当前指令日期（用于 /newproject 起始日期自动填充）。
      # 优先用 Rails 时区（Time.zone），无则回退系统本地日期。
      def current_date
        # Time.zone 仅在加载 ActiveSupport 时区扩展后存在（Rails 环境恒有）。
        return Time.zone.today if Time.respond_to?(:zone) && Time.zone

        Date.today
      end

      # 解析日期为 Date：支持 2026-09-24 / 2026-09-24 14:00 / 2026-09-24T14:00；失败返回 nil。
      def parse_date(str)
        Date.parse(str.to_s)
      rescue ArgumentError, TypeError
        begin
          DateTime.parse(str.to_s).to_date
        rescue ArgumentError, TypeError
          nil
        end
      end

      # ---- 草稿辅助 ----
      def create_draft(user_id, title: nil, start_date: nil, due_date: nil, project_id: nil)
        title = title.presence || enforce_title(user_id)
        body = header(user_id)
        eid = @backend.create_experiment(title, body, start_date: start_date,
                                                due_date: due_date, project_id: project_id)
        @store.put(user_id, eid, body)
        eid
      end

      # 无当前草稿时自动建一条。项目来源：用户默认项目 > 实例配置（writer 内部回落）。
      def ensure_draft(user_id)
        draft = @store.get(user_id)
        return draft if draft

        exp_id = create_draft(user_id, project_id: resolve_default_project_id(user_id))
        { exp_id: exp_id, body: header(user_id) }
      end

      def header(user_id)
        "微信录入草稿\n" \
          "- 录入人：#{user_id}\n" \
          "- 来源：微信群\n" \
          "- 状态：待整理\n" \
          "记录："
      end

      def enforce_title(user_id)
        "#{@title_prefix}-#{user_id}"
      end

      def media?(message)
        message.media && !message.media.empty?
      end

      def media_kind_label(kind)
        case kind
        when :image then '图片'
        when :voice then '语音'
        when :file then '文件'
        when :video then '视频'
        else '附件'
        end
      end

      # ---- 进程内入口（由 Inbound.intake_handler 调用）----
      # 解析真实 User 并构建 writer；用户不存在时返回友好提示，不抛异常给回调。
      # mention_resolver: (wechat_id, platform) -> scinote_user_id | nil，用于群 @ 指派。
      # vision_describer: (media_descriptor) -> String | nil，用于图片识别（Ticket 05）。
      # ai_llm: (text) -> StructuredRecord | nil，用于 AI 结构化抽取（Ticket 06）。
      # formulation_writer: FormulationWriter | nil，落 ai_eln Formulation 实体。
      def self.handle(user_id, message, mention_resolver: nil, vision_describer: nil,
                      ai_llm: nil, formulation_writer: nil)
        user = User.find(user_id)
        new(
          backend: ScinoteServiceWriter.new(user, formulation_writer: formulation_writer),
          store: SessionDraftStore.new,
          state_store: UserStateStore.new,
          mention_resolver: mention_resolver,
          vision_describer: vision_describer,
          ai_llm: ai_llm
        ).handle(user_id, message)
      rescue ActiveRecord::RecordNotFound => e
        "⚠️ 用户不存在：#{e.message}"
      end
    end
  end
end
