# frozen_string_literal: true

cask "infravibe" do
  version "2.12.0"
  sha256 "fecb26de26f4119d560f9e152a618f29adee317590ec51afed72487985a79cc4"

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
