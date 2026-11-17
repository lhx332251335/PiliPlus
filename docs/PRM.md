# PiliPlus PRM

本仓库是 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的个人修改版，沿用上游 GPL-3.0 许可证及原有致谢。视频封面读取 PRM 已有观看记录，本机保存用于展示的缓存。

## 安装与配置

安装包与每版实际验证结果见[本仓库 Releases](https://github.com/lhx332251335/PiliPlus/releases)。

- Android 包名：`com.example.piliplus.prm`；显示名称：`PiliPlus PRM`。与上游正式包独立安装，不需要卸载原版，不迁移原版登录态或应用数据。
- 在设置的 PRM 入口填写服务器**根地址**与独立的**只读**接口令牌。默认地址为 `https://prm.konryu.top:60443`，不要在根地址后加 `/api/v1`。
- 令牌安装后由本人填写；APK 和公开源码不包含实际令牌。令牌和缓存放在独立的应用私有存储，不进入原有 WebDAV 设置导出；卸载修改版会丢失它们，但不会删除 PRM 服务器数据。
- 推荐 HTTPS。HTTP 明文传输令牌，仅适合可信的本地网络。

## 标记的含义

- **已看完**：PRM 将该视频记录为完成。与网页扩展采用同一服务端判定，不代表逐秒看过 100%。
- **看到 N%**：PRM 保存的历史最高到达位置，不是上次退出位置。
- **有记录**：有观看记录但没有可用比例，不猜测进度。
- **有分 P 记录**：只有部分分 P 的记录，不能推断整个视频已经看完，因而不画整视频进度线。
- **无标记**：没有查询到可显示的 PRM 记录，**不等于没看过**。

标记以 PRM 配置对应的数据源为准，不因为 PiliPlus 切换 B 站账号而自动更换 PRM 账户。更换 PRM 地址或令牌会清除本机旧快照，防止串库。

## 数据流与边界

```text
B 站观看历史 → 现有同步程序 → PRM
                                  ↓ 只读同步
                         PiliPlus PRM 本机缓存 → 视频封面
```

- 只调用 `GET /api/v1/media/progress?platform=bilibili&since=...&limit=5000`，使用游标增量、分页及 ETag。
- 不写入 PRM，不改变现有 B 站 → PRM 同步规则，不伪造观看心跳；新观看记录的显示仍取决于现有上游同步的延迟。
- 卡片读取本机缓存，不逐卡联网，不把正在浏览的视频编号发送给 PRM。启动、返回前台和活跃定时器会检查刷新条件，自动请求间隔至少 30 分钟；设置页可随时手动同步。Android 后台挂起时不承诺准点同步。
- 分页完整成功后提交快照；离线、认证失败、格式错误或同步中断时保留上一份成功缓存。
- PRM 使用独立网络客户端，不带 B 站 Cookie，不跟随重定向，不继承上游允许无效证书的设置。
- 修改版的更新检查指向本 fork，避免提示安装回上游正式 APK。

## 开发环境与验收

上游基线为 `217fb54f51f6764176319bbdedab2a7522d75401`。Flutter 和 Dart 约束以 `pubspec.yaml` 为准；Android 构建流程见 [Build 工作流](../.github/workflows/build.yml)。

工作流面向一次性 CI runner：`lib/scripts/patch.ps1` 依赖 `FLUTTER_ROOT` 指向 Flutter SDK、`GITHUB_WORKSPACE` 指向仓库根，并会重置 SDK 工作树、删除默认 HOME 包缓存中的依赖后打补丁。因此复现构建须同时隔离 SDK、HOME 和依赖缓存，不能仅另备 SDK 后直接在日常开发环境运行该脚本。

发布签名通过未提交的 `android/key.properties` 配置，字段为 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。未提供时上游构建逻辑回退到 debug 签名；正式分发须提供固定的个人 fork 密钥，并在构建后核对证书。私钥和口令不进仓库或同步目录；同包名升级须继续使用同一私钥。

构建前检查：

```sh
flutter analyze --no-fatal-infos
flutter test test/prm_*_test.dart
```

测试覆盖模型与分 P 语义、分页/304/reset、离线保留、配置切换竞态、真实 HTTP 重定向隔离，以及实际组件的明暗主题、尺寸、点击和长按。

APK 生成后核对包名、版本、arm64 ABI、签名和凭据缺席，再做安装与启动检查。模拟器结果与真机结果、合成数据与生产 PRM 联调应分别记录在对应版本的发行说明中。
