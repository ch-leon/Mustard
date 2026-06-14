# CI on a self-hosted macOS runner

Mustard is a native SwiftUI + SwiftData app, so `swift build` / `swift test` only
run on macOS. GitHub-hosted `macos-*` runners aren't available on this account —
every CI job failed in ~3 seconds because no runner could be allocated (the job
never reached `swift build`). The fix is to point CI at a **self-hosted macOS
runner**: a Mac you control (Leon's) that GitHub dispatches jobs to.

`.github/workflows/ci.yml` targets `runs-on: [self-hosted, macOS, mustard]`. Until a
runner with the `mustard` label is registered, CI jobs on PRs will sit **queued**
rather than fail — register the runner once and they'll start running.

## Register the runner (one-time, ~5 min)

On the Mac that will run CI:

1. **Repo → Settings → Actions → Runners → New self-hosted runner**, pick **macOS**.
   GitHub shows a `./config.sh` command pre-filled with the repo URL and a
   registration token.
2. Download and configure, adding the custom label so this workflow targets it:
   ```bash
   mkdir -p ~/actions-runner && cd ~/actions-runner
   # use the download URL + token GitHub shows you on the "New runner" page
   curl -o actions-runner-osx.tar.gz -L <url-from-github>
   tar xzf actions-runner-osx.tar.gz
   ./config.sh --url https://github.com/BiggestFella/Mustard \
     --token <token-from-github> \
     --labels mustard
   ```
3. **Prereq:** the Mac needs the Swift toolchain on `PATH` (Xcode or the Command
   Line Tools — `xcode-select --install`). Verify with `swift --version`.
4. Run it:
   - Foreground (simplest): `./run.sh`
   - As a background service (survives logout): `./svc.sh install && ./svc.sh start`

Once it shows **Idle** under Settings → Actions → Runners, re-run the failed CI
job (or push a commit) and it will build + test on the Mac.

## Security note

A self-hosted runner executes workflow code from PRs. This repo is single-user and
private, so that's acceptable here. If it ever takes outside contributions, restrict
the runner to trusted branches or move back to hosted runners — never run untrusted
PR workflows on a personal machine.
