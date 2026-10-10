# CI and supply-chain pinning

Everything the CI (and the build) pulls in is pinned to something that cannot change underneath us, so a hijacked tag, a
re-pushed image or a swapped package fails loudly instead of running.

| What | How it is pinned | How to update it |
|---|---|---|
| GitHub Actions (`uses:`) | the full 40-character commit SHA, the release in a comment after it | Dependabot proposes it weekly (7 day cooldown); or resolve the release tag to its commit: `gh api repos/OWNER/REPO/git/ref/tags/TAG` (an annotated tag needs a second step: `git/tags/SHA` → `.object.sha`) |
| Docker actions (hassfest, HACS) | run by image **digest** (`image@sha256:…`): their `action.yml` pulls a floating tag (`:latest`, `:main`), so pinning the action commit alone would not pin what runs | read the digest from the registry (`docker-content-digest` of `GET /v2/<image>/manifests/<tag>` with an anonymous pull token) and replace it; hassfest follows each Home Assistant release, so refresh it then |
| Flutter | exact `flutter-version` in `ci.yml` (the version the tests were run with) | bump it together with a local `flutter test` |
| Dart packages | `app/pubspec.lock` (versions and content hashes), CI uses `flutter pub get --enforce-lockfile` | `flutter pub upgrade`, review the lockfile diff; Dependabot also proposes |
| Gradle itself | `distributionSha256Sum` in `gradle-wrapper.properties` (from services.gradle.org, `…-all.zip.sha256`) | bump the wrapper, then the checksum |
| Gradle libraries and plugins | `app/android/gradle/verification-metadata.xml` (SHA-256 of every artifact; a mismatch fails the build) | `./gradlew --write-verification-metadata sha256 :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`, then **review the diff** |
| Token | `permissions: contents: read`, `persist-credentials: false` on checkout | — |
| Python / Node in CI | the standard library only (no `pip install`, no `npm install`) | — |

Rules when adding something: no `@main`, `@master`, `@v4` or `:latest`; prefer the standard library; if a tool must be installed,
pin its exact version **and** hash (`pip install --require-hashes`, `npm ci` with a lockfile). Third-party code that runs with a
token or on release builds is the thing to keep short.

Also checked by CI since this was introduced: `hassfest` and the HACS validation (installable through HACS), Android lint
(it found two crashes on Android 8.0 and a missing permission), the Dart analyzer and all unit tests.
