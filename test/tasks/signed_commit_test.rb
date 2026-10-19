# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/signed_commit"

module Tasks
  class SignedCommitTest < Minitest::Test
    module BranchAssertions
      private

      def assert_branch_exists(response)
        stubbing_gh_api "repos/{owner}/{repo}/git/ref/heads/update-keys", response do
          assert SignedCommit.new("Update the keys", ["keys"]).branch_exists?("update-keys")
        end
      end

      def refute_branch_exists(response, error)
        stubbing_gh_api "repos/{owner}/{repo}/git/ref/heads/update-keys", response, error: do
          refute SignedCommit.new("Update the keys", ["keys"]).branch_exists?("update-keys")
        end
      end

      def stubbing_gh_api(path, response, error: nil, &)
        Open3.stub(:capture3, ->(*args) { respond_to_args(args, path, response, error:) }, &)
      end

      def respond_to_args(args, expected_path, response, error: nil)
        assert_equal ["gh", "api", expected_path], args

        [response, error, Open3.capture2(error ? "false" : "true").last]
      end
    end

    module GitActions
      private

      def push(force: false)
        Dir.chdir(@repo) { @commit.push("update-keys", force:) }
      end

      def git(*args)
        Open3.capture2e("git", *args, chdir: @repo)
             .tap { |output, status| assert_predicate status, :success?, output }
             .first
      end

      def write(path, contents)
        FileUtils.mkdir_p File.join(@repo, File.dirname(path))
        File.binwrite File.join(@repo, path), contents
      end
    end

    class RecordedCommit < SignedCommit
      class Requests < Array
        def bodies(name)
          with_path(name).map(&:last)
        end

        def with_path(name)
          select { |_method, path, _body| path == "git/#{name}" }
        end

        def with_path_prefix(prefix)
          select { |_method, path, _body| path.start_with?(prefix) }
        end
      end

      attr_accessor :branch_exists, :verified
      attr_reader :requests

      def initialize(...)
        super
        @requests = Requests.new
        @verified = true
      end

      def branch_exists?(_branch)
        branch_exists
      end

      private

      def api(method, path, **body)
        @requests << [method, path, body]
        { "sha" => "#{path.split("/").last}-sha", "verification" => { "verified" => verified } }
      end
    end

    include BranchAssertions
    include GitActions

    setup do
      @repo = Dir.mktmpdir
      git "init", "--quiet", "--initial-branch=main"
      git "config", "user.name", "Test"
      git "config", "user.email", "test@example.com"
      write "keys/kept", "kept"
      write "keys/changed", "old"
      write "keys/deleted", "deleted"
      write "unrelated", "old"
      git "add", "."
      git "commit", "--quiet", "-m", "Initial commit"
      @head = git("rev-parse", "HEAD").chomp
      @tree = git("rev-parse", "HEAD^{tree}").chomp

      write "keys/changed", "new \x00 binary".b
      write "keys/added", "added"
      File.delete File.join(@repo, "keys", "deleted")
      write "unrelated", "new"
      @commit = RecordedCommit.new("Update the keys", ["keys"])
    end

    teardown do
      FileUtils.remove_entry @repo
    end

    test "uploads the changed and added files under the paths as blobs" do
      push

      assert_equal [{ content: ["new \x00 binary".b].pack("m0"), encoding: "base64" },
                    { content: ["added".b].pack("m0"), encoding: "base64" }],
                   @commit.requests.bodies("blobs")
    end

    test "builds a tree on HEAD's with the changed, added and deleted files under the paths" do
      push

      assert_equal Hash(base_tree: @tree,
                        tree: [{ path: "keys/changed", mode: "100644", type: "blob", sha: "blobs-sha" },
                               { path: "keys/deleted", mode: "100644", type: "blob", sha: nil },
                               { path: "keys/added", mode: "100644", type: "blob", sha: "blobs-sha" }]),
                   @commit.requests.bodies("trees").first
    end

    test "keeps the mode git has for a tracked file" do
      git "update-index", "--chmod=+x", "keys/changed"
      push

      assert_equal "100755", @commit.requests.bodies("trees").first.fetch(:tree).first.fetch(:mode)
    end

    test "commits the tree on HEAD without an author or committer, so GitHub signs it" do
      push

      assert_equal Hash(message: "Update the keys", tree: "trees-sha", parents: [@head]),
                   @commit.requests.bodies("commits").first
    end

    test "creates the branch when it doesn't exist" do
      push

      assert_equal ["POST", "git/refs", { ref: "refs/heads/update-keys", sha: "commits-sha" }], @commit.requests.last
    end

    test "moves an existing branch without forcing it" do
      @commit.branch_exists = true
      push

      assert_equal ["PATCH", "git/refs/heads/update-keys", { sha: "commits-sha", force: false }], @commit.requests.last
    end

    test "forces an existing branch when asked to" do
      @commit.branch_exists = true
      push force: true

      assert_equal ["PATCH", "git/refs/heads/update-keys", { sha: "commits-sha", force: true }], @commit.requests.last
    end

    test "raises without moving the branch when GitHub didn't sign the commit" do
      @commit.verified = false

      assert_raises RuntimeError, match: /GitHub didn't sign commits-sha/ do
        push
      end
      refute_predicate @commit.requests.with_path_prefix("git/refs"), :any?
    end

    test "a branch exists when GitHub finds its ref" do
      assert_branch_exists '{"ref":"refs/heads/update-keys"}'
    end

    test "a branch doesn't exist when GitHub doesn't find its ref" do
      refute_branch_exists '{"message":"Not Found","status":"404"}', "gh: Not Found (HTTP 404)\n"
    end

    test "checking for a branch raises with gh's error when GitHub fails otherwise" do
      stubbing_gh_api "repos/{owner}/{repo}/git/ref/heads/update-keys", '{"message":"Bad credentials","status":"401"}',
                      error: "gh: Bad credentials (HTTP 401)\n" do
        assert_raises RuntimeError, match: /Couldn't check whether update-keys exists: gh: Bad credentials/ do
          SignedCommit.new("Update the keys", ["keys"]).branch_exists?("update-keys")
        end
      end
    end

    test "checking for a branch raises when gh gets no response" do
      stubbing_gh_api "repos/{owner}/{repo}/git/ref/heads/update-keys", "",
                      error: "error connecting to api.github.com\n" do
        assert_raises RuntimeError, match: /Couldn't check whether update-keys exists: error connecting/ do
          SignedCommit.new("Update the keys", ["keys"]).branch_exists?("update-keys")
        end
      end
    end
  end
end
