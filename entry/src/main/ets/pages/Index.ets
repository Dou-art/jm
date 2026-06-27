import {
  ComicDetailResponse,
  ComicDetailRelatedListItemResponse,
  ComicDetailSeriesListItemResponse,
  createJmApiClient,
  DEFAULT_API_LIST,
  HomeSwiperComicListItemResponse,
  ListComicItemResponse,
  StoredCookie
} from '../api';
import { md5 } from '../api/Crypto';
import { PrefStore } from '../api/PrefStore';
import { DecodedReaderImage, getDecodedReaderImage } from '../reader/ReaderImageDecoder';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { curves } from '@kit.ArkUI';

const PREF_KEY_IMG_HOST = 'img_host';
const PREF_KEY_HOME = 'home_sections';
const PREF_KEY_COOKIES = 'cookies';

const DOMAIN = 0x0000;
const TAG = 'JMApp';
const COLOR_BG = $r('app.color.jm_bg');
const COLOR_SURFACE = $r('app.color.jm_surface');
const COLOR_TEXT = $r('app.color.jm_text');
const COLOR_MUTED = $r('app.color.jm_muted');
const COLOR_PRIMARY = $r('app.color.jm_primary');
const COLOR_PRIMARY_SOFT = $r('app.color.jm_primary_soft');
const COLOR_ON_PRIMARY = $r('app.color.jm_on_primary');
const COLOR_ACCENT = $r('app.color.jm_accent');
const COLOR_ACCENT_SOFT = $r('app.color.jm_accent_soft');
const COLOR_BORDER = $r('app.color.jm_border');
const COLOR_TAB_MUTED = $r('app.color.jm_tab_muted');
const COLOR_SURFACE_SOFT = $r('app.color.jm_surface_soft');
const COLOR_DIVIDER = $r('app.color.jm_divider');
const COLOR_ERROR = $r('app.color.jm_error');

// 统一圆角规范：消除散落的魔法圆角值，全局四档 + 胶囊
const RADIUS_SM = 10;
const RADIUS_MD = 14;
const RADIUS_LG = 20;
const RADIUS_PILL = 999;
// 统一间距规范
const SPACE_PAGE = 18;
const SPACE_CARD_GAP = 16;
const PAGE_TITLE_SIZE = 22;
const STATUS_BAR_OFFSET = 38;
const TAB_BAR_WIDTH = 232;
const TAB_BAR_HEIGHT = 60;
const TAB_BAR_BOTTOM_MARGIN = 22;
const TAB_ITEM_WIDTH = TAB_BAR_WIDTH / 3;
const TAB_INDICATOR_WIDTH = 64;
const TAB_INDICATOR_HEIGHT = 44;
const TAB_CONTENT_BOTTOM_PADDING = 104;
const GRID_BOTTOM_PADDING = TAB_CONTENT_BOTTOM_PADDING + 40;
const SEARCH_VISIBLE_STEP = 24;
const HOME_VISIBLE_STEP = 12;

// 统一动画基线：弹簧曲线给予物理弹性，时序常量集中管理避免魔法数字
// springMotion(response, dampingFraction)：response 越大越绵长，dampingFraction 越小弹性越强
const SPRING_RESPONSE_SNAPPY = 0.34;
const SPRING_RESPONSE_GENTLE = 0.5;
const SPRING_RESPONSE_TAB = 0.42;
const SPRING_DAMPING_TIGHT = 0.86;
const SPRING_DAMPING_BOUNCY = 0.7;
const SPRING_DAMPING_GLIDE = 0.9;
const PRESS_SCALE = 0.96;
const PRESS_DURATION = 140;
const PRESS_RESET_DELAY = 130;
const OVERLAY_EXIT_DURATION = 200;

const ROOT_TAB_EXIT_DURATION = 120;
const ROOT_TAB_SWAP_DELAY = 95;
const ROOT_TAB_UNLOCK_DELAY = 260;
const ROOT_TAB_EXIT_OPACITY = 0;
const ROOT_TAB_OFFSET = 10;
const CARD_ENTER_STAGGER = 38;
const CARD_ENTER_BASE_DELAY = 60;
const CARD_ENTER_OFFSET = 26;
const LIST_ITEM_ENTER_STAGGER = 35;
const LIST_ITEM_ENTER_OFFSET = 16;
const DETAIL_BLOCK_STAGGER = 48;
const REMOVED_HOME_SECTION_KEYWORDS: string[] = ['连载更新', '连续更新'];

const springSnappy: ICurve = curves.springMotion(SPRING_RESPONSE_SNAPPY, SPRING_DAMPING_TIGHT);
const springBouncy: ICurve = curves.springMotion(SPRING_RESPONSE_GENTLE, SPRING_DAMPING_BOUNCY);
const springTabGlide: ICurve = curves.springMotion(SPRING_RESPONSE_TAB, SPRING_DAMPING_GLIDE);

enum AppView {
  HOME = 'home',
  SEARCH = 'search',
  DETAIL = 'detail',
  READER = 'reader',
  SETTINGS = 'settings'
}

interface ComicCardItem {
  id: string;
  name: string;
  author: string;
  description: string;
}

interface ReaderImageItem {
  id: string;
  url: string;
  index: number;
  seed: number;
}

// 阅读器图片数据源：配合 LazyForEach 实现按需渲染，避免一次性创建全部页
class ReaderImageDataSource implements IDataSource {
  private items: ReaderImageItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ReaderImageItem {
    return this.items[index];
  }

  reload(items: ReaderImageItem[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }
}

@Reusable
@Component
struct ReaderImagePage {
  url: string = '';
  index: number = 0;
  total: number = 0;
  seed: number = 1;
  @State pixelMap: image.PixelMap | null = null;
  @State imageWidth: number = 0;
  @State imageHeight: number = 0;
  @State error: string = '';
  @State loading: boolean = false;
  @State imageShown: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.url = params.url as string;
    this.index = params.index as number;
    this.total = params.total as number;
    this.seed = params.seed as number;
    // 复用时解除旧引用并重置渲染态，按新参数重新加载（释放交由 LRU 统一负责）
    this.pixelMap = null;
    this.imageWidth = 0;
    this.imageHeight = 0;
    this.error = '';
    this.imageShown = false;
    this.loading = false;
    this.load();
  }

  aboutToDisappear(): void {
    // 仅解除组件对 PixelMap 的引用，真正释放交给解码 LRU 淘汰，避免 use-after-free
    this.pixelMap = null;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pixelMap !== null && this.imageWidth > 0 && this.imageHeight > 0) {
        Image(this.pixelMap)
          .width('100%')
          .aspectRatio(this.imageWidth / this.imageHeight)
          .objectFit(ImageFit.Fill)
          .backgroundColor('#050505')
          .opacity(this.imageShown ? 1 : 0)
          .animation({
            duration: 320,
            curve: springSnappy,
            iterations: 1,
            playMode: PlayMode.Normal
          })
      } else if (this.error.length > 0) {
        Column({ space: 8 }) {
          Text(this.error)
            .fontSize(12)
            .fontColor('#FFFFFF')
          Button('重试')
            .height(34)
            .backgroundColor(COLOR_ACCENT)
            .fontColor('#FFFFFF')
            .borderRadius(RADIUS_SM)
            .onClick(() => {
              this.load();
            })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height(360)
        .backgroundColor('#050505')
      } else {
        Stack() {
          LoadingProgress()
            .width(32)
            .height(32)
        }
        .width('100%')
        .height(360)
        .backgroundColor('#050505')
      }

      Text(`${this.index + 1} / ${this.total}`)
        .fontSize(10)
        .fontColor('#FFFFFF')
        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .backgroundColor('#66000000')
        .borderRadius(4)
        .margin({ left: 4, top: 4 })
    }
    .width('100%')
    .backgroundColor('#000000')
  }

  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.error = '';
    this.imageShown = false;
    try {
      const result: DecodedReaderImage = await getDecodedReaderImage(this.url, this.seed);
      this.pixelMap = result.pixelMap;
      this.imageWidth = result.width;
      this.imageHeight = result.height;
      // 下一帧再显示，确保 Image 以 opacity:0 渲染后再淡入
      setTimeout((): void => { this.imageShown = true; }, 16);
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
    }
    this.loading = false;
  }
}

@Entry
@Component
struct Index {
  private jm = createJmApiClient();
  @State baseUrl: string = DEFAULT_API_LIST[0];
  @State imgHost: string = '';
  @State status: string = 'Ready';
  @State error: string = '';
  @State loading: boolean = false;
  @State homeSections: HomeSwiperComicListItemResponse[] = [];
  @State selectedSectionIndex: number = 0;
  @State homeVisibleCount: number = HOME_VISIBLE_STEP;
  @State homeTotalCount: number = 0;
  @State activeHomeTitle: string = '';
  @State activeHomeItems: ComicCardItem[] = [];
  @State visibleHomeItems: ComicCardItem[] = [];
  @State searchText: string = '';
  @State searchItems: ComicCardItem[] = [];
  @State visibleSearchItems: ComicCardItem[] = [];
  @State searchVisibleCount: number = SEARCH_VISIBLE_STEP;
  @State detailId: number = 0;
  @State detailComic: ComicDetailResponse | null = null;
  @State readerImages: ReaderImageItem[] = [];
  private readerSource: ReaderImageDataSource = new ReaderImageDataSource();
  @State readerTitle: string = '';
  @State overlayView: AppView = AppView.HOME;
  @State currentTabIndex: number = 0;
  @State rootContentTabIndex: number = 0;
  @State rootTabOpacity: number = 1;
  @State rootTabTranslateX: number = 0;
  @State rootTabScale: number = 1;
  @State chromeOpacity: number = 0;
  @State chromeTranslateY: number = 14;
  @State overlayOpacity: number = 1;
  @State overlayTranslateY: number = 0;
  @State overlayScale: number = 1;
  @State homeCardsEntered: boolean = false;
  @State searchCardsEntered: boolean = false;
  @State settingsEntered: boolean = false;
  @State detailEntered: boolean = false;
  @State chapterListEntered: boolean = false;
  @State detailFavorited: boolean = false;
  @State detailLiked: boolean = false;
  @State favoriteBusy: boolean = false;
  @State likeBusy: boolean = false;
  @State pressedCardId: string = '';
  @State pressedChapterId: string = '';
  @State pressedSource: string = '';
  @State pressedTab: number = -1;
  @State homeRefreshing: boolean = false;
  @State searchRefreshing: boolean = false;
  @State descExpanded: boolean = false;
  @StorageProp('currentColorMode') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  private homeScroller: Scroller = new Scroller();
  private searchScroller: Scroller = new Scroller();
  private searchRequestSeq: number = 0;
  private lastSearchKeyword: string = '';
  private searchScrollY: number = 0;
  private homeAutoLoadingMore: boolean = false;
  private searchAutoLoadingMore: boolean = false;
  private rootTabSwitching: boolean = false;
  private prefStore: PrefStore | null = null;

  private isDarkMode(): boolean {
    return this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private tabBlurColorMode(): ThemeColorMode {
    return this.isDarkMode() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT;
  }

  private tabIndicatorColor(): string {
    return this.isDarkMode() ? '#1FFFFFFF' : '#12000000';
  }

  private tabIndicatorEffectColor(): string {
    return this.isDarkMode() ? '#14FFFFFF' : '#1A000000';
  }

  private tabBarColor(): string {
    return this.isDarkMode() ? '#9916181F' : '#B3FFFFFF';
  }

  private tabBarEffectColor(): string {
    return this.isDarkMode() ? '#26FFFFFF' : '#33FFFFFF';
  }

  private tabBarBorderColor(): string {
    return this.isDarkMode() ? '#33FFFFFF' : '#33E0E2EA';
  }

  private tabShadowColor(): string {
    return this.isDarkMode() ? '#40000000' : '#14000000';
  }

  private playChromeEnter(): void {
    this.chromeOpacity = 0;
    this.chromeTranslateY = 14;
    // 弹簧曲线驱动，无需 setTimeout；首帧提交后立即动画
    this.getUIContext().animateTo({ duration: 0, curve: springSnappy }, () => {
      this.chromeOpacity = 1;
      this.chromeTranslateY = 0;
    });
  }

  private playOverlayEnter(): void {
    this.overlayOpacity = 0;
    this.overlayTranslateY = 28;
    this.overlayScale = 0.98;
    this.getUIContext().animateTo({ duration: 0, curve: springSnappy }, () => {
      this.overlayOpacity = 1;
      this.overlayTranslateY = 0;
      this.overlayScale = 1;
    });
  }

  // 退场动画与进场对称：下滑 + 淡出 + 缩小，结束后再切视图，避免瞬间消失的割裂感
  private playOverlayExit(onDone: () => void): void {
    this.getUIContext().animateTo({
      duration: OVERLAY_EXIT_DURATION,
      curve: springSnappy,
      onFinish: () => {
        this.overlayOpacity = 1;
        this.overlayTranslateY = 0;
        this.overlayScale = 1;
        onDone();
      }
    }, () => {
      this.overlayOpacity = 0;
      this.overlayTranslateY = 28;
      this.overlayScale = 0.98;
    });
  }

  private playCardsEnter(source: AppView): void {
    if (source === AppView.SEARCH) {
      this.searchCardsEntered = false;
    } else {
      this.homeCardsEntered = false;
    }
    this.getUIContext().animateTo({ duration: 0, curve: springBouncy }, () => {
      if (source === AppView.SEARCH) {
        this.searchCardsEntered = true;
      } else {
        this.homeCardsEntered = true;
      }
    });
  }

  private playSettingsEnter(): void {
    this.settingsEntered = false;
    this.getUIContext().animateTo({ duration: 0, curve: springBouncy }, () => {
      this.settingsEntered = true;
    });
  }

  private playDetailEnter(): void {
    this.detailEntered = false;
    this.chapterListEntered = false;
    this.getUIContext().animateTo({ duration: 0, curve: springBouncy }, () => {
      this.detailEntered = true;
    });
  }

  private playChapterListEnter(): void {
    this.chapterListEntered = false;
    this.getUIContext().animateTo({ duration: 0, curve: springBouncy }, () => {
      this.chapterListEntered = true;
    });
  }

  private cardEnterOpacity(source: AppView): number {
    return source === AppView.SEARCH
      ? (this.searchCardsEntered ? 1 : 0)
      : (this.homeCardsEntered ? 1 : 0);
  }

  private cardEnterTranslateY(source: AppView): number {
    return source === AppView.SEARCH
      ? (this.searchCardsEntered ? 0 : CARD_ENTER_OFFSET)
      : (this.homeCardsEntered ? 0 : CARD_ENTER_OFFSET);
  }

  private cardEnterDelay(index: number): number {
    return CARD_ENTER_BASE_DELAY + Math.min(index, 8) * CARD_ENTER_STAGGER;
  }

  private settingsBlockOpacity(index: number): number {
    return this.settingsEntered ? 1 : Math.max(0.08, 0.28 - index * 0.04);
  }

  private settingsBlockTranslateY(index: number): number {
    return this.settingsEntered ? 0 : CARD_ENTER_OFFSET + index * 6;
  }

  private listItemOpacity(entered: boolean): number {
    return entered ? 1 : 0;
  }

  private listItemTranslateY(index: number, entered: boolean): number {
    return entered ? 0 : LIST_ITEM_ENTER_OFFSET + Math.min(index, 6) * 5;
  }

  private listItemDelay(index: number): number {
    return CARD_ENTER_BASE_DELAY + Math.min(index, 8) * LIST_ITEM_ENTER_STAGGER;
  }

  private detailBlockDelay(order: number): number {
    return CARD_ENTER_BASE_DELAY + order * DETAIL_BLOCK_STAGGER;
  }

  private formatCount(value: number): string {
    if (value < 1000) {
      return String(value);
    }
    if (value < 10000) {
      return `${(value / 1000).toFixed(1)}k`;
    }
    return `${(value / 10000).toFixed(1)}w`;
  }

  private sortedChapters(): ComicDetailSeriesListItemResponse[] {
    if (this.detailComic === null) {
      return [];
    }
    // 倒序：最新章节（sort 值大）在前，便于定位最近更新
    return this.detailComic.series.slice().sort((a: ComicDetailSeriesListItemResponse, b: ComicDetailSeriesListItemResponse) => {
      return Number.parseFloat(b.sort) - Number.parseFloat(a.sort);
    });
  }

  aboutToAppear(): void {
    this.playChromeEnter();
    this.initPrefStore();
    this.wireCookiePersistence();
    this.loadCachedShell();
    this.bootstrap();
  }

  private initPrefStore(): void {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context !== undefined) {
      this.prefStore = new PrefStore(context);
    } else {
      hilog.error(DOMAIN, TAG, 'abilityContext missing, persistence disabled');
    }
  }

  // 恢复上次登录态 Cookie，并在 Set-Cookie 变更时落盘，进程重启后保持登录
  private async wireCookiePersistence(): Promise<void> {
    if (this.prefStore === null) {
      return;
    }
    const stored = await this.prefStore.getObject<StoredCookie[]>(PREF_KEY_COOKIES);
    if (stored !== null && stored.length > 0) {
      this.jm.http.cookieJar.restore(stored);
      hilog.info(DOMAIN, TAG, 'cookie restored count=%{public}d', stored.length);
    }
    this.jm.http.setCookiePersister(() => {
      this.prefStore?.putObject<StoredCookie[]>(PREF_KEY_COOKIES, this.jm.http.cookieJar.snapshot());
    });
  }

  // 冷启动先用上次落盘的 img_host 与首页分区秒显，再由 bootstrap 后台刷新覆盖（stale-while-revalidate）
  private async loadCachedShell(): Promise<void> {
    if (this.prefStore === null) {
      return;
    }
    const cachedHost = await this.prefStore.getString(PREF_KEY_IMG_HOST, '');
    if (cachedHost.length > 0 && this.imgHost.length === 0) {
      this.imgHost = cachedHost;
    }
    const cachedHome = await this.prefStore.getObject<HomeSwiperComicListItemResponse[]>(PREF_KEY_HOME);
    if (cachedHome !== null && cachedHome.length > 0 && this.homeSections.length === 0) {
      this.rebuildHomeCards(cachedHome);
      hilog.info(DOMAIN, TAG, 'home shell from cache sections=%{public}d', cachedHome.length);
    }
  }

  onBackPress(): boolean {
    if (this.overlayView === AppView.READER) {
      // 阅读器退回详情：detail 内容已在同一 overlay 容器，直接切换无需重播进场
      this.overlayView = AppView.DETAIL;
      this.readerImages = [];
      this.readerSource.reload([]);
      this.readerTitle = '';
      return true;
    }
    if (this.overlayView === AppView.DETAIL) {
      // 详情退回首页：播对称退场动画，结束后再切视图并恢复搜索滚动
      this.playOverlayExit(() => {
        this.overlayView = AppView.HOME;
        if (this.rootContentTabIndex === this.tabIndexFromRootView(AppView.SEARCH)) {
          this.restoreSearchScrollOffset();
        }
      });
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      Column() {
        if (this.error.length > 0) {
          Text(this.error)
            .fontSize(12)
            .fontColor(COLOR_ERROR)
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }

        this.rootTabs()
      }
      .height('100%')
      .width('100%')
      .backgroundColor(COLOR_BG)

      if (this.overlayView === AppView.DETAIL) {
        this.detailOverlay()
      } else if (this.overlayView === AppView.READER) {
        this.readerOverlay()
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(COLOR_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private detailOverlay() {
    Column() {
      this.header()
      this.detailView()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
    .opacity(this.overlayOpacity)
    .translate({ y: this.overlayTranslateY })
    .scale({ x: this.overlayScale, y: this.overlayScale })
    .zIndex(20)
  }

  @Builder
  private readerOverlay() {
    Column() {
      this.header()
      this.readerView()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .opacity(this.overlayOpacity)
    .translate({ y: this.overlayTranslateY })
    .scale({ x: this.overlayScale, y: this.overlayScale })
    .zIndex(20)
  }

  @Builder
  private rootTabs() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.rootContentTabIndex === 1) {
          this.searchViewV2()
        } else if (this.rootContentTabIndex === 2) {
          this.settingsViewV2()
        } else {
          this.homeView()
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.rootTabOpacity)
      .translate({ x: this.rootTabTranslateX, y: 0 })
      .scale({ x: this.rootTabScale, y: this.rootTabScale })

      this.floatingLightTabBar()
    }
    .layoutWeight(1)
    .width('100%')
    .alignContent(Alignment.Bottom)
  }

  @Builder
  private floatingLightTabBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width(TAB_INDICATOR_WIDTH)
        .height(TAB_INDICATOR_HEIGHT)
        .margin({
          left: this.tabIndicatorLeft(),
          top: (TAB_BAR_HEIGHT - TAB_INDICATOR_HEIGHT) / 2
        })
        .borderRadius(TAB_INDICATOR_HEIGHT / 2)
        .backgroundColor(this.tabIndicatorColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, {
          colorMode: this.tabBlurColorMode(),
          adaptiveColor: AdaptiveColor.DEFAULT,
          scale: 0.6
        })
        .backdropBlur(14)
        .backgroundEffect({
          radius: 16,
          saturation: 1,
          brightness: 1.03,
          color: this.tabIndicatorEffectColor(),
          adaptiveColor: AdaptiveColor.DEFAULT
        })
        .shadow({
          radius: 6,
          color: this.tabShadowColor(),
          offsetX: 0,
          offsetY: 1
        })
        .animation({
          duration: 0,
          curve: springSnappy,
          iterations: 1,
          playMode: PlayMode.Normal
        })

      Row() {
        this.floatingTabItem($r('sys.symbol.house'), '首页', 0)
        this.floatingTabItem($r('sys.symbol.magnifyingglass'), '搜索', 1)
        this.floatingTabItem($r('sys.symbol.gearshape'), '设置', 2)
      }
      .width(TAB_BAR_WIDTH)
      .height(TAB_BAR_HEIGHT)
    }
    .width(TAB_BAR_WIDTH)
    .height(TAB_BAR_HEIGHT)
    .margin({ bottom: TAB_BAR_BOTTOM_MARGIN })
    .borderRadius(TAB_BAR_HEIGHT / 2)
    .backgroundColor(this.tabBarColor())
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, {
      colorMode: this.tabBlurColorMode(),
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.7
    })
    .backdropBlur(20)
    .backgroundEffect({
      radius: 20,
      saturation: 1,
      brightness: 1.03,
      color: this.tabBarEffectColor(),
      adaptiveColor: AdaptiveColor.DEFAULT
    })
    .border({ width: 1, color: this.tabBarBorderColor() })
    .shadow({
      radius: 14,
      color: this.tabShadowColor(),
      offsetX: 0,
      offsetY: 6
    })
    .clip(true)
    .opacity(this.chromeOpacity)
    .translate({ y: this.chromeTranslateY })
    .zIndex(10)
  }

  @Builder
  private floatingTabItem(icon: Resource, text: string, index: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 2 }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([this.currentTabIndex === index ? COLOR_ACCENT : COLOR_TAB_MUTED])
          .fontWeight(FontWeight.Medium)
        Text(text)
          .fontSize(11)
          .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.currentTabIndex === index ? COLOR_ACCENT : COLOR_TAB_MUTED)
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(TAB_ITEM_WIDTH)
      .height(TAB_BAR_HEIGHT)
    }
    .width(TAB_ITEM_WIDTH)
    .height(TAB_BAR_HEIGHT)
    .backgroundColor(Color.Transparent)
    .borderRadius(TAB_BAR_HEIGHT / 2)
    .padding(0)
    .scale({ x: this.pressedTab === index ? PRESS_SCALE : 1, y: this.pressedTab === index ? PRESS_SCALE : 1 })
    .animation({
      duration: PRESS_DURATION,
      curve: springSnappy,
      iterations: 1,
      playMode: PlayMode.Normal
    })
    .onClick(() => {
      this.pressedTab = index;
      this.schedulePressReset((): void => { this.pressedTab = -1; });
      this.switchRootTab(index);
    })
  }

  private tabIndicatorLeft(): number {
    return this.currentTabIndex * TAB_ITEM_WIDTH + (TAB_ITEM_WIDTH - TAB_INDICATOR_WIDTH) / 2;
  }

  private switchRootTab(index: number): void {
    if (this.currentTabIndex === index || this.rootTabSwitching) {
      return;
    }
    this.scheduleRootTabSwitch(index);
  }

  private headerForeground(): ResourceColor {
    return this.overlayView === AppView.READER ? '#FFFFFF' : COLOR_TEXT;
  }

  private headerButtonBg(): ResourceColor {
    return this.overlayView === AppView.READER ? '#29FFFFFF' : COLOR_PRIMARY_SOFT;
  }

  @Builder
  private header() {
    Row() {
      if (this.canGoBack()) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([this.headerForeground()])
        }
          .width(36)
          .height(36)
          .backgroundColor(this.headerButtonBg())
          .onClick(() => {
            this.goBack();
          })
      }
      Text(this.titleText())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.headerForeground())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: this.canGoBack() ? 8 : 4 })
      if (this.loading) {
        LoadingProgress()
          .width(26)
          .height(26)
          .color(this.headerForeground())
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: STATUS_BAR_OFFSET, bottom: 2 })
  }

  @Builder
  private homeView() {
    Stack({ alignContent: Alignment.Bottom }) {
      Refresh({ refreshing: $$this.homeRefreshing }) {
        Scroll(this.homeScroller) {
          Column() {
            if (this.homeSections.length > 0) {
              this.homeHero()
              this.homeSectionPicker()
            }
            if (this.visibleHomeItems.length > 0) {
              this.homeComicGrid()
            } else if (this.homeSections.length > 0) {
              this.emptyState($r('sys.symbol.house'), '暂无内容', '换个分区或稍后刷新')
            } else if (this.loading) {
              this.homeSkeleton()
            } else {
              this.emptyState($r('sys.symbol.house'), '暂无内容', '下拉刷新或稍后重试')
            }
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.72)
        .onScrollEdge((side: Edge) => {
          if (side === Edge.Bottom) {
            this.autoLoadMoreHomeItems();
          }
        })
      }
      .onRefreshing(() => {
        this.refreshHome();
      })
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  private async refreshHome(): Promise<void> {
    // 下拉刷新强制跳过缓存，拿最新首页与设置
    this.jm.cache.invalidate('home');
    this.jm.cache.invalidate('setting');
    await this.bootstrap();
    this.homeRefreshing = false;
  }

  @Builder
  private homeSkeleton() {
    Column({ space: 16 }) {
      Row() {
        Column()
          .width(140)
          .height(22)
          .borderRadius(6)
          .backgroundColor(COLOR_SURFACE_SOFT)
        Blank()
        Column()
          .width(56)
          .height(20)
          .borderRadius(10)
          .backgroundColor(COLOR_SURFACE_SOFT)
      }
      .width('100%')
      .padding({ left: 20, right: 20 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach([0, 1, 2, 3, 4, 5], (n: number) => {
          Column()
            .width('48%')
            .aspectRatio(0.72)
            .borderRadius(RADIUS_MD)
            .backgroundColor(COLOR_SURFACE_SOFT)
            .margin({ bottom: SPACE_CARD_GAP })
        }, (n: number) => `sk-${n}`)
      }
      .padding({ left: 16, right: 16, top: 14, bottom: GRID_BOTTOM_PADDING })
    }
    .width('100%')
    .padding({ top: STATUS_BAR_OFFSET })
  }

  @Builder
  private homeSectionPicker() {
    Column({ space: 10 }) {
      List({ space: 8 }) {
        ForEach(this.homeSections, (section: HomeSwiperComicListItemResponse, index: number) => {
          ListItem() {
            this.homeSectionChip(section, index)
          }
        }, (section: HomeSwiperComicListItemResponse, index: number) => `${section.id}-${index}`)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .height(32)
      .padding({ left: 20, right: 20 })
      .width('100%')
    }
    .width('100%')
    .padding({ top: 2, bottom: 4 })
    .opacity(this.chromeOpacity)
    .translate({ y: this.chromeTranslateY })
  }

  @Builder
  private homeSectionChip(section: HomeSwiperComicListItemResponse, index: number) {
    Button(this.sectionChipTitle(section.title, index), { type: ButtonType.Normal, stateEffect: true })
      .height(34)
      .fontSize(13)
      .fontWeight(index === this.selectedSectionIndex ? FontWeight.Bold : FontWeight.Medium)
      .backgroundColor(index === this.selectedSectionIndex ? COLOR_PRIMARY : COLOR_SURFACE)
      .fontColor(index === this.selectedSectionIndex ? COLOR_ON_PRIMARY : COLOR_MUTED)
      .border({ width: 1, color: index === this.selectedSectionIndex ? Color.Transparent : COLOR_BORDER })
      .borderRadius(RADIUS_PILL)
      .padding({ left: 16, right: 16 })
      .animation({
        duration: 0,
        curve: springSnappy,
        iterations: 1,
        playMode: PlayMode.Normal
      })
      .scale({
        x: this.pressedSource === `chip-${index}` ? PRESS_SCALE : 1,
        y: this.pressedSource === `chip-${index}` ? PRESS_SCALE : 1
      })
      .animation({
        duration: PRESS_DURATION,
        curve: springSnappy,
        iterations: 1,
        playMode: PlayMode.Normal
      })
      .onClick(() => {
        this.pressedSource = `chip-${index}`;
        this.schedulePressReset((): void => { this.pressedSource = ''; });
        this.setActiveHomeSection(index);
      })
  }

  @Builder
  private homeHero() {
    Row() {
      Text(this.activeHomeTitle.length > 0 ? this.activeHomeTitle : '精选')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(`${this.homeTotalCount} 本`)
        .fontSize(12)
        .fontColor(COLOR_MUTED)
        .margin({ right: 12 })

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.loading ? $r('sys.symbol.arrow_2_circlepath') : $r('sys.symbol.arrow_clockwise'))
          .fontSize(17)
          .fontColor([COLOR_PRIMARY])
      }
      .width(36)
      .height(36)
      .backgroundColor(COLOR_PRIMARY_SOFT)
      .onClick(async () => {
        await this.bootstrap();
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: STATUS_BAR_OFFSET, bottom: 2 })
    .opacity(this.chromeOpacity)
    .translate({ y: this.chromeTranslateY })
  }

  @Builder
  private searchViewV2() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Column({ space: 12 }) {
          Text('搜索漫画')
            .fontSize(PAGE_TITLE_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
            .margin({ top: STATUS_BAR_OFFSET - 8 })

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(20)
              .fontColor([COLOR_MUTED])

            TextInput({ placeholder: '关键词或 JM ID', text: $$this.searchText })
              .layoutWeight(1)
              .height(42)
              .fontSize(15)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .onChange((value: string) => {
                this.handleSearchTextChange(value);
              })

            if (this.searchText.length > 0) {
              Button({ type: ButtonType.Circle }) {
                Text('×')
                  .fontSize(18)
                  .fontColor(COLOR_MUTED)
              }
              .width(30)
              .height(30)
              .backgroundColor(COLOR_SURFACE_SOFT)
              .onClick(() => {
                this.searchText = '';
                this.clearSearchResults();
                this.error = '';
              })
            }

            Button('搜索')
              .height(34)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(COLOR_PRIMARY)
              .fontColor(COLOR_ON_PRIMARY)
              .borderRadius(RADIUS_PILL)
              .padding({ left: 16, right: 16 })
              .onClick(async () => {
                this.getUIContext().getFocusController().clearFocus();
                await this.search();
              })
          }
          .height(50)
          .padding({ left: 16, right: 6 })
          .borderRadius(RADIUS_PILL)
          .backgroundColor(COLOR_SURFACE)
          .border({ width: 1, color: COLOR_BORDER })
          .shadow({
            radius: 16,
            color: this.tabShadowColor(),
            offsetX: 0,
            offsetY: 6
          })
        }
        .padding({ left: 18, right: 18, top: 8, bottom: 12 })
        .backgroundColor(Color.Transparent)
        .opacity(this.chromeOpacity)
        .translate({ y: this.chromeTranslateY })

        Refresh({ refreshing: $$this.searchRefreshing }) {
          Scroll(this.searchScroller) {
            Column() {
              if (this.visibleSearchItems.length > 0) {
                this.sectionHeader('搜索结果', `${this.searchItems.length} 本`, this.searchText.trim())
                this.searchComicGrid()
              } else {
                this.emptyState($r('sys.symbol.magnifyingglass'), '输入关键词搜索', '支持漫画名、作者或 JM ID')
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .friction(0.72)
          .onScrollEdge((side: Edge) => {
            if (side === Edge.Bottom) {
              this.autoLoadMoreSearchItems();
            }
          })
        }
        .onRefreshing(() => {
          this.refreshSearch();
        })
      }
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }

  private async refreshSearch(): Promise<void> {
    if (this.searchText.trim().length > 0) {
      await this.search();
    }
    this.searchRefreshing = false;
  }

  @Builder
  private sectionHeader(title: string, meta: string, subtitle: string) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)

      Text(meta)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_ACCENT)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(COLOR_ACCENT_SOFT)
        .borderRadius(RADIUS_SM)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 4 })
  }

  @Builder
  private emptyState(icon: Resource, title: string, desc: string) {
    Column({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(34)
        .fontColor([COLOR_MUTED])
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT)
      Text(desc)
        .fontSize(13)
        .fontColor(COLOR_MUTED)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(360)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
  }

  @Builder
  private detailView() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.detailComic !== null) {
          Row({ space: 14 }) {
            Image(this.coverUrl(String(this.detailComic.id)))
              .width(126)
              .height(168)
              .objectFit(ImageFit.Cover)
              .borderRadius(RADIUS_MD)
              .backgroundColor(COLOR_DIVIDER)
              .shadow({
                radius: 16,
                color: this.tabShadowColor(),
                offsetX: 0,
                offsetY: 8
              })

            Column({ space: 8 }) {
              Text(this.detailComic.name)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`JM${this.detailComic.id}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_ACCENT)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(COLOR_ACCENT_SOFT)
                .borderRadius(RADIUS_SM)
              Text(this.detailComic.author.join(', '))
                .fontSize(13)
                .fontColor(COLOR_MUTED)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Blank()
            }
            .alignItems(HorizontalAlign.Start)
            .height(168)
            .layoutWeight(1)
          }
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: CARD_ENTER_BASE_DELAY,
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          Column() {
            this.detailStatsRow()
          }
          .width('100%')
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: this.detailBlockDelay(1),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          Column() {
            this.detailActionBar()
          }
          .width('100%')
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: this.detailBlockDelay(2),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          Column() {
            this.detailDescription()
          }
          .width('100%')
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: this.detailBlockDelay(3),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          Column() {
            this.tagLine('标签', this.detailComic.tags)
          }
          .width('100%')
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: this.detailBlockDelay(4),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          Column() {
            this.tagLine('角色', this.detailComic.actors)
          }
          .width('100%')
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: this.detailBlockDelay(5),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          Column() {
            this.relatedComics()
          }
          .width('100%')
          .opacity(this.listItemOpacity(this.detailEntered))
          .translate({ y: this.listItemTranslateY(0, this.detailEntered) })
          .animation({
            duration: 0,
            delay: this.detailBlockDelay(6),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })

          this.chapterList()
        } else {
          this.detailSkeleton()
        }
      }
      .padding(16)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private sectionTitle(title: string) {
    Row({ space: 8 }) {
      Row()
        .width(4)
        .height(15)
        .borderRadius(RADIUS_PILL)
        .backgroundColor(COLOR_ACCENT)
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
    }
    .width('100%')
  }

  @Builder
  private detailStatsRow() {
    Row() {
      this.statItem('浏览', this.formatCount(this.detailComic?.total_views ?? 0))
      Divider().vertical(true).height(22).color(COLOR_DIVIDER)
      this.statItem('点赞', this.formatCount(this.detailComic?.likes ?? 0))
      Divider().vertical(true).height(22).color(COLOR_DIVIDER)
      this.statItem('评论', this.formatCount(this.detailComic?.comment_total ?? 0))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(RADIUS_MD)
    .border({ width: 1, color: COLOR_BORDER })
  }

  @Builder
  private statItem(label: string, value: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
      Text(label)
        .fontSize(11)
        .fontColor(COLOR_MUTED)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private detailDescription() {
    if (this.detailComic !== null && this.detailComic.description.length > 0) {
      Column({ space: 8 }) {
        this.sectionTitle('简介')
        Text(this.detailComic.description)
          .fontSize(14)
          .fontColor(COLOR_TEXT)
          .lineHeight(22)
          .width('100%')
          .maxLines(this.descExpanded ? 1000 : 4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.descExpanded ? '收起' : '展开全部')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_ACCENT)
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 0, curve: springBouncy }, () => {
              this.descExpanded = !this.descExpanded;
            });
          })
      }
      .width('100%')
      .padding(14)
      .backgroundColor(COLOR_SURFACE)
      .borderRadius(RADIUS_MD)
      .border({ width: 1, color: COLOR_BORDER })
    }
  }

  @Builder
  private detailSkeleton() {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        Column()
          .width(126)
          .height(168)
          .borderRadius(RADIUS_MD)
          .backgroundColor(COLOR_SURFACE_SOFT)
        Column({ space: 10 }) {
          Column().width('80%').height(22).borderRadius(6).backgroundColor(COLOR_SURFACE_SOFT)
          Column().width(64).height(18).borderRadius(6).backgroundColor(COLOR_SURFACE_SOFT)
          Column().width('60%').height(16).borderRadius(6).backgroundColor(COLOR_SURFACE_SOFT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Column()
        .width('100%')
        .height(56)
        .borderRadius(RADIUS_MD)
        .backgroundColor(COLOR_SURFACE_SOFT)
      Column()
        .width('100%')
        .height(44)
        .borderRadius(RADIUS_PILL)
        .backgroundColor(COLOR_SURFACE_SOFT)
      Column()
        .width('100%')
        .height(110)
        .borderRadius(RADIUS_MD)
        .backgroundColor(COLOR_SURFACE_SOFT)
    }
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  private detailActionBar() {
    Row({ space: 10 }) {
      Button('开始阅读')
        .layoutWeight(1)
        .height(44)
        .backgroundColor(COLOR_PRIMARY)
        .fontColor(COLOR_ON_PRIMARY)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .borderRadius(RADIUS_PILL)
        .scale({
          x: this.pressedSource === 'read' ? PRESS_SCALE : 1,
          y: this.pressedSource === 'read' ? PRESS_SCALE : 1
        })
        .animation({
          duration: PRESS_DURATION,
          curve: springSnappy,
          iterations: 1,
          playMode: PlayMode.Normal
        })
        .onClick(async () => {
          this.pressedSource = 'read';
          this.schedulePressReset((): void => { this.pressedSource = ''; });
          await this.openReader();
        })

      this.iconActionButton(
        this.detailFavorited ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
        '收藏',
        'fav',
        this.detailFavorited,
        () => { this.toggleFavorite(); }
      )
      this.iconActionButton(
        this.detailLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        '点赞',
        'like',
        this.detailLiked,
        () => { this.toggleLike(); }
      )
    }
    .width('100%')
  }

  @Builder
  private iconActionButton(icon: Resource, label: string, key: string, active: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 }) {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([active ? COLOR_ACCENT : COLOR_MUTED])
        Text(label)
          .fontSize(10)
          .fontColor(active ? COLOR_ACCENT : COLOR_MUTED)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(56)
    .height(44)
    .backgroundColor(active ? COLOR_ACCENT_SOFT : COLOR_SURFACE)
    .border({ width: 1, color: active ? Color.Transparent : COLOR_BORDER })
    .borderRadius(RADIUS_MD)
    .scale({
      x: this.pressedSource === key ? PRESS_SCALE : 1,
      y: this.pressedSource === key ? PRESS_SCALE : 1
    })
    .animation({
      duration: 0,
      curve: springSnappy,
      iterations: 1,
      playMode: PlayMode.Normal
    })
    .onClick(() => {
      this.pressedSource = key;
      this.schedulePressReset((): void => { this.pressedSource = ''; });
      action();
    })
  }

  @Builder
  private relatedComics() {
    if (this.detailComic !== null && this.detailComic.related_list.length > 0) {
      Column({ space: 10 }) {
        this.sectionTitle('相关推荐')
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.detailComic.related_list, (item: ComicDetailRelatedListItemResponse) => {
              Column() {
                Image(this.coverUrl(item.id))
                  .width(96)
                  .height(134)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(RADIUS_SM)
                  .backgroundColor(COLOR_SURFACE_SOFT)
                Text(item.name)
                  .fontSize(11)
                  .fontColor(COLOR_TEXT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(96)
                  .margin({ top: 4 })
              }
              .width(96)
              .onClick(() => {
                this.openDetail(Number.parseInt(item.id, 10));
              })
            }, (item: ComicDetailRelatedListItemResponse) => item.id)
          }
          .padding({ left: 2, right: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private readerView() {
    List() {
      LazyForEach(this.readerSource, (item: ReaderImageItem) => {
        ListItem() {
          ReaderImagePage({
            url: item.url,
            index: item.index,
            total: this.readerImages.length,
            seed: item.seed
          })
        }
      }, (item: ReaderImageItem) => item.id)
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .cachedCount(2)
  }

  private goBack(): void {
    this.onBackPress();
  }

  private canGoBack(): boolean {
    return this.overlayView === AppView.DETAIL || this.overlayView === AppView.READER;
  }

  private resetRootView(target: AppView): void {
    this.overlayView = AppView.HOME;
    this.syncTabIndex(target);
    if (target !== AppView.READER) {
      this.readerImages = [];
      this.readerSource.reload([]);
      this.readerTitle = '';
    }
  }

  private scheduleRootTabSwitch(index: number): void {
    const previousIndex = this.currentTabIndex;
    const direction = index > previousIndex ? 1 : -1;
    this.rootTabSwitching = true;
    this.currentTabIndex = index;
    // exit：内容快速淡出 + 轻微反向偏移；opacity 降到 0 让 swap 时旧内容已不可见
    this.getUIContext().animateTo({ duration: ROOT_TAB_EXIT_DURATION, curve: springSnappy }, () => {
      this.rootTabOpacity = ROOT_TAB_EXIT_OPACITY;
      this.rootTabTranslateX = -ROOT_TAB_OFFSET * direction;
      this.rootTabScale = 0.985;
    });
    // 中段 swap 内容：此时旧内容已淡到接近不可见，立即切内容并以平滑曲线淡入，新旧过渡视觉重叠无空窗
    setTimeout((): void => {
      this.rootContentTabIndex = index;
      this.resetRootView(this.rootViewFromTabIndex(index));
      // 新内容初始为淡出 + 反向偏移，为 enter 蓄势
      this.rootTabOpacity = 0;
      this.rootTabTranslateX = ROOT_TAB_OFFSET * direction;
      this.rootTabScale = 0.985;
      this.prepareRootEnter(index);
      this.getUIContext().animateTo({ duration: 0, curve: springTabGlide }, () => {
        this.rootTabOpacity = 1;
        this.rootTabTranslateX = 0;
        this.rootTabScale = 1;
      });
    }, ROOT_TAB_SWAP_DELAY);
    setTimeout((): void => {
      this.rootTabSwitching = false;
    }, ROOT_TAB_UNLOCK_DELAY);
  }

  private rootViewFromTabIndex(index: number): AppView {
    if (index === 1) {
      return AppView.SEARCH;
    }
    if (index === 2) {
      return AppView.SETTINGS;
    }
    return AppView.HOME;
  }

  private tabIndexFromRootView(target: AppView): number {
    if (target === AppView.SEARCH) {
      return 1;
    }
    if (target === AppView.SETTINGS) {
      return 2;
    }
    return 0;
  }

  private syncTabIndex(target: AppView): void {
    if (target === AppView.HOME || target === AppView.SEARCH || target === AppView.SETTINGS) {
      this.currentTabIndex = this.tabIndexFromRootView(target);
      this.rootContentTabIndex = this.currentTabIndex;
      this.rootTabOpacity = 1;
      this.rootTabTranslateX = 0;
      this.rootTabScale = 1;
    }
  }

  private prepareRootEnter(index: number): void {
    if (index === this.tabIndexFromRootView(AppView.SETTINGS)) {
      this.playSettingsEnter();
      return;
    }
    if (index === this.tabIndexFromRootView(AppView.SEARCH)) {
      if (this.visibleSearchItems.length > 0) {
        this.playCardsEnter(AppView.SEARCH);
      }
      return;
    }
    if (this.visibleHomeItems.length > 0) {
      this.playCardsEnter(AppView.HOME);
    }
  }

  private extractPageFromUrl(url: string): string {
    const lastSlash = url.lastIndexOf('/');
    const fileName = lastSlash >= 0 ? url.substring(lastSlash + 1) : url;
    const lastDot = fileName.lastIndexOf('.');
    return lastDot >= 0 ? fileName.substring(0, lastDot) : fileName;
  }

  private async calculateImageSeed(comicId: number, imageUrl: string, scrambleId: number, speed: string): Promise<number> {
    if (imageUrl.endsWith('.gif') || comicId <= scrambleId || speed === '1') {
      return 1;
    }
    const seedMap: number[] = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20];
    const keyMd5 = await md5(`${comicId}${this.extractPageFromUrl(imageUrl)}`);
    let code = keyMd5.charCodeAt(keyMd5.length - 1);
    const left = 268850;
    const right = 421925;
    if (comicId >= left && comicId <= right) {
      code = code % 10;
    } else if (comicId >= right + 1) {
      code = code % 8;
    }
    const seed = seedMap[code];
    return seed !== undefined ? seed : 10;
  }

  private async buildReaderImages(comicId: number, list: string[], scrambleId: number, speed: string): Promise<ReaderImageItem[]> {
    const items: ReaderImageItem[] = [];
    for (let index = 0; index < list.length; index++) {
      const url = list[index];
      items.push({
        id: `${index}-${url}`,
        url,
        index,
        seed: await this.calculateImageSeed(comicId, url, scrambleId, speed)
      });
    }
    return items;
  }

  @Builder
  private settingsViewV2() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text('设置')
                .fontSize(PAGE_TITLE_SIZE)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Text('阅读源')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_MUTED)
                .width('100%')
              Text(this.baseUrl)
                .fontSize(12)
                .fontColor(COLOR_ACCENT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph(this.loading ? $r('sys.symbol.arrow_2_circlepath') : $r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([COLOR_ON_PRIMARY])
            }
            .width(46)
            .height(46)
            .backgroundColor(COLOR_ACCENT)
            .onClick(async () => {
              await this.bootstrap();
            })
          }

          Text(this.status)
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: STATUS_BAR_OFFSET, bottom: 18 })
        .borderRadius(RADIUS_LG)
        .backgroundColor(COLOR_SURFACE)
        .border({ width: 1, color: COLOR_BORDER })
        .shadow({
          radius: 18,
          color: this.tabShadowColor(),
          offsetX: 0,
          offsetY: 8
        })
        .opacity(this.settingsBlockOpacity(0))
        .translate({ y: this.settingsBlockTranslateY(0) })

        Column({ space: 0 }) {
          ForEach(DEFAULT_API_LIST, (source: string, index: number) => {
            this.sourceOptionV2(source, index)
          }, (source: string) => source)
        }
        .width('100%')
        .borderRadius(RADIUS_LG)
        .backgroundColor(COLOR_SURFACE)
        .border({ width: 1, color: COLOR_DIVIDER })
        .clip(true)
        .opacity(this.settingsBlockOpacity(1))
        .translate({ y: this.settingsBlockTranslateY(1) })

        Column({ space: 6 }) {
          Text('关于项目')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT)
            .width('100%')
          Text('https://github.com/Dou-art/jm')
            .fontSize(13)
            .fontColor(COLOR_ACCENT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('开源漫画阅读器 · HarmonyOS NEXT')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 16 })
        .borderRadius(RADIUS_LG)
        .backgroundColor(COLOR_SURFACE)
        .border({ width: 1, color: COLOR_DIVIDER })

        Text('切换阅读源后会自动重新加载首页数据。')
          .fontSize(12)
          .fontColor(COLOR_MUTED)
          .width('100%')
          .padding({ left: 4, right: 4 })
      }
      .padding({ left: 16, right: 16, top: 6, bottom: TAB_CONTENT_BOTTOM_PADDING })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private sourceOptionV2(source: string, index: number) {
    Row({ space: 12 }) {
      Column() {
        Text(`${index + 1}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(source === this.baseUrl ? COLOR_ACCENT : COLOR_MUTED)
      }
      .width(30)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(RADIUS_SM)
      .backgroundColor(source === this.baseUrl ? COLOR_ACCENT_SOFT : COLOR_SURFACE_SOFT)

      Column({ space: 4 }) {
        Text(source)
          .fontSize(14)
          .fontWeight(source === this.baseUrl ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(COLOR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(source === this.baseUrl ? '当前使用' : '点击切换')
          .fontSize(12)
          .fontColor(source === this.baseUrl ? COLOR_ACCENT : COLOR_MUTED)
          .width('100%')
      }
      .layoutWeight(1)

      if (source === this.baseUrl) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(22)
          .fontColor([COLOR_ACCENT])
      }
    }
    .width('100%')
    .height(68)
    .padding({ left: 16, right: 16 })
    .backgroundColor(source === this.baseUrl ? COLOR_ACCENT_SOFT : COLOR_SURFACE)
    .border({ width: { bottom: index === DEFAULT_API_LIST.length - 1 ? 0 : 1 }, color: COLOR_DIVIDER })
    .scale({
      x: this.pressedSource === source ? PRESS_SCALE : 1,
      y: this.pressedSource === source ? PRESS_SCALE : 1
    })
    .animation({
      duration: PRESS_DURATION,
      curve: springSnappy,
      iterations: 1,
      playMode: PlayMode.Normal
    })
    .onClick(() => {
      this.pressedSource = source;
      this.schedulePressReset((): void => { this.pressedSource = ''; });
      this.selectHost(source);
    })
  }

  @Builder
  private homeComicGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.visibleHomeItems, (item: ComicCardItem, index: number) => {
        Column() {
          this.comicCard(item, index, AppView.HOME)
        }
        .width('48%')
      }, (item: ComicCardItem) => `home-${item.id}`)
    }
    .padding({ left: 16, right: 16, top: 14, bottom: GRID_BOTTOM_PADDING })
    .width('100%')
  }

  @Builder
  private searchComicGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.visibleSearchItems, (item: ComicCardItem, index: number) => {
        Column() {
          this.comicCard(item, index, AppView.SEARCH)
        }
        .width('48%')
      }, (item: ComicCardItem) => `search-${item.id}`)
    }
    .padding({ left: 16, right: 16, top: 14, bottom: GRID_BOTTOM_PADDING })
    .width('100%')
  }

  @Builder
  private comicCard(item: ComicCardItem, index: number, source: AppView) {
    Button({ type: ButtonType.Normal }) {
      Column() {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image(this.coverUrl(item.id))
            .width('100%')
            .aspectRatio(0.72)
            .objectFit(ImageFit.Cover)
            .backgroundColor(COLOR_SURFACE_SOFT)

          // 底部渐变信息遮罩
          Column({ space: 3 }) {
            Text(item.name)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (item.author.length > 0) {
              Text(item.author)
                .fontSize(11)
                .fontColor('#E6FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 28, bottom: 12 })
          .linearGradient({
            angle: 180,
            colors: [['#00000000', 0], ['#A6000000', 0.55], ['#E6000000', 1]]
          })

          // 右上角 JM ID 角标
          Text(`JM${item.id}`)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#99000000')
            .borderRadius(RADIUS_SM)
            .margin({ top: 8, right: 8 })
            .align(Alignment.TopEnd)
        }
        .width('100%')
        .borderRadius(RADIUS_MD)
        .clip(true)
        .shadow({
          radius: 12,
          color: this.tabShadowColor(),
          offsetX: 0,
          offsetY: 6
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(0)
    .margin({ bottom: SPACE_CARD_GAP })
    .backgroundColor(Color.Transparent)
    .borderRadius(RADIUS_MD)
    .stateEffect(false)
    // 入场：opacity + translate，弹簧曲线 + stagger delay
    .opacity(this.cardEnterOpacity(source))
    .animation({
      duration: 0,
      delay: this.cardEnterDelay(index),
      curve: springBouncy,
      iterations: 1,
      playMode: PlayMode.Normal
    })
    .translate({ y: this.cardEnterTranslateY(source) })
    // 按压回弹：scale 独立动画，无 delay，即时响应
    .scale({ x: this.pressedCardId === item.id ? PRESS_SCALE : 1, y: this.pressedCardId === item.id ? PRESS_SCALE : 1 })
    .animation({
      duration: PRESS_DURATION,
      curve: springSnappy,
      iterations: 1,
      playMode: PlayMode.Normal
    })
    .onClick(async () => {
      hilog.info(DOMAIN, TAG, 'card clicked id=%{public}s name=%{public}s', item.id, item.name);
      this.playCardPress(item.id);
      await this.openDetail(Number.parseInt(item.id, 10));
    })
  }

  // 统一按压回弹复位时序，消除散落的 setTimeout(..., 130) 魔法数字
  private schedulePressReset(reset: () => void): void {
    setTimeout(reset, PRESS_RESET_DELAY);
  }

  private playCardPress(id: string): void {
    this.pressedCardId = id;
    this.schedulePressReset((): void => { this.pressedCardId = ''; });
  }

  @Builder
  private tagLine(label: string, values: string[]) {
    if (values.length > 0) {
      Column({ space: 10 }) {
        this.sectionTitle(label)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(values, (tag: string) => {
            Text(tag)
              .fontSize(12)
              .fontColor(COLOR_TEXT)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(COLOR_SURFACE)
              .borderRadius(RADIUS_PILL)
              .border({ width: 1, color: COLOR_BORDER })
          }, (tag: string) => tag)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private chapterList() {
    if (this.detailComic !== null && this.detailComic.series.length > 0) {
      Column({ space: 10 }) {
        Row() {
          this.sectionTitle('章节')
          Blank()
          Text(`共 ${this.detailComic.series.length} 话 · 最新在前`)
            .fontSize(11)
            .fontColor(COLOR_MUTED)
        }
        .width('100%')
        ForEach(this.sortedChapters(), (chapter: ComicDetailSeriesListItemResponse, index: number) => {
          Row({ space: 10 }) {
            Text(chapter.name)
              .fontSize(14)
              .fontColor(COLOR_TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`JM${chapter.id}`)
              .fontSize(12)
              .fontColor(COLOR_MUTED)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([COLOR_MUTED])
          }
          .width('100%')
          .height(48)
          .padding({ left: 14, right: 12 })
          .backgroundColor(COLOR_SURFACE)
          .borderRadius(RADIUS_MD)
          .border({ width: 1, color: COLOR_BORDER })
          .opacity(this.listItemOpacity(this.chapterListEntered))
          .translate({ y: this.listItemTranslateY(index, this.chapterListEntered) })
          .animation({
            duration: 0,
            delay: this.listItemDelay(index),
            curve: springBouncy,
            iterations: 1,
            playMode: PlayMode.Normal
          })
          .scale({
            x: this.pressedChapterId === chapter.id ? PRESS_SCALE : 1,
            y: this.pressedChapterId === chapter.id ? PRESS_SCALE : 1
          })
          .animation({
            duration: PRESS_DURATION,
            curve: springSnappy,
            iterations: 1,
            playMode: PlayMode.Normal
          })
          .onClick(async () => {
            this.pressedChapterId = chapter.id;
            this.schedulePressReset((): void => { this.pressedChapterId = ''; });
            await this.openReader(Number.parseInt(chapter.id, 10), chapter.name);
          })
        }, (chapter: ComicDetailSeriesListItemResponse) => chapter.id)
      }
      .width('100%')
    }
  }

  private titleText(): string {
    if (this.overlayView === AppView.READER) {
      return this.readerTitle.length > 0 ? this.readerTitle : '阅读';
    }
    if (this.overlayView === AppView.DETAIL) {
      return '详情';
    }
    if (this.rootContentTabIndex === this.tabIndexFromRootView(AppView.SEARCH)) {
      return '搜索';
    }
    if (this.rootContentTabIndex === this.tabIndexFromRootView(AppView.SETTINGS)) {
      return '设置';
    }
    return '首页';
  }

  private coverUrl(id: string): string {
    if (this.imgHost.length === 0) {
      return '';
    }
    return `${this.imgHost}/media/albums/${id}_3x4.jpg`;
  }

  private sectionChipTitle(title: string, index: number): string {
    let value = title
      .split('→').join('')
      .split('->').join('')
      .split('右滑看更多').join('')
      .split('右滑').join('')
      .split('看更多').join('')
      .trim();
    if (value.length === 0) {
      return `分区 ${index + 1}`;
    }
    if (value.length > 8) {
      return value.substring(0, 8);
    }
    return value;
  }

  private currentHomeItems(): ComicCardItem[] {
    return this.activeHomeItems;
  }

  private toCardItem(item: ListComicItemResponse): ComicCardItem {
    return {
      id: item.id,
      name: item.name,
      author: item.author,
      description: item.description ?? ''
    };
  }

  private toDetailCardItem(item: ComicDetailResponse): ComicCardItem {
    return {
      id: String(item.id),
      name: item.name,
      author: item.author.join(' '),
      description: item.description
    };
  }

  private isNumericKeyword(keyword: string): boolean {
    if (keyword.length === 0) {
      return false;
    }
    for (let index = 0; index < keyword.length; index++) {
      const code = keyword.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private shouldRemoveHomeSection(title: string): boolean {
    for (let index = 0; index < REMOVED_HOME_SECTION_KEYWORDS.length; index++) {
      if (title.includes(REMOVED_HOME_SECTION_KEYWORDS[index])) {
        return true;
      }
    }
    return false;
  }

  private rebuildHomeCards(sections: HomeSwiperComicListItemResponse[]): void {
    this.homeSections = sections.filter((section: HomeSwiperComicListItemResponse) => {
      return !this.shouldRemoveHomeSection(section.title);
    });
    this.setActiveHomeSection(0);
  }

  private setActiveHomeSection(index: number): void {
    if (this.homeSections.length === 0) {
      this.selectedSectionIndex = 0;
      this.homeVisibleCount = 0;
      this.homeTotalCount = 0;
      this.activeHomeTitle = '';
      this.activeHomeItems = [];
      this.visibleHomeItems = [];
      this.status = '首页暂无分区';
      return;
    }
    const safeIndex = Math.max(0, Math.min(index, this.homeSections.length - 1));
    const items = this.homeSections[safeIndex].content.map((item: ListComicItemResponse) => this.toCardItem(item));
    const visibleCount = Math.min(HOME_VISIBLE_STEP, items.length);
    this.selectedSectionIndex = safeIndex;
    this.activeHomeTitle = this.sectionChipTitle(this.homeSections[safeIndex].title, safeIndex);
    this.activeHomeItems = items;
    this.homeVisibleCount = visibleCount;
    this.homeTotalCount = items.length;
    this.visibleHomeItems = items.slice(0, visibleCount);
    this.playCardsEnter(AppView.HOME);
    this.status = `分区 ${safeIndex + 1}/${this.homeSections.length} · ${this.sectionChipTitle(this.homeSections[safeIndex].title, safeIndex)} · 显示 ${visibleCount}/${items.length}`;
  }

  private showMoreHomeItems(): void {
    const items = this.currentHomeItems();
    if (this.homeVisibleCount >= items.length) {
      return;
    }
    const visibleCount = Math.min(this.homeVisibleCount + HOME_VISIBLE_STEP, items.length);
    this.homeVisibleCount = visibleCount;
    this.homeTotalCount = items.length;
    this.visibleHomeItems = items.slice(0, visibleCount);
    this.status = `自动加载 · 显示 ${visibleCount}/${items.length}`;
  }

  private autoLoadMoreHomeItems(): void {
    if (this.homeAutoLoadingMore || this.visibleHomeItems.length <= 0 || this.visibleHomeItems.length >= this.homeTotalCount) {
      return;
    }
    this.homeAutoLoadingMore = true;
    this.showMoreHomeItems();
    setTimeout(() => {
      this.homeAutoLoadingMore = false;
    }, 360);
  }

  private clearSearchResults(): void {
    this.searchRequestSeq++;
    this.lastSearchKeyword = '';
    this.searchItems = [];
    this.visibleSearchItems = [];
    this.searchVisibleCount = SEARCH_VISIBLE_STEP;
    this.searchScrollY = 0;
  }

  private handleSearchTextChange(value: string): void {
    const normalized = value.trim();
    if (value === this.searchText && normalized === this.lastSearchKeyword) {
      return;
    }
    this.searchText = value;
    if (normalized !== this.lastSearchKeyword) {
      this.clearSearchResults();
      this.error = '';
    }
  }

  private saveSearchScrollOffset(): void {
    try {
      this.searchScrollY = Math.max(0, this.searchScroller.currentOffset().yOffset);
    } catch (err) {
      this.searchScrollY = 0;
    }
  }

  private restoreSearchScrollOffset(): void {
    const offset = this.searchScrollY;
    if (offset <= 0) {
      return;
    }
    setTimeout((): void => {
      this.searchScroller.scrollTo({
        xOffset: 0,
        yOffset: offset,
        animation: false
      });
    }, 40);
  }

  private setSearchResults(items: ComicCardItem[]): void {
    const visibleCount = Math.min(SEARCH_VISIBLE_STEP, items.length);
    this.searchItems = items;
    this.searchVisibleCount = visibleCount;
    this.visibleSearchItems = items.slice(0, visibleCount);
    this.playCardsEnter(AppView.SEARCH);
  }

  private showMoreSearchItems(): void {
    if (this.searchVisibleCount >= this.searchItems.length) {
      return;
    }
    const visibleCount = Math.min(this.searchVisibleCount + SEARCH_VISIBLE_STEP, this.searchItems.length);
    this.searchVisibleCount = visibleCount;
    this.visibleSearchItems = this.searchItems.slice(0, visibleCount);
    this.status = `自动加载 · 显示 ${visibleCount}/${this.searchItems.length}`;
  }

  private autoLoadMoreSearchItems(): void {
    if (this.searchAutoLoadingMore || this.visibleSearchItems.length <= 0 || this.visibleSearchItems.length >= this.searchItems.length) {
      return;
    }
    this.searchAutoLoadingMore = true;
    this.showMoreSearchItems();
    setTimeout(() => {
      this.searchAutoLoadingMore = false;
    }, 360);
  }

  private async bootstrap(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'bootstrap start host=%{public}s', this.baseUrl);
    this.loading = true;
    this.error = '';
    this.status = '加载接口设置';
    const setting = await this.jm.remoteSetting.getRemoteSetting();
    if (setting.ok && setting.data !== undefined) {
      this.imgHost = setting.data.img_host;
      this.prefStore?.putString(PREF_KEY_IMG_HOST, setting.data.img_host);
      hilog.info(DOMAIN, TAG, 'setting ok imgHost=%{public}s', this.imgHost);
    } else {
      this.error = setting.message ?? '接口设置加载失败';
      hilog.error(DOMAIN, TAG, 'setting failed code=%{public}d msg=%{public}s', setting.code, this.error);
    }

    this.status = '加载首页';
    const home = await this.jm.comic.getHomeSwiperComicList();
    if (home.ok && home.data !== undefined) {
      this.rebuildHomeCards(home.data);
      this.prefStore?.putObject<HomeSwiperComicListItemResponse[]>(PREF_KEY_HOME, home.data);
      this.status = `已加载 ${home.data.length} 个分区`;
      hilog.info(DOMAIN, TAG, 'home ok sections=%{public}d', home.data.length);
    } else {
      this.error = home.message ?? '首页加载失败';
      this.status = '加载失败';
      hilog.error(DOMAIN, TAG, 'home failed code=%{public}d msg=%{public}s', home.code, this.error);
    }
    this.loading = false;
  }

  private async search(): Promise<void> {
    const keyword = this.searchText.trim();
    if (keyword.length === 0) {
      this.clearSearchResults();
      this.error = '先输入关键词';
      return;
    }
    const requestSeq = ++this.searchRequestSeq;
    this.lastSearchKeyword = keyword;
    this.loading = true;
    this.error = '';
    this.searchItems = [];
    this.visibleSearchItems = [];
    this.searchVisibleCount = SEARCH_VISIBLE_STEP;
    this.status = '搜索中';
    try {
      if (this.isNumericKeyword(keyword)) {
        const id = Number.parseInt(keyword, 10);
        const detail = await this.jm.comic.getComicDetail(id);
        if (requestSeq !== this.searchRequestSeq) {
          return;
        }
        if (detail.ok && detail.data !== undefined) {
          this.setSearchResults([this.toDetailCardItem(detail.data)]);
          this.status = '找到 1 条';
          return;
        }
      }
      const result = await this.jm.comic.getComicList(1, 'mr', keyword);
      if (requestSeq !== this.searchRequestSeq) {
        return;
      }
      if (result.ok && result.data !== undefined) {
        if (result.data.redirect_aid !== undefined && result.data.redirect_aid.length > 0) {
          const redirectId = Number.parseInt(result.data.redirect_aid, 10);
          if (!Number.isNaN(redirectId) && redirectId > 0) {
            const detail = await this.jm.comic.getComicDetail(redirectId);
            if (requestSeq !== this.searchRequestSeq) {
              return;
            }
            if (detail.ok && detail.data !== undefined) {
              this.setSearchResults([this.toDetailCardItem(detail.data)]);
              this.status = '找到 1 条';
              return;
            }
          }
        }
        const items = result.data.content.map((item: ListComicItemResponse) => this.toCardItem(item));
        this.setSearchResults(items);
        this.status = `找到 ${items.length} 条`;
      } else {
        this.error = result.message ?? '搜索失败';
        this.status = '搜索失败';
      }
    } catch (error) {
      if (requestSeq !== this.searchRequestSeq) {
        return;
      }
      this.searchItems = [];
      this.visibleSearchItems = [];
      this.error = error instanceof Error ? error.message : String(error);
      this.status = '搜索失败';
    } finally {
      if (requestSeq === this.searchRequestSeq) {
        this.loading = false;
      }
    }
  }

  private async openDetail(id: number): Promise<void> {
    if (Number.isNaN(id) || id <= 0) {
      this.error = '漫画 ID 无效';
      return;
    }
    if (this.rootContentTabIndex === this.tabIndexFromRootView(AppView.SEARCH)) {
      this.saveSearchScrollOffset();
    }
    this.detailId = id;
    this.detailComic = null;
    this.descExpanded = false;
    this.loading = true;
    this.error = '';
    this.status = `加载 JM${id}`;
    this.overlayView = AppView.DETAIL;
    this.playOverlayEnter();
    hilog.info(DOMAIN, TAG, 'open detail id=%{public}d', id);
    const result = await this.jm.comic.getComicDetail(id);
    if (result.ok && result.data !== undefined) {
      this.detailComic = result.data;
      this.detailFavorited = result.data.is_favorite;
      this.detailLiked = result.data.liked;
      this.status = '详情已加载';
      hilog.info(DOMAIN, TAG, 'detail ok id=%{public}d name=%{public}s', id, result.data.name);
      this.playDetailEnter();
      if (result.data.series.length > 0) {
        this.playChapterListEnter();
      }
    } else {
      this.error = result.message ?? '详情加载失败';
      this.status = '详情加载失败';
      hilog.error(DOMAIN, TAG, 'detail failed id=%{public}d msg=%{public}s', id, this.error);
    }
    this.loading = false;
  }

  private async openReader(id?: number, title?: string): Promise<void> {
    const targetId = id ?? this.detailId;
    if (targetId <= 0) {
      this.error = '章节 ID 无效';
      return;
    }
    this.loading = true;
    this.error = '';
    this.status = '加载图片';
    const result = await this.jm.comic.getComicPicList(targetId, '1');
    if (result.ok && result.data !== undefined) {
      this.readerImages = await this.buildReaderImages(
        targetId,
        result.data.list,
        result.data.__scrambleId,
        result.data.__speed
      );
      this.readerSource.reload(this.readerImages);
      this.readerTitle = title ?? `JM${targetId}`;
      this.overlayView = AppView.READER;
      this.playOverlayEnter();
      this.status = `已加载 ${result.data.list.length} 页`;
    } else {
      this.error = result.message ?? '阅读页加载失败';
      this.status = '阅读页加载失败';
    }
    this.loading = false;
  }

  private selectHost(source: string): void {
    if (source === this.baseUrl) {
      return;
    }
    this.baseUrl = source;
    this.jm.http.setBaseUrl(this.baseUrl);
    // 切换接口源后全部缓存失效，避免跨源串数据
    this.jm.cache.invalidateAll();
    this.status = '接口源已切换';
    this.error = '';
  }

  private async toggleFavorite(): Promise<void> {
    if (this.detailComic === null || this.favoriteBusy) {
      return;
    }
    this.favoriteBusy = true;
    const wasFavorited = this.detailFavorited;
    this.detailFavorited = !wasFavorited;
    const result = await this.jm.comic.collectComic(this.detailComic.id);
    if (!result.ok) {
      this.detailFavorited = wasFavorited;
      this.error = result.message ?? '收藏操作失败';
    } else {
      this.status = wasFavorited ? '已取消收藏' : '已加入收藏';
    }
    this.favoriteBusy = false;
  }

  private async toggleLike(): Promise<void> {
    if (this.detailComic === null || this.likeBusy) {
      return;
    }
    this.likeBusy = true;
    const wasLiked = this.detailLiked;
    this.detailLiked = !wasLiked;
    const result = await this.jm.comic.likeComic(this.detailComic.id);
    if (!result.ok) {
      this.detailLiked = wasLiked;
      this.error = result.message ?? '点赞操作失败';
    } else {
      this.status = wasLiked ? '已取消点赞' : '已点赞';
    }
    this.likeBusy = false;
  }
}
