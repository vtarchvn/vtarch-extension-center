(() => {
  let state = { plugins: [], backups: [], profiles: [], logs: [], restartRequired: false };
  const bridge = (name, ...args) => window.sketchup && window.sketchup[name] && window.sketchup[name](...args);
  const escapeHtml = value => String(value || '').replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const stamp = value => value ? new Date(value).toLocaleString('vi-VN') : '';
  const bytes = value => value < 1024 * 1024 ? `${Math.round(value / 1024)} KB` : `${(value / 1024 / 1024).toFixed(1)} MB`;
  function render() {
    document.querySelector('#exit').classList.toggle('hidden', !state.restartRequired);
    const term = document.querySelector('#search').value.toLowerCase();
    const plugins = state.plugins.filter(p => (p.name || '').toLowerCase().includes(term));
    document.querySelector('#plugins').innerHTML = plugins.length ? plugins.map(p => `<article class="card"><div><h3>${escapeHtml(p.name)}</h3><p class="meta">${escapeHtml(p.type)} · ${escapeHtml(p.status)}${p.version ? ' · v' + escapeHtml(p.version) : ''}</p>${p.path ? `<p class="meta">${escapeHtml(p.path)}</p>` : ''}</div><div class="actions">${p.managed ? `<button class="secondary" data-backup="${escapeHtml(p.id)}">Sao lưu</button><button class="danger" data-uninstall="${escapeHtml(p.id)}">Chuyển vào backup</button>` : p.toggleable ? `<button data-toggle="${escapeHtml(p.name)}" data-enabled="${p.enabled ? 'false' : 'true'}">${p.enabled ? 'Tắt' : 'Bật'}</button>` : '<span class="badge">Không do VEC quản lý</span>'}</div></article>`).join('') : '<div class="note">Không tìm thấy plugin phù hợp.</div>';
    document.querySelector('#backups-list').innerHTML = state.backups.length ? state.backups.map(b => `<article class="card"><div><h3>${escapeHtml(b.pluginName)}</h3><p class="meta">${escapeHtml(b.reason)} · ${stamp(b.createdAt)} · ${bytes(b.sizeBytes || 0)}</p></div><button data-restore="${escapeHtml(b.id)}">Khôi phục</button></article>`).join('') : '<div class="note">Chưa có bản sao lưu.</div>';
    document.querySelector('#logs-list').innerHTML = state.logs.length ? state.logs.map(l => `<article class="log"><strong>${escapeHtml(l.message)}</strong><time>${stamp(l.at)} · ${escapeHtml(l.action)}</time></article>`).join('') : '<div class="note">Chưa có thao tác nào.</div>';
    document.querySelector('#profiles-list').innerHTML = state.profiles.length ? state.profiles.map(p => `<article class="card"><div><h3>${escapeHtml(p.name)}</h3><p class="meta">${p.extensions.length} extension · ${stamp(p.createdAt)}</p></div><button data-apply-profile="${escapeHtml(p.id)}">Áp dụng</button></article>`).join('') : '<div class="note">Chưa có profile nào.</div>';
    document.querySelector('#max-backups').value = state.settings.maxBackupsPerPlugin || 0;
    document.querySelector('#backup-limit').value = state.settings.backupLimitMb || 0;
    document.querySelector('#backup-stats').textContent = `${state.backupStats.count} bản sao lưu · ${bytes(state.backupStats.sizeBytes || 0)}`;
  }
  window.VEC = { setState: next => { state = next; render(); } };
  window.VEC.setDiagnostics = report => {
    const issues = report.missingFiles.length ? `File thiếu: ${escapeHtml(report.missingFiles.join(', '))}` : 'Không phát hiện file plugin bị thiếu.';
    document.querySelector('#diagnostics-result').innerHTML = `<h3>SketchUp ${escapeHtml(report.sketchupVersion)} · ${escapeHtml(report.platform)}</h3><p>Plugins: ${escapeHtml(report.pluginsDir)}</p><p>Backup: ${escapeHtml(report.backupDir)}</p><p>Quyền ghi Plugins: ${report.pluginsWritable ? 'Có' : 'Không'} · Backup: ${report.backupWritable ? 'Có' : 'Không'}</p><p>${issues}</p>`;
  };
  document.addEventListener('click', event => {
    const tab = event.target.dataset.tab; if (tab) { document.querySelectorAll('.tab, nav button').forEach(e => e.classList.remove('active')); document.querySelector('#' + tab).classList.add('active'); event.target.classList.add('active'); }
    if (event.target.dataset.action === 'install-rb') bridge('vec_install_rb');
    if (event.target.dataset.action === 'install-rbz') bridge('vec_install_rbz');
    if (event.target.dataset.action === 'open-backups') bridge('vec_open_backup_folder');
    if (event.target.dataset.action === 'diagnostics') bridge('vec_diagnostics');
    if (event.target.dataset.action === 'save-profile') bridge('vec_save_profile', document.querySelector('#profile-name').value);
    if (event.target.dataset.action === 'export-profiles') bridge('vec_export_profiles');
    if (event.target.dataset.action === 'import-profiles') bridge('vec_import_profiles');
    if (event.target.dataset.action === 'save-settings') bridge('vec_save_settings', JSON.stringify({ maxBackupsPerPlugin: document.querySelector('#max-backups').value, backupLimitMb: document.querySelector('#backup-limit').value }));
    if (event.target.dataset.backup) bridge('vec_backup', event.target.dataset.backup);
    if (event.target.dataset.uninstall) bridge('vec_uninstall', event.target.dataset.uninstall);
    if (event.target.dataset.restore) bridge('vec_restore', event.target.dataset.restore);
    if (event.target.dataset.toggle) bridge('vec_toggle_extension', event.target.dataset.toggle, event.target.dataset.enabled);
    if (event.target.dataset.applyProfile) bridge('vec_apply_profile', event.target.dataset.applyProfile);
    if (event.target.id === 'exit') bridge('vec_exit');
  });
  document.querySelector('#search').addEventListener('input', render);
  bridge('vec_ready');
})();
