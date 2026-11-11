#!/bin/sh
# Наполняет ленивые подменю Happ: шлёт AboutToShow всем пунктам корня трей-меню.
# Quickshell сам зовёт AboutToShow только для корня, поэтому «Сменить сервер» остаётся пустым.
items=$(busctl --user call org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null)
for e in $(printf '%s\n' "$items" | grep -o ':[0-9][0-9.]*/[^"]*'); do
  svc=$(printf '%s' "$e" | cut -d/ -f1)
  path=$(printf '%s' "$e" | cut -d/ -f2-)
  path=/$path
  id=$(busctl --user call "$svc" "$path" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Id 2>/dev/null)
  case "$id" in *'"Happ"'*) ;; *) continue ;; esac
  menu=$(busctl --user call "$svc" "$path" org.freedesktop.DBus.Properties Get ss org.kde.StatusNotifierItem Menu 2>/dev/null | sed -n 's/^v o "\(.*\)"$/\1/p')
  [ -n "$menu" ] || continue
  json=$(busctl --user --json=short call "$svc" "$menu" com.canonical.dbusmenu GetLayout iias 0 1 0 2>/dev/null)
  for i in $(printf '%s' "$json" | grep -oE '"data":\[[0-9]+,{' | grep -oE '[0-9]+' | sort -un); do
    busctl --user call "$svc" "$menu" com.canonical.dbusmenu AboutToShow i "$i" >/dev/null 2>&1
  done
done
