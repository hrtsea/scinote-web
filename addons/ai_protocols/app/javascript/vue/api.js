// AI 协议解析（Import with AI）前端 API 封装。
// 端点族对齐官方源码级反抽 §3（资源名 parsed_protocols，JSON:API 响应）。
// 用原生 fetch（带 CSRF），避免引入 axios 依赖。

function csrfToken() {
  const el = document.querySelector('meta[name="csrf-token"]');
  return el ? el.getAttribute('content') : '';
}

function jsonHeaders() {
  return {
    'X-CSRF-Token': csrfToken(),
    'X-Requested-With': 'XMLHttpRequest'
  };
}

// GET /parsed_protocols/remaining_count -> { data: { daily_limit, remaining_count } }
export async function remainingCount() {
  const res = await fetch('/parsed_protocols/remaining_count', { headers: jsonHeaders() });
  return res.json();
}

// POST /parsed_protocols -> { data: { id } }
//   body: parsed_protocol[mode] (prompt_only|file_upload),
//         parsed_protocol[prompt], parsed_protocol[file] (File)
export async function createProtocol({ mode, prompt, file }) {
  const form = new FormData();
  form.append('parsed_protocol[mode]', mode || 'prompt_only');
  form.append('parsed_protocol[prompt]', prompt || '');
  if (file) form.append('parsed_protocol[file]', file);

  const res = await fetch('/parsed_protocols', {
    method: 'POST',
    headers: jsonHeaders(),
    body: form
  });
  if (!res.ok) {
    let msg = '';
    try { msg = (await res.json()).data?.error || ''; } catch (e) { /* ignore */ }
    const err = new Error(msg || `HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

// GET /parsed_protocols/:id -> { data: { id, attributes: { status, valid, parsed_data, last_error } } }
export async function showProtocol(id) {
  const res = await fetch(`/parsed_protocols/${id}`, { headers: jsonHeaders() });
  return res.json();
}

// POST /parsed_protocols/:id/import -> { data: { success, protocol_id } }
//   body: my_module_id, load_mode (merge|replace)
export async function importProtocol(id, { myModuleId, loadMode }) {
  const form = new FormData();
  if (myModuleId) form.append('my_module_id', myModuleId);
  form.append('load_mode', loadMode || 'replace');

  const res = await fetch(`/parsed_protocols/${id}/import`, {
    method: 'POST',
    headers: jsonHeaders(),
    body: form
  });
  if (!res.ok) {
    let msg = '';
    try { msg = (await res.json()).data?.error || ''; } catch (e) { /* ignore */ }
    const err = new Error(msg || `HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}
