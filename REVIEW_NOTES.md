# App Review Notes / 审核备注

Paste the English section into **App Store Connect → App Review Information → Notes**.
把英文部分粘贴到 App Store Connect 的「App 审核信息 → 备注」里。

---

## English (for the review team)

### What the app does

ShuttleBusClock wakes commuters before their bus stop. The user saves a
destination and a trigger radius; the app rings a loud alarm when they get
within that radius, so they don't sleep past their stop.

### How to test it

Physical device required — the Simulator's GPS is not reliable enough.

1. Launch the app and grant location permission. Choose **Always** when
   prompted; **While Using** is not sufficient for the core feature, and the
   app shows a warning banner explaining this.
2. Tap **+**, name the stop, search for a place or tap the map, pick a radius
   (1–10 km), save.
3. Tap the saved stop to start a trip. The screen shows live distance.
4. Lock the device or switch to another app. Move toward the destination — or
   use Xcode's **Debug → Simulate Location** with a GPX track.
5. When the distance drops below the radius, a full-screen red alarm rings and
   vibrates until **我醒了 ("I'm awake")** is tapped.

A tap on the clock icon in any row opens optional scheduled monitoring
(weekday + time-of-day window) for hands-free daily use.

### Why two background modes are declared

**`location`** — the whole purpose of the app is to notice the user
approaching a destination while the device is locked and the app is
backgrounded. Region monitoring plus continuous updates are used only while a
trip is armed, or while the user has explicitly enabled scheduled monitoring
for a stop. Everything stops the moment the alarm is acknowledged or the trip
is canceled. `showsBackgroundLocationIndicator` is enabled, so the user always
sees the status bar indicator while we hold location.

**`audio`** — the alarm must be audible when the device is locked *and* when
the ringer switch is set to silent, because a commuter asleep on a bus will
have neither the app in the foreground nor the ringer on.
`AVAudioSession.Category.playback` is the only category that plays through the
silent switch, and it requires the `audio` background mode or iOS tears the
session down within seconds of backgrounding.

### Why a silent audio session is held during a trip

This is deliberate and is not a background-execution loophole.

iOS arbitrates audio focus **only at session-activation time**, and it refuses
to let a *backgrounded* app activate a session that would interrupt an app that
is currently playing (`AVAudioSessionErrorCodeCannotInterruptOthers`). We
confirmed this on device: activating the session at alarm time while a video
app was playing failed five times in a row and the alarm was silent.

So from the moment a trip is armed, the app holds an **active but silent and
`.mixWithOthers`** session. It is inaudible, it does not interrupt or duck
anything, and it exists purely so that a session already exists when the alarm
needs to sound. Without it, the alarm silently fails for any user who fell
asleep with headphones and a video playing — which is the exact situation the
app is built for. The session is released when the trip ends.

### Privacy

- The app makes **no network requests of any kind**. There is no analytics SDK,
  no crash reporter, no advertising SDK, and no third-party SDK at all.
- Location never leaves the device. Stops, schedules and the local alarm
  diagnostics log are stored in on-device SwiftData / UserDefaults and are
  removed when the app is deleted.
- `PrivacyInfo.xcprivacy` declares no collected data types and one Required
  Reason API: `NSPrivacyAccessedAPICategoryUserDefaults`, reason **CA92.1**
  (app's own settings and its local diagnostics log).
- Accordingly the App Privacy answers are **Data Not Collected**.
- Map search uses Apple's own MapKit (`MKLocalSearch`), which is a first-party
  system service.

### Content

All assets are original. The alarm tone is synthesized specifically for this
app; no third-party or system ringtone is bundled. The app icon is built from
SF Symbols. Source is MIT-licensed at
https://github.com/vicsun0425/shuttlebusclock

---

## 中文（自用速查）

审核最可能被问的就是「为什么同时声明 location 和 audio 两个后台模式」。
上面英文部分第三、四节就是针对这个准备的，重点是说明：

1. `location` 只在行程进行中或用户主动开启定时监测时使用，闹钟确认后立即停止，
   且全程显示系统定位指示器。
2. `audio` 是为了突破静音键——`.playback` 是唯一能做到的类别，而它必须配
   `audio` 后台模式，否则进后台几秒会话就被拆。
3. 行程期间持有静音会话这件事必须主动解释，否则容易被当成「用音频后台模式
   骗取后台运行时间」。理由是 iOS 只在激活会话那一刻仲裁音频焦点，后台 App
   无法从正在播放的 App 手里抢焦点（真机实测连续五次
   `Session activation failed`），不提前持有会话闹钟就是哑的。

提交前还要在 App Store Connect 里：

- 隐私标签选 **不收集数据**（我们确实不联网）
- 填隐私政策 URL（把 `PrivacyPolicy.md` 部署到 GitHub Pages 即可）
- 截图至少包含行程页和闹钟页
