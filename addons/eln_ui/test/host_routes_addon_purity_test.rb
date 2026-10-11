# frozen_string_literal: true
#
# 全仓库 addon 路由守卫（.scratch/addon-route-compliance-sweep）
#
# ## 守的是什么
# ADR-0022 的统一契约：**addon 路由一律由各自 engine initializer 自注册，
# 宿主 config/routes.rb 零 addon 路由**；启用/禁用只由 Gemfile 一行决定
# （注释掉 ⇒ 引擎不加载 ⇒ 路由不注册 ⇒ 宿主照常启动，仅该 addon 路由 404）。
#
# 契约失效时最典型的症状：`config/routes.rb` 里留了几条 `to: 'scinote/xxx/'`。
# 这看着只是"多几行"，实际后果是 **注释 Gemfile 行不再能优雅禁用**——
# 宿主路由表会指向一个不再被 Bundler 加载的 controller。
# 本仓库历史上 ELN UI（30 条）与 workbench（1 条）都踩过，
# access_control 还在宿主文件里留了 4 条**早已失效**的死路由。
#
# ## 为什么断言的是"文件内容"而不是"运行时路由表"
# `RAILS_ENV=test` 与独立 `rails runner` 进程里，addon 的 `Engine.routes` 都是 **0 条**
# （addon 的 routes initializer 只在服务进程启动时执行）。所以依赖运行时路由表的断言
# 在测试环境恒假，只能静态判宿主文件。
#
# ## 🔴 带前导斜杠的写法会让 Rails 直接拒绝加载整个 routes.rb
# 实测：往宿主 routes.rb 里加一条 `to: '/scinote/workbench/a#b'`，Rails 在**加载该文件时**
# 就抛 ArgumentError（`'/scinote/workbench/a' is not a supported controller name`），
# 测试进程根本起不来 ⇒ 此时任何 minitest 守卫都"跑不起来"，也就无从报红。
# 这解释了 access_control 那4 条宿主路由为何是死代码：它们带前导斜杠，在 Rails 7.2 下
# 根本无法被加载（应是旧 Rails 时代写法留下的）。
# ⇒ 所以自证只用**不依赖 Rails 成功加载**的样本（单引号无斜杠 / 双引号），
#   带斜杠那一路在注释里记录实测结论，不放进自证（否则会把"守卫失效"与"文件本身非法"混淆）。
#
# ## 护栏必须自证有效
# 本断言曾长期缺失，导致上述三处残留各自存在数周。改动本文件时，
# 请注入一违反规路由确认它**精确变红**，再还原（见test_offending_detector_actually_detects）。

require_relative 'test_helper'

class HostRoutesAddonPurityTest < AcTest::Base
  HOST_ROUTES_PATH = Rails.root.join('config/routes.rb')

  # addon 目录名清单——比正则匹配更严：只在册 addon 才算"应该自注册"。
  # 刻意用目录实测而非硬编码，避免新增 addon 时忘了更新这份清单。
  KNOWN_ADDONS = Dir.children(Rails.root.join('addons')).select do |d|
    File.directory?(Rails.root.join('addons', d))
  end.freeze

  def host_routes_content
    File.read(HOST_ROUTES_PATH)
  end

  # 宿主的 addon 路由行长什么样：
  #   to: 'scinote/eln_ui/project_detail#show'         （单引号，无前导斜杠）
  #   to: '/scinote/access_control/visibility_matrix#show'（单引号，有前导斜杠）
  #   to: "scinote/workbench/x#y"                     （双引号 —— 也可能）
  # 三种写法都要覆盖。access_control 那批死代码用的是带前导斜杠的单引号，
  # 而自证注入用的是双引号 —— 只认单引号的正则会被双引号绕过，
  # 守卫就成了假绿（实测踩过：注入双引号违规，`filter_map` 返回 0 条，测试仍全绿）。
  def offending_lines
    # 用引号字符类而非固定单引号，两种引号都覆盖。
    pattern = %r{to:\s*['"]/?scinote/([a-z_0-9]+)/}

    host_routes_content.lines.each_with_index.filter_map do |line, idx|
      next if line.strip.start_with?('#')

      m = pattern.match(line)
      next unless m

      "#{idx + 1} 行（addon: #{m[1]}）：#{line.strip}"
    end
  end

  def test_host_routes_file_has_no_addon_routes
    offenders = offending_lines

    assert_empty offenders,
                 "宿主 config/routes.rb 不得含 addon 路由（ADR-0022 零入侵契约）。" \
                 "当前残留 #{offenders.size} 处：\n#{offenders.join("\n")}\n" \
                 '这些路由应移到对应 addon 自己的 config/routes.rb，由 engine 自注册。'
  end

  def test_offending_detector_actually_detects
    # 护栏自证：把三种写法各喂一遍检测器，确认它真能认出来。
    # 若这段自身失败，说明检测正则坏了 —— 那样 test_host_routes_file_has_no_addon_routes
    # 的"绿"是没有意义的假绿。
    #
    # 🔴 三种写法缺一不可：单引号无斜杠 / 单引号带斜杠（access_control 死代码的写法）/
    #   双引号（自证注入用的写法）。实测漏掉双引号时，注入违规后守卫仍全绿 = 假绿，
    #   这条自证就是为拦住那类漏洞而存在。
    samples = {
      '单引号无前导斜杠' => "get 'x', to: 'scinote/eln_ui/project_detail#show'",
      '双引号' => 'get "x", to: "scinote/workbench/x#y"'
      # ⚠ 故意不含「单引号带前导斜杠」样本：那会让 Rails 加载 routes.rb 时就抛
      # ArgumentError（not a supported controller name），测试进程起不来、
      # 无法用来验证检测器。实测结论已记在文件头注释里。
    }

    samples.each do |desc, line|
      assert line =~ %r{to:\s*['"]/?scinote/[a-z_0-9]+/},
             "检测正则必须能认出「#{desc}」写法，实际漏检：#{line}"
    end

    # 带前导斜杠仍须被识别（只是不能作为可运行的注入样本）
    assert %q{get 'x', to: '/scinote/access_control/vm#show'} =~
             %r{to:\s*['"]/?scinote/[a-z_0-9]+/},
           '检测正则必须能认出带前导斜杠写法（access_control 死代码的形态）'

    # 纯注释行不算违规（routes.rb 里大量注释提及 scinote/xxx 属正常）。
    # 这条守的是"检测器按注释过滤"这个前提本身——若将来实现改成不跳过注释，
    # 本条会先于主断言报错，指出过滤逻辑坏了。
    assert_equal '#', '# to: \'scinote/eln_ui/project_detail#show\''.strip[0],
                 'sanity: 注释行首字符应为 #，检测器据此跳过它'
  end

  def test_known_addons_list_is_populated
    # 清单为空 ⇒ 上面的守卫等于没查任何东西（假绿）。守住这个前提。
    refute_empty KNOWN_ADDONS, 'addon 清单为空，守卫失去意义'
    assert_includes KNOWN_ADDONS, 'eln_ui'
    assert_includes KNOWN_ADDONS, 'workbench'
  end
end