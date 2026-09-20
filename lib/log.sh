#!/usr/bin/env bash
# hyprdots/lib/log.sh
# Emoji logging helpers. Source this; do not execute.

log_info()    { echo "ℹ️  $*"; }
log_ok()      { echo "✅ $*"; }
log_warn()    { echo "⚠️  $*"; }
log_err()     { echo "❌ $*" >&2; }
log_step()    { echo "🔍 $*"; }
log_link()    { echo "🔗 $*"; }
log_replace() { echo "♻️  $*"; }
log_clean()   { echo "🧹 $*"; }
log_backup()  { echo "🗂  $*"; }
log_config()  { echo "⚙️  $*"; }
log_sync()    { echo "🔧 $*"; }
