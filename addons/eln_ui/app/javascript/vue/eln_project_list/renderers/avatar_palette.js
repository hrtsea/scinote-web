// ELN 头像调色板 —— 与「旧版」保持一致。
//
// 真源：原型 ELN系统-Vue3/src/data/mock.js#avatarPalette 与旧 addon blob
// （eln_vue3/eln_project_list.js 内联的 _i 调色板）两处**逐字节一致**：
//   blue:#DBEAFE/#2563EB  green:#E7F7E9/#047857  orange:#FCF2E3/#B45309
//   purple:#E9DFF6/#6D28D9  cyan:#E3F6F7/#0E7490
// 形态是「浅底 + 深字」，不是实心色块 —— 对齐旧版，别改成实心。
//
// color key 由后端下发：payload 的 AVATAR_COLORS = %w[blue green orange cyan purple]，
// 组授予恒为 GROUP_AVATAR_COLOR = 'blue'。取不到就回落 blue（与旧版 `|| avatarPalette.blue` 同）。
export const AVATAR_PALETTE = {
  blue: { background: '#DBEAFE', color: '#2563EB' },
  green: { background: '#E7F7E9', color: '#047857' },
  orange: { background: '#FCF2E3', color: '#B45309' },
  purple: { background: '#E9DFF6', color: '#6D28D9' },
  cyan: { background: '#E3F6F7', color: '#0E7490' }
};

export function avatarStyle(color) {
  return AVATAR_PALETTE[color] || AVATAR_PALETTE.blue;
}

// 头像之间的叠压间距（旧版 `.avatar-group .avatar + .avatar { margin-left: -6px }`）
export const AVATAR_OVERLAP_PX = -6;

// 叠压时每个头像的描边色 = 卡片底色（旧版 `border: 2px solid var(--color-card)`）。
// 宿主 token：sn-white #FFFFFF。
export const AVATAR_BORDER = '#FFFFFF';

// 「+N」气泡（旧版 `.avatar.more`：--color-border 底 + --color-subtle-text 字）。
// 宿主 token：sn-light-grey #EAECF0 / sn-dark-grey #475467。
export const AVATAR_MORE = { background: '#EAECF0', color: '#475467' };
