# frozen_string_literal: true

require_relative "helpers"

class ReleaseTask
  class PlatformTasks # :nodoc: all
    class VenetianGemHelper < Bundler::GemHelper
      def initialize(*, namespace: nil, **)
        super(*, **)
        @namespace = namespace
      end

      def install
        namespace @namespace do
          super
        end
      end
    end

    include Rake::DSL
    include Helpers

    def self.create_for(*platforms)
      platforms.each do |platform|
        new(platform).define
      end
    end

    def self.node_version
      @node_version ||= JSON.parse(URI.open(node_releases_url).read) # rubocop:disable Security/Open
                            .find { |release| release["lts"] }
                            .fetch("version")
                            .delete_prefix("v")
    end

    def self.node_releases_url
      "#{Venetian::Upstream::NODE_DIST_URL}/index.json"
    end

    def initialize(platform)
      @platform = platform
    end

    def define
      executable_tasks
      gemspec_tasks
      namespaced_tasks
    end

    private

    attr_reader :platform

    def executable_tasks
      directory "exe/#{platform}"
      CLEAN.include File.join("exe", platform)

      file "exe/#{platform}/#{platform_info.executable_name}" => %W[exe/#{platform} tmp/playwright-core/package] do
        download_and_extract_node platform, File.join("exe", platform)
        cp_r "tmp/playwright-core/package", File.join("exe", platform, "package"), remove_destination: true
      end
    end

    def gemspec_tasks
      directory "tmp/#{platform}"
      CLEAN.include "tmp/#{platform}"

      file "tmp/#{platform}/venetian-#{platform}.gemspec" => %W[tmp/#{platform}
                                                                exe/#{platform}/#{platform_info.executable_name}] do
        write_gemspec File.join("tmp", platform, "venetian-#{platform}.gemspec"), Venetian::Upstream.build_gemspec_for(platform)
      end
    end

    def namespaced_tasks
      namespace platform do
        install_release_tasks_task

        %w[build install release].each do |name|
          task "#{name}_platform": :install_tasks do
            Rake::Task["#{platform}:#{name}"].invoke
          end

          Rake::Task[name].enhance %W[#{platform}:#{name}_platform] unless name == "build"
        end
      end
    end

    def install_release_tasks_task
      task install_tasks: "tmp/#{platform}/venetian-#{platform}.gemspec" do
        copy_files Venetian::Upstream.base_files, File.join("tmp", platform)
        cp_r File.join("exe", platform), File.join("tmp", platform, "exe", platform), remove_destination: true
        install_release_tasks_for platform
      end
    end

    def install_release_tasks_for(platform)
      VenetianGemHelper.new(gem_path, "venetian-#{platform}", namespace: platform).install
    end

    def gem_path
      Pathname.new(__dir__).join("..", "..", "tmp", platform).expand_path
    end

    def download_and_extract_node(platform, destination_dir)
      Venetian::Upstream::NATIVE_PLATFORMS.fetch(platform).then do |platform_info|
        with_tmp_download_pathname platform_info.node_archive_extension do |pathname|
          pathname.binwrite URI.open(platform_info.node_url_for(PlatformTasks.node_version)).read # rubocop:disable Security/Open
          extract_node_archive platform_info, pathname, destination_dir
        end
      end
    end

    def node_dir_name_for(platform_info)
      "node-v#{PlatformTasks.node_version}-#{platform_info.node_dir}"
    end

    def extract_node_archive(platform_info, archive_pathname, destination_dir)
      Dir.mktmpdir do |extract_dir|
        if platform_info.windows
          extract_node_for_windows archive_pathname, node_dir_name_for(platform_info), extract_dir, destination_dir
        else
          extract_node_for_unix archive_pathname, node_dir_name_for(platform_info), extract_dir, destination_dir
        end
        cp File.join(extract_dir, node_dir_name_for(platform_info), "LICENSE"), File.join(destination_dir, "LICENSE")
      end
    end

    def extract_node_for_windows(archive_pathname, node_dir_name, extract_dir, destination_dir)
      system "unzip", "-q", "-o", archive_pathname.to_path, "-d", extract_dir, exception: true
      cp File.join(extract_dir, node_dir_name, "node.exe"), File.join(destination_dir, "node.exe")
    end

    def extract_node_for_unix(archive_pathname, node_dir_name, extract_dir, destination_dir)
      system "tar", "-xzf", archive_pathname.to_path, "-C", extract_dir, exception: true
      cp File.join(extract_dir, node_dir_name, "bin", "node"), File.join(destination_dir, "node")
      chmod 0o755, File.join(destination_dir, "node")
    end

    def platform_info
      @platform_info ||= Venetian::Upstream::NATIVE_PLATFORMS.fetch(platform)
    end
  end
end
