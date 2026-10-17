# frozen_string_literal: true

require "rake"
require_relative "tasks/pull_request_task"
require_relative "tasks/signatures"
require_relative "tasks/versioning"

# Defines the tasks keeping the pinned upstream dependencies current, each with a task opening a pull request for it
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

      Pinned Node.js release keys:

      ```
      #{list_gpg_keys(node_keyring.to_path)}```
    MARKDOWN
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
