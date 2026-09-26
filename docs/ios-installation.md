> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# iPhone installation and calendar setup

The development app is **Reha Calendar Lab 0.1.2**, bundle identifier `at.rehakalender.personal`. It bundles the frontend, OCR models and native runtime; no development server or reachable Mac is needed after installation. Image recognition remains local. Calendar synchronization follows the settings of the selected iOS calendar account.

## Install the private build

The versioned package is `artifacts/private/builds/rehab-plan-ocr-lab-0.1.2.ipa`. Installation requires a device included in its signing profile. The paired iPhone 17 is included. The current profile expires **September 26, 2026, 10:57 UTC**; build and sign a fresh package when it expires.

1. Connect the iPhone to the Mac, unlock it and accept **Trust This Computer** if prompted.
2. Open Xcode's **Window → Devices and Simulators** and select the phone.
3. On the phone, enable **Settings → Privacy & Security → Developer Mode**, restart and confirm. The option appears after pairing with Xcode. [Apple Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
4. In Xcode's device view, click **+** under **Installed Apps**, select the IPA and wait for installation. [Apple installation instructions](https://help.apple.com/xcode/mac/current/en.lproj/devade83d1d7.html)
5. If iOS blocks the first launch, open **Settings → General → VPN & Device Management**, select the developer entry for the app and trust its certificate. This approval must be completed on the phone. [Apple's Personal Team instructions](https://developer.apple.com/documentation/appclip/fruta-building-a-feature-rich-app-with-swiftui)
6. Open **Reha Calendar Lab** on the phone.

Use the same bundle identifier and signing team when updating. The application's retained scans and import ledger are preserved by an ordinary app update.

## Save to the separate calendar

1. Import or photograph a schedule in **Run**.
2. Correct the selected appointments in **Appointments**. Resolve date/time/title errors or exclude incomplete items, then confirm the review.
3. Open **Calendar → Set up Reha Calendar** and allow full calendar access. This creates or reuses a separate **Reha Calendar**; it does not save appointments yet.
4. Check the selected calendar and account, then choose **Prepare calendar operations**.
5. Review the operations and choose **Approve and apply**. Resolve any conflicts first; removals require their separate confirmation.

New imports select the dedicated calendar. Revisions of an existing app import keep its recorded destination. The app retains stable import IDs and marks its EventKit events for reconciliation and duplicate prevention. Calendar setup reuses its saved identifier even if the calendar is renamed.

If the provider rejects calendar creation, create **Reha Calendar** in Apple Calendar and retry, or explicitly choose another writable calendar. If a previously configured calendar becomes unavailable, restore its account or choose a destination; the app does not silently create duplicates. Full access is required for direct EventKit imports and revisions. ICS export remains available without calendar permission.

## Show or hide the appointments

In Apple's **Calendar** app, tap **Calendars**, select or deselect **Reha Calendar**, then tap **Done**. This toggles visibility for that calendar's events. [Apple calendar visibility instructions](https://support.apple.com/en-gb/102180)

An ICS file does not force a destination calendar. When importing one manually, choose **Reha Calendar** in the receiving calendar app. Previously imported ICS events are not automatically moved by this update.

## Development build

From the repository, with the existing generated iOS project and signing team:

```sh
source "$HOME/.cargo/env"
APPLE_DEVELOPMENT_TEAM=<team-id> IPHONEOS_DEPLOYMENT_TARGET=17.0 \
  npm run tauri -- ios build --target aarch64 --ci --export-method debugging \
  --features ios-onnx -- --no-default-features
```

The build exports an IPA under `src-tauri/gen/apple/build/`. Copy the verified package to the private builds folder. Do not publish signing profiles, device identifiers, source images or clinical run outputs.

The known extraction limitations remain: pages containing multiple date sections and some row/field associations require correction. Simulator verification and a signed build do not establish physical-device acceptance.
