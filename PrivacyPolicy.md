# 班车闹钟 Privacy Policy

Last updated: 2026-08-19

## 我们不收集任何数据

班车闹钟 ShuttleBusClock 是一个**完全本地**运行的应用。

- **不联网**:app 在任何时候都不会向任何服务器发送数据
- **不上传位置**:你的当前位置和保存的站点信息**永远不离开你的设备**
- **不收集使用统计**:没有分析 SDK、没有崩溃上报、没有广告 SDK
- **不接入第三方**:app 内没有任何第三方服务

## 我们使用了哪些系统权限

| 权限 | 用途 | 是否必需 |
|---|---|---|
| 定位(使用时) | 行程中实时显示剩余距离 | 必需 |
| 定位(始终) | app 关闭/锁屏后仍能触发闹钟 | 必需 |
| 音频后台播放 | 闹钟能在后台响铃,跨静音模式 | 必需 |

**重要说明**:即使我们声明了「始终定位」权限,app 也**只在行程启动期间**持续获取位置。行程结束(用户主动取消或闹钟触发后用户点击「我醒了」)后,定位立即停止。我们不会在行程外获取你的位置。

## 数据存储

所有用户数据保存在 iOS 的 SwiftData 本地存储中,与系统「通讯录」「照片」等同等级保护:

- 站点名称
- 站点经纬度
- 提醒距离设置

这些数据:

- **不上传**
- **不参与备份以外的其他用途**
- 删除 app 时**立即全部清除**(iOS 自动行为)

## 崩溃与性能

我们没有接入任何崩溃报告 SDK。如果 app 崩溃,崩溃日志只会保留在你本机的「设置 → 隐私 → 分析与改进」中,可选是否提交给 Apple。

## 儿童隐私

本 app 不面向 13 岁以下儿童设计,也没有任何机制收集儿童数据。

## 联系我们

如有疑问:yourname@example.com(改成你自己的邮箱)

---

如果 Apple 审核团队需要英文版本,以下为参考翻译:

> ShuttleBusClock runs entirely on-device. The app does not transmit, upload, or share any user data — including location — with any server or third party. All saved data (stop names, coordinates, radius) is stored locally via SwiftData and is deleted when the app is uninstalled. Location access is requested only while a trip is armed and stops immediately when the alarm is acknowledged or the trip is canceled.