class WorkSwiftKit < Formula
  desc "Interactive macOS dev environment setup for multi-account workflows"
  homepage "https://github.com/Samirlb/Work-Swift-Kit"
  url "https://github.com/Samirlb/Work-Swift-Kit/releases/download/v0.2.0/wsk-v0.2.0.tar.gz"
  sha256 "ff85a1fae9281bf562626e3e16af85518ac56f17b496eb9a3c7c2289891c58a5"
  license "MIT"

  depends_on "gum"
  depends_on "stow"
  depends_on "fzf"
  depends_on "gettext"
  depends_on :macos

  def install
    prefix.install Dir["*"]
    (bin/"wsk").write <<~EOS
      #!/usr/bin/env bash
      WSK_DIR="#{prefix}"
      export WSK_DIR
      case "$1" in
        install) exec bash "$WSK_DIR/install.sh" ;;
        relink)  exec bash "$WSK_DIR/install.sh" --relink ;;
        *)
          echo "Usage: wsk [install|relink]"
          exit 1
          ;;
      esac
    EOS
    chmod 0755, bin/"wsk"
  end

  def caveats
    <<~EOS
      To launch the interactive setup:
        wsk install

      To re-link your dotfiles without re-collecting accounts:
        wsk relink
    EOS
  end

  test do
    assert_predicate prefix/"install.sh", :exist?
  end
end
