import {
  ComicDetailResponse,
  ComicDetailSeriesListItemResponse,
  createJmApiClient,
  DEFAULT_API_LIST,
  HomeSwiperComicListItemResponse,
  ListComicItemResponse
} from '../api';
import { md5 } from '../api/Crypto';
import { DecodedReaderImage, getDecodedReaderImage } from '../reader/ReaderImageDecoder';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'JMApp';
const COLOR_BG = $r('app.color.jm_bg');
const COLOR_SURFACE = $r('app.color.jm_surface');
const COLOR_TEXT = $r('app.color.jm_text');
const COLOR_MUTED = $r('app.color.jm_muted');
const COLOR_PRIMARY = $r('app.color.jm_primary');
const COLOR_PRIMARY_SOFT = $r('app.color.jm_primary_soft');
const COLOR_ACCENT = $r('app.color.jm_accent');
const COLOR_BORDER = $r('app.color.jm_border');
const COLOR_SELECTED_BG = $r('app.color.jm_selected_bg');
const COLOR_TAB_MUTED = $r('app.color.jm_tab_muted');
const COLOR_SURFACE_SOFT = $r('app.color.jm_surface_soft');
const COLOR_WARM_SOFT = $r('app.color.jm_warm_soft');
const COLOR_DIVIDER = $r('app.color.jm_divider');
const TAB_BAR_WIDTH = 238;
const TAB_BAR_HEIGHT = 56;
const TAB_BAR_BOTTOM_MARGIN = 14;
const TAB_ITEM_WIDTH = TAB_BAR_WIDTH / 3;
const TAB_INDICATOR_WIDTH = 66;
const TAB_INDICATOR_HEIGHT = 44;
const TAB_CONTENT_BOTTOM_PADDING = 94;
const GRID_BOTTOM_PADDING = TAB_CONTENT_BOTTOM_PADDING + 54;
const SEARCH_VISIBLE_STEP = 24;
const HOME_VISIBLE_STEP = 12;
const ROOT_TAB_EXIT_DURATION = 140;
const ROOT_TAB_ENTER_DURATION = 280;
const ROOT_TAB_SWAP_DELAY = 145;
const ROOT_TAB_UNLOCK_DELAY = ROOT_TAB_ENTER_DURATION + 10;
const ROOT_TAB_EXIT_OPACITY = 0.88;
const ROOT_TAB_OFFSET = 12;
const TAB_MATERIAL_ANIMATION_DURATION = 230;

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

  aboutToAppear(): void {
    this.load();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pixelMap !== null && this.imageWidth > 0 && this.imageHeight > 0) {
        Image(this.pixelMap)
          .width('100%')
          .aspectRatio(this.imageWidth / this.imageHeight)
          .objectFit(ImageFit.Fill)
          .backgroundColor('#050505')
      } else if (this.error.length > 0) {
        Column({ space: 8 }) {
          Text(this.error)
            .fontSize(12)
            .fontColor('#FFFFFF')
          Button('重试')
            .height(34)
            .backgroundColor(COLOR_PRIMARY)
            .fontColor('#FFFFFF')
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
    try {
      const result: DecodedReaderImage = await getDecodedReaderImage(this.url, this.seed);
      this.pixelMap = result.pixelMap;
      this.imageWidth = result.width;
      this.imageHeight = result.height;
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
  @State readerTitle: string = '';
  @State overlayView: AppView = AppView.HOME;
  @State currentTabIndex: number = 0;
  @State rootContentTabIndex: number = 0;
  @State rootTabOpacity: number = 1;
  @State rootTabTranslateX: number = 0;
  @StorageProp('currentColorMode') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  private homeScroller: Scroller = new Scroller();
  private searchScroller: Scroller = new Scroller();
  private searchRequestSeq: number = 0;
  private lastSearchKeyword: string = '';
  private searchScrollY: number = 0;
  private homeAutoLoadingMore: boolean = false;
  private searchAutoLoadingMore: boolean = false;
  private rootTabSwitching: boolean = false;

  private isDarkMode(): boolean {
    return this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private tabBlurColorMode(): ThemeColorMode {
    return this.isDarkMode() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT;
  }

  private tabIndicatorColor(): string {
    return this.isDarkMode() ? '#503F4743' : '#72D3D8D6';
  }

  private tabIndicatorEffectColor(): string {
    return this.isDarkMode() ? '#203F4743' : '#2AD3D8D6';
  }

  private tabBarColor(): string {
    return this.isDarkMode() ? '#5A343B38' : '#60D0D6D3';
  }

  private tabBarEffectColor(): string {
    return this.isDarkMode() ? '#24343B38' : '#26D0D6D3';
  }

  private tabBarBorderColor(): string {
    return this.isDarkMode() ? '#26FFFFFF' : '#38AEB8B3';
  }

  private tabShadowColor(): string {
    return this.isDarkMode() ? '#22000000' : '#10000000';
  }

  aboutToAppear(): void {
    this.bootstrap();
  }

  onBackPress(): boolean {
    if (this.overlayView === AppView.READER) {
      this.overlayView = AppView.DETAIL;
      this.readerImages = [];
      this.readerTitle = '';
      return true;
    }
    if (this.overlayView === AppView.DETAIL) {
      this.overlayView = AppView.HOME;
      if (this.rootContentTabIndex === this.tabIndexFromRootView(AppView.SEARCH)) {
        this.restoreSearchScrollOffset();
      }
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
            .fontColor('#B3261E')
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

      this.floatingLightTabBar()
    }
    .layoutWeight(1)
    .width('100%')
    .alignContent(Alignment.Bottom)
  }

  @Builder
  private floatingLightTabBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.lightTabParticle()

      Row()
        .width(TAB_INDICATOR_WIDTH)
        .height(TAB_INDICATOR_HEIGHT)
        .margin({
          left: this.tabIndicatorLeft(),
          top: (TAB_BAR_HEIGHT - TAB_INDICATOR_HEIGHT) / 2
        })
        .borderRadius(TAB_INDICATOR_HEIGHT / 2)
        .backgroundColor(this.tabIndicatorColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN, {
          colorMode: this.tabBlurColorMode(),
          adaptiveColor: AdaptiveColor.DEFAULT,
          scale: 0.54
        })
        .backdropBlur(16)
        .backgroundEffect({
          radius: 17,
          saturation: 1,
          brightness: 1.04,
          color: this.tabIndicatorEffectColor(),
          adaptiveColor: AdaptiveColor.DEFAULT
        })
        .shadow({
          radius: 7,
          color: this.tabShadowColor(),
          offsetX: 0,
          offsetY: 1
        })
        .motionBlur({
          radius: 0.22,
          anchor: { x: 0.5, y: 0.5 }
        })
        .animation({
          duration: TAB_MATERIAL_ANIMATION_DURATION,
          curve: Curve.Smooth,
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
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN, {
      colorMode: this.tabBlurColorMode(),
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.58
    })
    .backdropBlur(22)
    .backgroundEffect({
      radius: 23,
      saturation: 1,
      brightness: 1.04,
      color: this.tabBarEffectColor(),
      adaptiveColor: AdaptiveColor.DEFAULT
    })
    .border({ width: 1, color: this.tabBarBorderColor() })
    .shadow({
      radius: 12,
      color: this.tabShadowColor(),
      offsetX: 0,
      offsetY: 6
    })
    .clip(true)
    .zIndex(10)
  }

  @Builder
  private lightTabParticle() {
    Particle({
      particles: [
        {
          emitter: {
            particle: {
              type: ParticleType.POINT,
              config: { radius: 2 },
              count: 12,
              lifetime: 900,
              lifetimeRange: 420
            },
            emitRate: 7,
            shape: ParticleEmitterShape.ELLIPSE,
            position: [this.tabParticleLeft(), 15],
            size: [34, 24]
          },
          color: {
            range: ['#99FFFFFF', '#66FFFFFF'],
            distributionType: DistributionType.GAUSSIAN
          },
          opacity: {
            range: [0.02, 0.08]
          },
          scale: {
            range: [0.55, 1.2]
          },
          velocity: {
            speed: [2, 18],
            angle: [235, 305]
          },
          acceleration: {
            speed: {
              range: [0, 5]
            },
            angle: {
              range: [260, 280]
            }
          }
        }
      ]
    })
      .width(TAB_BAR_WIDTH)
      .height(TAB_BAR_HEIGHT)
      .hitTestBehavior(HitTestMode.None)
      .animation({
        duration: TAB_MATERIAL_ANIMATION_DURATION,
        curve: Curve.Smooth,
        iterations: 1,
        playMode: PlayMode.Normal
      })
  }

  @Builder
  private floatingTabItem(icon: Resource, text: string, index: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 2 }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([this.currentTabIndex === index ? COLOR_PRIMARY : COLOR_TAB_MUTED])
          .fontWeight(FontWeight.Medium)
        Text(text)
          .fontSize(11)
          .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.currentTabIndex === index ? COLOR_PRIMARY : COLOR_TAB_MUTED)
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
    .animation({
      duration: 180,
      curve: Curve.Smooth,
      iterations: 1,
      playMode: PlayMode.Normal
    })
    .onClick(() => {
      this.switchRootTab(index);
    })
  }

  private tabIndicatorLeft(): number {
    return this.currentTabIndex * TAB_ITEM_WIDTH + (TAB_ITEM_WIDTH - TAB_INDICATOR_WIDTH) / 2;
  }

  private tabParticleLeft(): number {
    return this.currentTabIndex * TAB_ITEM_WIDTH + (TAB_ITEM_WIDTH - 34) / 2;
  }

  private switchRootTab(index: number): void {
    if (this.currentTabIndex === index || this.rootTabSwitching) {
      return;
    }
    this.scheduleRootTabSwitch(index);
  }

  @Builder
  private header() {
    Row() {
      if (this.canGoBack()) {
        Button({ type: ButtonType.Circle }) {
          Text('<')
            .fontSize(20)
            .fontColor(COLOR_PRIMARY)
            .fontWeight(FontWeight.Bold)
        }
          .width(36)
          .height(36)
          .backgroundColor(COLOR_PRIMARY_SOFT)
          .onClick(() => {
            this.goBack();
          })
      }
      Text(this.titleText())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.loading) {
        LoadingProgress()
          .width(28)
          .height(28)
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 16, right: 16 })
    .backgroundColor(COLOR_SURFACE)
    .border({ width: { bottom: 1 }, color: COLOR_BORDER })
  }

  @Builder
  private homeView() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.homeSections.length > 0) {
          this.homeShelfHeader()
          this.homeSectionTabs()
        }

        Scroll(this.homeScroller) {
          if (this.visibleHomeItems.length > 0) {
            this.homeComicGrid()
          } else {
            this.emptyState($r('sys.symbol.house'), '暂无内容', '换个分区或稍后刷新')
          }
        }
        .layoutWeight(1)
        .width('100%')
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
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  @Builder
  private homeSectionTabs() {
    List({ space: 8 }) {
      ForEach(this.homeSections, (section: HomeSwiperComicListItemResponse, index: number) => {
        ListItem() {
          Button(this.sectionChipTitle(section.title, index), { type: ButtonType.Normal, stateEffect: true })
            .height(34)
            .fontSize(12)
            .fontWeight(index === this.selectedSectionIndex ? FontWeight.Medium : FontWeight.Regular)
            .backgroundColor(index === this.selectedSectionIndex ? COLOR_PRIMARY_SOFT : COLOR_SURFACE)
            .fontColor(index === this.selectedSectionIndex ? COLOR_PRIMARY : COLOR_MUTED)
            .border({ width: 1, color: index === this.selectedSectionIndex ? COLOR_PRIMARY : COLOR_DIVIDER })
            .borderRadius(17)
            .padding({ left: 12, right: 12 })
            .animation({
              duration: 180,
              curve: Curve.Smooth,
              iterations: 1,
              playMode: PlayMode.Normal
            })
            .onClick(() => {
              this.setActiveHomeSection(index);
            })
        }
      }, (section: HomeSwiperComicListItemResponse, index: number) => `${section.id}-${index}`)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .height(42)
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .width('100%')
  }

  @Builder
  private homeShelfHeader() {
    Row() {
      Text(`${this.activeHomeTitle.length > 0 ? this.activeHomeTitle : '首页'} · ${this.homeTotalCount} 本`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_MUTED)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .width('100%')

      Button({ type: ButtonType.Circle }) {
        Text('↻')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY)
      }
      .width(34)
      .height(34)
      .backgroundColor(COLOR_PRIMARY_SOFT)
      .onClick(async () => {
        await this.bootstrap();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 18, right: 18, top: 8, bottom: 0 })
  }

  @Builder
  private searchViewV2() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Column() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(21)
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
              .fontWeight(FontWeight.Medium)
              .backgroundColor(COLOR_PRIMARY)
              .fontColor('#FFFFFF')
              .borderRadius(17)
              .padding({ left: 14, right: 14 })
              .onClick(async () => {
                this.getUIContext().getFocusController().clearFocus();
                await this.search();
              })
          }
          .height(48)
          .padding({ left: 14, right: 8 })
          .borderRadius(24)
          .backgroundColor(COLOR_SURFACE)
          .border({ width: 1, color: COLOR_DIVIDER })
        }
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })
        .backgroundColor(COLOR_BG)

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
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1)
    .width('100%')
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
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_PRIMARY)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(COLOR_PRIMARY_SOFT)
        .borderRadius(13)
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
      Column({ space: 14 }) {
        if (this.detailComic !== null) {
          Row({ space: 14 }) {
              Image(this.coverUrl(String(this.detailComic.id)))
                .width(126)
                .height(168)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .backgroundColor(COLOR_DIVIDER)

            Column({ space: 8 }) {
              Text(this.detailComic.name)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`JM${this.detailComic.id}`)
                .fontSize(12)
                .fontColor(COLOR_MUTED)
              Text(this.detailComic.author.join(', '))
                .fontSize(13)
                .fontColor(COLOR_MUTED)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Button('开始阅读')
                .height(40)
                .backgroundColor(COLOR_ACCENT)
                .fontColor('#FFFFFF')
                .onClick(async () => {
                  await this.openReader();
                })
            }
            .layoutWeight(1)
          }

          Text(this.detailComic.description)
            .fontSize(14)
            .fontColor(COLOR_TEXT)
            .lineHeight(22)
            .width('100%')

          this.tagLine('Tags', this.detailComic.tags)
          this.tagLine('Actors', this.detailComic.actors)
          this.chapterList()
        } else {
          Text(this.status)
            .fontSize(16)
            .fontColor(COLOR_MUTED)
            .padding(16)
        }
      }
      .padding(16)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private readerView() {
    List() {
      ForEach(this.readerImages, (item: ReaderImageItem) => {
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
      this.readerTitle = '';
    }
  }

  private scheduleRootTabSwitch(index: number): void {
    const previousIndex = this.currentTabIndex;
    const direction = index > previousIndex ? 1 : -1;
    this.rootTabSwitching = true;
    this.currentTabIndex = index;
    this.getUIContext().animateTo({ duration: ROOT_TAB_EXIT_DURATION, curve: Curve.Smooth }, () => {
      this.rootTabOpacity = ROOT_TAB_EXIT_OPACITY;
      this.rootTabTranslateX = -ROOT_TAB_OFFSET * direction;
    });
    setTimeout((): void => {
      this.rootContentTabIndex = index;
      this.resetRootView(this.rootViewFromTabIndex(index));
      this.rootTabOpacity = ROOT_TAB_EXIT_OPACITY;
      this.rootTabTranslateX = ROOT_TAB_OFFSET * direction;
      this.getUIContext().animateTo({ duration: ROOT_TAB_ENTER_DURATION, curve: Curve.Smooth }, () => {
        this.rootTabOpacity = 1;
        this.rootTabTranslateX = 0;
      });
      setTimeout((): void => {
        this.rootTabSwitching = false;
      }, ROOT_TAB_UNLOCK_DELAY);
    }, ROOT_TAB_SWAP_DELAY);
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
  private settingsView() {
    Scroll() {
      Column({ space: 14 }) {
        Text('接口源')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width('100%')
        Text(this.baseUrl)
          .fontSize(13)
          .fontColor(COLOR_MUTED)
          .width('100%')

        Column({ space: 10 }) {
          ForEach(DEFAULT_API_LIST, (source: string, index: number) => {
            this.sourceOption(source, index)
          }, (source: string) => source)
        }
        .width('100%')

        Button('重载首页')
          .height(42)
          .width('100%')
          .backgroundColor(COLOR_SELECTED_BG)
          .fontColor(COLOR_PRIMARY)
          .border({ width: 1, color: COLOR_BORDER })
          .onClick(async () => {
            await this.bootstrap();
          })
        Text(this.status)
          .fontSize(13)
          .fontColor(COLOR_MUTED)
          .width('100%')
      }
      .padding({ left: 16, right: 16, top: 16, bottom: TAB_CONTENT_BOTTOM_PADDING })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private sourceOption(source: string, index: number) {
    Row({ space: 12 }) {
      Column() {
        Text(`${index + 1}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(source === this.baseUrl ? COLOR_PRIMARY : COLOR_MUTED)
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(14)
      .backgroundColor(source === this.baseUrl ? COLOR_PRIMARY_SOFT : COLOR_SURFACE_SOFT)

      Column({ space: 4 }) {
        Text(source)
          .fontSize(14)
          .fontWeight(source === this.baseUrl ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(COLOR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(source === this.baseUrl ? '当前使用' : '点按切换')
          .fontSize(12)
          .fontColor(source === this.baseUrl ? COLOR_PRIMARY : COLOR_MUTED)
          .width('100%')
      }
      .layoutWeight(1)

      if (source === this.baseUrl) {
        Text('✓')
          .fontSize(18)
          .fontColor(COLOR_PRIMARY)
      }
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor(source === this.baseUrl ? COLOR_SELECTED_BG : COLOR_SURFACE)
    .border({ width: 1, color: source === this.baseUrl ? COLOR_PRIMARY : COLOR_BORDER })
    .onClick(() => {
      this.selectHost(source);
    })
  }

  @Builder
  private settingsViewV2() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 8 }) {
          Row() {
            Column({ space: 4 }) {
              Text('接口源')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Text(this.baseUrl)
                .fontSize(12)
                .fontColor(COLOR_MUTED)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)

            Button({ type: ButtonType.Circle }) {
              Text('↻')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_PRIMARY)
            }
            .width(40)
            .height(40)
            .backgroundColor(COLOR_PRIMARY_SOFT)
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
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .borderRadius(8)
        .backgroundColor(COLOR_SURFACE)
        .border({ width: 1, color: COLOR_DIVIDER })

        Column({ space: 0 }) {
          ForEach(DEFAULT_API_LIST, (source: string, index: number) => {
            this.sourceOptionV2(source, index)
          }, (source: string) => source)
        }
        .width('100%')
        .borderRadius(8)
        .backgroundColor(COLOR_SURFACE)
        .border({ width: 1, color: COLOR_DIVIDER })
        .clip(true)

        Column({ space: 6 }) {
          Text('开源地址')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT)
            .width('100%')
          Text('https://github.com/Dou-art/jm')
            .fontSize(13)
            .fontColor(COLOR_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('全程由AI完成')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .borderRadius(8)
        .backgroundColor(COLOR_SURFACE)
        .border({ width: 1, color: COLOR_DIVIDER })

        Text('切换源后会自动重新加载首页数据。')
          .fontSize(12)
          .fontColor(COLOR_MUTED)
          .width('100%')
          .padding({ left: 4, right: 4 })
      }
      .padding({ left: 16, right: 16, top: 16, bottom: TAB_CONTENT_BOTTOM_PADDING })
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
          .fontColor(source === this.baseUrl ? COLOR_PRIMARY : COLOR_MUTED)
      }
      .width(30)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(15)
      .backgroundColor(source === this.baseUrl ? COLOR_PRIMARY_SOFT : COLOR_SURFACE_SOFT)

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
          .fontColor(source === this.baseUrl ? COLOR_PRIMARY : COLOR_MUTED)
          .width('100%')
      }
      .layoutWeight(1)

      if (source === this.baseUrl) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(22)
          .fontColor([COLOR_PRIMARY])
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 12, right: 12 })
    .backgroundColor(source === this.baseUrl ? COLOR_SURFACE_SOFT : COLOR_SURFACE)
    .border({ width: { bottom: index === DEFAULT_API_LIST.length - 1 ? 0 : 1 }, color: COLOR_DIVIDER })
    .onClick(() => {
      this.selectHost(source);
    })
  }

  @Builder
  private homeComicGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.visibleHomeItems, (item: ComicCardItem) => {
        Column() {
          this.comicCard(item)
        }
        .width('31%')
      }, (item: ComicCardItem) => `home-${item.id}`)
    }
    .padding({ left: 16, right: 16, top: 8, bottom: GRID_BOTTOM_PADDING })
    .width('100%')
  }

  @Builder
  private searchComicGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.visibleSearchItems, (item: ComicCardItem) => {
        Column() {
          this.comicCard(item)
        }
        .width('31%')
      }, (item: ComicCardItem) => `search-${item.id}`)
    }
    .padding({ left: 16, right: 16, top: 8, bottom: GRID_BOTTOM_PADDING })
    .width('100%')
  }

  @Builder
  private comicCard(item: ComicCardItem) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 7 }) {
        Stack() {
          Image(this.coverUrl(item.id))
            .width('100%')
            .aspectRatio(0.75)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .backgroundColor(COLOR_SURFACE_SOFT)
        }
        .width('100%')
        .borderRadius(8)
        .clip(true)
        .shadow({
          radius: 8,
          color: '#14000000',
          offsetX: 0,
          offsetY: 3
        })

        Text(item.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.author.length > 0 ? item.author : 'Unknown')
          .fontSize(11)
          .fontColor(COLOR_MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .padding(0)
    .margin({ bottom: 18 })
    .backgroundColor(Color.Transparent)
    .borderRadius(8)
    .stateEffect(true)
    .onClick(async () => {
      hilog.info(DOMAIN, TAG, 'card clicked id=%{public}s name=%{public}s', item.id, item.name);
      await this.openDetail(Number.parseInt(item.id, 10));
    })
  }

  @Builder
  private tagLine(label: string, values: string[]) {
    if (values.length > 0) {
      Column({ space: 8 }) {
        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(values, (tag: string) => {
            Text(tag)
              .fontSize(12)
              .fontColor(COLOR_PRIMARY)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(COLOR_PRIMARY_SOFT)
              .borderRadius(14)
          }, (tag: string) => tag)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private chapterList() {
    if (this.detailComic !== null && this.detailComic.series.length > 0) {
      Column({ space: 8 }) {
        Text('章节')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .width('100%')
        ForEach(this.detailComic.series, (chapter: ComicDetailSeriesListItemResponse) => {
          Row() {
            Text(chapter.name)
              .fontSize(14)
              .fontColor(COLOR_TEXT)
              .layoutWeight(1)
            Text(`JM${chapter.id}`)
              .fontSize(12)
              .fontColor(COLOR_MUTED)
          }
          .height(44)
          .padding({ left: 12, right: 12 })
          .backgroundColor(COLOR_SURFACE)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_BORDER })
          .onClick(async () => {
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

  private rebuildHomeCards(sections: HomeSwiperComicListItemResponse[]): void {
    this.homeSections = sections;
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
      hilog.info(DOMAIN, TAG, 'setting ok imgHost=%{public}s', this.imgHost);
    } else {
      this.error = setting.message ?? '接口设置加载失败';
      hilog.error(DOMAIN, TAG, 'setting failed code=%{public}d msg=%{public}s', setting.code, this.error);
    }

    this.status = '加载首页';
    const home = await this.jm.comic.getHomeSwiperComicList();
    if (home.ok && home.data !== undefined) {
      this.rebuildHomeCards(home.data);
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
    this.loading = true;
    this.error = '';
    this.status = `加载 JM${id}`;
    this.overlayView = AppView.DETAIL;
    hilog.info(DOMAIN, TAG, 'open detail id=%{public}d', id);
    const result = await this.jm.comic.getComicDetail(id);
    if (result.ok && result.data !== undefined) {
      this.detailComic = result.data;
      this.status = '详情已加载';
      hilog.info(DOMAIN, TAG, 'detail ok id=%{public}d name=%{public}s', id, result.data.name);
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
      this.readerTitle = title ?? `JM${targetId}`;
      this.overlayView = AppView.READER;
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
    this.status = '接口源已切换';
    this.error = '';
  }
}
