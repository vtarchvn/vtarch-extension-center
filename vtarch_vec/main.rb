# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'time'

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
          type: 'Extension', status: (ext.loaded? ? 'Đang bật' : 'Đang tắt'),
          path: ext.extension_path.to_s, managed: false
        }
      end
      tracked = registry['plugins'].values.map do |item|
        item.merge(
          'managed' => Array(item['paths']).any?,
          'status' => (Array(item['paths']).any? ? 'Được VEC theo dõi' : 'Đã cài qua VEC')
        )
      end
      (extensions + tracked).sort_by { |item| item['name'].to_s.downcase }
    rescue StandardError => e
      log('error', "Không thể quét extension: #{e.message}")
      []
    end

    def install_rb_dialog
      source = UI.openpanel('Chọn file Ruby (.rb)', plugins_dir, 'Ruby Files|*.rb||')
      return unless source && File.file?(source)
      target = File.join(plugins_dir, File.basename(source))
      return unless confirm_overwrite(target, File.basename(source))
      install_files([source], 'rb', File.basename(source, '.rb'))
    end

    def install_rbz_dialog
      source = UI.openpanel('Chọn gói SketchUp (.rbz)', plugins_dir, 'SketchUp Extension|*.rbz||')
      return unless source && File.file?(source)
      unless UI.messagebox("Cài gói #{File.basename(source)}? VEC sẽ tạo bản sao của gói trong nhật ký cài đặt.", MB_YESNO) == IDYES
        return
      end
      begin
        result = Sketchup.install_from_archive(source)
        if result
          register_plugin(File.basename(source, '.rbz'), 'rbz', [], source)
          log('install', "Đã cài #{File.basename(source)}")
          mark_restart_required
          notify('Cài đặt thành công. Hãy thoát SketchUp để áp dụng thay đổi.')
        else
          notify('SketchUp không thể cài gói này.')
        end
      rescue StandardError => e
        log('error', "Lỗi cài RBZ: #{e.message}")
        notify("Không thể cài .rbz: #{e.message}")
      ensure
        send_state
      end
    end

    def install_files(sources, kind, name)
      paths = sources.map { |source| File.join(plugins_dir, File.basename(source)) }
      paths.each { |path| backup_paths([path], name, 'ghi đè') if File.exist?(path) }
      sources.zip(paths).each { |source, target| FileUtils.cp(source, target) }
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
      return unless UI.messagebox("Khôi phục #{manifest['pluginName']}? Trạng thái hiện tại sẽ được giữ nguyên nếu trùng file.", MB_YESNO) == IDYES
      files_root = File.join(backup_dir, id, 'files')
      manifest['files'].each do |file|
        source = File.join(files_root, file['storedAs'])
        target = file['originalPath']
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(source, target)
      end
      log('restore', "Đã khôi phục #{manifest['pluginName']}")
      mark_restart_required
      notify('Đã khôi phục. Hãy thoát SketchUp để áp dụng thay đổi.')
      send_state
    rescue StandardError => e
      log('error', "Lỗi khôi phục: #{e.message}")
      notify("Không thể khôi phục: #{e.message}")
    end

    def backups
      Dir.glob(File.join(backup_dir, '*', 'manifest.json')).filter_map { |file| read_json(file, nil) }.sort_by { |item| item['createdAt'].to_s }.reverse
    end

    def backup_paths(paths, plugin_name, reason)
      existing = paths.select { |path| File.exist?(path) }
      raise 'Không có file để sao lưu.' if existing.empty?
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
      id
    end

    # Chỉ dùng khi người dùng loại plugin khỏi thư mục Plugins. File được di
    # chuyển, không bị xóa, để có thể khôi phục nguyên trạng từ tab Sao lưu.
    def move_paths_to_backup(paths, plugin_name, reason)
      existing = paths.select { |path| File.exist?(path) }
      raise 'Không có file để chuyển vào backup.' if existing.empty?
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
      id
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
