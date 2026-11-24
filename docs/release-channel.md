# Release channel

`.github/workflows/release-channel.yml` plans a release. It does not publish
one. A pull request, a push to `main`, and a **workflow_dispatch** with
**dry_run** left on (the default) all exit 0 with no secrets configured.
The job uploads one artifact, `release-channel-plan`, which is the JSON from
`tools/release_channel.py`. Turning **dry_run** off fails the job before that
plan is written. `python3 tools/release_channel.py --publish` does the same
on a laptop.

Nothing in this workflow calls `gh release create`, `ovr-platform-util`, or
`steamcmd`, and it does not push a tag. The token it requests is
`contents: read`. Store uploads and the GitHub Release itself stay with
Kevin, using the commands below, after the secrets exist.

The version in the plan comes from `tools/stamp_version.py` (`git describe`
for the name, `GITHUB_RUN_NUMBER` or the commit count for the code). The
planner does not rewrite `export_presets.cfg`.

## What Kevin adds

Repository **secrets** (Settings → Secrets and variables → Actions → Secrets),
unless a row says variable. Names are exact. The planner reads them to decide
`ready` / `missing` and never writes the values into the plan or the log.

### Android signing

Used by `.github/workflows/build.yml` when it exports the APK. A `v*` tag
**fails** unless all three are set, because a throwaway key cannot update an
install. A branch or pull-request build still warns and signs with a
throwaway key. This dry-run reports `signing.mode` as `unsigned` (none of
them), `incomplete` (some of them), or `release` (all three).

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the release keystore file, one line |
| `ANDROID_KEYSTORE_USER` | Key alias |
| `ANDROID_KEYSTORE_PASSWORD` | Store password |

The key password and the store password have to be the same string. The
export sets `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` from
`ANDROID_KEYSTORE_PASSWORD` and Godot uses that one password for the store.
There is no second secret for the key password.

Create the keystore locally and do not commit it:

```bash
keytool -genkeypair -v \
  -keystore release.keystore \
  -alias paddlequest \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$STORE_PASS" -keypass "$STORE_PASS" \
  -dname "CN=Paddle Quest, O=Cascadia Collections, C=US"
base64 -w0 release.keystore
```

`ANDROID_KEYSTORE_USER` is `paddlequest` in that example.
`ANDROID_KEYSTORE_PASSWORD` is `$STORE_PASS`. Put the base64 output in
`ANDROID_KEYSTORE_BASE64`. Delete `release.keystore` from any machine that
should not hold it, or keep it offline.

After the three secrets exist, re-run this workflow. The plan should say
`signing.mode` is `release` and `would_create_release` is still false.

### GitHub Release

No extra secret. `build.yml` already drafts the Release on a tag `v*`, with
`contents: write` and the default `GITHUB_TOKEN`, attaching:

- `build/paddleball-release.apk`
- `build/paddlequest.arm64`
- `build/xr-webview-addon.zip`

The release is a draft. Push the tag only once the three keystore secrets
are set; otherwise that workflow fails the tag on purpose. This release-channel
workflow does not push that tag and does not create the Release.

### Meta Horizon, ALPHA channel

| Name | Kind | Value |
| --- | --- | --- |
| `HORIZON_APP_ID` | Secret | App ID from the app's API page in the Meta Horizon Developer Dashboard |
| `HORIZON_APP_SECRET` | Secret | App secret from that same API page |
| `HORIZON_AGE_GROUP` | **Variable** (not a secret) | `TEENS_AND_ADULTS`, `MIXED_AGES`, or `CHILDREN` |

The age group is a store-policy choice. The planner does not pick one. An
upload without `--age-group` lands as a draft on Meta's side, and an upload
with the wrong group is the wrong rating. Set the variable to the group that
matches the listing.

The command the plan prints, with those names still as variables:

```bash
ovr-platform-util upload-quest-build \
  --age-group "$HORIZON_AGE_GROUP" \
  --app-id "$HORIZON_APP_ID" \
  --app-secret "$HORIZON_APP_SECRET" \
  --apk build/paddleball-release.apk \
  --channel ALPHA \
  --notes "Paddle Quest <version>" \
  --disable-progress-bar
```

`--channel ALPHA` is the alpha release channel from the issue. Channel names
are not case-sensitive. `STORE` is production; do not point this at `STORE`
for a first upload.

Install `ovr-platform-util` from Meta's command-line utility page
(<https://developers.meta.com/vr/resources/publish-reference-platform-command-line-utility/>).
The Linux build is marked experimental there. Run the command on a machine
that has the signed APK. CI does not download the utility and does not run it.

The first upload often fails until an org admin has signed the Developer
Distribution Agreement in the dashboard. That signature is Kevin's; the
workflow cannot do it.

### Steam depot (Steam Frame)

The Frame build is `build/paddlequest.arm64`, a Linux arm64 binary. The depot
in Steamworks has to be that OS and architecture. Uploading it does not grant
"Steam Frame Standalone Verified"; that is a review status.

Steam Guard rejects a password login from GitHub's runners, so the credential
is a one-time interactive login, not `STEAM_PASSWORD`.

| Secret | Value |
| --- | --- |
| `STEAM_USERNAME` | Steamworks account that can upload the app |
| `STEAM_CONFIG_VDF_BASE64` | Base64 of `config.vdf` from that login |
| `STEAM_SSFN_FILENAME` | File name of the `ssfn*` sentry file written beside it |
| `STEAM_SSFN_BASE64` | Base64 of that sentry file |
| `STEAM_APP_ID` | Steam app id |
| `STEAM_DEPOT_FRAME_ID` | Depot id for the Linux arm64 Frame build |

On a trusted machine:

```bash
steamcmd +login "$STEAM_USERNAME"
```

Complete Steam Guard. Then base64 the files steamcmd wrote. On Linux they are
under `~/.local/share/Steam/config/` (`config.vdf` and a file whose name
starts with `ssfn`). `STEAM_SSFN_FILENAME` is that file's name, so a later
manual upload can place it next to `config.vdf` again.

The plan's `app_build.vdf` maps `paddlequest.arm64` into `$STEAM_DEPOT_FRAME_ID`.
The command it prints is:

```bash
steamcmd +login "$STEAM_USERNAME" +run_app_build build/steam/app_build.vdf +quit
```

Write the vdf from the plan to `build/steam/app_build.vdf`, with the real app
id and depot id substituted, and run that on a machine that already has the
config and the sentry file. CI does not install steamcmd and does not log in.

### Launcher icons

`export_presets.cfg` leaves these empty, so the APK falls back to
`config/icon` (`icon.svg`). A store listing wants the explicit sizes. The
planner reports them under `launcher_icons` and does not generate the files.

| Preset key | Size |
| --- | --- |
| `launcher_icons/main_192x192` | 192×192 |
| `launcher_icons/adaptive_foreground_432x432` | 432×432 |
| `launcher_icons/adaptive_background_432x432` | 432×432 |
| `launcher_icons/adaptive_monochrome_432x432` | 432×432 |

Fill those in before a Horizon or Steam submission. The GitHub Release can
go out without them; sideload does not care.

## Order of operations, when a real publish is wanted

1. Add the three `ANDROID_KEYSTORE_*` secrets. Re-run this workflow and
   confirm `signing.mode` is `release`.
2. Push a `v*` tag. `build.yml` drafts the GitHub Release. This workflow
   still only plans.
3. Set `HORIZON_APP_ID`, `HORIZON_APP_SECRET`, and the `HORIZON_AGE_GROUP`
   variable. Run `ovr-platform-util` locally against the signed APK. Sign the
   distribution agreement if Meta asks.
4. Create the Steam app and the arm64 depot, store the Steam secrets, and
   run `steamcmd` locally.
5. Add the four launcher icons before either store submission.

Until those exist, the dry-run is the whole channel: it is green, unsigned,
and it uploads nothing but its own plan.
