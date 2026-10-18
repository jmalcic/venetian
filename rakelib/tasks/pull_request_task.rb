# frozen_string_literal: true

require "open3"
require "rake"
require_relative "signed_commit"

module Tasks
  class PullRequestTask # :nodoc:
    include Rake::DSL

    def initialize(name, branch:, title:, paths:, body:)
      @name = name
      @branch = branch
      @title = title
      @paths = paths
      @body = body
    end

    def define
      namespace name do
        desc "Opens, updates or closes a pull request for the changes made by #{name}"
        task pull_request: name do
          update_pull_request
        end
      end
    end

    private

    attr_reader :name, :branch, :title, :paths, :body

    def update_pull_request
      if no_changes?
        close if open?
      else
        push_signed_commit unless open? && pushed?
        open? ? edit : create
      end
    end

    def push_signed_commit
      SignedCommit.new(title, paths).push(branch, force: true)
    end

    def edit
      gh "pr", "edit", branch, "--body", body.call
    end

    def create
      gh "pr", "create", "--head", branch, "--title", title, "--body", body.call
    end

    def close
      gh "pr", "close", branch, "--delete-branch", "--comment", "Closing, as main now matches upstream."
    end

    def pushed?
      system("git", "fetch", "origin", branch) && system("git", "diff", "--quiet", "FETCH_HEAD", "--", *paths)
    end

    def no_changes?
      system "git", "diff", "--quiet", "--", *paths
    end

    def open?(force: false)
      @open = pull_request_state == "OPEN" if force || @open.nil?
      @open
    end

    def pull_request_state
      Open3.capture2("gh", "pr", "view", branch, "--json", "state", "--jq", ".state", err: File::NULL)
           .then { |state, status| state.strip if status.success? }
    end

    def gh(*)
      system("gh", *, exception: true)
    end
  end
end
