# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'time'
require File.join(File.dirname(__FILE__), 'zip_archive')

module VTARCH
  module VEC
    extend self

    PLUGIN_ID = 'vtarch_vec'
    DATA_DIR_NAME = 'VTARCH VEC'

    def show_dialog
      @dialog ||= build_dialog
      @dialog.show
      send_state
    end

    def build_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title: 'VTARCH Extension Center (VEC)',
        preferences_key: 'VTARCH::VEC',
        scrollable: true,
        resizable: true,
        width: 1060,
        height: 700,
        min_width: 820,
        min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_file(File.join(extension_dir, 'ui', 'index.html'))
      dialog.add_action_callback('vec_ready') { |_ctx| send_state }
      dialog.add_action_callback('vec_install_rb') { |_ctx| install_rb_dialog }
      dialog.add_action_callback('vec_install_rbz') { |_ctx| install_rbz_dialog }
      dialog.add_action_callback('vec_backup') { |_ctx, id| backup_plugin(id) }
      dialog.add_action_callback('vec_uninstall') { |_ctx, id| uninstall_plugin(id) }
      dialog.add_action_callback('vec_restore') { |_ctx, id| restore_backup(id) }
      dialog.add_action_callback('vec_toggle_extension') { |_ctx, name, enabled| toggle_extension(name, enabled == 'true') }
      dialog.add_action_callback('vec_diagnostics') { |_ctx| send_diagnostics }
      dialog.add_action_callback('vec_export_diagnostics') { |_ctx| export_diagnostics }
      dialog.add_action_callback('vec_save_profile') { |_ctx, name| save_profile(name) }
      dialog.add_action_callback('vec_apply_profile') { |_ctx, id| apply_profile(id) }
      dialog.add_action_callback('vec_export_profiles') { |_ctx| export_profiles }
      dialog.add_action_callback('vec_import_profiles') { |_ctx| import_profiles }
      dialog.add_action_callback('vec_save_settings') { |_ctx, payload| save_settings(payload) }
      dialog.add_action_callback('vec_open_backup_folder') { |_ctx| UI.openURL("file:///#{backup_dir.tr('\\\\', '/')}") }
      dialog.add_action_callback('vec_exit') { |_ctx| exit_to_apply }
      dialog.set_on_closed { @dialog = nil }
      dialog
    end

    def extension_dir
      File.dirname(__FILE__)
    end

    def plugins_dir
      Sketchup.find_support_file('Plugins') || File.dirname(__FILE__)
    end

    def data_dir
      @data_dir ||= begin
        base = Sketchup.find_support_file('') || ENV['APPDATA'] || Dir.home
        path = File.join(base, DATA_DIR_NAME)
        FileUtils.mkdir_p(path)
        path
      end
    end

    def backup_dir
      path = File.join(data_dir, 'backups')
      FileUtils.mkdir_p(path)
      path
    end

    def registry_path
      File.join(data_dir, 'registry.json')
    end

    def log_path
      File.join(data_dir, 'activity.json')
    end

    def settings_path
      File.join(data_dir, 'settings.json')
    end

    def settings
      @settings ||= { 'maxBackupsPerPlugin' => 0, 'backupLimitMb' => 0 }.merge(read_json(settings_path, {}))
    end

    def save_settings(payload)
      incoming = JSON.parse(payload.to_s)
      @settings = {
        'maxBackupsPerPlugin' => [incoming['maxBackupsPerPlugin'].to_i, 0].max,
        'backupLimitMb' => [incoming['backupLimitMb'].to_i, 0].max
      }
      write_json(settings_path, @settings)
      log('settings', 'Đã lưu cài đặt backup')
      notify('Đã lưu cài đặt backup.')
      send_state
    rescue JSON::ParserError
      notify('Cài đặt không hợp lệ.')
    end

    def profiles_dir
      path = File.join(data_dir, 'profiles')
      FileUtils.mkdir_p(path)
      path
    end

    def registry
      @registry ||= read_json(registry_path, { 'plugins' => {} })
    end

    def save_registry
      write_json(registry_path, registry)
    end

    def send_state
      return unless @dialog
      state = {
        plugins: scanned_plugins,
        tracked: registry['plugins'].values,
        backups: backups,
        profiles: profiles,
        settings: settings,
        backupStats: backup_stats,
        logs: read_json(log_path, []),
        restartRequired: restart_required?
      }
      @dialog.execute_script("window.VEC && window.VEC.setState(#{JSON.generate(state)});")
    end

    def scanned_plugins
      extensions = Sketchup.extensions.map do |ext|
        {
          id: "extension:#{ext.name}", name: ext.name, version: ext.version.to_s,
          creator: ext.creator.to_s, description: ext.description.to_s,
          type: 'Extension', status: (ext.load_on_start? ? 'Bật khi khởi động' : 'Tắt khi khởi động'),
          path: ext.extension_path.to_s, managed: false, toggleable: ext.name != EXTENSION_NAME,
          enabled: ext.load_on_start?
        }
      end
      tracked = registry['plugins'].values.map do |item|
        item.merge(
          'managed' => Array(item['paths']).any?,
          'status' => (Array(item['paths']).any? ? 'Được VEC theo dõi' : 'Đã cài qua VEC')
        )
      end
      tracked_paths = tracked.flat_map { |item| Array(item['paths']) }
      scripts = Dir.glob(File.join(plugins_dir, '*.rb')).reject { |path| tracked_paths.include?(path) }.map do |path|
        { 'id' => "script:#{path}", 'name' => File.basename(path), 'type' => 'Script .rb',
          'status' => 'Không do VEC theo dõi', 'path' => path, 'managed' => false }
      end
      (extensions + tracked + scripts).sort_by { |item| (item['name'] || item[:name]).to_s.downcase }
    rescue StandardError => e
      log('error', "Không thể quét extension: #{e.message}")
      []
    end

    def install_rb_dialog
      source = UI.openpanel('Chọn file Ruby (.rb)', plugins_dir, 'Ruby Files|*.rb||')
      return unless source && File.file?(source)
      sources = [source]
      companion = File.join(File.dirname(source), File.basename(source, '.rb'))
      if File.directory?(companion) && UI.messagebox("Phát hiện thư mục phụ trợ #{File.basename(companion)}. Cài cùng plugin?", MB_YESNO) == IDYES
        sources << companion
      end
      targets = sources.map { |item| File.join(plugins_dir, File.basename(item)) }
      overwritten = targets.select { |target| File.exist?(target) }
      if overwritten.any? && UI.messagebox("Các mục sẽ bị ghi đè:\n#{overwritten.map { |item| File.basename(item) }.join("\n")}\n\nVEC sẽ backup trước. Tiếp tục?", MB_YESNO) != IDYES
        return
      end
      install_files(sources, 'rb', File.basename(source, '.rb'))
    end

    def install_rbz_dialog
      source = UI.openpanel('Chọn gói SketchUp (.rbz)', plugins_dir, 'SketchUp Extension|*.rbz||')
      return unless source && File.file?(source)
      begin
        entries = ZipArchive.entries(source)
      files = entries.reject { |entry| entry.name.end_with?('/') }
      loaders = files.select { |entry| entry.name.end_with?('.rb') && !entry.name.include?('/') }
      targets = files.map { |entry| File.join(plugins_dir, entry.name) }
      overwritten = targets.select { |target| File.exist?(target) }
      preview = files.first(25).map(&:name).join("\n")
      preview += "\n... và #{files.length - 25} file khác" if files.length > 25
      detail = ["#{files.length} file", (loaders.empty? ? 'Không tìm thấy loader .rb ở gốc.' : "Loader: #{loaders.map(&:name).join(', ')}"), (overwritten.empty? ? nil : "Ghi đè: #{overwritten.length} file")].compact.join("\n")
      return unless UI.messagebox("Cài #{File.basename(source)}?\n\n#{detail}\n\nXem trước:\n#{preview}\n\nVEC sẽ theo dõi file để chuyển nguyên plugin vào backup.", MB_YESNO) == IDYES
        install_rbz(source, entries)
      rescue StandardError => e
        log('error', "Lỗi cài RBZ: #{e.message}")
        notify("Không thể cài .rbz: #{e.message}")
      ensure
        send_state
      end
    end

    def install_rbz(source, entries)
      name = File.basename(source, '.rbz')
      files = entries.reject { |entry| entry.name.end_with?('/') }
      targets = files.map { |entry| File.join(plugins_dir, entry.name) }
      existing = targets.select { |path| File.exist?(path) }
      unless existing.empty?
        move_paths_to_backup(existing, name, 'ghi đè khi cài RBZ')
      end
      staging = File.join(data_dir, 'staging', "#{Time.now.to_i}_#{safe_name(name)}")
      FileUtils.rm_rf(staging) if File.exist?(staging)
      ZipArchive.extract(source, staging, entries)
      files.each do |entry|
        source_file = File.join(staging, entry.name)
        target = File.join(plugins_dir, entry.name)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source_file, target)
      end
      register_plugin(name, 'rbz', targets, source)
      log('install', "Đã cài #{name} (#{targets.length} file)")
      mark_restart_required
      notify('Cài đặt thành công. Hãy thoát SketchUp để áp dụng thay đổi.')
    ensure
      FileUtils.rm_rf(staging) if staging && File.exist?(staging)
      send_state
    end

    def install_files(sources, kind, name)
      paths = sources.map { |source| File.join(plugins_dir, File.basename(source)) }
      existing = paths.select { |path| File.exist?(path) }
      move_paths_to_backup(existing, name, 'ghi đè') unless existing.empty?
      sources.zip(paths).each { |source, target| FileUtils.cp_r(source, target) }
      register_plugin(name, kind, paths, nil)
      log('install', "Đã cài #{name}")
      mark_restart_required
      notify('Cài đặt thành công. Hãy thoát SketchUp để áp dụng thay đổi.')
    rescue StandardError => e
      log('error', "Lỗi cài #{name}: #{e.message}")
      notify("Không thể cài plugin: #{e.message}")
    ensure
      send_state
    end

    def backup_plugin(id)
      item = registry['plugins'][id]
      return notify('VEC chỉ sao lưu tự động các plugin do VEC theo dõi.') unless item
      backup_paths(item['paths'] || [], item['name'], 'sao lưu thủ công')
      notify('Đã tạo bản sao lưu.')
      send_state
    end

    def uninstall_plugin(id)
      item = registry['plugins'][id]
      return notify('VEC chỉ gỡ tự động các plugin do VEC theo dõi.') unless item
      return unless UI.messagebox("Chuyển #{item['name']} vào thư mục backup? File sẽ không bị xóa.", MB_YESNO) == IDYES
      move_paths_to_backup(item['paths'] || [], item['name'], 'chuyển vào backup')
      registry['plugins'].delete(id)
      save_registry
      log('archive', "Đã chuyển #{item['name']} vào backup")
      mark_restart_required
      notify('Đã chuyển plugin vào backup. Hãy thoát SketchUp để áp dụng thay đổi.')
      send_state
    rescue StandardError => e
      log('error', "Lỗi gỡ plugin: #{e.message}")
      notify("Không thể gỡ plugin: #{e.message}")
    end

    def restore_backup(id)
      manifest = backups.find { |entry| entry['id'] == id }
      return notify('Không tìm thấy bản sao lưu.') unless manifest
      return unless UI.messagebox("Khôi phục #{manifest['pluginName']}? File hiện có cùng đường dẫn sẽ được chuyển vào backup trước.", MB_YESNO) == IDYES
      files_root = File.join(backup_dir, id, 'files')
      existing = manifest['files'].map { |file| file['originalPath'] }.select { |path| File.exist?(path) }
      move_paths_to_backup(existing, manifest['pluginName'], 'trạng thái trước khi khôi phục', cleanup: false) unless existing.empty?
      manifest['files'].each do |file|
        source = File.join(files_root, file['storedAs'])
        target = file['originalPath']
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(source, target)
      end
      cleanup_old_backups(manifest['pluginName'])
      log('restore', "Đã khôi phục #{manifest['pluginName']}")
      mark_restart_required
      notify('Đã khôi phục. Hãy thoát SketchUp để áp dụng thay đổi.')
      send_state
    rescue StandardError => e
      log('error', "Lỗi khôi phục: #{e.message}")
      notify("Không thể khôi phục: #{e.message}")
    end

    def toggle_extension(name, enabled)
      extension = Sketchup.extensions[name]
      return notify('Không tìm thấy extension.') unless extension
      enabled ? extension.check : extension.uncheck
      mark_restart_required
      log('extension', "Đã #{enabled ? 'bật' : 'tắt'} #{name} cho lần khởi động tiếp theo")
      notify("Đã #{enabled ? 'bật' : 'tắt'} extension. Hãy thoát SketchUp để áp dụng thay đổi.")
      send_state
    rescue StandardError => e
      log('error', "Lỗi thay đổi extension: #{e.message}")
      notify("Không thể thay đổi extension: #{e.message}")
    end

    def diagnostics
      plugin_issues = scanned_plugins.select do |item|
        path = item['path'] || item[:path]
        path && !path.empty? && !File.exist?(path)
      end
      {
        sketchupVersion: Sketchup.version.to_s,
        platform: Sketchup.platform.to_s,
        pluginsDir: plugins_dir,
        backupDir: backup_dir,
        pluginsWritable: File.writable?(plugins_dir),
        backupWritable: File.writable?(backup_dir),
        registeredExtensions: Sketchup.extensions.count,
        trackedPlugins: registry['plugins'].length,
        missingFiles: plugin_issues.map { |item| item['name'] || item[:name] },
        checkedAt: Time.now.iso8601
      }
    end

    def send_diagnostics
      report = diagnostics
      log('diagnostic', "Đã chạy chẩn đoán: #{report['missingFiles'].length} file thiếu")
      @dialog.execute_script("window.VEC && window.VEC.setDiagnostics(#{JSON.generate(report)});") if @dialog
    end

    def export_diagnostics
      destination = UI.savepanel('Xuất báo cáo chẩn đoán VEC', data_dir, 'vec_diagnostics.json')
      return unless destination
      write_json(destination, diagnostics.merge('generatedBy' => EXTENSION_NAME, 'generatedAt' => Time.now.iso8601))
      notify('Đã xuất báo cáo chẩn đoán.')
    end

    def profiles
      Dir.glob(File.join(profiles_dir, '*.json')).filter_map { |path| read_json(path, nil) }.sort_by { |profile| profile['name'].to_s.downcase }
    end

    def save_profile(name)
      name = name.to_s.strip
      return notify('Hãy nhập tên profile.') if name.empty?
      values = Sketchup.extensions.map { |extension| { 'name' => extension.name, 'enabled' => extension.load_on_start? } }
      profile = { 'id' => safe_name(name), 'name' => name, 'createdAt' => Time.now.iso8601, 'extensions' => values }
      write_json(File.join(profiles_dir, "#{profile['id']}.json"), profile)
      log('profile', "Đã lưu profile #{name}")
      notify("Đã lưu profile #{name}.")
      send_state
    end

    def apply_profile(id)
      profile = profiles.find { |item| item['id'] == id }
      return notify('Không tìm thấy profile.') unless profile
      changes = 0
      profile['extensions'].each do |item|
        extension = Sketchup.extensions[item['name']]
        next unless extension && extension.name != EXTENSION_NAME
        item['enabled'] ? extension.check : extension.uncheck
        changes += 1
      end
      mark_restart_required
      log('profile', "Đã áp dụng profile #{profile['name']} (#{changes} extension)")
      notify("Đã áp dụng profile #{profile['name']}. Hãy thoát SketchUp để áp dụng thay đổi.")
      send_state
    rescue StandardError => e
      log('error', "Lỗi áp dụng profile: #{e.message}")
      notify("Không thể áp dụng profile: #{e.message}")
    end

    def export_profiles
      destination = UI.savepanel('Xuất profiles VEC', data_dir, 'vec_profiles.json')
      return unless destination
      write_json(destination, { 'exportedAt' => Time.now.iso8601, 'profiles' => profiles })
      notify('Đã xuất profiles.')
    end

    def import_profiles
      source = UI.openpanel('Nhập profiles VEC', data_dir, 'JSON Files|*.json||')
      return unless source
      payload = read_json(source, nil)
      raise 'File profiles không hợp lệ.' unless payload.is_a?(Hash) && payload['profiles'].is_a?(Array)
      payload['profiles'].each do |profile|
        next unless profile['id'] && profile['name'] && profile['extensions'].is_a?(Array)
        write_json(File.join(profiles_dir, "#{safe_name(profile['id'])}.json"), profile)
      end
      log('profile', 'Đã nhập profiles')
      notify('Đã nhập profiles.')
      send_state
    rescue StandardError => e
      notify("Không thể nhập profiles: #{e.message}")
    end

    def backups
      Dir.glob(File.join(backup_dir, '*', 'manifest.json')).filter_map do |file|
        manifest = read_json(file, nil)
        manifest && manifest.merge('sizeBytes' => directory_size(File.dirname(file)))
      end.sort_by { |item| item['createdAt'].to_s }.reverse
    end

    def backup_stats
      { 'count' => backups.length, 'sizeBytes' => directory_size(backup_dir) }
    end

    def backup_paths(paths, plugin_name, reason)
      existing = paths.select { |path| File.exist?(path) }
      raise 'Không có file để sao lưu.' if existing.empty?
      ensure_backup_space!(existing)
      id = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{safe_name(plugin_name)}"
      root = File.join(backup_dir, id)
      files_root = File.join(root, 'files')
      FileUtils.mkdir_p(files_root)
      files = existing.each_with_index.map do |path, index|
        stored_as = "#{index}_#{File.basename(path)}"
        FileUtils.cp_r(path, File.join(files_root, stored_as))
        { 'originalPath' => path, 'storedAs' => stored_as }
      end
      write_json(File.join(root, 'manifest.json'), {
        'id' => id, 'pluginName' => plugin_name, 'reason' => reason,
        'createdAt' => Time.now.iso8601, 'files' => files
      })
      log('backup', "Đã sao lưu #{plugin_name} (#{reason})")
      cleanup_old_backups(plugin_name)
      id
    end

    # Chỉ dùng khi người dùng loại plugin khỏi thư mục Plugins. File được di
    # chuyển, không bị xóa, để có thể khôi phục nguyên trạng từ tab Sao lưu.
    def move_paths_to_backup(paths, plugin_name, reason, cleanup: true)
      existing = paths.select { |path| File.exist?(path) }
      raise 'Không có file để chuyển vào backup.' if existing.empty?
      ensure_backup_space!(existing)
      id = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{safe_name(plugin_name)}"
      root = File.join(backup_dir, id)
      files_root = File.join(root, 'files')
      FileUtils.mkdir_p(files_root)
      files = existing.each_with_index.map do |path, index|
        stored_as = "#{index}_#{File.basename(path)}"
        FileUtils.mv(path, File.join(files_root, stored_as))
        { 'originalPath' => path, 'storedAs' => stored_as }
      end
      write_json(File.join(root, 'manifest.json'), {
        'id' => id, 'pluginName' => plugin_name, 'reason' => reason,
        'createdAt' => Time.now.iso8601, 'files' => files
      })
      cleanup_old_backups(plugin_name) if cleanup
      id
    end

    def ensure_backup_space!(paths)
      limit_mb = settings['backupLimitMb'].to_i
      return if limit_mb.zero?
      estimated = paths.sum { |path| directory_size(path) }
      limit = limit_mb * 1024 * 1024
      raise "Backup sẽ vượt giới hạn #{limit_mb} MB." if backup_stats['sizeBytes'] + estimated > limit
    end

    def cleanup_old_backups(plugin_name)
      keep = settings['maxBackupsPerPlugin'].to_i
      return if keep.zero?
      old = backups.select { |item| item['pluginName'] == plugin_name }.sort_by { |item| item['createdAt'].to_s }.reverse.drop(keep)
      old.each { |item| FileUtils.rm_rf(File.join(backup_dir, item['id'])) }
      log('backup', "Đã dọn #{old.length} backup cũ của #{plugin_name}") unless old.empty?
    end

    def directory_size(path)
      return 0 unless File.exist?(path)
      return File.size(path) if File.file?(path)
      Dir.glob(File.join(path, '**', '*')).sum { |item| File.file?(item) ? File.size(item) : 0 }
    end

    def register_plugin(name, kind, paths, source)
      id = "managed:#{safe_name(name)}"
      registry['plugins'][id] = {
        'id' => id, 'name' => name, 'type' => kind.upcase,
        'paths' => paths, 'source' => source, 'installedAt' => Time.now.iso8601
      }
      save_registry
    end

    def confirm_overwrite(target, display_name)
      return true unless File.exist?(target)
      UI.messagebox("#{display_name} đã tồn tại. Bản cũ sẽ được backup trước khi ghi đè. Tiếp tục?", MB_YESNO) == IDYES
    end

    def restart_required?
      Sketchup.read_default(PLUGIN_ID, 'restart_required', false) == true
    end

    def mark_restart_required
      Sketchup.write_default(PLUGIN_ID, 'restart_required', true)
    end

    def clear_restart_required
      Sketchup.write_default(PLUGIN_ID, 'restart_required', false)
    end

    def exit_to_apply
      Sketchup.quit
    end

    def log(action, message)
      entries = read_json(log_path, [])
      entries.unshift({ 'at' => Time.now.iso8601, 'action' => action, 'message' => message })
      write_json(log_path, entries.take(200))
    end

    def notify(message)
      UI.messagebox(message)
    end

    def read_json(path, fallback)
      return fallback unless File.file?(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError, Errno::ENOENT
      fallback
    end

    def write_json(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data))
    end

    def safe_name(value)
      value.to_s.gsub(/[^a-zA-Z0-9_-]+/, '_')
    end

    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('VTARCH Extension Center') { show_dialog }
      toolbar = UI::Toolbar.new('VTARCH Extension Center')
      command = UI::Command.new('Mở VEC') { show_dialog }
      command.tooltip = 'VTARCH Extension Center'
      command.status_bar_text = 'Mở VTARCH Extension Center'
      toolbar.add_item(command)
      toolbar.restore
      clear_restart_required
      file_loaded(__FILE__)
    end
  end
end
