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
      case "${1:-}" in
        ""|menu)                       exec bash "$WSK_DIR/install.sh" ;;
        setup|accounts|terminals|relink|doctor|check|update)
                                       exec bash "$WSK_DIR/install.sh" "$1" ;;
        install)                       exec bash "$WSK_DIR/install.sh" setup ;;  # back-compat
        -h|--help|help)
          echo "Usage: wsk [command]"
          echo
          echo "  (no command)  Open the interactive menu"
          echo "  setup         Full setup: accounts, packages, terminals, dotfiles"
          echo "  accounts      Configure accounts only"
          echo "  terminals     Install terminals/editors only"
          echo "  doctor        Check configuration (read-only health check)"
          echo "  update        Update the kit and upgrade packages"
          echo "  relink        Re-symlink dotfiles without re-collecting accounts"
          ;;
        *)
          echo "Unknown command: $1" >&2
          echo "Run 'wsk --help' for usage." >&2
          exit 1
          ;;
      esac
    EOS
    chmod 0755, bin/"wsk"
  end

  def caveats
    <<~EOS
      To open the interactive menu:
        wsk

      Direct commands:
        wsk setup      # full setup
        wsk doctor     # check configuration
        wsk update     # update kit and tools
        wsk relink     # re-link dotfiles
    EOS
  end

  test do
    assert_predicate prefix/"install.sh", :exist?
  end
end
