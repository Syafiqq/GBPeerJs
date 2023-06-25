#!/bin/zsh
# run with root path `sh Script/post-install.sh`
# GotoScript

cp Script/pod-lint.example.sh Script/pod-lint.sh
chmod +x Script/pod-lint.sh
rm Readme.md
rm -rf .git
