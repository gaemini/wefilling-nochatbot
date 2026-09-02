#!/usr/bin/env python3
"""Fail-closed checks for Wefilling production release artifacts.

This script never uploads or deploys. It validates the canonical manifest,
source configuration, Store state and (when provided) the generated artifact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
META_PATH = ROOT / "assets/release/release_metadata.json"
STORE_STATE_PATH = ROOT / "release/store_state.json"
RC_TEMPLATE_PATH = ROOT / "release/remote_config_update_policy.template.json"


class GuardFailure(RuntimeError):
    pass


def fail(message: str) -> None:
    raise GuardFailure(message)


def read_json(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, ValueError) as error:
        fail(f"cannot read {path.relative_to(ROOT)}: {error}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        fail(f"cannot read {path.relative_to(ROOT)}: {error}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def pubspec_version() -> tuple[str, int]:
    match = re.search(
        r"(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$",
        read_text(ROOT / "pubspec.yaml"),
    )
    if not match:
        fail("pubspec.yaml version must be x.y.z+integer")
    return match.group(1), int(match.group(2))


def properties(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    for line in read_text(path).splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def validate_common(meta: dict, store: dict) -> None:
    version, build = pubspec_version()
    require(meta.get("versionName") == version, "release versionName != pubspec")
    require(meta.get("buildNumber") == build, "release buildNumber != pubspec")
    require(meta.get("releaseChannel") == "production", "release channel is not production")
    require(meta.get("firebaseProjectId") == "flutterproject3-af322", "unexpected Firebase project")
    require(bool(meta.get("releaseId")), "releaseId is empty")
    require(int(meta.get("cacheSchemaVersion", 0)) > 0, "cache schema must be positive")

    migrations = meta.get("migrations", {})
    require(isinstance(migrations, dict), "migrations must be an object")
    for schema in range(1, int(meta["cacheSchemaVersion"]) + 1):
        require(str(schema) in migrations, f"missing cache migration plan {schema}")

    durable = {"dm_messages_v1", "snack_chat_state_v1"}
    planned = {
        str(item)
        for values in migrations.values()
        if isinstance(values, list)
        for item in values
    }
    require(not (durable & planned), "migration attempts to delete durable chat state")

    rc = read_json(RC_TEMPLATE_PATH)
    require(rc.get("update_kill_switch") is True, "Remote Config default kill switch must be true")
    for platform in ("android", "ios"):
        require(rc.get(f"{platform}_release_state") == "paused", f"{platform} RC default must be paused")
        require(int(rc.get(f"{platform}_minimum_build", -1)) == 0, f"{platform} default minimum build must be 0")

    app_check = read_text(ROOT / "lib/services/firebase_app_check_service.dart")
    for token in (
        "AndroidDebugProvider",
        "AndroidPlayIntegrityProvider",
        "AppleDebugProvider",
        "AppleAppAttestWithDeviceCheckFallbackProvider",
    ):
        require(token in app_check, f"App Check provider missing: {token}")
    require("kDebugMode" in app_check, "App Check providers are not build-mode separated")
    require("RELEASE_CHANNEL" in app_check, "App Check production provider is not release-channel gated")

    forbidden = re.compile(r"(10\.0\.2\.2|127\.0\.0\.1|localhost|useFirestoreEmulator|useAuthEmulator)")
    production_sources = "\n".join(
        read_text(path)
        for path in (
            ROOT / "lib/main.dart",
            ROOT / "lib/config/app_config.dart",
            ROOT / "lib/firebase_options.dart",
        )
    )
    require(not forbidden.search(production_sources), "emulator/development endpoint found in production startup")

    for platform in ("android", "ios"):
        state = store.get(platform, {}).get("releaseState", "")
        require(state in {"draft", "uploaded", "storeProcessing", "storeReady", "active", "paused"}, f"invalid {platform} release state")
        require(meta[platform].get("releaseState") in {"draft", "uploaded", "storeProcessing"}, f"candidate metadata cannot claim {platform} Store activation")


def validate_android(meta: dict, store: dict, strict_signing: bool) -> None:
    android = meta["android"]
    expected_id = "com.wefilling.app"
    require(android.get("applicationId") == expected_id, "wrong Android applicationId")
    require(android.get("flavor") == "production", "wrong Android flavor")
    require(android.get("entryPoint") == "lib/main.dart", "wrong Android entry point")

    gradle = read_text(ROOT / "android/app/build.gradle.kts")
    require(f'applicationId = "{expected_id}"' in gradle, "Gradle production applicationId mismatch")
    require('create("production")' in gradle, "production flavor missing")
    require('signingConfig = signingConfigs.getByName("release")' in gradle, "release signing config missing")

    google = read_json(ROOT / "android/app/google-services.json")
    require(google.get("project_info", {}).get("project_id") == meta["firebaseProjectId"], "Android Firebase project mismatch")
    clients = []
    for client in google.get("client", []):
        package = client.get("client_info", {}).get("android_client_info", {}).get("package_name")
        if package == expected_id:
            clients.append(client)
    require(len(clients) == 1, "google-services.json needs exactly one production client")
    actual_app_id = clients[0].get("client_info", {}).get("mobilesdk_app_id")
    require(actual_app_id == android.get("firebaseAppId"), "Android Firebase App ID mismatch")

    previous = properties(ROOT / "android/release-version.properties")
    last_build = int(previous.get("lastUsedVersionCode", "0") or 0)
    require(int(meta["buildNumber"]) >= last_build, f"Android build must not be lower than locally generated build {last_build}")
    verified = int(store.get("android", {}).get("verifiedStoreBuild", 0))
    require(int(meta["buildNumber"]) > verified, f"Android build must exceed verified Store build {verified}")
    if strict_signing:
        android_state = store.get("android", {})
        expected_upload = android_state.get("uploadCertificateSha256", "")
        require(bool(expected_upload), "set Android upload certificate SHA-256 in release/store_state.json")
        play_signing = android_state.get("playAppSigningCertificateSha256", "")
        if not play_signing:
            print(
                "RELEASE WARNING: Play App Signing SHA-256 is not recorded. "
                "The AAB upload signature is still verified, but register the "
                "Play signing fingerprint in Firebase App Check before rollout.",
                file=sys.stderr,
            )
        else:
            require(
                len(normalize_fingerprint(play_signing)) == 64,
                "invalid Play App Signing SHA-256 format",
            )
        signing = properties(ROOT / "android/key.properties")
        for key in ("storeFile", "storePassword", "keyAlias"):
            require(bool(signing.get(key)), f"android/key.properties is missing {key}")
        store_file = Path(signing["storeFile"])
        if not store_file.is_absolute():
            store_file = ROOT / "android/app" / store_file
        require(store_file.is_file(), "Android upload keystore is missing")
        certificate = run([
            "keytool", "-list", "-v", "-keystore", str(store_file),
            "-alias", signing["keyAlias"], "-storepass", signing["storePassword"],
        ])
        match = re.search(r"SHA256:\s*([0-9A-Fa-f:]+)", certificate)
        require(match is not None, "cannot read Android upload certificate")
        require(normalize_fingerprint(match.group(1)) == normalize_fingerprint(expected_upload), "configured Android upload certificate mismatch")

    script = read_text(ROOT / "scripts/android_release.sh")
    require("--flavor production" in script or "--flavor\n  production" in script, "Android release script must build production flavor")
    require("-t lib/main.dart" in script or '--target="lib/main.dart"' in script, "Android release script must pin lib/main.dart")
    require("FLUTTER_APP_FLAVOR=production" in script, "Android release script must enable production App Check")


def validate_ios(meta: dict, store: dict, strict_signing: bool) -> None:
    ios = meta["ios"]
    expected_id = "com.wefilling.app"
    require(ios.get("bundleId") == expected_id, "wrong iOS bundle identifier")
    require(ios.get("scheme") == "Runner", "unexpected iOS production scheme")
    require(ios.get("configuration") == "Release", "unexpected iOS production configuration")
    require(bool(ios.get("appStoreId")), "App Store ID is missing")

    project = read_text(ROOT / "ios/Runner.xcodeproj/project.pbxproj")
    runner_ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", project)
    require(expected_id in runner_ids, "Runner bundle identifier mismatch")
    require(ios.get("teamId") in project, "iOS development team mismatch")
    require(
        project.count('"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";') >= 4,
        "Runner and Share Extension Release/Profile must use Apple Distribution",
    )

    with (ROOT / "ios/Runner/GoogleService-Info.plist").open("rb") as handle:
        firebase = plistlib.load(handle)
    require(firebase.get("BUNDLE_ID") == expected_id, "iOS Firebase bundle ID mismatch")
    require(firebase.get("PROJECT_ID") == meta["firebaseProjectId"], "iOS Firebase project mismatch")
    require(firebase.get("GOOGLE_APP_ID") == ios.get("firebaseAppId"), "iOS Firebase App ID mismatch")

    scheme = read_text(ROOT / "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme")
    require('<ArchiveAction\n      buildConfiguration = "Release"' in scheme, "Runner archive is not Release")
    for filename, environment in (
        ("RunnerDebug.entitlements", "development"),
        ("RunnerProfile.entitlements", "production"),
        ("RunnerRelease.entitlements", "production"),
    ):
        with (ROOT / "ios/Runner" / filename).open("rb") as handle:
            entitlements = plistlib.load(handle)
        require(
            entitlements.get("com.apple.developer.devicecheck.appattest-environment") == environment,
            f"{filename} App Attest environment must be {environment}",
        )
    ios_script = read_text(ROOT / "scripts/ios_release.sh")
    require("FLUTTER_APP_FLAVOR=production" in ios_script, "iOS release script must enable production App Check")
    verified = int(store.get("ios", {}).get("verifiedStoreBuild", 0))
    require(int(meta["buildNumber"]) > verified, f"iOS build must exceed verified Store build {verified}")
    if strict_signing:
        require(bool(store.get("ios", {}).get("distributionCertificateSha256")), "set iOS distribution certificate SHA-256 in release/store_state.json")
        identities = run(["security", "find-identity", "-v", "-p", "codesigning"])
        require(
            "Apple Distribution" in identities or "iPhone Distribution" in identities,
            "Apple Distribution signing identity/private key is not installed in this Mac keychain",
        )


def run(command: list[str]) -> str:
    try:
        return subprocess.run(command, check=True, text=True, capture_output=True).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        fail(f"command failed: {' '.join(command)}: {detail.strip()}")


def bundled_metadata(archive: zipfile.ZipFile) -> dict:
    candidates = [
        name for name in archive.namelist()
        if name.endswith("flutter_assets/assets/release/release_metadata.json")
    ]
    require(len(candidates) == 1, "artifact release metadata is missing or duplicated")
    return json.loads(archive.read(candidates[0]).decode("utf-8"))


def bundletool_manifest(artifact: Path) -> str:
    executable = shutil.which("bundletool")
    jar = os.environ.get("BUNDLETOOL_JAR", "").strip()
    if executable:
        return run([executable, "dump", "manifest", f"--bundle={artifact}"])
    if jar and Path(jar).is_file():
        return run(["java", "-jar", jar, "dump", "manifest", f"--bundle={artifact}"])
    fail("bundletool is required for AAB manifest verification (or set BUNDLETOOL_JAR)")


def normalize_fingerprint(value: str) -> str:
    return re.sub(r"[^0-9A-F]", "", value.upper())


def validate_android_artifact(meta: dict, store: dict, artifact: Path) -> None:
    require(artifact.suffix == ".aab" and artifact.is_file(), "Android artifact must be an existing .aab")
    with zipfile.ZipFile(artifact) as archive:
        require(bundled_metadata(archive) == meta, "AAB release metadata differs from canonical metadata")
    manifest = bundletool_manifest(artifact)
    require(f'package="{meta["android"]["applicationId"]}"' in manifest, "AAB applicationId mismatch")
    require(f'android:versionCode="{meta["buildNumber"]}"' in manifest, "AAB versionCode mismatch")
    require(f'android:versionName="{meta["versionName"]}"' in manifest, "AAB versionName mismatch")
    # Play upload keys are commonly self-signed. `-strict` returns exit code 4
    # for that expected trust-chain warning even when every AAB entry is
    # correctly signed. Verify the JAR signature normally, then enforce the
    # exact configured upload certificate fingerprint below.
    signature_result = run(["jarsigner", "-verify", "-verbose", str(artifact)])
    require("jar verified." in signature_result.lower(), "AAB JAR signature verification failed")
    certificate = run(["keytool", "-printcert", "-jarfile", str(artifact)])
    match = re.search(r"SHA256:\s*([0-9A-Fa-f:]+)", certificate)
    require(match is not None, "cannot read AAB signing certificate")
    expected = store["android"]["uploadCertificateSha256"]
    require(normalize_fingerprint(match.group(1)) == normalize_fingerprint(expected), "AAB upload certificate mismatch")


def ios_app_from_artifact(artifact: Path, temp: Path) -> Path:
    if artifact.suffix == ".ipa":
        with zipfile.ZipFile(artifact) as archive:
            archive.extractall(temp)
        apps = list((temp / "Payload").glob("*.app"))
    elif artifact.suffix == ".xcarchive":
        apps = list((artifact / "Products/Applications").glob("*.app"))
    else:
        apps = []
    require(len(apps) == 1, "iOS artifact must contain exactly one app")
    return apps[0]


def validate_ios_artifact(meta: dict, store: dict, artifact: Path) -> None:
    require(artifact.exists(), "iOS artifact does not exist")
    with tempfile.TemporaryDirectory(prefix="wefilling-release-") as directory:
        app = ios_app_from_artifact(artifact, Path(directory))
        with (app / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        require(info.get("CFBundleIdentifier") == meta["ios"]["bundleId"], "IPA bundle identifier mismatch")
        require(info.get("CFBundleShortVersionString") == meta["versionName"], "IPA version mismatch")
        require(str(info.get("CFBundleVersion")) == str(meta["buildNumber"]), "IPA build mismatch")
        asset = app / "Frameworks/App.framework/flutter_assets/assets/release/release_metadata.json"
        require(asset.is_file(), "IPA release metadata is missing")
        require(read_json(asset) == meta, "IPA release metadata differs from canonical metadata")
        embedded_profile = app / "embedded.mobileprovision"
        require(embedded_profile.is_file(), "IPA provisioning profile is missing")
        profile_xml = run(["security", "cms", "-D", "-i", str(embedded_profile)])
        try:
            profile = plistlib.loads(profile_xml.encode("utf-8"))
        except (ValueError, plistlib.InvalidFileException) as error:
            fail(f"cannot parse IPA provisioning profile: {error}")
        profile_entitlements = profile.get("Entitlements", {})
        require(
            profile_entitlements.get("com.apple.developer.devicecheck.appattest-environment") == "production",
            "IPA provisioning profile does not authorize production App Attest",
        )
        cert_prefix = Path(directory) / "signing"
        run(["codesign", "-d", f"--extract-certificates={cert_prefix}", str(app)])
        cert = Path(f"{cert_prefix}0")
        require(cert.is_file(), "cannot extract iOS signing certificate")
        digest = hashlib.sha256(cert.read_bytes()).hexdigest()
        expected = normalize_fingerprint(store["ios"]["distributionCertificateSha256"])
        require(digest.upper() == expected, "iOS distribution certificate mismatch")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--strict-signing", action="store_true")
    args = parser.parse_args()
    try:
        meta = read_json(META_PATH)
        store = read_json(STORE_STATE_PATH)
        validate_common(meta, store)
        if args.platform == "android":
            validate_android(meta, store, args.strict_signing)
            if args.artifact:
                validate_android_artifact(meta, store, args.artifact.resolve())
        else:
            validate_ios(meta, store, args.strict_signing)
            if args.artifact:
                validate_ios_artifact(meta, store, args.artifact.resolve())
        print(f"Release Guard passed: {args.platform} {meta['versionName']}+{meta['buildNumber']}")
        return 0
    except GuardFailure as error:
        print(f"RELEASE BLOCKED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
