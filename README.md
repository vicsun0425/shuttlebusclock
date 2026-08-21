# 班车闹钟 ShuttleBusClock

> 坐班车通勤的你不应该因为睡觉而坐过站。这个 app 会在你距离目的地 N 公里时**大声响铃**(即使手机静音),把你叫醒。

## 功能

- 🗺️ 保存多个常用站点(公司、家、客户),每个站点独立设置提前提醒距离
- 📍 后台 GPS 持续监测,锁屏后照常工作
- 🔔 自定义闹钟声,跨静音模式播放,搭配振动
- 📊 行程中实时显示剩余距离
- 💾 所有数据本地存储,绝不上传服务器

## 环境要求

- macOS + Xcode 15 或更高
- iOS 17 或更高(iOS 18 也支持)
- 真机测试(模拟器 GPS 不可靠,无法验证后台定位)

## 安装

```bash
# 1. 克隆仓库
git clone <your-repo-url>
cd shuttlebusclock

# 2. 安装 XcodeGen(一次性)
brew install xcodegen

# 3. 生成 .xcodeproj 并在 Xcode 中打开
make
# 等价于: xcodegen generate && open ShuttleBusClock.xcodeproj
```

如果你不想装 XcodeGen,也可以手动建工程:
1. Xcode → File → New → Project → iOS App
2. Interface 选 SwiftUI,Language 选 Swift,Storage 选 SwiftData
3. 把 `ShuttleBusClock/` 下的所有文件夹拖进去 (选 Copy items if needed, Create groups)
4. 把 `ShuttleBusClock/Resources/Sounds/alarm.caf` 拖进 Resources
5. 在 Signing & Capabilities 里:
   - 勾选 **Background Modes** → 勾上 **Location updates** 和 **Audio, AirPlay, and Picture in Picture**
6. 确认 Info.plist 里有定位权限文案(参考 `project.yml`)

## 配置

首次编译前修改两处:

1. **Bundle ID** — 打开 `project.yml`,已设为 `com.vicsun0425.shuttlebusclock`;fork 本仓库的话改成你自己的(否则签名会失败)
2. **签名 Team** — `project.yml` 里 `DEVELOPMENT_TEAM` 留空,然后在 Xcode 里 Signing & Capabilities 选自己的 Team

## 使用

### 添加站点

1. 启动 app,允许「使用时」定位权限
2. 点右上角 + → 输入名字 → 在地图上选点(或用「当前位置」)→ 选提醒距离
3. 保存

### 启动行程

1. 在站点列表里点任一站点
2. 首次启动会请求「始终定位」权限(必须选「始终允许」才能后台响铃)
3. 进入 ArmedTripView,显示实时剩余距离
4. 锁屏、回家其他 app 都不影响
5. 距离进入设定半径时,app 全屏红屏响起大声闹钟,只有点「我醒了」才能关

### 删除 / 编辑

- 站点列表左滑删除
- 暂不支持直接编辑(设计原则是减少误触);需要改就删除重建

## 技术架构

```
┌─────────────────┐    距离 < radius     ┌──────────────┐
│ LocationManager │ ──────────────────▶ │ AlarmManager │
│ (GPS + Region)  │                      │ (AVAudioPlayer)│
└─────────────────┘                      └──────────────┘
        │                                          │
        ▼                                          ▼
   SwiftData @Model                          跨静音模式播放
   BusStop (name/lat/lng/radius)             中断后自动恢复
```

**三股定位流**:
- **Region monitoring** (`CLCircularRegion`): iOS 硬件级监控,即使 app 被挂起也能在到达时唤醒,**主触发**
- **Continuous location**: `distanceFilter=500m`、`accuracy=HundredMeters`,实时显示剩余距离,**辅助触发**
- **Significant changes**: 长时间挂起后兜底唤醒

**迟滞 (hysteresis)**: 触发阈值 = radius;清除阈值 = radius + 500m。防止边界处反复触发。

**音频**:
- `AVAudioSession.Category.playback` — 唯一能跨静音模式的分类
- `UIBackgroundModes` 含 `audio` — 否则进后台几秒音频会话就被拆
- 监听 `interruptionNotification` — 来电 / Siri 中断后自动恢复

## 测试

```bash
# 在 Xcode 里 ⌘U 运行所有单元测试
# DistanceCalculationTests 覆盖:
# - 边界触发 (刚好 radius 米时触发,差 1 米不触发)
# - 迟滞行为 (radius+100m 内不重置)
# - 手动 dismiss
```

真机测试要点(模拟器不可靠):
1. **响铃**: 把站点设置在当前位置 1km 外 → 启动行程 → 把模拟位置往站点移动,听到响铃
2. **静音模式**: iPhone 拨到静音侧,再次启动行程 → 闹钟仍能响
3. **后台**: 启动行程后锁屏 → 5 分钟后解锁,GPS 仍在工作
4. **中断**: 行程中让另一个手机打过来 → 挂断 → 闹钟自动继续

## 已知问题 / 未来工作

- [ ] 编辑站点(v1 只支持删除重建,故意减少误触)
- [ ] Apple Watch 端的强烈振动(对听障用户更友好)
- [ ] 历史行程统计
- [ ] iCloud 同步多设备
- [ ] 多站点链式提醒(例如先提醒一次,然后快到站时再提醒一次)

## App Store 提交注意事项

发布前需要:

1. **替换 AppIcon** — 当前 `AppIcon.appiconset` 是空的,Xcode 里加 1024×1024 的 PNG
2. **修改 Bundle ID 和签名 Team** — 见上文「配置」
3. **Privacy Policy URL** — 已写好 `PrivacyPolicy.md`,部署到任意公开 URL(GitHub Pages / Notion 都行),填进 App Store Connect
4. **审核备注** — App 审核团队会问为什么同时声明 `location` + `audio` 后台模式。提交时在备注里写:
   > App uses location to monitor proximity to a user-configured destination; uses audio playback to deliver the wake-up alarm sound even when the device is in silent mode. Both background capabilities are used solely while a trip is armed; both stop immediately when the alarm is acknowledged or the trip is canceled. No location or audio data leaves the device.
5. **隐私标签** — App Store Connect 选「是,收集位置数据」 → 「用于应用功能」 → 勾「单次会话,仅前台和后台,不上传」
6. **截图要求** — 至少包含 ArmedTripView 和 ActiveAlarmView 的截图,审核会看

参考 Apple 审核指南 2.5.4 (后台定位) 和 5.1.1 (隐私)。

## License

MIT (alarm.caf 自带,无第三方素材)