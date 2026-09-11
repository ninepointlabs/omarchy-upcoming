#!/bin/bash
# Run a job in its own process group with producer-side byte caps on stdout
# and stderr. Tested on bash 5.3 (Arch). This is the same script Panel.qml in
# omarchy-hermes-chat assembles inline (commit 94167a2); keep them in sync.
#
# Usage:  bounded-job-wrapper.sh MAXOUT MAXERR GRACE [--] cmd args...
#   stdin is passed through to the job (feed secrets/messages this way, never argv)
#   exit: job's rc, or 201 if stdout exceeded MAXOUT, 202 if stderr exceeded MAXERR,
#         143 if TERMed from outside.
#
# How it works: each stream goes through a `limit` process substitution. `head -c N`
# forwards at most N bytes; if one more byte follows, the limiter signals this shell
# (USR1 stdout / USR2 stderr), which TERMs the job's whole process group and
# escalates to KILL after GRACE seconds. A TERM-ignoring grandchild still dies.
# The consumer only ever receives N bytes; nothing is buffered then trimmed.
set -m
maxout=$1; maxerr=$2; grace=$3; shift 3; [ "$1" = "--" ] && shift
pid=''; excess=0
limit() { head -c "$1"; if [ "$(head -c 1 | wc -c)" -gt 0 ]; then kill -"$2" "$$" 2>/dev/null; fi; }
stop() { if [ -n "$pid" ]; then kill -TERM -- "-$pid" 2>/dev/null; sleep "$grace"; kill -KILL -- "-$pid" 2>/dev/null; fi; }
trap 'stop' TERM
trap 'excess=201; stop' USR1
trap 'excess=202; stop' USR2
exec {out}> >(limit "$maxout" USR1); outpid=$!
exec {err}> >(limit "$maxerr" USR2 >&2); errpid=$!
"$@" >&"$out" 2>&"$err" & pid=$!
exec {out}>&- {err}>&-
wait "$pid"; rc=$?
wait "$outpid" "$errpid" 2>/dev/null
if [ "$excess" -ne 0 ]; then exit "$excess"; fi
exit "$rc"
