#!/bin/sh
printf '\033c\033]0;%s\a' Third Person
base_path="$(dirname "$(realpath "$0")")"
"$base_path/GroceryGetterMP_Test.x86_64" "$@"
