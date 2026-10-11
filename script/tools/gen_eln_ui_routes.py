"""从宿主 config/routes.rb 的 ELN UI 路由块生成 addon 自己的 config/routes.rb。

机械迁移，不手抄：
  1. 控制器名去掉 `scinote/eln_ui/` 前缀（isolate_namespace 已自带该前缀，写全会双层）
  2. 路径去掉前导斜杠（Rails 7.2 的 translate_controller 校验直接抛异常）
  3. as: 具名名逐字保留（对外 URL 与 helper 名必须不变）
"""
import io
import re
import sys

HOST = 'F:/elndev/scinote-web/config/routes.rb'
ADDON = 'F:/elndev/scinote-web/addons/eln_ui/config/routes.rb'

lines = io.open(HOST, encoding='utf-8').read().split('\n')
start = next(i for i, l in enumerate(lines) if 'ELN UI —— 按 Vue3 原型' in l)
end = next(i for i, l in enumerate(lines) if '工作台（workbench addon' in l)
block = lines[start:end]

# 逐条解析 (verb, path, controller#action, as)
ROUTE_RE = re.compile(
    r"^[ \t]*(get|post|patch|delete|put|match)[ \t]+"
    r"(?:'([^']*)'|\"([^\"]*)\")"
    r"[ \t]*,?[ \t]*$"
)
# ⚠ 一律用 `[ \t]` 而不是 `\s`：正则作用在多行 chunk 上，`\s` 含换行，
#   `\s*` 跨行贪婪后会吞掉换行再要求 `'`，导致明明 chunk 里有 to: 却匹配不到
#   （实测就是这样漏掉了紧邻的孤儿 V1 路由，且只在计数不符时才暴露）。
# ⚠ action 名**可能含数字**（实测 `project_list#v1`）：`([a-z_]+)` 会把 `v1` 截成 `v`，
#   后面要求 `'` 就失败 ⇒ 又丢一条。同样只在这个动作上出错，极难察觉。
TO_RE = re.compile(r"to:[ \t]*'scinote/eln_ui/([a-z_0-9]+)#([a-z0-9_]+)'")
AS_RE = re.compile(r"as:[ \t]*:([a-z_0-9]+)")

parsed = []
i = 0
while i < len(block):
    line = block[i]
    # match 路由是多行块，需要吃到 as: 为止
    m = ROUTE_RE.match(line)
    if not m:
        i += 1
        continue

    verb = m.group(1)
    path = (m.group(2) if m.group(2) is not None else m.group(3)) or ''

    # 收集本条路由的多行内容（到下一个动词行或块尾）
    j = i + 1
    chunk = [line]
    while j < len(block) and not ROUTE_RE.match(block[j]):
        chunk.append(block[j])
        j += 1
    body = '\n'.join(chunk)

    to_m = TO_RE.search(body)
    if not to_m:
        # 该动词行不是 ELN UI 的路由（原块里混有宿主自己的路由）⇒ **只跳过本行**，
        # 不能 i = j：j 已经越过了整个多行块，会把后面的 ELN UI 路由一起吞掉
        # （实测这样会只解析出 29/30 条，且缺的恰好是紧邻的那条，极难察觉）。
        i += 1
        continue
    controller, action = to_m.group(1), to_m.group(2)
    as_m = AS_RE.search(body)

    # match 路由的 via: 动词
    via = None
    if verb == 'match':
        vm = re.search(r'via:[ \t]*\[([^\]]*)\]', body)
        via = vm.group(1).strip() if vm else None

    parsed.append({
        'verb': verb,
        'path': path,
        'controller': controller,   # 已剥前缀
        'action': action,
        'as': as_m.group(1) if as_m else None,
        'via': via,
    })
    i = j

print('PARSED=%d' % len(parsed))
if len(parsed) != 30:
    sys.exit('期望 30 条，实得 %d —— 停止，不生成' % len(parsed))

header = """# frozen_string_literal: true
#
# ELN UI —— addon 自己的路由定义（ADR-0022：宿主 config/routes.rb 零 addon 路由）
#
# 本文件由`script/tools/` 的一次性机械迁移生成，逐条对照宿主原路由搬入，
# **对外 URL 与具名 helper 名逐字不变**（spec 第一验收标准）。
# 守卫：test/eln_ui_route_baseline_test.rb 冻结了迁移前后的 30 条三元组，
# 任何新增/缺失/改名都会让它变红。
#
# ---- 两条踩过的坑（access_control 侧先踩，勿再踩）----
#
# 1. **控制器名不能带命名空间前缀**。本引擎声明了 `isolate_namespace Scinote::ElnUi`，
#    其 route set 自带 `scinote/eln_ui/` 前缀。路由里再写全名会解析成
#    `scinote/eln_ui/scinote/eln_ui/xxx`，而 Zeitwerk 里没有那个类 ⇒
#    路由**匹配得上**但 recognition 报 "references missing controller" ⇒ 500。
#
# 2. **路径不能带前导斜杠**。Rails 7.2 的 `Mapper#translate_controller` 只放行
#    /\\A[a-z_0-9][a-z_0-9\\/]*\\z/，前导 '/' 直接抛 "is not a supported controller name"。
#
# 挂载点为根（engine.rb 的 `app.routes.append { mount ... => '/' }`），因此这里的
# 路径必须写**完整对外路径**（含 /projects/... 等前缀），挂到根后对外 URL 才与迁移前一致。
#
# ⚠ `append` 而非 `prepend`：addon 路由排在宿主之后，addon 无法用同名路径覆盖核心路由
#   （ADR-0022 的安全取舍）。代价是 addon 路由优先级最低——新增路由必须校验不与既有冲突。

Scinote::ElnUi::Engine.routes.draw do
"""

out = [header]
for r in parsed:
    if r['verb'] == 'match':
        # match 的真实动词在 via: 里（宿主原式是 `via: [:get, :post]`），
        # 注释按实际动词写，别一律标 GET —— 注释骗人会误导后来人核对动词。
        verbs_txt = r['via'] or 'GET'
        out.append("  # %s\n" % verbs_txt.replace(' :', ':').replace(': ', ': ').strip())
        out.append("  match '%s',\n" % r['path'])
        out.append("        to: '%s#%s',\n" % (r['controller'], r['action']))
        if r['as']:
            out.append("        as: :%s,\n" % r['as'])
        else:
            out[-1] = out[-1].rstrip(',\n') + '\n'
        if r['via']:
            # 宿主原式 `via: [:get, :post]`；反引号内已带冒号，直接去掉行首空白后原样输出。
            out.append("        via: [%s]\n" % r['via'].strip())
        else:
            out[-1] = out[-1].rstrip(',\n') + '\n'
    else:
        out.append("  # %s\n" % r['verb'].upper())
        out.append("  %s '%s',\n" % (r['verb'], r['path']))
        out.append("      to: '%s#%s',\n" % (r['controller'], r['action']))
        if r['as']:
            out.append("      as: :%s\n" % r['as'])
        else:
            out[-1] = out[-1].rstrip(',\n') + '\n'
    out.append('\n')

out.append("end\n")

text = ''.join(out)
# match 路由的 as 需放在 via 之后由 Rails 解析，此处保持 verb->path->to->as->via 的可读序
io.open(ADDON, 'w', encoding='utf-8', newline='\n').write(text)
print('WROTE %s (%d lines)' % (ADDON, text.count('\n')))