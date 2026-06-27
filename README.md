# JM

禁漫纯血鸿蒙版漫画阅读应用。

基于安卓项目 [jmcomic-next](https://github.com/HongShi2333/jmcomic-next) 的功能与接口思路，移植到 HarmonyOS NEXT（ArkTS / ArkUI）。

## 功能特性

- **首页分区浏览**：多分区切换、瀑布卡片流、下拉刷新、滚动自动加载更多。
- **搜索**：支持漫画名 / 作者 / JM 号搜索，数字 ID 直达详情。
- **详情页**：封面、统计（浏览 / 点赞 / 评论）、简介展开收起、标签、相关推荐、章节列表，逐级入场动画。
- **阅读器**：垂直滚动连续翻页，自动解扰加扰图片，懒加载 + 预加载。
- **收藏与点赞**：登录态下可收藏、点赞。
- **深色模式**：全量语义色，跟随系统深 / 浅色自动切换。
- **多接口源**：内置多个 API 源，可在设置页一键切换。

## 性能与体验优化

- **API 响应缓存**：内存 LRU + TTL + 并发去重，缓存解密后的明文，减少重复网络往返。
- **持久化秒开**：img_host / 首页分区 / 登录 Cookie 落盘 preferences，冷启动先显缓存再后台刷新（stale-while-revalidate）。
- **图片解码线程化**：下载 + 解扰像素重组迁移到 TaskPool 子线程，主线程仅 createPixelMap，滚动不卡帧。
- **解码缓存与内存控制**：解码结果 LRU 缓存，淘汰时释放 PixelMap，内存紧张时（onMemoryLevel）主动清理。
- **阅读器懒加载**：List + LazyForEach + cachedCount，配合 @Reusable 复用图片页组件。
- **统一动画基线**：弹簧曲线（curves.springMotion）驱动入场 / 退场 / 按压回弹，页面切换对称连贯。

## 技术栈

- 语言：ArkTS（HarmonyOS NEXT）
- UI：ArkUI 声明式
- 模型：Stage 模型，单 UIAbility
- 网络：@ohos.net.http
- 加解密：@ohos.security.cryptoFramework（MD5 / AES-ECB）
- 数据：@kit.ArkData（preferences）
- 并发：@kit.ArkTS（taskpool / @Concurrent / LRUCache）
- 图像：@kit.ImageKit（PixelMap 解扰）

## 工程结构

```
entry/src/main/ets/
├─ api/                  # 网络层
│  ├─ HttpClient.ets     # HTTP 客户端、token、Cookie
│  ├─ CacheStore.ets     # API 响应缓存 + 并发去重
│  ├─ PrefStore.ets      # preferences 持久化封装
│  ├─ Crypto.ets         # MD5 / AES 解密
│  ├─ DataDecode.ets     # 章节 HTML 解析
│  └─ services/          # ComicApi / UserApi / RemoteSettingApi
├─ reader/
│  ├─ ReaderImageDecoder.ets  # 解码调度 + LRU 缓存
│  └─ ReaderDecodeTask.ets    # TaskPool 解扰 worker
├─ entryability/         # UIAbility
└─ pages/Index.ets       # 全部页面 UI 与交互
```

## 构建与运行

环境：DevEco Studio + HarmonyOS SDK，已配置 `DEVECO_SDK_HOME`。

```bash
# 编译 HAP
hvigorw assembleHap --no-daemon --mode module -p product=default

# 安装到设备（hdc）
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

产物：

- `entry-default-signed.hap` —— 调试签名包，可直接安装。
- `entry-default-unsigned.hap` —— 未签名包，见 [Releases](https://github.com/Dou-art/jm/releases)，需自行签名后安装。

## 说明

项目从接口迁移、页面开发、UI 调整、调试、构建到发布，全部由 AI 自动完成。

## 仓库

https://github.com/Dou-art/jm

## 致谢

- [jmcomic-next](https://github.com/HongShi2333/jmcomic-next) —— 功能与接口参考。
