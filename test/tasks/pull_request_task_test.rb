# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/pull_request_task"

module Tasks
  class PullRequestTaskTest < Minitest::Test
    BRANCH = "update-keys"
    TITLE = "Update the pinned signing keys"

    class Requested < PullRequestTask
      attr_accessor :state
      attr_reader :gh_calls

      def initialize(body = "Body")
        super(:update_keys, branch: BRANCH, title: TITLE, paths: ["keys"],
                            body: body.respond_to?(:call) ? body : -> { body })
        @gh_calls = []
      end

      public :update_pull_request

      private

      def pull_request_state
        @state
      end

      def gh(*args)
        @gh_calls << args
      end

      # Stands in for committing through the GitHub API, pushing to the test's origin instead
      def push_signed_commit
        system "git", "switch", "--quiet", "-C", branch, exception: true
        system "git", "commit", "--quiet", "-m", title, "--", *paths, exception: true
        system "git", "push", "--quiet", "--force", "origin", branch, exception: true
      end
    end

    module GitActions
      private

      def update
        capture_subprocess_io { Dir.chdir(@repo) { @requested.update_pull_request } }
      end

      def git(*args)
        Open3.capture2e("git", *args, chdir: File.exist?(@repo) ? @repo : @tmpdir)
             .tap { |output, status| assert_predicate status, :success?, output }
             .first
      end

      def write_key(contents)
        FileUtils.mkdir_p File.join(@repo, "keys")
        File.write File.join(@repo, "keys", "key"), contents
      end

      def push_branch_with_key(contents, message = "Update")
        git "switch", "--quiet", "-c", BRANCH
        write_key contents
        git "commit", "--quiet", "-am", message
        git "push", "--quiet", "origin", BRANCH
        git "switch", "--quiet", "main"
        git "branch", "--quiet", "-D", BRANCH
      end

      def remote_branch
        git "fetch", "--quiet", "--prune", "origin"
        "origin/#{BRANCH}" unless git("branch", "--remotes", "--list", "origin/#{BRANCH}").empty?
      end

      def remote_key
        git "show", "#{remote_branch}:keys/key"
      end
    end

    module PullRequestState
      module Tests
        extend ActiveSupport::Concern

        included do
          test "a pull request is open when gh says so" do
            assert open_with("OPEN\n")
          end

          test "a pull request isn't open when gh says it's closed" do
            refute open_with("CLOSED\n")
          end

          test "a pull request isn't open when gh finds none" do
            refute open_with("", error: "no pull requests found for branch \"#{BRANCH}\"\n")
          end

          test "checking whether a pull request is open raises with gh's error when gh fails otherwise" do
            assert_raises RuntimeError, match: /Couldn't check for a pull request from #{BRANCH}: HTTP 401/ do
              open_with "", error: "HTTP 401: Bad credentials (https://api.github.com/graphql)\n"
            end
          end
        end

        private

        def open_with(state, error: false)
          Open3.stub(:capture3, ->(*args) { respond_to_args(args, state, error:) }) do
            PullRequestTask.new(:update_keys, branch: BRANCH, title: TITLE, paths: ["keys"], body: -> { "Body" }).open?
          end
        end

        def respond_to_args(args, state, error:)
          assert_equal ["gh", "pr", "view", BRANCH, "--json", "state", "--jq", ".state"], args
          [state, error, Open3.capture2(error ? "false" : "true").last]
        end
      end
    end

    include GitActions
    include PullRequestState::Tests

    setup do
      @requested = Requested.new
      @tmpdir = Dir.mktmpdir
      @origin = File.join(@tmpdir, "origin.git")
      @repo = File.join(@tmpdir, "repo")
      git "init", "--quiet", "--bare", "--initial-branch=main", @origin
      git "-C", @origin, "config", "maintenance.auto", "false"
      git "-C", @origin, "config", "receive.autogc", "false"
      git "clone", "--quiet", @origin, @repo
      git "config", "maintenance.auto", "false"
      git "config", "user.name", "Test"
      git "config", "user.email", "test@example.com"
      write_key "old"
      git "add", "."
      git "commit", "--quiet", "-m", "Initial commit"
      git "push", "--quiet", "origin", "main"
    end

    teardown do
      FileUtils.remove_entry @tmpdir
    end

    test "defines a pull request task after the task making the changes" do
      Rake.with_application do
        Requested.new.define

        assert_equal ["update_keys"], Rake::Task["update_keys:pull_request"].prerequisites
      end
    end

    test "does nothing without changes or a pull request" do
      update

      assert_empty @requested.gh_calls
      refute remote_branch
    end

    test "closes an open pull request once there are no changes" do
      @requested.state = "OPEN"
      update

      assert_equal [["pr", "close", BRANCH, "--delete-branch", "--comment", "Closing, as main now matches upstream."]],
                   @requested.gh_calls
    end

    test "pushes the changes and opens a pull request" do
      write_key "new"
      update

      assert_equal "new", remote_key
      assert_equal TITLE, git("log", "-1", "--format=%s", remote_branch).chomp
      assert_equal [["pr", "create", "--head", BRANCH, "--title", TITLE, "--body", "Body"]], @requested.gh_calls
    end

    test "pushes nothing when the body can't be rendered" do
      @requested = Requested.new(-> { raise "Couldn't render the body" })
      write_key "new"

      assert_raises(RuntimeError, match: /Couldn't render the body/) { update }
      assert_empty @requested.gh_calls
      refute remote_branch
    end

    test "replaces the branch of a closed pull request" do
      push_branch_with_key "stale"
      @requested.state = "CLOSED"
      write_key "new"
      update

      assert_equal "new", remote_key
      assert_equal "create", @requested.gh_calls.dig(0, 1)
    end

    test "keeps commits pushed to an open pull request when the changes are the same" do
      push_branch_with_key "new", "Reviewer's commit"
      @requested = Requested.new("New body")
      @requested.state = "OPEN"
      write_key "new"
      update

      assert_equal "Reviewer's commit", git("log", "-1", "--format=%s", remote_branch).chomp
      assert_equal [["pr", "edit", BRANCH, "--body", "New body"]], @requested.gh_calls
    end

    test "replaces the branch of an open pull request when the changes differ" do
      push_branch_with_key "stale"
      @requested.state = "OPEN"
      write_key "new"
      update

      assert_equal "new", remote_key
      assert_equal "edit", @requested.gh_calls.dig(0, 1)
    end
  end
end
