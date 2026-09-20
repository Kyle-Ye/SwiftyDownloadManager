#!/usr/bin/env ruby

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com/v1"
SUCCESS_STATUS = "SUCCEEDED"
TERMINAL_STATUSES = %w[SUCCEEDED FAILED ERRORED CANCELED SKIPPED].freeze
NOTARIZED_ARTIFACT_TYPE = "STAPLED_NOTARIZED_ARCHIVE"

def base64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def jwt(private_key, key_id, issuer_id)
  issued_at = Time.now.to_i
  header = base64url(JSON.generate(alg: "ES256", kid: key_id, typ: "JWT"))
  payload = base64url(JSON.generate(
    iss: issuer_id,
    iat: issued_at,
    exp: issued_at + 1_200,
    aud: "appstoreconnect-v1"
  ))
  signing_input = "#{header}.#{payload}"
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  sequence = OpenSSL::ASN1.decode(private_key.dsa_sign_asn1(digest))
  signature = sequence.value.map { |integer| integer.value.to_s(2).rjust(32, "\0")[-32, 32] }.join
  "#{signing_input}.#{base64url(signature)}"
end

def request_json(path, private_key, options, query = {}, method: "GET", body: nil)
  uri = URI(path.start_with?("https://") ? path : "#{API_BASE}#{path}")
  abort "Unexpected App Store Connect API URL" unless uri.scheme == "https" &&
    uri.host == "api.appstoreconnect.apple.com" && uri.path.start_with?("/v1/")
  uri.query = URI.encode_www_form(query) unless query.empty?
  request = method == "POST" ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{jwt(private_key, options[:key_id], options[:issuer_id])}"
  request["Accept"] = "application/json"
  if body
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.open_timeout = 30
    http.read_timeout = 60
    http.request(request)
  end
  return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

  abort "App Store Connect API #{response.code} for #{path}: #{response.body}"
end

def request_all_pages(path, private_key, options, query = {})
  result = { "data" => [], "included" => [] }
  while path
    page = request_json(path, private_key, options, query)
    result["data"].concat(page.fetch("data"))
    result["included"].concat(page.fetch("included", []))
    path = page.dig("links", "next")
    query = {}
  end
  result
end

def rebuild_release_tag(product, workflow, private_key, options)
  repositories = request_all_pages(
    "/ciProducts/#{product.fetch('id')}/primaryRepositories", private_key, options,
    "limit" => "200"
  ).fetch("data")
  abort "Expected one primary Xcode Cloud repository" unless repositories.length == 1
  references = request_all_pages(
    "/scmRepositories/#{repositories.first.fetch('id')}/gitReferences", private_key, options,
    "fields[scmGitReferences]" => "name,canonicalName,kind,isDeleted", "limit" => "200"
  ).fetch("data")
  tags = references.select do |reference|
    attributes = reference.fetch("attributes")
    attributes["canonicalName"] == "refs/tags/#{options[:tag]}" && !attributes["isDeleted"]
  end
  abort "Expected one Xcode Cloud Git reference for tag #{options[:tag]}" unless tags.length == 1

  request_json("/ciBuildRuns", private_key, options, {}, method: "POST", body: {
    data: {
      type: "ciBuildRuns",
      attributes: { clean: true },
      relationships: {
        workflow: { data: { type: "ciWorkflows", id: workflow.fetch("id") } },
        sourceBranchOrTag: { data: { type: "scmGitReferences", id: tags.first.fetch("id") } },
      },
    },
  }).fetch("data")
end

def release_main(argv = ARGV)
  options = {
    timeout: 5_400,
    interval: 30,
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: wait-for-xcode-cloud-artifact.rb [options]"
    parser.on("--bundle-id VALUE") { |value| options[:bundle_id] = value }
    parser.on("--workflow VALUE") { |value| options[:workflow] = value }
    parser.on("--branch VALUE") { |value| options[:branch] = value }
    parser.on("--tag VALUE") { |value| options[:tag] = value }
    parser.on("--rebuild") { options[:rebuild] = true }
    parser.on("--commit VALUE") { |value| options[:commit] = value.downcase }
    parser.on("--key-id VALUE") { |value| options[:key_id] = value }
    parser.on("--issuer-id VALUE") { |value| options[:issuer_id] = value }
    parser.on("--private-key PATH") { |value| options[:private_key] = value }
    parser.on("--output PATH") { |value| options[:output] = value }
    parser.on("--timeout SECONDS", Integer) { |value| options[:timeout] = value }
    parser.on("--interval SECONDS", Integer) { |value| options[:interval] = value }
  end.parse!(argv)

  required = %i[bundle_id workflow branch tag commit key_id issuer_id private_key output]
  missing = required.select { |key| options[key].nil? || options[key].empty? }
  abort "Missing required options: #{missing.join(', ')}" unless missing.empty?
  abort "Branch must use release/MAJOR.MINOR format" unless options[:branch].match?(%r{\Arelease/\d+\.\d+\z})
  abort "Tag must use MAJOR.MINOR.PATCH format" unless options[:tag].match?(/\A\d+\.\d+\.\d+\z/)
  abort "Tag and release branch do not match" unless options[:branch] == "release/#{options[:tag].rpartition('.').first}"
  abort "Commit must be a full Git SHA" unless options[:commit].match?(/\A[0-9a-f]{40}\z/)
  abort "Timeout must be positive and interval non-negative" unless options[:timeout] > 0 && options[:interval] >= 0

  private_key = OpenSSL::PKey::EC.new(File.read(options[:private_key]))

  apps = request_json(
    "/apps",
    private_key,
    options, {
      "filter[bundleId]" => options[:bundle_id],
      "fields[apps]" => "name,bundleId",
      "limit" => "2"
    }
  ).fetch("data")
  abort "Expected one App Store Connect app for #{options[:bundle_id]}, found #{apps.length}" unless apps.length == 1

  product = request_json("/apps/#{apps.first.fetch('id')}/ciProduct", private_key, options).fetch("data")
  workflows = request_all_pages(
    "/ciProducts/#{product.fetch('id')}/workflows",
    private_key,
    options,
    "fields[ciWorkflows]" => "name,isEnabled",
    "limit" => "200"
  ).fetch("data")
  workflow = workflows.find do |item|
    attributes = item.fetch("attributes")
    attributes.fetch("name") == options[:workflow] && attributes.fetch("isEnabled")
  end
  abort "Enabled Xcode Cloud workflow #{options[:workflow].inspect} was not found" unless workflow

  deadline = Time.now + options[:timeout]
  build_run = options[:rebuild] ? rebuild_release_tag(product, workflow, private_key, options) : nil
  warn "Started Xcode Cloud rebuild of tag #{options[:tag]}." if build_run

  until build_run
    abort "Timed out waiting for Xcode Cloud to build #{options[:branch]}" if Time.now >= deadline

    response = request_all_pages(
      "/ciWorkflows/#{workflow.fetch('id')}/buildRuns",
      private_key,
      options,
      "fields[ciBuildRuns]" => "number,sourceCommit,executionProgress,completionStatus,sourceBranchOrTag",
      "fields[scmGitReferences]" => "name,canonicalName,kind",
      "include" => "sourceBranchOrTag",
      "limit" => "200",
      "sort" => "-number"
    )
    references = response.fetch("included", []).to_h { |item| [item.fetch("id"), item.fetch("attributes")] }
    build_run = response.fetch("data").find do |item|
      attributes = item.fetch("attributes")
      reference_id = item.dig("relationships", "sourceBranchOrTag", "data", "id")
      reference = references[reference_id] || {}
      commit_matches = attributes.dig("sourceCommit", "commitSha").to_s.downcase == options[:commit]
      branch_matches = reference["canonicalName"] == "refs/heads/#{options[:branch]}"
      tag_matches = reference["canonicalName"] == "refs/tags/#{options[:tag]}"
      commit_matches && (branch_matches || tag_matches)
    end

    unless build_run
      warn "Waiting for Xcode Cloud to build #{options[:branch]} at #{options[:commit]}..."
      sleep options[:interval]
    end
  end

  loop do
    abort "Timed out waiting for Xcode Cloud build #{build_run.fetch('id')}" if Time.now >= deadline

    build_run = request_json(
      "/ciBuildRuns/#{build_run.fetch('id')}",
      private_key,
      options, {
        "fields[ciBuildRuns]" => "number,sourceCommit,executionProgress,completionStatus"
      }
    ).fetch("data")
    attributes = build_run.fetch("attributes")
    # A newly created manual build can return unresolved source metadata.
    # Validate the completed build's commit before requesting any artifacts.
    status = attributes["completionStatus"]
    break if status && TERMINAL_STATUSES.include?(status)

    warn "Xcode Cloud build ##{attributes.fetch('number')} is #{attributes.fetch('executionProgress')}..."
    sleep options[:interval]
  end

  attributes = build_run.fetch("attributes")
  abort "Xcode Cloud build ##{attributes.fetch('number')} completed with #{attributes.fetch('completionStatus')}" unless attributes.fetch("completionStatus") == SUCCESS_STATUS
  abort "Xcode Cloud build is missing the expected source commit" unless attributes.dig("sourceCommit", "commitSha").to_s.downcase == options[:commit]

  artifact = nil
  until artifact
    abort "Timed out waiting for notarized artifact from build #{build_run.fetch('id')}" if Time.now >= deadline

    actions = request_all_pages(
      "/ciBuildRuns/#{build_run.fetch('id')}/actions",
      private_key,
      options,
      "fields[ciBuildActions]" => "name,actionType,completionStatus",
      "limit" => "200"
    ).fetch("data")
    archive_actions = actions.select do |item|
      action_attributes = item.fetch("attributes")
      action_attributes["actionType"] == "ARCHIVE" && action_attributes["completionStatus"] == SUCCESS_STATUS
    end
    if archive_actions.empty?
      warn "Waiting for a successful Xcode Cloud archive action..."
      sleep options[:interval]
      next
    end

    notarized_artifacts = archive_actions.flat_map do |archive_action|
      request_all_pages(
        "/ciBuildActions/#{archive_action.fetch('id')}/artifacts",
        private_key,
        options,
        "fields[ciArtifacts]" => "fileType,fileName,fileSize,downloadUrl",
        "limit" => "200"
      ).fetch("data").select do |item|
        item.dig("attributes", "fileType") == NOTARIZED_ARTIFACT_TYPE
      end
    end
    abort "Expected at most one stapled notarized archive, found #{notarized_artifacts.length}" if notarized_artifacts.length > 1

    artifact = notarized_artifacts.first
    unless artifact
      warn "Waiting for the stapled notarized archive..."
      sleep options[:interval]
    end
  end

  artifact_attributes = artifact.fetch("attributes")
  result = {
    build_run_id: build_run.fetch("id"),
    build_number: attributes.fetch("number"),
    source_branch: options[:branch],
    source_commit: options[:commit],
    artifact_name: artifact_attributes.fetch("fileName"),
    artifact_size: artifact_attributes.fetch("fileSize"),
    artifact_url: artifact_attributes.fetch("downloadUrl"),
  }

  File.write(options[:output], JSON.pretty_generate(result), mode: "w", perm: 0o600)
  puts "Xcode Cloud build ##{result[:build_number]} produced #{result[:artifact_name]} (#{result[:artifact_size]} bytes)."
end

release_main if $PROGRAM_NAME == __FILE__
