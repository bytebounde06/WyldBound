# WyldBound — iPhone setup (Windows PC, no Mac)

This repository sets up **both** ways to play WyldBound on your iPhone. GitHub's servers build the iPhone app (which normally needs a Mac) and host the web app for you.

| | Option 1: Home Screen web app | Option 2: Real app via SideStore |
|---|---|---|
| Expires? | Never | Every 7 days, but SideStore renews it on the phone |
| Needs PC after setup? | No | No (one-time setup only) |
| Apple ID needed? | No | Yes (a free one works) |
| Internet needed to play? | Only for the first open | No |
| Setup effort | ~10 minutes | ~30–45 minutes |

---

## Part 1 — Finish GitHub setup (once)

Everything is already uploaded, including the game. You only need to do two things:

1. **Turn on the web app hosting** (public repository only): go to **Settings → Pages** and under **Build and deployment → Source**, choose **GitHub Actions**.
2. **Run the build.** Open the **Actions** tab → **Build WyldBound** → **Run workflow**. It takes about 5–10 minutes. Both jobs should get a green check:
   - **web** = the Home Screen web app.
   - **ipa** = the iPhone app for SideStore.

**To update the game later**, upload a new `WyldBound.html` (Add file → Upload files) to replace the old one. Everything rebuilds by itself.

---

## Option 1 — Home Screen web app (never expires)

1. On your iPhone, open **Safari** and go to:
   `https://bytebounde06.github.io/WyldBound/`
   The exact link is also in **Settings → Pages** after the first build.
2. Wait for the title screen to appear. This first visit saves the whole game onto your phone.
3. Tap **Share** (□↑) → **Add to Home Screen** → **Add**.
4. Open WyldBound from the new icon. It runs full screen and works with no internet from then on, even in airplane mode.

**Saves:** saves stay on your phone inside the Home Screen app. Use START → OPTIONS → **EXPORT SAVE CODE** now and then and paste the code into Notes as a backup.
**Updates:** when a new version is uploaded, open the app once while you're online. The new version loads the next time you open it.

---

## Option 2 — Real app with SideStore (Windows)

SideStore installs apps with your Apple ID and renews them on the phone every week, so you don't need the PC after setup.
A secondary Apple ID works fine if you'd rather not use your main one.

### A. One-time setup

**On your iPhone**
1. Make sure the phone has a passcode.
2. Install **LocalDevVPN** from the App Store (free).
3. Go to **Settings → Privacy & Security → Developer Mode** → turn it **On**, then restart.
   - If Developer Mode isn't listed, it will appear after step 7.

**On your Windows PC**

4. Install **iTunes from Apple's website**, *not* the Microsoft Store version:
   `https://www.apple.com/itunes/download/win64`
   Open it once, then close it. This installs the iPhone USB drivers.
5. Download and install **iloader**: `https://github.com/nab138/iloader/releases/latest`
   - Get `iloader-windows-x64.msi`. iloader works on 64-bit Windows only, not Windows on ARM.
6. Plug your iPhone into the PC with a cable. On the phone, tap **Trust** and enter your passcode.
7. Open iloader → **sign in with your Apple ID** → choose **Install SideStore**. Wait for it to finish. iloader also sets up the pairing file SideStore needs.

**Back on your iPhone**

8. Go to **Settings → General → VPN & Device Management**, tap your Apple ID under *Developer App*, and tap **Trust**.
9. Open **LocalDevVPN** → **Connect** → allow the VPN.
10. Open **SideStore** → **Settings** → sign in with the **same Apple ID**.
11. In SideStore's **My Apps** tab, tap the **7 DAYS** button next to SideStore to refresh it once. This confirms the setup works.

You can unplug from the PC now. You won't need it again.

### B. Install WyldBound

1. On your iPhone, open Safari and go to:
   `https://github.com/bytebounde06/WyldBound/releases/latest`
   (If the repository is private, sign in to GitHub in Safari first.)
2. Tap **WyldBound.ipa** → **Download**. It goes to Files → Downloads.
3. Turn on **LocalDevVPN** → open **SideStore** → **My Apps** → **+** (top left) → choose **WyldBound.ipa**.
4. WyldBound appears on your Home Screen. Play!

### C. Keeping it working (the 7-day renewal)

- At least once a week: turn on **LocalDevVPN**, open **SideStore**, and tap **Refresh All** in **My Apps**. No PC needed.
- In SideStore **Settings**, turn on **Background Refresh**, and allow Background App Refresh for SideStore in iPhone Settings. This lets it try on its own, but the weekly manual tap is the reliable way.
- If you miss the window, the app just won't open until you refresh. **Your saves are not lost.**
- A free Apple ID can have **3 sideloaded apps** at a time, and SideStore counts as one.

**Updating WyldBound:** download the new `WyldBound.ipa` from the releases page and install it the same way (My Apps → +). Your saves carry over.
**Saves in the app version** are also written to **Files → On My iPhone → WyldBound**, so they can be backed up.

---

## Android

1. On your Android phone, open `https://github.com/bytebounde06/WyldBound/releases/latest` and tap **WyldBound.apk** to download it.
2. Open the downloaded file. If Android asks, allow your browser or Files app to **install unknown apps**, then tap **Install**.
3. Open WyldBound. It runs fully offline. Updates install over the old version and keep your saves.

On Android, trading works with QR codes, including with iPhone players. Nearby Wi-Fi trading is iPhone-only for now.

## Trading

START → TRADE. With two phones together, one shows a QR code and the other scans it with the camera, three scans in all. Each phone asks for camera permission the first time. Every QR screen also has a text code for trading over Messages. In the iPhone app (SideStore version), **NEARBY TRADE (WI-FI)** finds friends' phones on the same Wi-Fi automatically. No codes needed; allow Local Network access when asked. Two files on the same phone can trade directly with TRADE ON THIS PHONE. Nuzlocke files can't trade.

## Troubleshooting

- **The build says WyldBound.html is missing.** Upload it to the top level of the repository, not inside a folder.
- **The "web" job failed.** Check that **Settings → Pages → Source** is set to **GitHub Actions**, then re-run the job from the Actions tab.
- **The "ipa" job failed.** Open the failed job, copy the red error lines, and send them to Claude.
- **SideStore errors.** See SideStore's error code guide: `https://docs.sidestore.io/docs/troubleshooting/error-codes`. iloader also suggests fixes for common problems.

## What's in this repository

- `WyldBound.html` — the whole game as one offline file.
- `ios/WyldBoundApp/` — the iPhone app project. It's built automatically, so you don't need a Mac or Xcode.
- `tools/prepare.py` and `icon/` — make the web app and app icon during the build.
- `.github/workflows/build.yml` — the automatic build.
- `OFL-PixelifySans.txt` — license notice for the game's font.
