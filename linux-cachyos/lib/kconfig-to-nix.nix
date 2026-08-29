{
  runCommand,
  configfile,
}:

# Transform kernel .config file into a static Nix attribute set.
runCommand "config.nix" { } ''
  echo "{" > "$out"
  while IFS='=' read -r key val; do
    [ "x''${key#CONFIG_}" != "x$key" ] || continue
    no_firstquote="''${val#\"}";
    echo '  "'"$key"'" = "'"''${no_firstquote%\"}"'";' >> "$out"
  done < "${configfile}"
  echo "}" >> $out
''
