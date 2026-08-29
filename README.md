# 源论坛 YcoForum(Android)

一个 **阅读侧** 的源论坛非官方 Android 客户端。数据来自 <https://www.ycoo.net>(Discuz!X + comiis 手机模板),运行时实时在线拉取。本应用只做**浏览**,发布 / 回帖 / 回复等请使用网页端。

## 功能

- **首页**:最新发表 / 最新回复 / 热点推荐 / 社区热门 四段导读流,下拉刷新;右上角进入搜索
- **社区**:版块分类 → 子版块网格 → 帖子列表(上滑分页)→ 帖子详情
- **帖子详情**:原生头部(标题 / 作者 / 等级 / 时间 / 版块)+ 正文(WebView 渲染抓取到的正文 HTML,兼容图片 / 附件 / 超链接)
- **我的**:登录 / 注册入口(内置 WebView)、官网链接、关于
- **搜索**:内置 WebView 打开原站移动端搜索页(该站搜索需表单校验)

底部导航:首页 · 社区 · 我的

## 技术栈

- Flutter(本工程用 Flutter 3.47.2 / Dart 3.13 构建)
- 依赖:`http`(网络)、`html`(页面解析)、`webview_flutter`(正文 / 内置页面渲染)
- 数据接口:
  - 导读: `forum.php?mod=guide&view={newthread|newreply|hot|digest}&mobile=2`
  - 版块索引: `forum.php?forumlist=1&mobile=2`
  - 版块帖子: `forum.php?mod=forumdisplay&fid={fid}&mobile=2&page={page}`
  - 帖子详情: `thread-{tid}-1-1.html`(抓 `.comiis_message_table` 正文)

## 环境准备与构建

```bash
flutter pub get
flutter run          # 调试运行(需连接 / 启用模拟器或真机)
flutter build apk --release   # 构建发布 APK
```

产物路径:`build/app/outputs/flutter-apk/app-release.apk`

也可通过 `.github/workflows/build_apk.yml` 在 GitHub Actions 上云端构建。

## 项目结构

```
lib/
  main.dart                       # 入口 + 底部导航(首页/社区/我的)
  models/thread_item.dart         # 帖子条目
  models/board.dart               # 版块分类 / 子版块
  models/thread_detail.dart       # 帖子详情
  services/api_service.dart       # 抓取 + HTML 解析
  pages/home_page.dart            # 首页四段导读流
  pages/board_page.dart           # 版块列表
  pages/thread_list_page.dart     # 版块帖子列表(分页)
  pages/detail_page.dart          # 帖子详情(头部 + WebView 正文)
  pages/search_page.dart          # 搜索(WebView)
  pages/profile_page.dart         # 我的
  pages/webview_page.dart         # 通用 WebView 容器
  widgets/thread_card.dart        # 帖子卡片
  widgets/thread_list_view.dart   # 复用列表(下拉刷新 + 分页)
test/
  widget_test.dart                # 冒烟测试
```

## 已知点

- 仅覆盖阅读侧;发布 / 回复 / 登录态内的附件查看需登录,请跳转网页端
- 原生应用图标暂复用默认 Flutter 图标,上线前可替换 `mipmap-*` 与启动页
- Android 层配置沿用自可构建模板(AGP 8.11.1、腾讯镜像 Gradle,见 `android/`)
- 上线分发前建议:替换正式签名、更换 `applicationId`