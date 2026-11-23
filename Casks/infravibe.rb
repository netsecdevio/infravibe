# frozen_string_literal: true

cask "infravibe" do
  version "2.13.1"
  sha256 "5993751d555a9f25a14ed64209489881a5bea5b0f96c5905a1089d5514d21e0d"

  url "https://github.com/netsecdevio/infravibe/releases/download/v#{version}/infravibe-#{version}.dmg"
  name "infravibe"
  desc "Infrastructure, remote terminals, and DevOps monitoring"
  homepage "https://github.com/netsecdevio/infravibe"

  auto_updates true
  depends_on macos: :sequoia

  app "infravibe.app"

  caveats do
    <<~EOS
      infravibe requires macOS 15.5 or later.
      Provider tools and tmux are optional and installed separately.
      Use the in-app updater, or brew upgrade --cask --greedy infravibe.
    EOS
  end
end
