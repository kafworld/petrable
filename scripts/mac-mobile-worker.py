#!/usr/bin/env python3
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


REPO_ROOT = Path(os.environ.get("KEITHABLE_REPO_ROOT", Path(__file__).resolve().parents[1])).resolve()
OUT_ROOT = Path(
    os.environ.get(
        "KEITHABLE_WORKER_OUT_ROOT",
        REPO_ROOT / "ios" / "build" / "mac-mobile-worker",
    )
).resolve()
WORKER_ID = os.environ.get("KEITHABLE_WORKER_ID", os.uname().nodename or "keith-mac")
TOKEN = os.environ.get("KEITHABLE_WORKER_TOKEN")
ENV_SCRIPT = Path(os.environ.get("KEITHABLE_ENV_SCRIPT", REPO_ROOT / "scripts" / "keithable-env.sh"))
AUTO_INSTALL = os.environ.get("KEITHABLE_AUTO_INSTALL_MOBILE", "1") != "0"
SIGNULOUS_API = os.environ.get("KEITHABLE_SIGNULOUS_API", "https://api2.signulous.com/sign-app")
PHONE_PROFILE = Path(
    os.environ.get(
        "KEITHABLE_IPHONE_PROFILE",
        "/Users/flybookpro/.codex/skills/iphone-wifi-app-delivery/references/keith-iphone-profile.json",
    )
)
APPLE_READY_LANDER = Path(
    os.environ.get("KEITHABLE_APPLE_READY_LANDER", "/Users/flybookpro/.codex/bin/apple-ready-ipa-lander")
)


def run(cmd, cwd=REPO_ROOT, check=True, capture=True):
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if check and result.returncode != 0:
        output = result.stdout or ""
        raise RuntimeError(output[-4000:] or f"Command failed: {' '.join(cmd)}")
    return result.stdout or ""


def convex(function, args):
    payload = json.dumps(args)
    command = (
        f"source {shlex.quote(str(ENV_SCRIPT))}; "
        f"convex run {shlex.quote(function)} {shlex.quote(payload)}"
    )
    out = run(["bash", "-lc", command])
    return parse_json(out)


def parse_json(text):
    cleaned = re.sub(r"\x1b\[[0-9;]*m", "", text).strip()
    if not cleaned:
        return None
    decoder = json.JSONDecoder()
    for index, char in enumerate(cleaned):
        if char in "[{\"tfn":
            try:
                value, _ = decoder.raw_decode(cleaned[index:])
                return value
            except json.JSONDecodeError:
                continue
    raise RuntimeError(f"Could not parse Convex JSON output:\n{cleaned[-1200:]}")


def safe_name(value):
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    return slug[:48] or "KeithableApp"


def icon_letters(name):
    words = re.findall(r"[A-Za-z0-9]+", name)
    if len(words) >= 2:
        return (words[0][0] + words[1][0]).upper()
    if words:
        return words[0][:2].upper()
    return "K"


def icon_colours(name):
    palettes = [
        ((245, 68, 92), (124, 92, 252)),
        ((25, 176, 140), (38, 132, 255)),
        ((255, 159, 67), (238, 82, 83)),
        ((91, 141, 239), (143, 83, 255)),
        ((52, 199, 89), (0, 122, 255)),
        ((255, 45, 85), (88, 86, 214)),
    ]
    index = sum(ord(char) for char in name) % len(palettes)
    return palettes[index]


def font_for(size):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Avenir Next Condensed.ttc",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def make_icon_png(path, pixels, name):
    top, bottom = icon_colours(name)
    image = Image.new("RGB", (pixels, pixels), top)
    draw = ImageDraw.Draw(image)
    for y in range(pixels):
        ratio = y / max(pixels - 1, 1)
        colour = tuple(int(top[i] * (1 - ratio) + bottom[i] * ratio) for i in range(3))
        draw.line([(0, y), (pixels, y)], fill=colour)

    inset = max(2, int(pixels * 0.11))
    radius = max(3, int(pixels * 0.22))
    draw.rounded_rectangle(
        [inset, inset, pixels - inset, pixels - inset],
        radius=radius,
        fill=(255, 255, 255),
        outline=(255, 255, 255),
    )
    inner = max(1, int(pixels * 0.035))
    if pixels - inset - inner > inset + inner:
        draw.rounded_rectangle(
            [inset + inner, inset + inner, pixels - inset - inner, pixels - inset - inner],
            radius=max(2, radius - inner),
            fill=None,
            outline=(235, 238, 246),
            width=max(1, int(pixels * 0.018)),
        )

    letters = icon_letters(name)
    font = font_for(max(16, int(pixels * (0.34 if len(letters) == 2 else 0.42))))
    bbox = draw.textbbox((0, 0), letters, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (pixels - text_width) / 2 - bbox[0]
    y = (pixels - text_height) / 2 - bbox[1] - pixels * 0.01
    draw.text((x, y), letters, font=font, fill=bottom)

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def write_app_icon_set(source_dir, app_name):
    icon_dir = source_dir / "Assets.xcassets" / "AppIcon.appiconset"
    images = []
    specs = [
        ("iphone", "20x20", "2x", 40),
        ("iphone", "20x20", "3x", 60),
        ("iphone", "29x29", "2x", 58),
        ("iphone", "29x29", "3x", 87),
        ("iphone", "40x40", "2x", 80),
        ("iphone", "40x40", "3x", 120),
        ("iphone", "60x60", "2x", 120),
        ("iphone", "60x60", "3x", 180),
        ("ipad", "20x20", "1x", 20),
        ("ipad", "20x20", "2x", 40),
        ("ipad", "29x29", "1x", 29),
        ("ipad", "29x29", "2x", 58),
        ("ipad", "40x40", "1x", 40),
        ("ipad", "40x40", "2x", 80),
        ("ipad", "76x76", "1x", 76),
        ("ipad", "76x76", "2x", 152),
        ("ipad", "83.5x83.5", "2x", 167),
        ("ios-marketing", "1024x1024", "1x", 1024),
    ]
    for idiom, size, scale, pixels in specs:
        filename = f"Icon-{idiom}-{size.replace('.', '_').replace('x', 'x')}@{scale}.png"
        make_icon_png(icon_dir / filename, pixels, app_name)
        images.append({"idiom": idiom, "size": size, "scale": scale, "filename": filename})

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (icon_dir / "Contents.json").write_text(json.dumps(contents, indent=2), encoding="utf-8")


def xcodegen_project(display_name, bundle_id, build_number):
    return f"""name: KeithableGenerated
options:
  bundleIdPrefix: com.keithable.generated
  deploymentTarget:
    iOS: "17.0"
targets:
  App:
    type: application
    platform: iOS
    sources:
      - App
      - Assets.xcassets
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        PRODUCT_BUNDLE_IDENTIFIER: {bundle_id}
        PRODUCT_NAME: App
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "{build_number}"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: "{display_name}"
        INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: UIInterfaceOrientationPortrait
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
        TARGETED_DEVICE_FAMILY: "1,2"
        SWIFT_VERSION: "5.0"
        CODE_SIGN_STYLE: Manual
schemes:
  App:
    build:
      targets:
        App: all
"""


def build_job(job):
    project_id = job["_id"]
    name = job["name"]
    bundle_id = job["bundleId"]
    stamp = time.strftime("%Y%m%d_%H%M%S")
    job_dir = OUT_ROOT / f"{stamp}_{project_id}"
    source_dir = job_dir / "source"
    app_dir = source_dir / "App"
    logs_dir = job_dir / "logs"
    ipa_dir = job_dir / "ipa"
    app_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    ipa_dir.mkdir(parents=True, exist_ok=True)

    build_number = str(int(time.time()))
    (source_dir / "project.yml").write_text(xcodegen_project(name, bundle_id, build_number), encoding="utf-8")
    write_app_icon_set(source_dir, name)
    for file in job["files"]:
        path = Path(file["path"])
        if path.is_absolute() or ".." in path.parts or path.suffix.lower() != ".swift":
            continue
        target = app_dir / path.name
        target.write_text(file["content"], encoding="utf-8")

    command = (
        f"source {shlex.quote(str(ENV_SCRIPT))}; "
        f"ensure_xcodegen; cd {shlex.quote(str(source_dir))}; "
        '"$XCODEGEN_BIN" generate'
    )
    run(["bash", "-lc", command], cwd=REPO_ROOT)

    build_log = logs_dir / "xcodebuild.log"
    build_cmd = [
        "xcodebuild",
        "-project",
        "KeithableGenerated.xcodeproj",
        "-scheme",
        "App",
        "-configuration",
        "Release",
        "-destination",
        "generic/platform=iOS",
        "-derivedDataPath",
        str(job_dir / "DerivedData"),
        "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO",
        'CODE_SIGN_IDENTITY=',
        "build",
    ]
    output = run(build_cmd, cwd=source_dir, check=False)
    build_log.write_text(output, encoding="utf-8")
    if "** BUILD SUCCEEDED **" not in output:
        raise RuntimeError(summarise_build_failure(output, build_log))

    app_path = job_dir / "DerivedData" / "Build" / "Products" / "Release-iphoneos" / "App.app"
    if not app_path.exists():
        raise RuntimeError(f"Build succeeded but App.app was not found at {app_path}")

    payload_dir = job_dir / "Payload"
    payload_dir.mkdir(exist_ok=True)
    packaged_app = payload_dir / f"{safe_name(name)}.app"
    if packaged_app.exists():
        raise RuntimeError(f"Unexpected existing package path: {packaged_app}")
    shutil.copytree(app_path, packaged_app, symlinks=True)

    ipa_path = ipa_dir / f"{safe_name(name)}-unsigned.ipa"
    with zipfile.ZipFile(ipa_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for item in payload_dir.rglob("*"):
            archive.write(item, item.relative_to(job_dir))

    return ipa_path


def signulous_udid():
    explicit = os.environ.get("KEITHABLE_SIGNULOUS_UDID")
    if explicit:
        return explicit
    if not PHONE_PROFILE.exists():
        return None
    try:
        profile = json.loads(PHONE_PROFILE.read_text(encoding="utf-8"))
    except Exception:
        return None
    return (
        profile.get("device", {}).get("udid")
        or profile.get("delivery", {}).get("preferredDeviceArgument")
    )


def auto_sign_install(ipa_path, name, bundle_id):
    if not AUTO_INSTALL:
        return {"installResult": "skipped", "detail": "Automatic install disabled"}
    udid = signulous_udid()
    if not udid:
        return {"installResult": "blocked", "detail": "Missing Signulous device UDID"}
    if not shutil.which("curl"):
        return {"installResult": "blocked", "detail": "curl is unavailable"}

    work_dir = ipa_path.parent / "signulous"
    signed_dir = ipa_path.parent / "signed"
    work_dir.mkdir(parents=True, exist_ok=True)
    signed_dir.mkdir(parents=True, exist_ok=True)
    headers = work_dir / "headers.txt"
    body = work_dir / "body.json"

    upload_cmd = [
        "curl",
        "-sS",
        "-L",
        "-D",
        str(headers),
        "-o",
        str(body),
        "-w",
        "%{http_code}",
        "-F",
        f"udid={udid}",
        "-F",
        f"customName={name}",
        "-F",
        "customVersion=1.0",
        "-F",
        f"customBundleIdentifier={bundle_id}",
        "-F",
        f"app=@{ipa_path};type=application/octet-stream",
        SIGNULOUS_API,
    ]
    http_code = run(upload_cmd).strip()
    response_text = body.read_text(encoding="utf-8", errors="replace") if body.exists() else ""
    try:
        response = json.loads(response_text)
    except json.JSONDecodeError:
        response = {}
    if http_code != "200" or response.get("status") != "success" or not response.get("message"):
        return {
            "installResult": "blocked",
            "detail": f"Signulous upload failed: HTTP {http_code} {response_text[-300:]}",
        }

    filename = response["message"]
    signed_ipa = signed_dir / f"{safe_name(name)}-signulous-signed.ipa"
    signed_url = f"https://cdn2.signulous.com/downloads/{udid.lower()}/{filename}"
    download_headers = signed_dir / f"{filename}.headers.txt"
    run([
        "curl",
        "-sS",
        "-L",
        "-D",
        str(download_headers),
        "-o",
        str(signed_ipa),
        signed_url,
    ])
    if not signed_ipa.exists() or signed_ipa.stat().st_size < 100_000:
        return {
            "installResult": "blocked",
            "detail": f"Signed IPA download failed from Signulous: {signed_url}",
        }
    if not APPLE_READY_LANDER.exists():
        return {
            "installResult": "signed",
            "signedIpaPath": str(signed_ipa),
            "detail": "Signed IPA ready; Apple-ready installer not found",
        }

    install_log = signed_dir / "install.log"
    install_output = run(
        [str(APPLE_READY_LANDER), str(signed_ipa), "--install-signed", "--launch"],
        check=False,
    )
    install_log.write_text(install_output, encoding="utf-8")
    installed = "Install: completed over Wi-Fi" in install_output or "Installed:" in install_output
    return {
        "installResult": "installed" if installed else "blocked",
        "signedIpaPath": str(signed_ipa),
        "detail": "Installed on FlyPhone17" if installed else install_output[-500:],
    }


def summarise_build_failure(output, log_path):
    lines = []
    for line in output.splitlines():
        if "error:" in line.lower() or "** BUILD FAILED **" in line:
            lines.append(line.strip())
    summary = " | ".join(lines[-8:]) if lines else output[-1200:]
    return f"{summary}\nFull log: {log_path}"


def process_one():
    args = {"token": TOKEN} if TOKEN else {}
    jobs = convex("worker:pendingMobileBuilds", args)
    queued = [job for job in jobs if job.get("status") == "mac_queued"]
    if not queued:
        print("No queued mobile builds.")
        return 0

    job = queued[0]
    claim_args = {"id": job["_id"], "workerId": WORKER_ID}
    if TOKEN:
        claim_args["token"] = TOKEN
    claimed = convex("worker:claimMobileBuild", claim_args)
    if not claimed:
        print(f"Job {job['_id']} was already claimed.")
        return 0

    try:
        ipa_path = build_job(job)
        delivery = auto_sign_install(ipa_path, job["name"], job["bundleId"])
        complete_args = {
            "id": job["_id"],
            "ipaPath": str(ipa_path),
            "bundleId": job["bundleId"],
            "workerId": WORKER_ID,
            "installResult": delivery.get("installResult"),
        }
        if delivery.get("signedIpaPath"):
            complete_args["signedIpaPath"] = delivery["signedIpaPath"]
        if TOKEN:
            complete_args["token"] = TOKEN
        convex("worker:completeMobileBuild", complete_args)
        print(f"Built IPA: {ipa_path}")
        print(f"Delivery: {delivery}")
        return 0
    except Exception as exc:
        fail_args = {
            "id": job["_id"],
            "error": str(exc)[-1200:],
            "workerId": WORKER_ID,
        }
        if TOKEN:
            fail_args["token"] = TOKEN
        convex("worker:failMobileBuild", fail_args)
        print(f"Build failed: {exc}", file=sys.stderr)
        return 1


def main():
    if "--loop" in sys.argv:
        interval = int(os.environ.get("KEITHABLE_WORKER_INTERVAL", "20"))
        while True:
            process_one()
            time.sleep(interval)
    return process_one()


if __name__ == "__main__":
    raise SystemExit(main())
