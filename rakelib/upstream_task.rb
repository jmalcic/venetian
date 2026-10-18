# frozen_string_literal: true

require "json"
require "open3"
require "rake"
require "tempfile"
require_relative "tasks/pull_request_task"
require_relative "tasks/signatures"
require_relative "tasks/versioning"

class UpstreamTask # :nodoc:
  include Rake::DSL
  include Tasks::Signatures
  include Tasks::Versioning

  def self.create
    new.define
  end

  def define
    update_keys_tasks
    update_node_tasks
  end

  private

  def update_keys_tasks
    desc "Updates the pinned Node.js release keys and npm registry keys from upstream"
    task :update_keys do
      NODE_KEYRING.binwrite read_https(NODE_KEYRING_URL)
      NPM_KEYS.write "#{JSON.pretty_generate(JSON.parse(read_https(NPM_KEYS_URL)))}\n"
    end

    Tasks::PullRequestTask.new(:update_keys,
                               branch: "update-keys", title: "Update the pinned signing keys",
                               paths: [KEYS_DIR.to_path], body: -> { render_key_pull_request_body })
                          .define
  end

  def update_node_tasks
    desc "Patches the version if there's a later Node.js LTS release than the bundled one"
    task :update_node do
      update_node
    end

    Tasks::PullRequestTask.new(:update_node,
                               branch: "update-node", title: "Bundle the latest Node.js LTS release",
                               paths: [version_file, "Gemfile.lock"], body: -> { render_node_pull_request_body })
                          .define
  end

  def render_key_pull_request_body
    <<~MARKDOWN
      The upstream signing keys changed. Before merging, check each new key against the release keys listed in
      https://github.com/nodejs/node#release-keys and the history of https://github.com/nodejs/release-keys, and
      npm registry keys against https://docs.npmjs.com/about-registry-signatures.

      #{render_key_changes}

      Pinned Node.js release keys:

      #{pinned_node_keys}
    MARKDOWN
  end

  def render_key_changes
    case all_key_changes
    in [_, *] => changes then changes.join("\n")
    else "No key was added, removed or changed in the details listed, but the key files differ, so check their diff."
    end
  end

  def all_key_changes
    committed_node_keys.changes_to(pinned_node_keys) + committed_npm_keys.changes_to(pinned_npm_keys)
  end

  def committed_node_keys
    Tempfile.create(%w[node .kbx], binmode: true) do |file|
      file.write committed_content(node_keyring)
      file.close
      GpgKeys.parse(gpg_key_listing(file.path))
    end
  end

  def pinned_node_keys
    @pinned_node_keys ||= GpgKeys.parse(gpg_key_listing(node_keyring.to_path))
  end

  def committed_npm_keys
    NpmKeys.parse(committed_content(NPM_KEYS))
  end

  def pinned_npm_keys
    NpmKeys.parse(NPM_KEYS.read)
  end

  def committed_content(path)
    Open3.capture3("git", "show", "HEAD:./#{File.basename(path)}", chdir: File.dirname(path), binmode: true)
         .tap { |_content, error, status| raise "Couldn't read #{path} in HEAD: #{error.strip}" unless status.success? }
         .first
  end

  def update_node
    return if latest_node_lts_version == Venetian::NODE_VERSION

    patch_version_file node: true
    update_lockfile
  end

  def render_node_pull_request_body
    "Bundles Node.js #{latest_node_lts_version}, the latest LTS release: " \
      "https://nodejs.org/en/blog/release/v#{latest_node_lts_version}"
  end
end
