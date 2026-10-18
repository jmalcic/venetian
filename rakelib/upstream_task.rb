# frozen_string_literal: true

require "rake"
require_relative "tasks/pull_request_task"
require_relative "tasks/versioning"

# Defines the tasks keeping the pinned upstream dependencies current, each with a task opening a pull request for it
class UpstreamTask # :nodoc:
  include Rake::DSL
  include Tasks::Versioning

  def self.create
    new.define
  end

  def define
    update_node_tasks
  end

  private

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
