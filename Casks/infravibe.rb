# frozen_string_literal: true

cask "infravibe" do
  version "2.12.1"
  sha256 "1c5669f8e64cb9b85cf3b3c5fedebd396d9d82846191de29dfea5dba5d5f965a"

  url "https://github.com/netsecdevio/infravibe/releases/download/v#{version}/infravibe-#{version}.dmg"
  name "infravibe"
  desc "Infrastructure, remote terminals, and DevOps monitoring"
  homepage "https://github.com/netsecdevio/infravibe"

  auto_updates true
  depends_on macos: :sequoia

  app "InfraProxy.app"

  caveats do
    <<~EOS
      infravibe requires macOS 15.5 or later.
      Provider tools and tmux are optional and installed separately.
      Use the in-app updater, or brew upgrade --cask --greedy infravibe.
    EOS
  end
end
