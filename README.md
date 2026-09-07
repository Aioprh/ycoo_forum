# 源论坛 YcoForum（Android）

一个面向 **ycoo.net 源论坛** 的非官方 Android 客户端，采用 Flutter 原生 UI 实现，主要提供移动端浏览、搜索、帖子阅读以及附件处理能力。

> 数据来源：<https://www.ycoo.net>（Discuz! X + Comiis 移动模板）
>
> 本项目为第三方客户端，与 ycoo.net 官方无关。

## ✨ 当前功能

### 首页

- 最新发表
- 最新回复
- 热点推荐
- 社区热门
- 下拉刷新
- 快速进入搜索

### 社区

- 版块分类
- 子版块网格
- 帖子列表
- 分页加载
- 帖子详情

### 帖子详情

帖子详情目前使用原生 Flutter 组件渲染主要内容，并针对源论坛的 Comiis HTML 结构做了适配：

- 原生显示标题、作者、等级、时间、版块等信息
- 正文文字可自由选择、复制
- 正文中的 `http/https` 链接可直接点击
- HTML `<a>` 链接支持外部浏览器打开
- 支持正文图片及 Comiis 懒加载图片
- 图片支持点击交互
- 自动过滤论坛 HTML 中的空节点、无效占位内容
- 附件链接与正文图片分离处理，避免把附件文件类型占位图误当成正文图片
- 支持附件下载
- 支持长按复制附件下载链接
- 附件下载失败时给出登录状态 / 网络提示

### 评论

- 评论列表原生展示
- 评论内容高度根据实际内容自适应
- 清理论坛 HTML 中导致异常空白高度的空段落、空节点及无效占位内容

### 我的

- 登录入口
- 注册入口
- 官网入口
- 关于页面

登录、注册等需要网页交互的功能通过内置 WebView 处理。

### 搜索

使用内置 WebView 打开源论坛移动端搜索页面，兼容站点自身的表单校验流程。

底部导航：**首页 · 社区 · 我的**

## 🖼️ 帖子内容渲染

项目针对 ycoo.net 当前页面结构进行了专门处理。

典型正文图片可能位于：

```html
<div class="comiis_messages comiis_aimg_show">
    <ul class="comiis_img_list">
        <li>
            <a href="...">
                <img src="..." data-src="..." />
            </a>
        </li>
    </ul>
</div>
```

客户端会兼容 `src`、`data-src`、`data-original`、`data-url`、`comiis_loadimages`、`zoomfile` 等常见图片地址字段，并根据论坛页面结构进行 URL 解析。

同时会区分以下两类资源：

- **正文图片**：正常显示并支持交互
- **附件文件**：交给附件下载逻辑处理，不把附件类型占位图当成正文图片

这样可以避免论坛附件占位资源在帖子正文中显示成巨大的问号、文件图标等异常内容。

## 🛠️ 技术栈

- **Flutter 3.47.2**
- **Dart 3.13.2**
- `http`：网络请求
- `html`：HTML 页面解析与 DOM 处理
- `cronet_http`：Android 网络请求实现
- `webview_flutter`：登录、注册、搜索等网页页面
- `url_launcher`：外部链接打开
- `shared_preferences`：本地配置
- `file_picker`：文件选择
- `path_provider`：文件路径管理
- `open_filex`：下载文件打开
- `package_info_plus`：应用信息
- `device_info_plus`：设备信息

当前应用版本：**2.7.4+178**。fileciteturn196file0L2-L2

## 🌐 数据接口

项目主要从 ycoo.net 移动端页面获取数据：

```text
forum.php?mod=guide&view={newthread|newreply|hot|digest}&mobile=2
forum.php?forumlist=1&mobile=2
forum.php?mod=forumdisplay&fid={fid}&mobile=2&page={page}
thread-{tid}-1-1.html
```

帖子详情会针对 Discuz! X + Comiis 页面结构提取正文、图片、附件等内容。

## 📁 项目结构

```text
lib/
├── main.dart
├── models/
│   ├── board.dart
│   ├── thread_detail.dart
│   └── thread_item.dart
├── pages/
│   ├── board_page.dart
│   ├── detail_page.dart
│   ├── home_page.dart
│   ├── profile_page.dart
│   ├── search_page.dart
│   ├── thread_list_page.dart
│   └── webview_page.dart
├── services/
│   ├── api_service.dart
│   └── attachment_download_service.dart
└── widgets/
    ├── native_comment_list.dart
    ├── native_post_content.dart
    ├── native_post_content_filter.dart
    ├── native_post_content_filter_v2.dart
    ├── native_post_content_selectable.dart
    ├── forum_attachment_section.dart
    ├── thread_card.dart
    └── thread_list_view.dart

test/
└── widget_test.dart
```

## 🚀 环境准备

需要安装 Flutter SDK，并确保 Android 开发环境可以正常运行 Flutter 项目。

检查环境：

```bash
flutter doctor
```

安装依赖：

```bash
flutter pub get
```

## ▶️ 本地运行

连接 Android 真机或启动模拟器后：

```bash
flutter run
```

## 📦 构建 APK

Debug：

```bash
flutter build apk --debug
```

Release：

```bash
flutter build apk --release
```

Release APK 默认位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

项目同时配置了 GitHub Actions，可使用仓库中的工作流进行自动构建与发布。

## 🧪 测试与代码检查

执行测试：

```bash
flutter test
```

执行静态分析：

```bash
flutter analyze
```

建议提交代码前至少执行：

```bash
flutter analyze
flutter test
```

## 🔧 开发说明

### HTML 渲染

源论坛页面并不是标准化的纯正文 HTML，而是带有 Discuz! X / Comiis 模板结构的页面。因此帖子内容处理分为几个阶段：

1. 从论坛页面提取帖子内容
2. 清理论坛模板产生的无效 HTML
3. 保留正文图片、链接和附件信息
4. 对特殊 Comiis 图片结构进行适配
5. 使用原生 Flutter Widget 渲染文字、链接、图片和列表

这样可以避免直接使用 WebView 渲染正文时难以控制复制、链接以及附件交互的问题。

### 正文复制

帖子正文采用可选择文本组件渲染，支持长按选择和复制文字，同时保留正文链接的点击能力。

### 附件处理

附件不作为普通正文图片处理。检测到附件 URL 后，会交给附件下载服务，并提供下载状态提示及下载链接复制功能。

## ⚠️ 已知限制

- 本项目主要定位为阅读侧客户端
- 发帖、回帖、回复等复杂论坛交互仍建议使用网页端
- 登录状态下的部分论坛功能依赖站点自身页面
- 某些需要特殊权限、验证码或动态校验的功能可能只能通过 WebView / 官网完成
- ycoo.net 页面结构发生变化时，HTML 解析规则可能需要同步调整
- 正式分发前建议配置正式 Android 签名与正式 `applicationId`

## 📄 免责声明

本项目为非官方第三方客户端，仅用于学习、研究 Flutter 原生 UI、HTML 解析及移动端论坛客户端开发。

项目不代表 ycoo.net 官方立场。使用本项目访问网站时，请遵守目标网站的服务条款及相关规则。

## 🔗 项目地址

GitHub：<https://github.com/Aioprh/ycoo_forum>

源论坛：<https://www.ycoo.net>
