# frozen_string_literal: true

cask "infravibe" do
  version "2.11.0"
  sha256 "2d154b92322ddb46409c6bad15ce4cfc840a2c9d9a891b762456081142aa7cdd"

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
