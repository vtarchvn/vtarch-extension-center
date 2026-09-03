# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'time'
require 'digest'
require 'uri'
require File.join(File.dirname(__FILE__), 'zip_archive')

module VTARCH
  module VEC
    extend self

    PLUGIN_ID = 'vtarch_vec'
    DATA_DIR_NAME = 'VTARCH VEC'

    def show_dialog
      @dialog ||= build_dialog
      @dialog.show
      # execute_script là bất đồng bộ; đợi trang HtmlDialog sẵn sàng rồi gửi
      # trạng thái. Đây cũng là đường kiểm tra độc lập với callback JavaScript.
      UI.start_timer(0.25, false) { send_state_safely }
      UI.start_timer(1.0, false) { send_state_safely }
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
      dialog.add_action_callback('vec_ready') { |_ctx| safe_callback('Khởi tạo VEC') { send_state } }
      dialog.add_action_callback('vec_install_rb') { |_ctx| install_rb_dialog }
      dialog.add_action_callback('vec_install_rbz') { |_ctx| install_rbz_dialog }
      dialog.add_action_callback('vec_backup') { |_ctx, id| backup_plugin(id) }
      dialog.add_action_callback('vec_backup_all') { |_ctx| safe_callback('Sao lưu tất cả') { backup_all_plugins } }
      dialog.add_action_callback('vec_adopt') { |_ctx, id| safe_callback('Đưa plugin vào VEC quản lý') { adopt_plugin(id) } }
      dialog.add_action_callback('vec_uninstall') { |_ctx, id| uninstall_plugin(id) }
      dialog.add_action_callback('vec_restore') { |_ctx, id| restore_backup(id) }
      dialog.add_action_callback('vec_toggle_extension') { |_ctx, name, enabled| toggle_extension(name, enabled == 'true') }
      dialog.add_action_callback('vec_diagnostics') { |_ctx| safe_callback('Chẩn đoán') { send_diagnostics } }
      dialog.add_action_callback('vec_export_diagnostics') { |_ctx| export_diagnostics }
      dialog.add_action_callback('vec_save_profile') { |_ctx, name| save_profile(name) }
      dialog.add_action_callback('vec_apply_profile') { |_ctx, id| apply_profile(id) }
      dialog.add_action_callback('vec_export_profiles') { |_ctx| export_profiles }
      dialog.add_action_callback('vec_import_profiles') { |_ctx| import_profiles }
      dialog.add_action_callback('vec_export_migration') { |_ctx| safe_callback('Xuất gói chuyển máy') { export_migration } }
      dialog.add_action_callback('vec_import_migration') { |_ctx| safe_callback('Nhập gói chuyển máy') { import_migration } }
      dialog.add_action_callback('vec_catalog_load') { |_ctx, url| load_catalog(url) }
      dialog.add_action_callback('vec_catalog_install') { |_ctx, id| install_catalog_plugin(id) }
      dialog.add_action_callback('vec_save_settings') { |_ctx, payload| safe_callback('Lưu cài đặt') { save_settings(payload) } }
      dialog.add_action_callback('vec_choose_backup_dir') { |_ctx| safe_callback('Chọn thư mục backup') { choose_backup_dir } }
      dialog.add_action_callback('vec_reset_backup_dir') { |_ctx| safe_callback('Đặt lại thư mục backup') { reset_backup_dir } }
      dialog.add_action_callback('vec_open_backup_folder') { |_ctx| safe_callback('Mở thư mục backup') { UI.openURL("file:///#{backup_dir.tr('\\\\', '/')}") } }
      dialog.add_action_callback('vec_open_plugin_location') { |_ctx, id| safe_callback('Mở vị trí plugin') { open_plugin_location(id) } }
      dialog.add_action_callback('vec_exit') { |_ctx| exit_to_apply }
      dialog.set_on_closed { @dialog = nil }
      # Callback phải được đăng ký trước khi nạp trang. Nếu set_file chạy trước,
      # JavaScript có thể gọi vec_ready khi window.sketchup chưa có callback.
      dialog.set_file(File.join(extension_dir, 'ui', 'index.html'))
      dialog
    end

    def extension_dir
      File.dirname(__FILE__)
    end

    def plugins_dir
      # main.rb luôn nằm tại <Plugins>/vtarch_vec/main.rb. Dùng parent của thư
      # mục extension thay vì find_support_file('Plugins'), vốn tìm *file* hỗ trợ
      # và không đảm bảo trả về thư mục Plugins trên mọi phiên bản SketchUp.
      File.dirname(extension_dir)
    end

    def data_dir
      @data_dir ||= begin
        # find_support_file('') có thể trả về thư mục cài SketchUp trong
        # Program Files (chỉ đọc). Dữ liệu người dùng phải ưu tiên AppData.
        base = ENV['APPDATA'].to_s
        base = Dir.home if base.empty?
        path = File.join(base, DATA_DIR_NAME)
        FileUtils.mkdir_p(path)
        path
      end
    end

    def backup_dir
      path = settings['backupPath'].to_s.empty? ? default_backup_dir : settings['backupPath']
      FileUtils.mkdir_p(path)
      path
    end

    def default_backup_dir
      File.join(data_dir, 'backups')
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
      @settings ||= { 'maxBackupsPerPlugin' => 0, 'backupLimitMb' => 0, 'backupPath' => nil, 'catalogUrl' => default_catalog_url }.merge(read_json(settings_path, {}))
    end

    def save_settings(payload)
      incoming = JSON.parse(payload.to_s)
      @settings = settings.merge(
        'maxBackupsPerPlugin' => [incoming['maxBackupsPerPlugin'].to_i, 0].max,
        'backupLimitMb' => [incoming['backupLimitMb'].to_i, 0].max
      )
      write_json(settings_path, @settings)
      log('settings', 'Đã lưu cài đặt backup')
      notify('Đã lưu cài đặt backup.')
      send_state
    rescue JSON::ParserError
      notify('Cài đặt không hợp lệ.')
    end

    def choose_backup_dir
      selected = UI.select_directory(title: 'Chọn thư mục backup VEC', directory: backup_dir)
      return unless selected
      @settings = settings.merge('backupPath' => selected)
      write_json(settings_path, @settings)
      log('settings', "Đã đổi thư mục backup: #{selected}")
      notify('Đã đổi thư mục backup. Backup cũ vẫn ở thư mục trước đó.')
      send_state
    end

    def reset_backup_dir
      @settings = settings.merge('backupPath' => nil)
      write_json(settings_path, @settings)
      log('settings', 'Đã dùng lại thư mục backup mặc định')
      notify('Đã dùng lại thư mục backup mặc định.')
      send_state
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
        catalog: @catalog,
        restartRequired: restart_required?
      }
      @dialog.execute_script("window.VEC && window.VEC.setState(#{JSON.generate(state)});")
    end

    def default_catalog_url
      'https://raw.githubusercontent.com/vtarchvn/vtarch-extension-center/main/catalog/catalog.json'
    end

    def send_state_safely
      send_state
    rescue StandardError => e
      report_dialog_error('Khởi tạo VEC', e)
    end

    def scanned_plugins
      tracked = registry['plugins'].values.map do |item|
        item.merge(
          'managed' => Array(item['paths']).any?,
          'status' => (Array(item['paths']).any? ? 'Được VEC theo dõi' : 'Đã cài qua VEC')
        )
      end
      tracked_paths = tracked.flat_map { |item| Array(item['paths']) }.map { |path| normalized_path(path) }
      extensions = Sketchup.extensions.map do |ext|
        extension_path = ext.extension_path.to_s
        tracked_item = tracked.find { |item| Array(item['paths']).map { |path| normalized_path(path) }.include?(normalized_path(extension_path)) }
        {
          id: (tracked_item ? tracked_item['id'] : "extension:#{ext.name}"), name: ext.name, version: ext.version.to_s,
          creator: ext.creator.to_s, description: ext.description.to_s,
          type: 'Extension', status: (tracked_item ? 'Được VEC theo dõi' : (ext.load_on_start? ? 'Bật khi khởi động' : 'Tắt khi khởi động')),
          path: extension_path, managed: !tracked_item.nil?, toggleable: ext.name != EXTENSION_NAME,
          enabled: ext.load_on_start?, management: (tracked_item ? 'vec' : 'sketchup'),
          adoptable: tracked_item.nil? && ext.name != EXTENSION_NAME,
          adoptPaths: adoption_paths(extension_path)
        }
      end
      extension_paths = extensions.map { |item| normalized_path(item[:path]) }
      scripts = Dir.glob(File.join(plugins_dir, '*.rb')).reject { |path| tracked_paths.include?(normalized_path(path)) || extension_paths.include?(normalized_path(path)) }.map do |path|
        { 'id' => "script:#{path}", 'name' => File.basename(path), 'type' => 'Script .rb',
          'status' => 'Không do VEC theo dõi', 'path' => path, 'managed' => false,
          'management' => 'none', 'adoptable' => true, 'adoptPaths' => adoption_paths(path) }
      end
      standalone_tracked = tracked.reject do |item|
        Array(item['paths']).map { |path| normalized_path(path) }.any? { |path| extension_paths.include?(path) }
      end
      (extensions + standalone_tracked + scripts).sort_by { |item| (item['name'] || item[:name]).to_s.downcase }
    rescue StandardError => e
      log('error', "Không thể quét extension: #{e.message}")
      []
    end

    def normalized_path(path)
      File.expand_path(path.to_s).tr('\\', '/').downcase
    end

    def path_in_plugins_dir?(path)
      root = normalized_path(plugins_dir)
      target = normalized_path(path)
      target == root || target.start_with?("#{root}/")
    end

    # Extension .rb thường đi kèm một thư mục cùng tên. Theo dõi cả hai để
    # backup/khôi phục không làm plugin mất file phụ trợ.
    def adoption_paths(path)
      return [] unless File.exist?(path) && path_in_plugins_dir?(path)
      paths = [path]
      companion = File.join(File.dirname(path), File.basename(path, '.rb'))
      paths << companion if File.directory?(companion) && path_in_plugins_dir?(companion)
      paths
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

    def backup_all_plugins
      items = registry['plugins'].values.select { |item| Array(item['paths']).any? }
      return notify('Chưa có plugin nào do VEC quản lý để sao lưu.') if items.empty?
      return unless UI.messagebox("Sao lưu tất cả #{items.length} plugin do VEC quản lý?\n\nPlugin sẽ được sao chép vào kho backup, không bị di chuyển.", MB_YESNO) == IDYES
      completed = []
      failed = []
      items.each do |item|
        begin
          backup_paths(item['paths'] || [], item['name'], 'sao lưu tất cả')
          completed << item['name']
        rescue StandardError => e
          failed << "#{item['name']}: #{e.message}"
          log('error', "Sao lưu tất cả - #{item['name']}: #{e.message}")
        end
      end
      log('backup', "Đã sao lưu hàng loạt #{completed.length}/#{items.length} plugin")
      message = "Đã sao lưu #{completed.length}/#{items.length} plugin."
      message += "\nKhông sao lưu được: #{failed.join('; ')}" unless failed.empty?
      notify(message)
      send_state
    end

    def open_plugin_location(id)
      item = scanned_plugins.find { |candidate| (candidate['id'] || candidate[:id]) == id }
      return notify('Không tìm thấy plugin.') unless item
      path = item['path'] || item[:path]
      return notify('Plugin không có đường dẫn để mở.') if path.to_s.empty?
      directory = File.directory?(path) ? path : File.dirname(path)
      return notify('Không tìm thấy thư mục plugin.') unless File.directory?(directory)
      UI.openURL("file:///#{directory.tr('\\', '/')}")
    end

    def adopt_plugin(id)
      item = scanned_plugins.find { |candidate| (candidate['id'] || candidate[:id]) == id }
      return notify('Không tìm thấy plugin để VEC theo dõi.') unless item
      return notify('Plugin này đã do VEC quản lý.') if item['managed'] || item[:managed]
      paths = Array(item['adoptPaths'] || item[:adoptPaths]).select { |path| File.exist?(path) && path_in_plugins_dir?(path) }
      return notify('Không tìm thấy file plugin hợp lệ trong thư mục Plugins.') if paths.empty?
      name = item['name'] || item[:name]
      detail = paths.map { |path| File.basename(path) }.join(', ')
      return unless UI.messagebox("Đưa #{name} vào VEC quản lý?\n\nVEC sẽ tạo backup ban đầu cho: #{detail}\nFile gốc không bị di chuyển.", MB_YESNO) == IDYES
      backup_paths(paths, name, 'backup ban đầu khi đưa vào VEC quản lý')
      register_plugin(name, 'existing', paths, nil)
      log('adopt', "Đã đưa #{name} vào VEC quản lý")
      notify('Đã tạo backup ban đầu và đưa plugin vào VEC quản lý.')
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
        if file['sha256'] && path_digest(source) != file['sha256']
          raise "Backup bị hỏng hoặc đã bị thay đổi: #{file['storedAs']}"
        end
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
      log('diagnostic', "Đã chạy chẩn đoán: #{report[:missingFiles].length} file thiếu")
      @dialog.execute_script("window.VEC && window.VEC.setDiagnostics(#{JSON.generate(report)});") if @dialog
    end

    # Callback HtmlDialog không tự đưa exception tới người dùng. Ghi nhật ký và
    # hiện thông báo giúp chẩn đoán ngay trong SketchUp thay vì nút im lặng.
    def safe_callback(action)
      yield
    rescue StandardError => e
      report_dialog_error(action, e)
    end

    def report_dialog_error(action, error)
      message = "#{action} gặp lỗi: #{error.class}: #{error.message}"
      begin
        log('error', message)
      rescue StandardError
        nil
      end
      begin
        @dialog.execute_script("window.VEC && window.VEC.showError(#{JSON.generate(message)});") if @dialog
      rescue StandardError
        UI.messagebox(message)
      end
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

    def export_migration
      items = registry['plugins'].values.select { |item| Array(item['paths']).any? }
      return notify('Chưa có plugin do VEC quản lý để đưa vào gói chuyển máy.') if items.empty?
      destination = UI.savepanel('Tạo gói chuyển máy VEC', data_dir, "vec_migration_#{Time.now.strftime('%Y%m%d')}.vecbackup")
      return unless destination
      payloads = {}
      manifest_plugins = items.each_with_index.map do |item, plugin_index|
        records = Array(item['paths']).each_with_index.map do |path, path_index|
          raise "Không tìm thấy plugin: #{path}" unless File.exist?(path)
          target = File.basename(path)
          archive_root = "payload/#{plugin_index}/#{path_index}/#{target}"
          payloads.merge!(migration_payloads(path, archive_root))
          { 'target' => target, 'archiveRoot' => archive_root }
        end
        { 'name' => item['name'], 'type' => item['type'], 'files' => records }
      end
      manifest = {
        'format' => 'vecbackup-1', 'createdAt' => Time.now.iso8601,
        'plugins' => manifest_plugins, 'profiles' => profiles,
        'settings' => settings.slice('maxBackupsPerPlugin', 'backupLimitMb')
      }
      payloads['manifest.json'] = JSON.pretty_generate(manifest)
      ZipArchive.create(destination, payloads)
      log('migration', "Đã xuất gói chuyển máy: #{items.length} plugin")
      notify("Đã tạo gói chuyển máy gồm #{items.length} plugin và #{profiles.length} profile.")
    end

    def import_migration
      source = UI.openpanel('Nhập gói chuyển máy VEC', data_dir, 'VEC Backup|*.vecbackup||')
      return unless source
      staging = File.join(data_dir, 'staging', "migration_#{Time.now.to_i}")
      entries = ZipArchive.entries(source)
      ZipArchive.extract(source, staging, entries)
      manifest = read_json(File.join(staging, 'manifest.json'), nil)
      raise 'Gói chuyển máy không hợp lệ.' unless manifest.is_a?(Hash) && manifest['format'] == 'vecbackup-1' && manifest['plugins'].is_a?(Array)
      names = manifest['plugins'].map { |item| item['name'] }.join("\n")
      detail = "#{manifest['plugins'].length} plugin · #{Array(manifest['profiles']).length} profile\n\n#{names}"
      return unless UI.messagebox("Nhập gói chuyển máy?\n\n#{detail}\n\nFile trùng sẽ được backup trước.", MB_YESNO) == IDYES
      imported = 0
      manifest['plugins'].each do |plugin|
        records = Array(plugin['files'])
        raise 'Plugin trong gói không có file.' if records.empty?
        targets = records.map do |record|
          target = record['target'].to_s
          raise 'Tên file trong gói không hợp lệ.' unless target == File.basename(target)
          archive_root = record['archiveRoot'].to_s
          raise 'Đường dẫn gói không hợp lệ.' unless ZipArchive.safe_path?(archive_root)
          source_root = File.join(staging, archive_root)
          raise 'Đường dẫn gói vượt thư mục tạm.' unless ZipArchive.inside?(staging, source_root)
          raise "Thiếu dữ liệu plugin: #{target}" unless File.exist?(source_root)
          [source_root, File.join(plugins_dir, target)]
        end
        existing = targets.map(&:last).select { |target| File.exist?(target) }
        move_paths_to_backup(existing, plugin['name'], 'trạng thái trước khi chuyển máy') unless existing.empty?
        targets.each do |source_root, target|
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp_r(source_root, target)
        end
        register_plugin(plugin['name'], plugin['type'].to_s.downcase, targets.map(&:last), 'vecbackup')
        imported += 1
      end
      Array(manifest['profiles']).each do |profile|
        next unless profile.is_a?(Hash) && profile['id'] && profile['name'] && profile['extensions'].is_a?(Array)
        write_json(File.join(profiles_dir, "#{safe_name(profile['id'])}.json"), profile)
      end
      incoming_settings = manifest['settings'].is_a?(Hash) ? manifest['settings'] : {}
      @settings = settings.merge('maxBackupsPerPlugin' => incoming_settings['maxBackupsPerPlugin'].to_i, 'backupLimitMb' => incoming_settings['backupLimitMb'].to_i)
      write_json(settings_path, @settings)
      mark_restart_required if imported.positive?
      log('migration', "Đã nhập gói chuyển máy: #{imported} plugin")
      notify("Đã nhập #{imported} plugin. Hãy thoát SketchUp để áp dụng.")
      send_state
    ensure
      FileUtils.rm_rf(staging) if staging && File.exist?(staging)
    end

    def migration_payloads(path, archive_root)
      if File.file?(path)
        { archive_root => File.binread(path) }
      else
        Dir.glob(File.join(path, '**', '*')).select { |item| File.file?(item) }.each_with_object({}) do |file, result|
          relative = file.delete_prefix(path).sub(%r{\A[\\/]}, '').tr('\\', '/')
          result["#{archive_root}/#{relative}"] = File.binread(file)
        end
      end
    end

    def load_catalog(url)
      catalog_url = validate_https_url(url.to_s.strip)
      @settings = settings.merge('catalogUrl' => catalog_url)
      write_json(settings_path, @settings)
      @catalog_request = Sketchup::Http::Request.new(catalog_url, Sketchup::Http::GET)
      @catalog_request.start do |_request, response|
        if response.status_code == 200
          begin
            catalog = JSON.parse(response.body)
            validate_catalog!(catalog)
            @catalog = catalog
            UI.start_timer(0, false) { send_catalog }
          rescue StandardError => e
            UI.start_timer(0, false) { notify("Danh mục không hợp lệ: #{e.message}") }
          end
        else
          UI.start_timer(0, false) { notify("Không tải được kho plugin (HTTP #{response.status_code}).") }
        end
      end
    rescue StandardError => e
      notify("Không thể tải kho plugin: #{e.message}")
    end

    def send_catalog
      return unless @dialog
      @dialog.execute_script("window.VEC && window.VEC.setCatalog(#{JSON.generate(@catalog || {})});")
    end

    def install_catalog_plugin(id)
      plugin = Array(@catalog && @catalog['plugins']).find { |item| item['id'] == id }
      return notify('Hãy tải danh mục trước.') unless plugin
      return unless UI.messagebox("Cài #{plugin['name']} v#{plugin['version']}?\n\nVEC sẽ tải RBZ qua HTTPS, kiểm tra SHA-256 rồi cài với backup an toàn.", MB_YESNO) == IDYES
      download_url = validate_https_url(plugin['downloadUrl'])
      @catalog_download = Sketchup::Http::Request.new(download_url, Sketchup::Http::GET)
      @catalog_download.start do |_request, response|
        if response.status_code == 200 && response.body.bytesize <= 100 * 1024 * 1024
          UI.start_timer(0, false) { install_catalog_download(plugin, response.body) }
        else
          UI.start_timer(0, false) { notify('Không tải được gói plugin hoặc gói quá lớn.') }
        end
      end
    rescue StandardError => e
      notify("Không thể cài từ kho: #{e.message}")
    end

    def install_catalog_download(plugin, bytes)
      expected = plugin['sha256'].to_s.downcase
      raise 'SHA-256 của plugin không hợp lệ.' unless expected.match?(/\A[0-9a-f]{64}\z/)
      raise 'Checksum không khớp; đã hủy cài đặt.' unless Digest::SHA256.hexdigest(bytes) == expected
      path = File.join(data_dir, 'downloads', "#{safe_name(plugin['id'])}_#{plugin['version']}.rbz")
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
      install_rbz(path, ZipArchive.entries(path))
    rescue StandardError => e
      notify("Không thể cài plugin từ kho: #{e.message}")
    ensure
      File.delete(path) if path && File.file?(path)
    end

    def validate_https_url(value)
      uri = URI.parse(value.to_s)
      raise 'URL phải dùng HTTPS.' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty?
      value
    end

    def validate_catalog!(catalog)
      raise 'Thiếu danh sách plugins.' unless catalog.is_a?(Hash) && catalog['plugins'].is_a?(Array) && catalog['plugins'].length <= 500
      catalog['plugins'].each do |plugin|
        %w[id name version downloadUrl sha256].each { |key| raise "Plugin thiếu #{key}." if plugin[key].to_s.empty? }
        validate_https_url(plugin['downloadUrl'])
        raise 'SHA-256 không hợp lệ.' unless plugin['sha256'].to_s.match?(/\A[0-9a-fA-F]{64}\z/)
      end
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
        backup_manifest_entry(path, stored_as)
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
        backup_manifest_entry(File.join(files_root, stored_as), stored_as, original_path: path)
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

    def backup_manifest_entry(path, stored_as, original_path: path)
      {
        'originalPath' => original_path,
        'storedAs' => stored_as,
        'sizeBytes' => directory_size(path),
        'sha256' => path_digest(path)
      }
    end

    def path_digest(path)
      return Digest::SHA256.file(path).hexdigest if File.file?(path)
      digest = Digest::SHA256.new
      Dir.glob(File.join(path, '**', '*')).sort.each do |item|
        next unless File.file?(item)
        digest.update(item.delete_prefix(path).tr('\\\\', '/'))
        digest.update("\0")
        digest.update(File.binread(item))
      end
      digest.hexdigest
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
      icon_path = File.join(extension_dir, 'icons', 'vec.svg')
      command.small_icon = icon_path
      command.large_icon = icon_path
      command.tooltip = 'VTARCH Extension Center'
      command.status_bar_text = 'Mở VTARCH Extension Center'
      toolbar.add_item(command)
      toolbar.restore
      clear_restart_required
      file_loaded(__FILE__)
    end
  end
end
