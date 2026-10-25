---
name: hyprdots-plugins
description: Re-review the personal chaz.* Omarchy shell plugins against a new Omarchy release and advance their recorded baselines. Use when working inside the hyprdots repository after an Omarchy update, when doctor warns "Plugin baseline ... is X; installed Omarchy is Y", or when a stock lock, idle, or weather change must be ported into chaz.lock, chaz.idle, or chaz-weather.
---

# Hyprdots plugin re-review

`chaz.lock`, `chaz.idle`, and `chaz-weather` under
`active/omarchy/.config/omarchy/plugins/` began as copies of stock Omarchy
plugins. Line 1 of each `UPSTREAM` file records the Omarchy release the copy
was last compared with; line 2 names the stock directory. `doctor/plugins.sh`
warns when that release differs from `pacman -Q omarchy`. Advancing line 1 is
the last step of a review, never a way to silence the warning.

| Plugin | Stock source | How to port |
| --- | --- | --- |
| `chaz.lock` | `shell/plugins/lock` | Close copy; a three-way merge usually applies cleanly. |
| `chaz.idle` | `shell/plugins/services/idle` | Rewrite (lock, then suspend; no screensaver). Port each fix by intent, not by merge. |
| `chaz-weather` | `shell/plugins/panels/weather` | Own architecture; port shell-integration changes only. Follow README's weather section. |

`chaz.todo` is based on a community plugin, not stock Omarchy. Still apply
shell-wide QML changes to it, such as palette qualification.

## 1. Get the old and new stock sources

The pacman cache usually lacks the old package, so use the upstream tags.
`v<version>` without the package release matches `/usr/share/omarchy`; check
that before trusting the diff. Work in a scratch directory outside the repo.

```bash
old=4.0.4 new=4.0.6          # from UPSTREAM line 1 and pacman -Q omarchy
src="$(mktemp -d)/omarchy"
git init -q "$src" && git -C "$src" remote add origin https://github.com/basecamp/omarchy.git
git -C "$src" fetch -q --filter=blob:none --shallow-exclude="v$old" origin tag "v$new"
git -C "$src" fetch -q --depth 1 --filter=blob:none origin tag "v$old"
dirs=(shell/plugins/lock shell/plugins/services/idle shell/plugins/panels/weather)
git -C "$src" diff --stat "v$old" "v$new" -- "${dirs[@]}"
git -C "$src" log --format='%h %s' "v$new" -- "${dirs[@]}"   # read each message: it states the bug
```

Confirm the tag matches the installed files (`git archive` the directory and
`diff -r` it against `/usr/share/omarchy/<dir>`). An empty diff means only the
baselines advance.

## 2. Port each change

- Close copies: run `git merge-file -p <clone> <old-stock> <new-stock>` per
  file. Review the output; conflicts mean the copy diverged there.
- Rewrites: for each upstream commit, decide whether the bug exists in the
  copy. Port the fix in the copy's own structure and keep its behavior.
  Check that `shell.json` values (for example `idle.lock`, `idle.suspend`)
  behave the same as before.
- Shell-wide changes: apply them to every personal plugin, including
  `chaz.todo`. Search all `chaz*` QML for the old pattern afterwards.
- Check that helper commands the new code calls exist under `/usr/bin`.

## 3. Verify, then advance

```bash
bash doctor/plugins.sh          # QML lint, manifests, bar, baselines
bash tests/weather.sh           # when chaz-weather changed
omarchy plugin validate active/omarchy/.config/omarchy/plugins/<id>
omarchy restart shell           # reloadConfig keeps the old plugin code running
journalctl --user --since -2min | grep -E '/plugins/chaz|TypeError|ReferenceError'
omarchy-shell lock status; omarchy-shell idle status
```

Then edit line 1 of each reviewed `UPSTREAM` to the installed release and
rerun `./doctor.sh`. Ask the user to lock and unlock once and to open the
weather panel. Report those as not verified until they confirm. Name each
ported upstream commit in the commit body.
