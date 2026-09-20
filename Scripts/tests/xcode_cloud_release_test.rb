require "minitest/autorun"
require "tmpdir"
require_relative "../wait-for-xcode-cloud-artifact"
require_relative "../previous-release-tag"

class XcodeCloudReleaseTest < Minitest::Test
  SHA = "a" * 40

  def setup
    @directory = Dir.mktmpdir("sdm-release-test")
    @output = File.join(@directory, "artifact.json")
    key_path = File.join(@directory, "test-key.p8")
    File.write(key_path, OpenSSL::PKey::EC.generate("prime256v1").to_pem)
    @arguments = %W[
      --bundle-id test.sdm --workflow Release --branch release/0.4
      --tag 0.4.0 --commit #{SHA} --key-id test --issuer-id test
      --private-key #{key_path} --output #{@output} --interval 0
    ]
    @responses = {}
    @requests = []
    respond("/apps", "data" => [{ "id" => "app" }])
    respond("/apps/app/ciProduct", "data" => { "id" => "product" })
    respond("/ciProducts/product/workflows", "data" => [
      { "id" => "release", "attributes" => { "name" => "Release", "isEnabled" => true } },
    ])
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  # Exercise the CLI's real discovery/polling/selection logic, replacing only
  # the network boundary. Unexpected requests fail instead of reaching Apple.
  def request_json(path, _key, _options, query = {}, method: "GET", body: nil)
    @requests << { path: path, query: query, method: method, body: body }
    queue = @responses.fetch([method, path]) { raise "Unexpected API request: #{method} #{path}" }
    raise "Unexpected repeated request: #{path}" if queue.empty?
    queue.shift
  end

  def respond(path, response, method = "GET")
    (@responses[[method, path]] ||= []) << response
  end

  def build(commit: SHA, status: "SUCCEEDED")
    { "id" => "build", "attributes" => {
      "number" => 42, "sourceCommit" => { "commitSha" => commit },
      "executionProgress" => "COMPLETE", "completionStatus" => status,
    }, "relationships" => { "sourceBranchOrTag" => { "data" => { "id" => "source" } } } }
  end

  def listing(reference = "refs/heads/release/0.4")
    { "data" => [build], "included" => [
      { "id" => "source", "attributes" => { "canonicalName" => reference } },
    ] }
  end

  def artifact
    { "attributes" => { "fileType" => NOTARIZED_ARTIFACT_TYPE,
      "fileName" => "notarized.zip", "fileSize" => 123,
      "downloadUrl" => "https://example.invalid/notarized.zip" } }
  end

  def archive_responses(artifacts = [artifact])
    respond("/ciBuildRuns/build/actions", "data" => %w[ios mac].map do |id|
      { "id" => id, "attributes" => { "actionType" => "ARCHIVE", "completionStatus" => "SUCCEEDED" } }
    end)
    respond("/ciBuildActions/ios/artifacts", "data" => [
      { "attributes" => { "fileType" => "ARCHIVE", "fileName" => "ios.zip" } },
    ])
    respond("/ciBuildActions/mac/artifacts", "data" => artifacts)
  end

  def run_release
    capture_io { release_main(@arguments) }
    JSON.parse(File.read(@output))
  end

  def test_selects_only_the_notarized_artifact_across_both_platform_archives
    respond("/ciWorkflows/release/buildRuns", listing)
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses
    result = run_release
    assert_equal 42, result.fetch("build_number")
    assert_equal SHA, result.fetch("source_commit")
    assert_equal "https://example.invalid/notarized.zip", result.fetch("artifact_url")
    assert_equal 0, File.stat(@output).mode & 0o077
  end

  def test_finds_an_older_matching_build_on_a_later_page
    next_page = "#{API_BASE}/ciWorkflows/release/buildRuns?cursor=older"
    respond("/ciWorkflows/release/buildRuns", "data" => [], "links" => { "next" => next_page })
    respond(next_page, listing("refs/tags/0.4.0"))
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses
    assert_equal SHA, run_release.fetch("source_commit")
  end

  def test_ignores_an_unrelated_branch_even_when_its_commit_matches
    respond("/ciWorkflows/release/buildRuns", listing("refs/heads/main"))
    respond("/ciWorkflows/release/buildRuns", listing)
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses
    run_release
    assert_equal 2, @requests.count { |request| request[:path] == "/ciWorkflows/release/buildRuns" }
  end

  def prepare_rebuild
    @arguments << "--rebuild"
    respond("/ciProducts/product/primaryRepositories", "data" => [{ "id" => "repo" }])
    respond("/scmRepositories/repo/gitReferences", "data" => [
      { "id" => "tag", "attributes" => { "canonicalName" => "refs/tags/0.4.0", "isDeleted" => false } },
      { "id" => "branch", "attributes" => { "canonicalName" => "refs/heads/release/0.4" } },
    ])
    respond("/ciBuildRuns", { "data" => { "id" => "build" } }, "POST")
  end

  def test_rebuilds_the_exact_tag_instead_of_the_advanced_release_branch
    prepare_rebuild
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses
    run_release
    request = @requests.find { |item| item[:method] == "POST" }
    assert_equal "/ciBuildRuns", request[:path]
    assert_equal true, request[:body].dig(:data, :attributes, :clean)
    assert_equal "tag", request[:body].dig(:data, :relationships, :sourceBranchOrTag, :data, :id)
    assert_equal "release", request[:body].dig(:data, :relationships, :workflow, :data, :id)
  end

  def test_rejects_a_rebuilt_tag_that_moved_to_another_commit
    prepare_rebuild
    respond("/ciBuildRuns/build", "data" => build(commit: "b" * 40))
    capture_io { assert_raises(SystemExit) { release_main(@arguments) } }
    refute File.exist?(@output)
  end

  def test_waits_for_a_new_build_to_resolve_its_source_commit
    prepare_rebuild
    pending = build(commit: "", status: nil)
    pending["attributes"]["executionProgress"] = "PENDING"
    respond("/ciBuildRuns/build", "data" => pending)
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses
    assert_equal SHA, run_release.fetch("source_commit")
  end

  def test_rejects_a_completed_build_without_a_source_commit
    prepare_rebuild
    respond("/ciBuildRuns/build", "data" => build(commit: ""))
    capture_io { assert_raises(SystemExit) { release_main(@arguments) } }
    refute File.exist?(@output)
  end

  def test_rejects_multiple_notarized_archives
    respond("/ciWorkflows/release/buildRuns", listing)
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses([artifact, artifact])
    capture_io { assert_raises(SystemExit) { release_main(@arguments) } }
    refute File.exist?(@output)
  end

  def test_waits_for_completion_and_artifact_availability
    respond("/ciWorkflows/release/buildRuns", listing)
    respond("/ciBuildRuns/build", "data" => build(status: nil))
    respond("/ciBuildRuns/build", "data" => build)
    archive_responses([])
    archive_responses
    assert_equal SHA, run_release.fetch("source_commit")
  end

  def test_rejects_failed_builds
    respond("/ciWorkflows/release/buildRuns", listing)
    respond("/ciBuildRuns/build", "data" => build(status: "FAILED"))
    capture_io { assert_raises(SystemExit) { release_main(@arguments) } }
    refute File.exist?(@output)
  end

  def test_rejects_mismatched_tag_and_branch_before_api_access
    @arguments[@arguments.index("--tag") + 1] = "0.5.0"
    capture_io { assert_raises(SystemExit) { release_main(@arguments) } }
    assert_empty @requests
  end

  def test_previous_tag_is_selected_by_version_not_creation_order
    tags = %w[0.5.0 0.3.0 0.4.0 0.2.1 0.10.0 0.9.0 0.11.0-rc.1]
    assert_equal "0.3.0", previous_release_tag("0.4.0", tags)
    assert_equal "0.9.0", previous_release_tag("0.10.0", tags)
    assert_nil previous_release_tag("0.1.0", tags)
  end
end
