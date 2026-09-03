(() => {
  let state = { plugins: [], backups: [], logs: [], restartRequired: false };
  const bridge = (name, ...args) => window.sketchup && window.sketchup[name] && window.sketchup[name](...args);
  const escapeHtml = value => String(value || '').replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const stamp = value => value ? new Date(value).toLocaleString('vi-VN') : '';
  function render() {
    document.querySelector('#exit').classList.toggle('hidden', !state.restartRequired);
    const term = document.querySelector('#search').value.toLowerCase();
    const plugins = state.plugins.filter(p => (p.name || '').toLowerCase().includes(term));
    document.querySelector('#plugins').innerHTML = plugins.length ? plugins.map(p => `<article class="card"><div><h3>${escapeHtml(p.name)}</h3><p class="meta">${escapeHtml(p.type)} · ${escapeHtml(p.status)}${p.version ? ' · v' + escapeHtml(p.version) : ''}</p>${p.path ? `<p class="meta">${escapeHtml(p.path)}</p>` : ''}</div><div class="actions">${p.managed ? `<button class="secondary" data-backup="${escapeHtml(p.id)}">Sao lưu</button><button class="danger" data-uninstall="${escapeHtml(p.id)}">Chuyển vào backup</button>` : '<span class="badge">Không do VEC quản lý</span>'}</div></article>`).join('') : '<div class="note">Không tìm thấy plugin phù hợp.</div>';
    document.querySelector('#backups-list').innerHTML = state.backups.length ? state.backups.map(b => `<article class="card"><div><h3>${escapeHtml(b.pluginName)}</h3><p class="meta">${escapeHtml(b.reason)} · ${stamp(b.createdAt)}</p></div><button data-restore="${escapeHtml(b.id)}">Khôi phục</button></article>`).join('') : '<div class="note">Chưa có bản sao lưu.</div>';
    document.querySelector('#logs-list').innerHTML = state.logs.length ? state.logs.map(l => `<article class="log"><strong>${escapeHtml(l.message)}</strong><time>${stamp(l.at)} · ${escapeHtml(l.action)}</time></article>`).join('') : '<div class="note">Chưa có thao tác nào.</div>';
  }
  window.VEC = { setState: next => { state = next; render(); } };
  document.addEventListener('click', event => {
    const tab = event.target.dataset.tab; if (tab) { document.querySelectorAll('.tab, nav button').forEach(e => e.classList.remove('active')); document.querySelector('#' + tab).classList.add('active'); event.target.classList.add('active'); }
    if (event.target.dataset.action === 'install-rb') bridge('vec_install_rb');
    if (event.target.dataset.action === 'install-rbz') bridge('vec_install_rbz');
    if (event.target.dataset.action === 'open-backups') bridge('vec_open_backup_folder');
    if (event.target.dataset.backup) bridge('vec_backup', event.target.dataset.backup);
    if (event.target.dataset.uninstall) bridge('vec_uninstall', event.target.dataset.uninstall);
    if (event.target.dataset.restore) bridge('vec_restore', event.target.dataset.restore);
    if (event.target.id === 'exit') bridge('vec_exit');
  });
  document.querySelector('#search').addEventListener('input', render);
  bridge('vec_ready');
})();
