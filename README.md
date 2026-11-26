# PexDL

私人本地使用的视频客户端（Flutter / Android）。架构参考 [FocuBili](https://github.com/L1Xu4n/FocuBili)：界面、接口源适配器、下载引擎、本机存储分模块。

## 功能
- 搜索 / 热门 / 详情 / 在线播放（MP4 与 M3U8 都支持），倍速，记住播放进度
- 收藏、观看记录（全部存在本机）
- 多接口源切换：`Pexels`（官方 API）、`直链 / M3U8`（粘贴链接，支持一次贴多行、`标题$链接`格式）
- 批量下载：长按多选 / 全选，收藏夹一键全部下载
- 下载引擎：多任务并发、m3u8 分片并发、断点续传（MP4 用 HTTP Range，m3u8 按分片）、AES-128 解密、fMP4（EXT-X-MAP）、FFmpeg 合并转 MP4、自定义保存目录
- 不支持 SAMPLE-AES / DRM 加密内容

## 编译
1. 把整个文件夹推到 GitHub 仓库（main 或 master 分支）
2. Actions 会自动运行（也可在 Actions 页面手动 Run workflow）
3. 完成后在该次运行页面底部 Artifacts 下载 `PexDL-apk`，手机一般装 `app-arm64-v8a-release.apk`

仓库里不含 `android/` 目录，CI 会用 `flutter create` 自动生成，再由 `tool/patch_android.py` 补上网络、存储权限和 minSdk 24。

## 首次使用
1. 到 https://www.pexels.com/api 免费申请 API Key
2. 打开 App →「我的」→ 填写 Pexels API Key
3. 想测试 m3u8：右上角切换到「直链 / M3U8」，里面有两个公开测试流

## 目录结构
```
lib/
  main.dart
  core/       全局状态、设置、收藏与记录、格式化工具
  models/     VideoItem / VideoStream
  sources/    接口源适配器（新增源：实现 VideoSource 并在 source_registry.dart 注册）
  download/   下载任务、管理器、m3u8 解析、AES 解密
  ui/         搜索、详情播放、下载管理、本地播放、我的
```

## 说明
- Pexels API 默认每小时 200 次请求；要求注明视频来自 Pexels 及作者（详情页已显示）
- 默认保存在 `Android/data/com.pexdl.pexdl/files/PexDL`，不需要权限；选择其他目录时会申请“所有文件访问权限”
- APK 内置 FFmpeg，体积较大；如只需 .ts，可在设置关闭“转成 MP4”
