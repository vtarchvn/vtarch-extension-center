(() => {
  let state = { plugins: [], backups: [], profiles: [], logs: [], settings: {}, backupStats: {}, catalog: {}, restartRequired: false };
  const showNotice = message => {
    const notice = document.querySelector('#app-notice');
    notice.textContent = message;
    notice.classList.remove('hidden');
  };
  const hasCallback = name => window.sketchup && typeof window.sketchup[name] === 'function';
  const bridge = (name, ...args) => {
    if (hasCallback(name)) return window.sketchup[name](...args);
    showNotice(window.sketchup ? 'VEC đang kết nối với SketchUp. Vui lòng thử lại sau vài giây.' : 'Chức năng này chỉ hoạt động khi VEC được mở bên trong SketchUp, không phải trong trình duyệt web.');
    return false;
  };
  const escapeHtml = value => String(value || '').replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const stamp = value => value ? new Date(value).toLocaleString('vi-VN') : '';
  const bytes = value => value < 1024 * 1024 ? `${Math.round(value / 1024)} KB` : `${(value / 1024 / 1024).toFixed(1)} MB`;
  function render() {
    document.querySelector('#exit').classList.toggle('hidden', !state.restartRequired);
    const term = document.querySelector('#search').value.toLowerCase();
    const type = document.querySelector('#filter-type').value;
    const scope = document.querySelector('#filter-scope').value;
    const sort = document.querySelector('#sort-plugins').value;
    const plugins = state.plugins.filter(p => {
      const typeMatch = type === 'all' || (type === 'RB' ? ['RB', 'RBZ'].includes(p.type) : p.type === type);
      const scopeMatch = scope === 'all' || (scope === 'managed' ? p.managed : !p.managed);
      return typeMatch && scopeMatch && (p.name || '').toLowerCase().includes(term);
    }).sort((a, b) => String(sort === 'type' ? a.type : sort === 'status' ? a.status : a.name).localeCompare(String(sort === 'type' ? b.type : sort === 'status' ? b.status : b.name), 'vi'));
    document.querySelector('#plugins').innerHTML = plugins.length ? plugins.map(p => {
      const detail = [p.creator && `Tác giả: ${escapeHtml(p.creator)}`, p.description && escapeHtml(p.description), p.installedAt && `VEC cài: ${stamp(p.installedAt)}`, p.source && `Nguồn: ${escapeHtml(p.source)}`, p.path && escapeHtml(p.path)].filter(Boolean).map(line => `<p class="meta">${line}</p>`).join('');
      const manager = p.management === 'vec' ? 'VEC quản lý' : p.management === 'sketchup' ? 'SketchUp quản lý' : 'Không do VEC quản lý';
      const actions = [];
      if (p.toggleable) actions.push(`<button data-toggle="${escapeHtml(p.name)}" data-enabled="${p.enabled ? 'false' : 'true'}">${p.enabled ? 'Tắt' : 'Bật'}</button>`);
      if (p.managed) actions.push(`<button class="secondary" data-backup="${escapeHtml(p.id)}">Sao lưu</button><button class="danger" data-uninstall="${escapeHtml(p.id)}">Chuyển vào backup</button>`);
      if (p.path) actions.push(`<button class="secondary" data-open-location="${escapeHtml(p.id)}">Mở vị trí</button>`);
      if (p.adoptable) actions.push(`<button class="secondary" data-adopt="${escapeHtml(p.id)}">Đưa vào VEC quản lý</button>`);
      return `<article class="card"><div><h3>${escapeHtml(p.name)}</h3><p class="meta">${escapeHtml(p.type)} · ${escapeHtml(p.status)}${p.version ? ' · v' + escapeHtml(p.version) : ''}</p><p class="meta"><span class="badge">${manager}</span></p>${detail}</div><div class="actions">${actions.join('') || '<span class="badge">Không có thao tác</span>'}</div></article>`;
    }).join('') : '<div class="note">Không tìm thấy plugin phù hợp.</div>';
    const backupTerm = document.querySelector('#backup-search').value.toLowerCase();
    const backupDate = document.querySelector('#backup-date').value;
    const backupReason = document.querySelector('#backup-reason').value.toLowerCase();
    const backups = state.backups.filter(b => (!backupTerm || String(b.pluginName || '').toLowerCase().includes(backupTerm)) && (!backupDate || String(b.createdAt || '').startsWith(backupDate)) && (!backupReason || String(b.reason || '').toLowerCase().includes(backupReason)));
    document.querySelector('#backups-list').innerHTML = backups.length ? backups.map(b => `<article class="card"><div><h3>${escapeHtml(b.pluginName)}</h3><p class="meta">${escapeHtml(b.reason)} · ${stamp(b.createdAt)} · ${bytes(b.sizeBytes || 0)}</p></div><div class="actions"><button class="secondary" data-backup-detail="${escapeHtml(b.id)}">Chi tiết</button><button data-restore="${escapeHtml(b.id)}">Khôi phục</button></div></article>`).join('') : '<div class="note">Không có bản sao lưu phù hợp.</div>';
    const logTerm = document.querySelector('#log-search').value.toLowerCase();
    const logs = state.logs.filter(l => `${l.message} ${l.action}`.toLowerCase().includes(logTerm));
    document.querySelector('#logs-list').innerHTML = logs.length ? logs.map(l => `<article class="log"><strong>${escapeHtml(l.message)}</strong><time>${stamp(l.at)} · ${escapeHtml(l.action)}</time></article>`).join('') : '<div class="note">Không có nhật ký phù hợp.</div>';
    document.querySelector('#profiles-list').innerHTML = state.profiles.length ? state.profiles.map(p => `<article class="card"><div><h3>${escapeHtml(p.name)}</h3><p class="meta">${p.extensions.length} extension · ${stamp(p.createdAt)}</p></div><button data-apply-profile="${escapeHtml(p.id)}">Áp dụng</button></article>`).join('') : '<div class="note">Chưa có profile nào.</div>';
    document.querySelector('#max-backups').value = state.settings.maxBackupsPerPlugin || 0;
    document.querySelector('#backup-limit').value = state.settings.backupLimitMb || 0;
    document.querySelector('#backup-path').textContent = state.settings.backupPath || 'Vị trí mặc định của VEC';
    document.querySelector('#backup-stats').textContent = `${state.backupStats.count} bản sao lưu · ${bytes(state.backupStats.sizeBytes || 0)}`;
    document.querySelector('#catalog-url').value = state.settings.catalogUrl || '';
  }
  window.VEC = { setState: next => { state = next; document.querySelector('#app-notice').classList.add('hidden'); render(); } };
  window.VEC.showError = message => showNotice(message);
  window.VEC.setCatalog = catalog => { state.catalog = catalog; const list = Array(catalog.plugins || []); document.querySelector('#catalog-list').innerHTML = list.length ? list.map(p => `<article class="card"><div><h3>${escapeHtml(p.name)}</h3><p class="meta">v${escapeHtml(p.version)}${p.author ? ' · ' + escapeHtml(p.author) : ''}</p><p class="meta">${escapeHtml(p.description || '')}</p></div><button data-catalog-install="${escapeHtml(p.id)}">Cài đặt</button></article>`).join('') : '<div class="note">Danh mục chưa có plugin.</div>'; };
  window.VEC.setDiagnostics = report => {
    const issues = report.missingFiles.length ? `File thiếu: ${escapeHtml(report.missingFiles.join(', '))}` : 'Không phát hiện file plugin bị thiếu.';
    document.querySelector('#diagnostics-result').innerHTML = `<h3>SketchUp ${escapeHtml(report.sketchupVersion)} · ${escapeHtml(report.platform)}</h3><p>Plugins: ${escapeHtml(report.pluginsDir)}</p><p>Backup: ${escapeHtml(report.backupDir)}</p><p>Quyền ghi Plugins: ${report.pluginsWritable ? 'Có' : 'Không'} · Backup: ${report.backupWritable ? 'Có' : 'Không'}</p><p>${issues}</p>`;
  };
  window.VEC.showBackupDetail = backup => {
    const files = (backup.files || []).map(file => `<li><code>${escapeHtml(file.originalPath)}</code> · ${bytes(file.sizeBytes || 0)}</li>`).join('');
    const panel = document.querySelector('#backup-detail');
    panel.innerHTML = `<h3>${escapeHtml(backup.pluginName)}</h3><p>${escapeHtml(backup.reason)} · ${stamp(backup.createdAt)}</p><p>${escapeHtml(backup.files ? backup.files.length : 0)} mục · ${bytes(backup.sizeBytes || 0)}</p><ul class="file-list">${files || '<li>Không có file.</li>'}</ul>`;
    panel.classList.remove('hidden');
  };
  document.addEventListener('click', event => {
    const tab = event.target.dataset.tab; if (tab) { document.querySelectorAll('.tab, nav button').forEach(e => e.classList.remove('active')); document.querySelector('#' + tab).classList.add('active'); event.target.classList.add('active'); }
    if (event.target.dataset.action === 'install-rb') bridge('vec_install_rb');
    if (event.target.dataset.action === 'install-rbz') bridge('vec_install_rbz');
    if (event.target.dataset.action === 'catalog-load') bridge('vec_catalog_load', document.querySelector('#catalog-url').value);
    if (event.target.dataset.action === 'open-backups') bridge('vec_open_backup_folder');
    if (event.target.dataset.action === 'backup-all') bridge('vec_backup_all');
    if (event.target.dataset.action === 'diagnostics') bridge('vec_diagnostics');
    if (event.target.dataset.action === 'export-diagnostics') bridge('vec_export_diagnostics');
    if (event.target.dataset.action === 'save-profile') bridge('vec_save_profile', document.querySelector('#profile-name').value);
    if (event.target.dataset.action === 'export-profiles') bridge('vec_export_profiles');
    if (event.target.dataset.action === 'import-profiles') bridge('vec_import_profiles');
    if (event.target.dataset.action === 'export-migration') bridge('vec_export_migration');
    if (event.target.dataset.action === 'import-migration') bridge('vec_import_migration');
    if (event.target.dataset.action === 'save-settings') bridge('vec_save_settings', JSON.stringify({ maxBackupsPerPlugin: document.querySelector('#max-backups').value, backupLimitMb: document.querySelector('#backup-limit').value }));
    if (event.target.dataset.action === 'choose-backup-dir') bridge('vec_choose_backup_dir');
    if (event.target.dataset.action === 'reset-backup-dir') bridge('vec_reset_backup_dir');
    if (event.target.dataset.backup) bridge('vec_backup', event.target.dataset.backup);
    if (event.target.dataset.adopt) bridge('vec_adopt', event.target.dataset.adopt);
    if (event.target.dataset.uninstall) bridge('vec_uninstall', event.target.dataset.uninstall);
    if (event.target.dataset.restore) bridge('vec_restore', event.target.dataset.restore);
    if (event.target.dataset.catalogInstall) bridge('vec_catalog_install', event.target.dataset.catalogInstall);
    if (event.target.dataset.openLocation) bridge('vec_open_plugin_location', event.target.dataset.openLocation);
    if (event.target.dataset.backupDetail) { const backup = state.backups.find(item => item.id === event.target.dataset.backupDetail); if (backup) window.VEC.showBackupDetail(backup); }
    if (event.target.dataset.toggle) bridge('vec_toggle_extension', event.target.dataset.toggle, event.target.dataset.enabled);
    if (event.target.dataset.applyProfile) bridge('vec_apply_profile', event.target.dataset.applyProfile);
    if (event.target.id === 'exit') bridge('vec_exit');
  });
  document.querySelector('#search').addEventListener('input', render);
  document.querySelector('#log-search').addEventListener('input', render);
  ['#backup-search', '#backup-date', '#backup-reason'].forEach(selector => document.querySelector(selector).addEventListener('input', render));
  ['#filter-type', '#filter-scope', '#sort-plugins'].forEach(selector => document.querySelector(selector).addEventListener('change', render));
  if (!window.sketchup) {
    showNotice('Chế độ xem trước: hãy mở VEC từ Extensions > VTARCH Extension Center trong SketchUp để dùng các nút chức năng.');
  } else {
    // Trên một số bản SketchUp, callback được bơm vào HtmlDialog chậm hơn
    // lúc JavaScript chạy lần đầu. Chờ tối đa 5 giây để lấy trạng thái.
    let readyAttempts = 0;
    const requestState = () => {
      if (hasCallback('vec_ready')) { bridge('vec_ready'); return; }
      readyAttempts += 1;
      if (readyAttempts < 25) window.setTimeout(requestState, 200);
      else showNotice('Không thể kết nối VEC với SketchUp. Hãy đóng cửa sổ VEC và mở lại từ menu Extensions.');
    };
    requestState();
  }
})();
