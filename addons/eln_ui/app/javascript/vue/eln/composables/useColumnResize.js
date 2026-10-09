// ============================================================================
// 列宽拖拽 + 表格横向滚动（复刻原生 /projects 的 ag-grid 行为）
//
// 原生口径（app/assets/builds/vue_projects_list.js → ag-grid）：
//   · 表格容器 domLayout 横向滚动，列总宽超出容器即出现横向滚动条
//   · 每个列头自带 resizable 手柄，拖拽改宽，minWidth 兜底
//   · colResizeDefault = 'shift'（按住 Shift 拖会改两侧列宽，单拖只改自己）
//   · 列宽持久化，刷新后保留
//   我们这里不复刻 ag-grid，只复刻**可观察行为**：手柄、拖拽改宽、横向滚动、持久化。
//
// 🔴 为什么宽度要走 CSS 变量而不是行内 style：
//   表头行和数据行是**两个独立 flex 容器**，列宽必须两边同步生效。
//   如果给每个 .th/.td 绑行内 width，既要写 2×N 个绑定、又容易漏；
//   写成 CSS 变量后**一条规则覆盖所有行**，且 drag 过程中只更新一个变量，
//   浏览器自己去重排 —— 拖拽 200 行也不会卡。
//
// 铁律：
//   1. 变量挂在**表格容器**上（--cw-name…），不是 :root —— 否则同页多个表格互相污染；
//   2. 宽度一律 min-width 兜底，不允许拖到 0（否则该列再也点不回来）；
//   3. 拖拽用 pointerdown + document 级监听（setPointerCapture 会让 mouseleave
//      时丢失事件，导致「拖出表格松手宽度卡住」这个经典 bug）；
//   4. 拖拽期间给 body 加 resizing 类禁掉文字选中，否则会一片蓝。
// ============================================================================

import { ref, onMounted, nextTick, onBeforeUnmount } from 'vue/dist/vue.esm-bundler.js'

// 列宽默认值 = 原型画布给的初始宽度；min = 拖拽下限；resizable = 哪些列可拖。
//   locked（星标/操作/选择这类固定小列）不给手柄，与原生「fixedWidth 列不参与 resize」同理。
export const COLUMN_WIDTHS = {
  check: { w: 40, min: 40, resizable: false },
  star: { w: 28, min: 28, resizable: false },
  name: { w: 220, min: 120, resizable: true },
  id: { w: 76, min: 48, resizable: true },
  status: { w: 92, min: 72, resizable: true },
  start: { w: 96, min: 80, resizable: true },
  due: { w: 96, min: 80, resizable: true },
  owner: { w: 112, min: 80, resizable: true },
  exp: { w: 100, min: 76, resizable: true },
  tasks: { w: 100, min: 76, resizable: true },
  users: { w: 116, min: 80, resizable: true },
  comments: { w: 64, min: 56, resizable: true },
  desc: { w: 240, min: 100, resizable: true },
  created: { w: 128, min: 100, resizable: true },
  updated: { w: 128, min: 100, resizable: true },
  archived: { w: 96, min: 80, resizable: true },
  action: { w: 40, min: 40, resizable: false }
}

const LS_KEY = 'eln.pl.colwidths.v1'

function loadSaved() {
  try {
    const raw = window.localStorage.getItem(LS_KEY)
    if (!raw) return {}
    const obj = JSON.parse(raw)
    return obj && typeof obj === 'object' ? obj : {}
  } catch (e) {
    // localStorage 不可用（隐私模式 / SSR）时静默降级为默认宽度
    return {}
  }
}

function persist(map) {
  try {
    window.localStorage.setItem(LS_KEY, JSON.stringify(map))
  } catch (e) {
    // 存不进去不影响功能，吞掉
  }
}

/**
 * @param {string} containerRef 表格容器 ref（CSS 变量挂它身上）
 */
export function useColumnResize(containerRef) {
  // 当前生效的列宽（已合并 localStorage）
  const widths = ref({})
  const dragKey = ref('')
  const dragStartX = ref(0)
  const dragStartW = ref(0)
  let shiftHeld = false

  function init() {
    const saved = loadSaved()
    const out = {}
    Object.keys(COLUMN_WIDTHS).forEach((k) => {
      const s = Number(saved[k])
      out[k] = Number.isFinite(s) && s > 0 ? s : COLUMN_WIDTHS[k].w
    })
    widths.value = out
    applyVars()
  }

  /** 把 widths 写成一组 CSS 变量挂到容器上（表头/数据行共用） */
  function applyVars() {
    const el = containerRef && containerRef.value
    if (!el || !el.style) return
    Object.keys(widths.value).forEach((k) => {
      el.style.setProperty(`--cw-${k}`, `${widths.value[k]}px`)
    })
  }

  function onDown(key, e) {
    const def = COLUMN_WIDTHS[key]
    if (!def || !def.resizable) return
    // 左键才拖；右键/中键留给浏览器菜单
    if (e.button !== 0) return
    e.preventDefault()
    e.stopPropagation()
    dragKey.value = key
    dragStartX.value = e.clientX
    dragStartW.value = widths.value[key] || def.w
    shiftHeld = e.shiftKey
    document.body.classList.add('eln-col-resizing')
    document.addEventListener('pointermove', onMove)
    document.addEventListener('pointerup', onUp)
    document.addEventListener('pointercancel', onUp)
  }

  function onMove(e) {
    const key = dragKey.value
    if (!key) return
    const def = COLUMN_WIDTHS[key]
    const delta = e.clientX - dragStartX.value
    let next = dragStartW.value + delta
    if (next < def.min) next = def.min
    if (next > 1200) next = 1200

    // Shift 语义对齐原生 colResizeDefault='shift'：把宽度差分给**右邻列**，
    // 这样总宽不变、不会出现「拖完整个表格变宽」。
    if (shiftHeld) {
      const neighbour = nextRightKey(key)
      if (neighbour) {
        const nd = COLUMN_WIDTHS[neighbour]
        const cur = widths.value[neighbour] || nd.w
        const other = cur - (next - (widths.value[key] || def.w))
        const clamped = Math.max(nd.min, other)
        widths.value = { ...widths.value, [key]: next, [neighbour]: clamped }
      } else {
        widths.value = { ...widths.value, [key]: next }
      }
    } else {
      widths.value = { ...widths.value, [key]: next }
    }
    applyVars()
  }

  function onUp() {
    if (dragKey.value) {
      persist(widths.value)
    }
    dragKey.value = ''
    document.body.classList.remove('eln-col-resizing')
    document.removeEventListener('pointermove', onMove)
    document.removeEventListener('pointerup', onUp)
    document.removeEventListener('pointercancel', onUp)
  }

  function nextRightKey(key) {
    const keys = Object.keys(COLUMN_WIDTHS)
    const i = keys.indexOf(key)
    return i >= 0 && i < keys.length - 1 ? keys[i + 1] : ''
  }

  /** 恢复默认宽度（列管理菜单里给一个入口，宽度调乱了要能回来） */
  function resetWidths() {
    const out = {}
    Object.keys(COLUMN_WIDTHS).forEach((k) => { out[k] = COLUMN_WIDTHS[k].w })
    widths.value = out
    persist(out)
    applyVars()
  }

  onBeforeUnmount(() => {
    document.body.classList.remove('eln-col-resizing')
    document.removeEventListener('pointermove', onMove)
    document.removeEventListener('pointerup', onUp)
    document.removeEventListener('pointercancel', onUp)
  })

  // 🔴 必须在 onMounted 之后才 applyVars，不能在 setup 期同步调 init()：
  //   setup 执行时模板还没渲染，containerRef.value === null，applyVars() 会静默
  //   return，于是 localStorage 里的列宽读出来了却**从没写进 DOM** ——
  //   表现是「刷新后列宽丢失」，而 widths ref 看着一切正常，极难察觉。
  //   （本轮真机验收就是靠这条抓到的：localStorage 有值但刷新后回默认。）
  onMounted(() => {
    init()
    nextTick(applyVars)
  })

  return { widths, dragKey, onDown, resetWidths, applyVars }
}
