# frozen_string_literal: true

require "json"
require "open3"

module Tasks
  class SignedCommit # :nodoc:
    def initialize(message, paths)
      @message = message
      @paths = paths
    end

    def push(branch, force: false)
      @sha ||= create_commit
      if branch_exists?(branch)
        api "PATCH", "git/refs/heads/#{branch}", sha: @sha, force:
      else
        api "POST", "git/refs", ref: "refs/heads/#{branch}", sha: @sha
      end
    end

    def branch_exists?(branch)
      Open3.capture3("gh", "api", "repos/{owner}/{repo}/git/ref/heads/#{branch}")
           .then do |response, error, status|
        next true if status.success?
        next false if !response.empty? && JSON.parse(response)["status"] == "404"

        raise "Couldn't check whether #{branch} exists: #{error.strip}"
      end
    end

    private

    attr_reader :message, :paths

    def create_commit
      api("POST", "git/commits", message:, tree: create_tree, parents: [git("rev-parse", "HEAD").chomp])
        .tap { |commit| raise "GitHub didn't sign #{commit["sha"]}" unless commit.dig("verification", "verified") }
        .fetch("sha")
    end

    def create_tree
      api("POST", "git/trees", base_tree: git("rev-parse", "HEAD^{tree}").chomp, tree: tree_entries).fetch("sha")
    end

    def tree_entries
      changed_files.map do |path|
        if File.exist?(File.join(root, path))
          { path:, mode: mode(path), type: "blob", sha: create_blob(path) }
        else
          { path:, mode: "100644", type: "blob", sha: nil }
        end
      end
    end

    def changed_files
      (tracked_changed_files + untracked_files).uniq
    end

    def tracked_changed_files
      git("diff", "--name-only", "-z", "HEAD", "--", *paths).split("\0")
    end

    def untracked_files
      git("ls-files", "--others", "--exclude-standard", "--full-name", "-z", "--", *paths).split("\0")
    end

    def mode(path)
      git("ls-files", "--stage", "--", File.join(root, path))[/\A\d+/] || "100644"
    end

    def create_blob(path)
      api("POST", "git/blobs", content: [File.binread(File.join(root, path))].pack("m0"), encoding: "base64")
        .fetch("sha")
    end

    def root
      @root ||= git("rev-parse", "--show-toplevel").chomp
    end

    def api(method, path, **body)
      Open3.capture2("gh", "api", "--method", method, "repos/{owner}/{repo}/#{path}", "--input", "-",
                     stdin_data: JSON.generate(body))
           .tap { |_response, status| raise "gh api --method #{method} #{path} failed" unless status.success? }
           .then { |response, _status| JSON.parse(response) }
    end

    def git(*args)
      Open3.capture2("git", *args)
           .tap { |_output, status| raise "git #{args.join(" ")} failed" unless status.success? }
           .first
    end
  end
end
