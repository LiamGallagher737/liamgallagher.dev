{ pkgs, ... }:

{
  packages = with pkgs; [
    zola
    fzf
    bat
  ];

  scripts = {
    write.exec = "find content -type f -name '*.md' | fzf --preview 'bat --color=always --style=plain {}' --preview-window '~3' --print0 | xargs -0 -o $EDITOR";
  };

  processes = {
    serve.exec = "zola serve --open";
  };
}
