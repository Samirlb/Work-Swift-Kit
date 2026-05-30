class WorkSwiftKit < Formula
  desc "Interactive macOS dev environment setup for multi-account workflows"
  homepage "https://github.com/yourusername/work-swift-kit"
  url "https://github.com/yourusername/work-swift-kit/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on "gum"
  depends_on "gnu-stow"
  depends_on "fzf"
  depends_on "gettext"

  def install
    libexec.install Dir["*"]
    (bin/"wsk").write <<~EOS
      #!/usr/bin/env bash
      exec "#{libexec}/install.sh" "$@"
    EOS
  end

  test do
    assert_predicate bin/"wsk", :exist?
    assert_predicate bin/"wsk", :executable?
  end
end
