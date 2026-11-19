// FLIDE · меню из плавающих окон.
// Тройной тап двумя пальцами → панель запуска → открывай сколько угодно окон.
// Окна таскаются за заголовок, меняют размер за уголок, сворачиваются.
// Игра под окнами продолжает работать: касания мимо окон уходят в UNO.
#import "FlideCore.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

BOOL gFlideMenuVisible = NO;

typedef NS_ENUM(NSInteger, FTab) { FTabMain, FTabTextures, FTabTexts, FTabFX, FTabFun, FTabEmotes, FTabPacks, FTabTools, FTabBoot, FTabSettings, FTabCount };

static NSString *tabTitle(FTab t) {
    switch (t) {
        case FTabMain:     return L(@"⚙️ Главное");
        case FTabBoot:     return L(@"🚀 Бут-лого");
        case FTabTextures: return L(@"🖼 Текстуры");
        case FTabTexts:    return L(@"🔤 Тексты");
        case FTabFX:       return L(@"✨ Эффекты");
        case FTabFun:      return L(@"🎉 Приколы");
        case FTabEmotes:   return L(@"😀 Эмоции и подарки");
        case FTabPacks:    return L(@"📦 Паки и темы");
        case FTabTools:    return L(@"📹 Стрим и скрины");
        case FTabSettings: return L(@"🛠 Настройки");
        default:           return @"";
    }
}
static NSString *tabIcon(FTab t) { return [tabTitle(t) componentsSeparatedByString:@" "].firstObject; }
static NSString *tabShort(FTab t) {
    switch (t) {
        case FTabMain:     return L(@"Главное");
        case FTabBoot:     return L(@"Бут-лого");
        case FTabTextures: return L(@"Текстуры");
        case FTabTexts:    return L(@"Тексты");
        case FTabFX:       return L(@"Эффекты");
        case FTabFun:      return L(@"Приколы");
        case FTabEmotes:   return L(@"Эмоции");
        case FTabPacks:    return L(@"Паки");
        case FTabTools:    return L(@"Стрим");
        case FTabSettings: return L(@"Настройки");
        default:           return @"";
    }
}

UIColor *FlideAccent(void) {
    NSString *hex = [FDefaults() stringForKey:kUIAccent];
    return hex ? FlideColorFromHex(hex) : [UIColor colorWithRed:0.56 green:0.49 blue:1 alpha:1];
}

static CGFloat uiScale(void) {
    NSInteger s = [FDefaults() objectForKey:kUIScale] ? [FDefaults() integerForKey:kUIScale] : 1;
    return s == 0 ? 0.9 : (s == 2 ? 1.15 : 1.0);
}

UIView *FlideGlass(CGFloat radius) {
    NSInteger style = [FDefaults() integerForKey:kUIGlass];
    if (style == 2) { // тёмная подложка — самый быстрый вариант
        UIView *v = [UIView new];
        v.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.1 alpha:0.96];
        v.layer.cornerRadius = radius;
        v.layer.cornerCurve = kCACornerCurveContinuous;
        v.clipsToBounds = YES;
        v.layer.borderWidth = 1;
        v.layer.borderColor = [FlideAccent() colorWithAlphaComponent:0.45].CGColor;
        return v;
    }
    UIVisualEffect *effect;
    Class glass = style == 0 ? NSClassFromString(@"UIGlassEffect") : nil;
    effect = glass ? [glass new] : [UIBlurEffect effectWithStyle:style == 1 ? UIBlurEffectStyleSystemThickMaterialDark
                                                                              : UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.32].CGColor;
    return v;
}

static UIView *glassContent(UIView *g) {
    return [g isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)g).contentView : g;
}

#pragma mark - окно-оверлей

@interface FlideOverlayWindow : UIWindow
@end
@implementation FlideOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil; // мимо окон — в игру
    return v;
}
@end

@interface FlideOverlayRoot : UIViewController
@end
@implementation FlideOverlayRoot
- (UIWindow *)gameWindow {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)s).windows)
                if (![w isKindOfClass:FlideOverlayWindow.class] && w.rootViewController && w.userInteractionEnabled) return w;
    return nil;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *g = [self gameWindow].rootViewController;
    return g ? g.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
@end

#pragma mark - строки таблиц

@interface FRow : NSObject
@property (nonatomic, copy) NSString *title, *subtitle, *defaultsKey, *sliderKey, *sliderFormat;
@property (nonatomic, assign) float sliderMin, sliderMax, sliderStep, sliderDefault;
@property (nonatomic, copy) void (^action)(UIView *source);
@property (nonatomic, copy) void (^changed)(void);
@property (nonatomic, strong) FlideItem *item;
@property (nonatomic, strong) UIColor *swatch;
@property (nonatomic, strong) NSArray *grid;                 // эмодзи-строки или пути PNG
@property (nonatomic, copy) void (^gridTap)(id thing, UIView *src);
@property (nonatomic, copy) void (^gridLong)(id thing);
@property (nonatomic, assign) BOOL destructive;
@property (nonatomic, copy) NSString *icon;   // эмодзи или SF Symbol для значка слева
@end
@implementation FRow
+ (instancetype)title:(NSString *)t sub:(NSString *)s action:(void (^)(UIView *))a {
    FRow *r = [FRow new]; r.title = t; r.subtitle = s; r.action = a; return r;
}
+ (instancetype)toggle:(NSString *)t sub:(NSString *)s key:(NSString *)k {
    FRow *r = [FRow new]; r.title = t; r.subtitle = s; r.defaultsKey = k; return r;
}
+ (instancetype)slider:(NSString *)t key:(NSString *)k min:(float)mn max:(float)mx step:(float)st def:(float)d fmt:(NSString *)fmt {
    FRow *r = [FRow new]; r.title = t; r.sliderKey = k; r.sliderMin = mn; r.sliderMax = mx; r.sliderStep = st;
    r.sliderDefault = d; r.sliderFormat = fmt; return r;
}
@end

@interface FSection : NSObject
@property (nonatomic, copy) NSString *title, *footer;
@property (nonatomic, strong) NSArray<FRow *> *rows;
@end
@implementation FSection
+ (instancetype)title:(NSString *)t rows:(NSArray *)rows footer:(NSString *)f {
    FSection *s = [FSection new]; s.title = t; s.rows = rows; s.footer = f; return s;
}
@end

#pragma mark - содержимое окна

typedef void (^FPick)(FlideItem *item);

@interface FlidePanelVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate,
    PHPickerViewControllerDelegate, UIColorPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, assign) FTab tab;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) NSArray<FSection *> *sections;
@property (nonatomic, strong) NSArray<FlideItem *> *items;
@property (nonatomic, copy) FPick picking;                 // режим выбора элемента на экране
@property (nonatomic, copy) NSString *pickTitle;
@property (nonatomic, copy) void (^photoHandler)(UIImage *img);
@property (nonatomic, strong) NSMutableSet<NSNumber *> *previewQueue;
@property (nonatomic, strong) NSTimer *refresh;
@property (nonatomic, copy) NSString *status;               // строка прогресса (темы)
@property (nonatomic, strong) NSMutableArray<FlideItem *> *previewTodo;
@property (nonatomic, strong) NSTimer *previewTimer;
@property (nonatomic, assign) NSInteger textureFilter;      // 0 все, 1 иконки, 2 фоны, 3 заменённые
@property (nonatomic, assign) BOOL pickingAccent;
@property (nonatomic, assign) BOOL selecting;               // режим «выбрать несколько»
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;  // имена текстур
@property (nonatomic, copy) void (^filesHandler)(NSArray<NSURL *> *urls);
@property (nonatomic, copy) NSString *openPreset;           // открытый для просмотра пресет
@end

@implementation FlidePanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.previewQueue = [NSMutableSet new];

    self.search = [UISearchBar new];
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.placeholder = L(@"Поиск");
    self.search.delegate = self;
    self.search.frame = CGRectMake(0, 0, 300, 44);

    self.previewTodo = [NSMutableArray new];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.estimatedRowHeight = 56;
    self.table.sectionHeaderTopPadding = 6;
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];

    if (self.tab == FTabTexts) {
        __weak typeof(self) ws = self;
        self.refresh = [NSTimer scheduledTimerWithTimeInterval:4.0 repeats:YES block:^(NSTimer *t) { [ws autoRefresh]; }];
    }
    [self reload];
}

- (void)dealloc {
    [self.refresh invalidate];
    [self.previewTimer invalidate];
    [[FlideEngine shared] releaseItems:self.items];
}

- (void)setItemsReleasingOld:(NSArray *)items {
    [[FlideEngine shared] releaseItems:self.items];
    self.items = items;
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [a dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)share:(NSArray *)things source:(UIView *)src {
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:things applicationActivities:nil];
    // сохранение в Фото требует отдельного разрешения в Info.plist — используем «Файлы»
    a.excludedActivityTypes = @[UIActivityTypeSaveToCameraRoll];
    a.popoverPresentationController.sourceView = src ?: self.view;
    a.popoverPresentationController.sourceRect = (src ?: self.view).bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)ask:(NSString *)title placeholder:(NSString *)ph done:(void (^)(NSString *text))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = ph; }];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *t = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length) done(t);
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)choose:(NSString *)title options:(NSArray<NSString *> *)opts source:(UIView *)src done:(void (^)(NSInteger i))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)opts.count; i++)
        [a addAction:[UIAlertAction actionWithTitle:opts[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(i); }]];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src ?: self.view;
    a.popoverPresentationController.sourceRect = (src ?: self.view).bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickPhoto:(void (^)(UIImage *))handler {
    self.photoHandler = handler;
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *p = results.firstObject.itemProvider;
    void (^h)(UIImage *) = self.photoHandler;
    self.photoHandler = nil;
    if (!h || ![p canLoadObjectOfClass:UIImage.class]) return;
    [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ if ([obj isKindOfClass:UIImage.class]) h((UIImage *)obj); });
    }];
}

- (void)startPicking:(NSString *)title then:(FPick)then {
    self.pickTitle = title;
    self.picking = then;
    [self setItemsReleasingOld:nil];
    self.search.text = @"";
    [self reload];
}

- (void)highlight:(FlideItem *)it {
    CGPoint p;
    if ([[FlideEngine shared] screenPointForItem:it point:&p]) [[FlideFX shared] highlightAt:p];
}

#pragma mark - данные

- (NSArray<FlideItem *> *)filtered {
    NSString *q = self.search.text;
    if (!q.length) return self.items;
    return [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FlideItem *it, id b) {
        return [it.name localizedCaseInsensitiveContainsString:q] || [it.detail localizedCaseInsensitiveContainsString:q];
    }]];
}

static NSString *friendlyPath(NSString *path) {
    NSArray *c = [path componentsSeparatedByString:@"/"];
    if (c.count <= 2) return [NSString stringWithFormat:@"📍 %@", [c componentsJoinedByString:@" › "]];
    return [NSString stringWithFormat:@"📍 %@ › %@", c[c.count - 2], c.lastObject];
}

static NSString *screenOf(NSString *path) {
    NSArray *c = [path componentsSeparatedByString:@"/"];
    return c.count >= 2 ? c[1] : (c.firstObject ?: @"?");
}

- (void)reload {
    __weak typeof(self) ws = self;
    NSMutableArray<FSection *> *S = [NSMutableArray new];
    self.table.tableHeaderView = nil;

    if (self.picking) { // общий режим «выбери элемент на экране»
        self.table.tableHeaderView = self.search;
        if (!self.items) [self setItemsReleasingOld:[[FlideEngine shared] scanElements]];
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[FRow title:L(@"← Назад") sub:nil action:^(UIView *v) {
            ws.picking = nil; [ws setItemsReleasingOld:nil]; [ws reload];
        }]];
        for (FlideItem *it in [self filtered]) {
            FRow *r = [FRow title:it.name.lastPathComponent sub:[NSString stringWithFormat:@"%@ · %@", it.detail, friendlyPath(it.name)]
                           action:^(UIView *v) {
                [ws highlight:it];
                FPick p = ws.picking;
                ws.picking = nil;
                [ws setItemsReleasingOld:nil];
                if (p) p(it);
                [ws reload];
            }];
            [rows addObject:r];
        }
        [S addObject:[FSection title:self.pickTitle rows:rows footer:L(@"Нажми — элемент подсветится в игре и выберется.")]];
        self.sections = S;
        [self.table reloadData];
        return;
    }

    switch (self.tab) {
    case FTabMain: [self buildMain:S]; break;
    case FTabBoot: [self buildBoot:S]; break;
    case FTabTextures: [self buildTextures:S]; break;
    case FTabTexts: [self buildTexts:S]; break;
    case FTabFX: [self buildFX:S]; break;
    case FTabFun: [self buildFun:S]; break;
    case FTabEmotes: [self buildEmotes:S]; break;
    case FTabPacks: [self buildPacks:S]; break;
    case FTabTools: [self buildTools:S]; break;
    case FTabSettings: [self buildSettings:S]; break;
    default: break;
    }
    self.sections = S;
    [self.table reloadData];
}

#pragma mark Главное

- (void)buildMain:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    if (![FDefaults() boolForKey:@"flide.help.hidden"])
        [S addObject:[FSection title:L(@"👋 Как пользоваться") rows:@[
            [FRow title:L(@"Окна") sub:L(@"Сверху — панель FLIDE. Нажми иконку — откроется окно. Окон можно открыть сколько угодно") action:nil],
            [FRow title:L(@"Двигать и сворачивать") sub:L(@"Тащи окно за заголовок, размер — за уголок справа внизу, ⌄ — свернуть") action:nil],
            [FRow title:L(@"Игра не мешает") sub:L(@"Мимо окон касания идут в игру — можно играть с открытым меню") action:nil],
            [FRow title:L(@"Понятно, скрыть подсказку") sub:nil action:^(UIView *v) {
                [FDefaults() setBool:YES forKey:@"flide.help.hidden"]; [ws reload];
            }],
        ] footer:nil]];
    FRow *base = [FRow title:L(@"🧹 Вернуть всё к базе") sub:L(@"Игра снова как оригинал — сразу, без перезапуска") action:^(UIView *v) { [ws confirmBase]; }];
    [S addObject:[FSection title:nil rows:@[base] footer:nil]];
    [S addObject:[FSection title:L(@"Чистота") rows:@[
        [FRow toggle:L(@"Без рекламы") sub:L(@"Межстраничная и баннеры. Нужен перезапуск") key:kNoAds],
    ] footer:L(@"Реклама за награду остаётся — смотришь, только если сам хочешь бонус.")]];
    if (FlideIsClone())
        [S addObject:[FSection title:L(@"Клон") rows:@[
            [FRow toggle:L(@"Маскировка Bundle ID") sub:[NSString stringWithFormat:@"%@ → com.mattel163.uno", FlideRealBundleID()] key:kSpoof],
        ] footer:L(@"Живёт рядом с обычным UNO. Нужен перезапуск.")]];
    FRow *fps = [FRow toggle:L(@"Макс. FPS") sub:L(@"До 120 Гц на ProMotion") key:kFPS120];
    fps.changed = ^{ [[FlideEngine shared] applyQuality]; };
    [S addObject:[FSection title:L(@"Качество") rows:@[
        [FRow toggle:L(@"HD-фильтрация") sub:L(@"Анизотропия 16×, трилинейная, резче мипмапы") key:kHD], fps,
    ] footer:L(@"HD-пак текстур — в окне «📦 Паки и темы».")]];
    NSArray *disabled = [FDefaults() arrayForKey:@"flide.disabled"];
    if (disabled.count)
        [S addObject:[FSection title:L(@"Защита от вылетов") rows:@[
            [FRow title:L(@"Восстановить отключённые функции") sub:[disabled componentsJoinedByString:@", "] action:^(UIView *v) {
                FlideGuardReset(); [ws toast:L(@"Включено обратно")]; [ws reload];
            }],
        ] footer:L(@"Эти функции вызвали вылет и были отключены автоматически.")]];
    FRow *reset = [FRow title:L(@"Сбросить все настройки FLIDE") sub:nil action:^(UIView *v) {
        for (NSString *k in @[kTexts, kAuras, kTextures, kHD, kFPS120, kFxTouch, kFxCombo, kFxStyle, kFxColor, kFunSpeed,
                              kFunRainbow, kFunTrail, kFunNight, kStreamerPaths, kMyAvatar])
            [FDefaults() removeObjectForKey:k];
        [NSFileManager.defaultManager removeItemAtPath:FlideDir(@"textures") error:nil];
        [[FlidePacks shared] stopAnimation];
        [[FlideFX shared] reloadRules];
        [ws toast:L(@"Сброшено. Перезапусти игру")];
        [ws reload];
    }];
    reset.destructive = YES;
    [S addObject:[FSection title:nil rows:@[reset] footer:L(@"FLIDE · только визуал на твоём устройстве.")]];
}

- (void)confirmBase {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"Вернуть всё к базе?")
        message:L(@"Текстуры, тексты, паки, ауры, ускорение, приколы и бут-лого вернутся к исходным. Язык и вид меню останутся.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Вернуть") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [FlideMenu resetToBase];
        [self toast:L(@"Готово — всё как в оригинале ✦")];
        [FlideMenu rebuildAll];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Бут-лого

- (void)buildBoot:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    NSArray *names = [FlideBoot animationNames];
    NSInteger cur = MIN((NSInteger)names.count - 1, [FDefaults() integerForKey:kBootAnim]);
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:
        [FRow toggle:L(@"Бут-лого при запуске") sub:L(@"Заставка FLIDE при открытии игры") key:kBoot],
        [FRow title:L(@"Анимация") sub:names[cur] action:^(UIView *v) {
            [ws choose:L(@"Анимация появления") options:names source:v done:^(NSInteger i) {
                [FDefaults() setInteger:i forKey:kBootAnim]; [ws reload];
            }];
        }],
        [FRow slider:L(@"Длительность") key:kBootSeconds min:1 max:5 step:0.5 def:2.2 fmt:L(@"%.1f сек")],
        [FRow title:L(@"Своя картинка") sub:[FlideBoot hasCustomImage] ? L(@"Стоит своя ✓") : L(@"Сейчас стандартное ✦ FLIDE") action:^(UIView *v) {
            [ws pickPhoto:^(UIImage *img) {
                [ws toast:[FlideBoot setCustomImage:img] ? L(@"Бут-лого обновлено ✦") : L(@"Не получилось")]; [ws reload];
            }];
        }], nil];
    if ([FlideBoot hasCustomImage])
        [rows addObject:[FRow title:L(@"Вернуть стандартное") sub:nil action:^(UIView *v) {
            [FlideBoot setCustomImage:nil]; [ws toast:L(@"Стандартное лого")]; [ws reload];
        }]];
    [rows addObject:[FRow title:L(@"▶︎ Показать сейчас") sub:nil action:^(UIView *v) { [FlideBoot showAnimated]; }]];
    [S addObject:[FSection title:L(@"Бут-лого") rows:rows footer:L(@"«Печатная машинка» работает со стандартным лого. PNG с прозрачностью смотрится лучше всего.")]];
}

#pragma mark Текстуры

- (void)buildTextures:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    self.table.tableHeaderView = self.search;
    if (!self.items) [self setItemsReleasingOld:[[FlideEngine shared] scanTextures]];
    NSDictionary *replaced = [FDefaults() dictionaryForKey:kTextures];
    NSString *anim = [[FlidePacks shared] animatedTexture];
    NSArray *kinds = @[L(@"Все"), L(@"🔣 Иконки"), L(@"🏞 Фоны"), L(@"✓ Заменённые")];
    FRow *kind = [FRow title:[NSString stringWithFormat:L(@"Показать: %@"), kinds[self.textureFilter]] sub:L(@"Иконки — маленькие картинки, фоны — большие") action:^(UIView *v) {
        [ws choose:L(@"Какие текстуры показать") options:kinds source:v done:^(NSInteger i) { ws.textureFilter = i; [ws reload]; }];
    }];
    kind.icon = @"line.3.horizontal.decrease.circle";
    FRow *refresh = [FRow title:L(@"Обновить список") sub:L(@"Открой нужный экран игры и обнови") action:^(UIView *v) {
        [ws setItemsReleasingOld:nil]; [ws.previewQueue removeAllObjects]; [ws reload];
    }];
    refresh.icon = @"arrow.clockwise";
    if (!self.selected) self.selected = [NSMutableSet new];
    FRow *sel = [FRow title:self.selecting ? [NSString stringWithFormat:L(@"Выбрано: %lu · готово"), (unsigned long)self.selected.count]
                                           : L(@"Выбрать несколько")
                        sub:self.selecting ? L(@"Нажми ещё раз, чтобы выйти из выбора") : L(@"Для автозамены сразу многих текстур")
                     action:^(UIView *v) { ws.selecting = !ws.selecting; if (!ws.selecting) [ws.selected removeAllObjects]; [ws reload]; }];
    sel.icon = @"checkmark.circle";
    NSMutableArray *top = [NSMutableArray arrayWithObjects:kind, refresh, sel, nil];
    if (self.selecting) {
        FRow *all = [FRow title:L(@"Выбрать все видимые") sub:nil action:^(UIView *v) {
            for (FlideItem *it in [ws filtered]) [ws.selected addObject:it.name];
            [ws reload];
        }];
        all.icon = @"checklist";
        [top addObject:all];
        if (self.selected.count) {
            FRow *go = [FRow title:[NSString stringWithFormat:L(@"Заменить выбранные (%lu)…"), (unsigned long)self.selected.count] sub:nil
                            action:^(UIView *v) { [ws batchMenu:v]; }];
            go.icon = @"wand.and.stars";
            [top addObject:go];
        }
    }
    NSString *rec = [[FlidePacks shared] recordingPreset];
    if (rec) {
        FRow *r = [FRow title:[NSString stringWithFormat:L(@"⏺ Запись в пресет «%@»"), [[FlidePacks shared] titleOf:rec]]
                          sub:L(@"Все замены сохраняются в пресет. Нажми, чтобы остановить") action:^(UIView *v) {
            [[FlidePacks shared] setRecordingPreset:nil]; [ws reload];
        }];
        [top addObject:r];
    }
    [S addObject:[FSection title:nil rows:top footer:nil]];
    NSMutableArray *rows = [NSMutableArray new];
    for (FlideItem *it in [self filtered]) {
        if (self.textureFilter) {
            NSArray *wh = [it.detail componentsSeparatedByString:@"×"];
            int w = [wh.firstObject intValue], h = wh.count > 1 ? [wh[1] intValue] : 0;
            if (self.textureFilter == 1 && MAX(w, h) > 256) continue;
            if (self.textureFilter == 2 && MAX(w, h) < 1024) continue;
            if (self.textureFilter == 3 && !replaced[it.name] && ![it.name isEqualToString:anim]) continue;
        }
        NSString *mark = [it.name isEqualToString:anim] ? L(@" · 🎞 анимация") : (replaced[it.name] ? L(@" · заменена ✓") : @"");
        BOOL on = [self.selected containsObject:it.name];
        NSString *title = self.selecting ? [NSString stringWithFormat:@"%@ %@", on ? @"☑︎" : @"☐", it.name] : it.name;
        FRow *r = [FRow title:title sub:[it.detail stringByAppendingString:mark] action:^(UIView *v) {
            if (ws.selecting) {
                if ([ws.selected containsObject:it.name]) [ws.selected removeObject:it.name]; else [ws.selected addObject:it.name];
                [ws reload];
                return;
            }
            FlideTextureEditor *e = [FlideTextureEditor editorForItem:it onChange:^{ it.preview = nil; [ws.previewQueue removeObject:@(it.instanceID)]; [ws reload]; }];
            [ws presentViewController:e animated:YES completion:nil];
        }];
        r.item = it;
        [rows addObject:r];
    }
    NSString *footer = FlideGuardTripped(@"preview")
        ? L(@"Превью отключены после вылета (включить: «Главное → Восстановить»). Замена работает.")
        : L(@"Нажми на текстуру — откроется редактор с предпросмотром: фото, фильтры, перекраска, анимация.");
    [S addObject:[FSection title:[NSString stringWithFormat:L(@"Текстуры · %lu"), (unsigned long)rows.count] rows:rows footer:footer]];
}

- (NSArray<FlideItem *> *)selectedItems {
    NSMutableArray *out = [NSMutableArray new];
    for (FlideItem *it in self.items) if ([self.selected containsObject:it.name]) [out addObject:it];
    return out;
}

- (void)batchDone:(NSUInteger)n {
    NSString *rec = [[FlidePacks shared] recordingPreset];
    NSString *msg = rec ? [NSString stringWithFormat:L(@"Заменено: %lu · сохранено в «%@»"), (unsigned long)n, [[FlidePacks shared] titleOf:rec]]
                        : [NSString stringWithFormat:L(@"Заменено: %lu"), (unsigned long)n];
    [self toast:msg];
    [self.selected removeAllObjects];
    self.selecting = NO;
    [self.previewQueue removeAllObjects];
    for (FlideItem *it in self.items) it.preview = nil;
    [self reload];
}

- (void)batchMenu:(UIView *)src {
    __weak typeof(self) ws = self;
    NSArray *targets = [self selectedItems];
    NSArray *opts = @[L(@"🔍 Автозамена по слову (ивент)"), L(@"🎮 Одной текстурой из игры"), L(@"📁 PNG из «Файлов»"),
                      L(@"🖼 Одной картинкой из Фото"), L(@"💾 Сохранить выбранные в пресет"), L(@"↺ Вернуть выбранным оригинал")];
    [self choose:L(@"Заменить выбранные") options:opts source:src done:^(NSInteger i) {
        FlidePacks *P = [FlidePacks shared];
        if (i == 0) {
            [ws ask:L(@"Слово ивента в названиях текстур") placeholder:L(@"например: halloween, xmas, event") done:^(NSString *kw) {
                NSDictionary *map = [P matchTargets:targets among:ws.items keyword:kw];
                if (!map.count) { [ws toast:L(@"Пар не найдено. Открой экран, где есть ивентовые текстуры, и обнови список")]; return; }
                [ws batchDone:[P replaceTargets:targets withSources:map]];
            }];
        } else if (i == 1) {
            [ws startTexturePick:^(FlideItem *src) {
                NSMutableDictionary *map = [NSMutableDictionary new];
                for (FlideItem *t in targets) if (t != src) map[t.name] = src;
                [ws batchDone:[P replaceTargets:targets withSources:map]];
            }];
        } else if (i == 2) {
            [ws pickFiles:^(NSArray<NSURL *> *urls) { [ws batchDone:[P replaceTargets:targets withFiles:urls]]; }];
        } else if (i == 3) {
            [ws pickPhoto:^(UIImage *img) {
                NSUInteger n = 0;
                for (FlideItem *t in targets) if ([[FlideEngine shared] replaceTexture:t withImage:img]) n++;
                [ws batchDone:n];
            }];
        } else if (i == 4) {
            [ws pickPreset:L(@"В какой пресет сохранить") then:^(NSString *pid) {
                NSUInteger n = 0;
                for (FlideItem *t in targets) @autoreleasepool {
                    UIImage *img = [[FlideEngine shared] imageOfTexture:t maxSide:4096];
                    if (!img) continue;
                    NSString *f = [[FlideDir(@"packs") stringByAppendingPathComponent:pid] stringByAppendingPathComponent:
                                   [FlideSafeName(t.name) stringByAppendingPathExtension:@"png"]];
                    if ([UIImagePNGRepresentation(img) writeToFile:f atomically:YES]) n++;
                }
                [ws toast:[NSString stringWithFormat:L(@"В пресет «%@» добавлено: %lu"), [P titleOf:pid], (unsigned long)n]];
                [ws.selected removeAllObjects]; ws.selecting = NO; [ws reload];
            }];
        } else {
            NSUInteger n = 0;
            for (FlideItem *t in targets) if ([[FlideEngine shared] resetTexture:t]) n++;
            [ws batchDone:n];
        }
    }];
}

// выбор одной текстуры-источника из этого же списка
- (void)startTexturePick:(void (^)(FlideItem *src))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"Текстура-источник")
        message:L(@"Введи часть названия текстуры, на которую заменить") preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = L(@"например: halloween_card"); }];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:L(@"Найти") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *q = a.textFields.firstObject.text;
        NSMutableArray *found = [NSMutableArray new];
        for (FlideItem *it in ws.items) if (q.length && [it.name localizedCaseInsensitiveContainsString:q]) [found addObject:it];
        if (!found.count) { [ws toast:L(@"Не найдено")]; return; }
        NSMutableArray *names = [NSMutableArray new];
        for (FlideItem *it in [found subarrayWithRange:NSMakeRange(0, MIN(found.count, 12))])
            [names addObject:[NSString stringWithFormat:@"%@ · %@", it.name, it.detail]];
        [ws choose:L(@"Заменить на") options:names source:ws.view done:^(NSInteger i) { done(found[i]); }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickFiles:(void (^)(NSArray<NSURL *> *urls))done {
    self.filesHandler = done;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder, UTTypePNG] asCopy:NO];
    p.allowsMultipleSelection = YES;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)pickPreset:(NSString *)title then:(void (^)(NSString *pid))done {
    FlidePacks *P = [FlidePacks shared];
    NSArray *packs = [P packs];
    NSMutableArray *names = [NSMutableArray arrayWithObject:L(@"＋ Новый пресет")];
    for (NSString *p in packs) [names addObject:[NSString stringWithFormat:@"%@ %@", [P iconOf:p], [P titleOf:p]]];
    __weak typeof(self) ws = self;
    [self choose:title options:names source:self.view done:^(NSInteger i) {
        if (i > 0) { done(packs[i - 1]); return; }
        [ws ask:L(@"Название пресета") placeholder:L(@"Например: Хэллоуин") done:^(NSString *t) { done([P createPreset:t icon:@"📦"]); }];
    }];
}

#pragma mark Тексты

- (void)buildTexts:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    self.table.tableHeaderView = self.search;
    if (!self.items) [self setItemsReleasingOld:[[FlideEngine shared] scanTexts]];
    NSDictionary *rules = [FDefaults() dictionaryForKey:kTexts];
    NSMutableArray *active = [NSMutableArray new];
    [rules enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSString *text, BOOL *stop) {
        [active addObject:[FRow title:[NSString stringWithFormat:@"«%@»", text] sub:friendlyPath(path) action:^(UIView *v) {
            [[FlideEngine shared] setOverride:nil forPath:path];
            [ws toast:L(@"Подмена убрана")];
            [ws reload];
        }]];
    }];
    if (active.count) [S addObject:[FSection title:L(@"✏️ Мои подмены") rows:active footer:L(@"Нажми, чтобы убрать.")]];

    // группируем по экранам игры
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary new];
    NSMutableArray *order = [NSMutableArray new];
    for (FlideItem *it in [self filtered]) {
        NSString *g = screenOf(it.name);
        if (!groups[g]) { groups[g] = [NSMutableArray new]; [order addObject:g]; }
        FRow *r = [FRow title:it.detail sub:friendlyPath(it.name) action:^(UIView *v) { [ws editText:it source:v]; }];
        r.item = it;
        [groups[g] addObject:r];
    }
    for (NSString *g in order)
        [S addObject:[FSection title:[NSString stringWithFormat:@"🖥 %@", g] rows:groups[g] footer:nil]];
    if (!order.count)
        [S addObject:[FSection title:L(@"Тексты на экране") rows:@[] footer:L(@"Пока пусто — открой экран игры, список обновится сам.")]];
    else
        ((FSection *)S.lastObject).footer = L(@"Список обновляется сам, когда открываешь новый экран (например, аватарку). Нажми строку — элемент подсветится в игре.");
}

- (void)autoRefresh {
    if (self.tab != FTabTexts || self.picking || self.presentedViewController || self.table.isDragging || self.search.isFirstResponder) return;
    NSArray *fresh = [[FlideEngine shared] scanTexts];
    NSMutableSet *a = [NSMutableSet new], *b = [NSMutableSet new];
    for (FlideItem *it in fresh) [a addObject:[it.name stringByAppendingString:it.detail]];
    for (FlideItem *it in self.items) [b addObject:[it.name stringByAppendingString:it.detail ?: @""]];
    if ([a isEqualToSet:b]) { [[FlideEngine shared] releaseItems:fresh]; return; }
    [self setItemsReleasingOld:fresh];
    [self reload];
}

- (void)editText:(FlideItem *)it source:(UIView *)src {
    [self highlight:it];
    NSString *path = it.name;
    NSString *before = [FDefaults() dictionaryForKey:kTexts][path];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"Текст в игре") message:[NSString stringWithFormat:L(@"%@\nМеняется вживую, пока печатаешь"), friendlyPath(path)]
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = before ?: it.detail;
        tf.clearButtonMode = UITextFieldViewModeAlways;
        [tf addTarget:self action:@selector(liveText:) forControlEvents:UIControlEventEditingChanged];
        objc_setAssociatedObject(tf, "path", path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Отмена") style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        [[FlideEngine shared] setOverride:before forPath:path];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:L(@"🕶 Скрыть как ник (стример)") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[FlideEngine shared] setOverride:before forPath:path];
        NSMutableArray *p = [[FDefaults() arrayForKey:kStreamerPaths] mutableCopy] ?: [NSMutableArray new];
        if (![p containsObject:path]) [p addObject:path];
        [FDefaults() setObject:p forKey:kStreamerPaths];
        [FDefaults() setBool:YES forKey:kStreamer];
        [self toast:L(@"Режим стримера: этот ник скрыт")];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:L(@"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[FlideEngine shared] setOverride:a.textFields.firstObject.text forPath:path];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)liveText:(UITextField *)tf {
    NSString *path = objc_getAssociatedObject(tf, "path");
    if (path) [[FlideEngine shared] setOverride:tf.text forPath:path];
}

#pragma mark Эффекты

- (void)buildFX:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    UIColor *color = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    FRow *style = [FRow title:L(@"Стиль") sub:FlideFxStyleName([FDefaults() integerForKey:kFxStyle]) action:^(UIView *v) {
        [ws pickStyle:^(FlideFxStyle s) { [FDefaults() setInteger:s forKey:kFxStyle]; [ws reload]; } source:v];
    }];
    FRow *col = [FRow title:L(@"Цвет") sub:FlideHexFromColor(color) action:^(UIView *v) { [ws pickColor]; }];
    col.swatch = color;
    [S addObject:[FSection title:L(@"Броски карт") rows:@[
        [FRow toggle:L(@"Искры при броске") sub:L(@"Свайп карты — вспышка частиц") key:kFxTouch],
        [FRow toggle:L(@"Комбо") sub:L(@"3+ карты подряд — ударная волна и COMBO ×N") key:kFxCombo],
        style, col,
    ] footer:nil]];

    NSMutableArray *auras = [NSMutableArray new];
    [[FDefaults() dictionaryForKey:kAuras] enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSDictionary *cfg, BOOL *stop) {
        FRow *r = [FRow title:[NSString stringWithFormat:@"%@  %@", FlideFxStyleName([cfg[@"style"] integerValue]), path.lastPathComponent]
                          sub:friendlyPath(path) action:^(UIView *v) {
            NSMutableDictionary *d = [[FDefaults() dictionaryForKey:kAuras] mutableCopy];
            [d removeObjectForKey:path];
            [FDefaults() setObject:d ?: @{} forKey:kAuras];
            [[FlideFX shared] reloadRules];
            [ws reload];
        }];
        r.swatch = FlideColorFromHex(cfg[@"color"]);
        [auras addObject:r];
    }];
    [auras addObject:[FRow title:L(@"＋ Добавить ауру к элементу") sub:nil action:^(UIView *v) {
        [ws startPicking:L(@"Выбери элемент для ауры") then:^(FlideItem *it) {
            NSString *path = it.name;
            [ws pickStyle:^(FlideFxStyle s) {
                NSMutableDictionary *d = [[FDefaults() dictionaryForKey:kAuras] mutableCopy] ?: [NSMutableDictionary new];
                d[path] = @{ @"style": @(s), @"color": [FDefaults() stringForKey:kFxColor] ?: @"#7CF7FF", @"radius": @46 };
                [FDefaults() setObject:d forKey:kAuras];
                [[FlideFX shared] reloadRules];
                [ws toast:L(@"Аура добавлена ✦")];
                [ws reload];
            } source:ws.view];
        }];
    }]];
    [S addObject:[FSection title:L(@"Ауры") rows:auras footer:L(@"Выбери подсветку хода — аура будет только у того, кто ходит. Нажми на ауру, чтобы удалить.")]];
}

- (void)pickStyle:(void (^)(FlideFxStyle))done source:(UIView *)src {
    NSMutableArray *names = [NSMutableArray new];
    for (NSInteger s = 0; s < FlideFxStyleCount; s++) [names addObject:FlideFxStyleName(s)];
    [self choose:L(@"Стиль эффекта") options:names source:src done:^(NSInteger i) { done(i); }];
}

- (void)pickColor {
    UIColorPickerViewController *p = [UIColorPickerViewController new];
    p.selectedColor = self.pickingAccent ? FlideAccent() : FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    p.supportsAlpha = NO;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    if (self.pickingAccent) {
        self.pickingAccent = NO;
        [FDefaults() setObject:FlideHexFromColor(vc.selectedColor) forKey:kUIAccent];
        [FlideMenu rebuildAll];
        return;
    }
    [FDefaults() setObject:FlideHexFromColor(vc.selectedColor) forKey:kFxColor];
    [self reload];
}

#pragma mark Приколы

- (void)buildFun:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FRow *speed = [FRow slider:L(@"Скорость игры") key:kFunSpeed min:1 max:5 step:0.5 def:1 fmt:@"×%.1f"];
    speed.changed = ^{ [[FlideFun shared] applySpeed]; };
    [S addObject:[FSection title:L(@"Скорость") rows:@[speed]
                          footer:L(@"Ускоряет анимации и меню. В онлайне сервер быстрее не станет — ход соперников всё равно ждёт сервер.")]];
    FRow *night = [FRow slider:L(@"Ночной фильтр") key:kFunNight min:0 max:0.45 step:0.05 def:0 fmt:@"%.0f%%"];
    night.sliderFormat = @"percent";
    night.changed = ^{ [[FlideFun shared] applyNight]; };
    [S addObject:[FSection title:L(@"Экран") rows:@[
        [FRow toggle:L(@"🌈 Радужные тексты") sub:L(@"Все надписи переливаются") key:kFunRainbow],
        [FRow toggle:L(@"✨ След пальца") sub:L(@"Светящийся хвост за пальцем") key:kFunTrail],
        [FRow toggle:L(@"📳 Вибро-отклик") sub:L(@"Лёгкий отклик при броске, сильный при комбо") key:kFunHaptic],
        [FRow toggle:L(@"💥 Тряска при комбо") sub:L(@"Экран вздрагивает на COMBO") key:kFunShake],
        [FRow toggle:@"FPS" sub:L(@"Счётчик кадров в углу") key:kFunFPS],
        [FRow toggle:L(@"🕐 Часы") sub:L(@"Время в углу экрана") key:kFunClock],
        night,
    ] footer:nil]];
    [S addObject:[FSection title:L(@"Вечеринка") rows:@[
        [FRow toggle:L(@"🪩 Режим вечеринки") sub:L(@"Радужные тексты + след + конфетти каждые 20 сек") key:kFunParty],
        [FRow toggle:L(@"📳 Встряхни — конфетти") sub:L(@"Потряси телефон, и посыплется конфетти") key:kFunShakeConfetti],
        [FRow toggle:L(@"🎲 Случайный эффект броска") sub:L(@"Каждый бросок — новый стиль и цвет") key:kFxRandom],
    ] footer:nil]];
    NSArray *vs = @[L(@"🎊 Конфетти"), L(@"🎆 Фейерверк"), L(@"🎊+🎆 Всё сразу")];
    NSInteger vi = MIN(2, [FDefaults() integerForKey:kVictoryStyle]);
    NSString *vt = [FDefaults() stringForKey:kVictoryText];
    [S addObject:[FSection title:L(@"Победа") rows:@[
        [FRow toggle:L(@"Анимация победы") sub:L(@"Срабатывает, когда на экране появляется «победа / win»") key:kFunConfetti],
        [FRow title:L(@"Эффект") sub:vs[vi] action:^(UIView *v) {
            [ws choose:L(@"Эффект победы") options:vs source:v done:^(NSInteger i) { [FDefaults() setInteger:i forKey:kVictoryStyle]; [ws reload]; }];
        }],
        [FRow title:L(@"Надпись") sub:vt.length ? vt : L(@"нет") action:^(UIView *v) {
            [ws ask:L(@"Надпись при победе") placeholder:L(@"Например: ИЗИ 😎") done:^(NSString *t) { [FDefaults() setObject:t forKey:kVictoryText]; [ws reload]; }];
        }],
        [FRow title:L(@"▶︎ Показать сейчас") sub:nil action:^(UIView *v) { [[FlideFun shared] victoryNow]; }],
    ] footer:nil]];
    NSDictionary *st = [[FlideFun shared] stats];
    int secs = [st[@"seconds"] intValue];
    [S addObject:[FSection title:L(@"📊 Статистика FLIDE") rows:@[
        [FRow title:[NSString stringWithFormat:L(@"⏱ В игре: %dч %02dм"), secs / 3600, (secs / 60) % 60] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:L(@"🃏 Бросков карт: %d"), [st[@"throws"] intValue]] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:L(@"🔥 Рекорд комбо: ×%d"), [st[@"bestCombo"] intValue]] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:L(@"🏆 Побед замечено: %d"), [st[@"wins"] intValue]] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:L(@"🚀 Запусков: %d"), [st[@"launches"] intValue]] sub:nil action:nil],
        [FRow title:L(@"Сбросить статистику") sub:nil action:^(UIView *v) { [[FlideFun shared] resetStats]; [ws reload]; }],
    ] footer:L(@"Считается только на этом устройстве.")]];
}

#pragma mark Эмоции и подарки

- (void)buildEmotes:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FlideEmotes *E = [FlideEmotes shared];
    NSString *me = [FDefaults() stringForKey:kMyAvatar];
    [S addObject:[FSection title:nil rows:@[
        [FRow title:L(@"👤 Мой аватар") sub:me ? friendlyPath(me) : L(@"Не выбран — эмоции появятся внизу по центру") action:^(UIView *v) {
            [ws startPicking:L(@"Выбери свой аватар") then:^(FlideItem *it) { [FDefaults() setObject:it.name forKey:kMyAvatar]; }];
        }],
    ] footer:L(@"🔒 Только визуал: видишь только ты. Никому ничего не отправляется и ничего не даёт.")]];

    FRow *emotes = [FRow new];
    emotes.grid = [[E builtinEmotes] arrayByAddingObjectsFromArray:[E customEmotes]];
    emotes.gridTap = ^(id thing, UIView *src) { [E sendEmote:thing]; };
    emotes.gridLong = ^(id thing) {
        if ([thing hasPrefix:@"/"]) { [E removeCustomEmote:thing]; [ws reload]; }
    };
    [S addObject:[FSection title:L(@"Эмоции") rows:@[emotes,
        [FRow title:L(@"＋ Своя эмоция из Фото") sub:nil action:^(UIView *v) {
            [ws pickPhoto:^(UIImage *img) { [E addCustomEmote:img]; [ws reload]; }];
        }],
    ] footer:L(@"Нажми — эмоция всплывёт над твоим аватаром. Свою — удержи, чтобы удалить.")]];

    NSMutableArray *gifts = [NSMutableArray arrayWithArray:[E builtinGifts]];
    [gifts addObjectsFromArray:[E customGifts]];
    FRow *giftRow = [FRow new];
    giftRow.grid = gifts;
    giftRow.gridTap = ^(id gift, UIView *src) {
        [ws choose:L(@"Кому подарок (только визуал)") options:@[L(@"🎁 Себе"), L(@"👆 Выбрать на экране")] source:src done:^(NSInteger i) {
            if (i == 0) { [E sendGift:gift toPoint:nil]; return; }
            [ws startPicking:L(@"Кому отправить подарок") then:^(FlideItem *it) {
                CGPoint p;
                BOOL ok = [[FlideEngine shared] screenPointForItem:it point:&p];
                [E sendGift:gift toPoint:ok ? [NSValue valueWithCGPoint:p] : nil];
            }];
        }];
    };
    giftRow.gridLong = ^(id thing) {
        if ([thing isKindOfClass:NSString.class] && [thing hasPrefix:@"/"]) { [E removeCustomGift:thing]; [ws reload]; }
    };
    [S addObject:[FSection title:L(@"Подарки") rows:@[giftRow,
        [FRow title:L(@"＋ Свой подарок из Фото") sub:nil action:^(UIView *v) {
            [ws pickPhoto:^(UIImage *img) { [E addCustomGift:img]; [ws reload]; }];
        }],
    ] footer:L(@"Наши собственные анимации — бесплатно и только у тебя на экране.")]];
}

#pragma mark Паки и темы

- (void)buildPacks:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FlidePacks *P = [FlidePacks shared];
    NSArray *names = FlideFilterNames();
    NSMutableArray *themes = [NSMutableArray new];
    if (P.themeRunning)
        [themes addObject:[FRow title:L(@"⏹ Остановить") sub:self.status action:^(UIView *v) { [P cancelTheme]; [ws reload]; }]];
    for (NSInteger i = 1; i < (NSInteger)names.count; i++)
        [themes addObject:[FRow title:names[i] sub:nil action:^(UIView *v) { [ws runTheme:i]; }]];
    [themes addObject:[FRow title:L(@"↺ Вернуть всем оригинал") sub:nil action:^(UIView *v) { [ws runTheme:0]; }]];
    [S addObject:[FSection title:L(@"🎨 Тема в одно нажатие") rows:themes
                          footer:L(@"Фильтр сразу ко всем текстурам на экране. Идёт по одной, игра не зависает. Шрифты не трогаются.")]];

    NSString *active = [FDefaults() stringForKey:kPackActive];
    NSString *rec = [P recordingPreset];

    if (self.openPreset) { // просмотр одного пресета
        NSString *pid = self.openPreset;
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[FRow title:L(@"← Назад") sub:nil action:^(UIView *v) {
            ws.openPreset = nil; [ws reload];
        }]];
        for (NSString *t in [P texturesIn:pid]) {
            FRow *r = [FRow title:t sub:L(@"Нажми, чтобы убрать из пресета") action:^(UIView *v) {
                [P removeTexture:t fromPreset:pid]; [ws reload];
            }];
            r.icon = @"photo";
            [rows addObject:r];
        }
        [S addObject:[FSection title:[NSString stringWithFormat:@"%@ %@", [P iconOf:pid], [P titleOf:pid]] rows:rows
                              footer:L(@"Добавлять: «🖼 Текстуры» → «Выбрать несколько» → «Сохранить в пресет», или включи запись.")]];
        return;
    }

    NSMutableArray *packs = [NSMutableArray new];
    for (NSString *p in [P packs]) {
        BOOL on = [p isEqualToString:active], recording = [p isEqualToString:rec];
        NSString *sub = [NSString stringWithFormat:L(@"%lu текстур%@%@"), (unsigned long)[P countOf:p],
                         on ? L(@" · включён") : @"", recording ? L(@" · ⏺ запись") : @""];
        FRow *r = [FRow title:[NSString stringWithFormat:@"%@ %@", [P iconOf:p], [P titleOf:p]] sub:sub action:^(UIView *v) {
            NSArray *opts = @[on ? L(@"Выключить") : L(@"▶︎ Применить"),
                              recording ? L(@"⏹ Остановить запись") : L(@"⏺ Записывать замены сюда"),
                              L(@"✏️ Переименовать"), L(@"🎨 Иконка"), L(@"👁 Что внутри"), L(@"⧉ Дублировать"),
                              L(@"Поделиться (zip)"), L(@"Удалить")];
            [ws choose:[P titleOf:p] options:opts source:v done:^(NSInteger i) {
                NSString *dir = [FlideDir(@"packs") stringByAppendingPathComponent:p];
                switch (i) {
                    case 0:
                        if (on) { [P deactivatePack]; [ws toast:L(@"Пак выключен")]; }
                        else [ws toast:[NSString stringWithFormat:L(@"Подставлено текстур: %lu"), (unsigned long)[P activatePack:p]]];
                        break;
                    case 1: [P setRecordingPreset:recording ? nil : p];
                        if (!recording) [ws toast:L(@"Запись включена: все замены текстур попадут в этот пресет")];
                        break;
                    case 2: [ws ask:L(@"Новое название") placeholder:[P titleOf:p] done:^(NSString *t) { [P rename:p to:t]; [ws reload]; }]; return;
                    case 3: {
                        NSArray *icons = @[@"📦", @"🎃", @"🎄", @"💖", @"🌸", @"🌌", @"🔥", @"❄️", @"👑", @"🎮", @"⭐️", @"🌴"];
                        [ws choose:L(@"Иконка") options:icons source:v done:^(NSInteger k) { [P setIcon:icons[k] of:p]; [ws reload]; }];
                        return;
                    }
                    case 4: ws.openPreset = p; break;
                    case 5: [P duplicate:p]; break;
                    case 6: { NSURL *zip = [P zipFolder:dir]; if (zip) [ws share:@[zip] source:v]; return; }
                    default:
                        if (on) [P deactivatePack];
                        if (recording) [P setRecordingPreset:nil];
                        [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
                }
                [ws reload];
            }];
        }];
        [packs addObject:r];
    }
    FRow *add = [FRow title:L(@"＋ Новый пресет") sub:L(@"Пустой — потом добавишь замены") action:^(UIView *v) {
        [ws ask:L(@"Название пресета") placeholder:L(@"Например: Хэллоуин") done:^(NSString *t) {
            NSString *pid = [P createPreset:t icon:@"📦"];
            [P setRecordingPreset:pid];
            [ws toast:L(@"Пресет создан, запись включена — меняй текстуры, они сохранятся сюда")];
            [ws reload];
        }];
    }];
    add.icon = @"plus.circle";
    [packs addObject:add];
    [packs addObject:[FRow title:L(@"📥 Импорт пака из «Файлов»") sub:L(@"Папка с PNG (распакуй zip в «Файлах»)") action:^(UIView *v) { [ws importPack]; }]];
    [packs addObject:[FRow title:L(@"💾 Сохранить мою тему как пак") sub:L(@"Замены + тексты + ауры + цвета") action:^(UIView *v) {
        [ws ask:L(@"Название пака") placeholder:L(@"Моя тема") done:^(NSString *t) {
            NSURL *u = [P savePresetNamed:t];
            if (u) [P rename:u.lastPathComponent to:t];
            NSURL *zip = u ? [P zipFolder:u.path] : nil;
            [ws reload];
            if (zip) [ws share:@[zip] source:v];
        }];
    }]];
    [S addObject:[FSection title:L(@"🗂 Пресеты") rows:packs
                          footer:L(@"Пресет — набор замен в одно нажатие. Создай, включи запись и меняй текстуры (или «Выбрать несколько» → автозамена). Потом просто «Применить».")]];

    [S addObject:[FSection title:L(@"✨ HD-пак (апскейл нейросетью)") rows:@[
        [FRow title:L(@"1. Экспортировать все текстуры в zip") sub:L(@"Сохрани zip в «Файлы»") action:^(UIView *v) {
            NSUInteger n = [[FlideEngine shared] exportAllTextures];
            NSURL *zip = [P zipFolder:FlideDir(@"export")];
            [ws toast:[NSString stringWithFormat:L(@"Текстур: %lu"), (unsigned long)n]];
            if (zip) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws share:@[zip] source:v]; });
        }],
        [FRow title:L(@"2. Загрузи zip в Release с тегом hd-src") sub:L(@"GitHub → Releases → hd-src → прикрепить export.zip") action:nil],
        [FRow title:@"3. Actions → HD texture pack → Run" sub:L(@"Real-ESRGAN улучшит каждую текстуру") action:nil],
        [FRow title:L(@"4. Скачай FLIDE-HD-pack, распакуй и импортируй") sub:L(@"«📥 Импорт пака» → включи пак") action:nil],
    ] footer:L(@"Нейросеть убирает мыло и артефакты сжатия. Размер текстур сохраняется, поэтому ничего не съезжает.")]];

    NSString *anim = [P animatedTexture];
    [S addObject:[FSection title:L(@"🎞 Анимированный стол") rows:anim ? @[
        [FRow title:[NSString stringWithFormat:L(@"Анимация: %@"), anim] sub:L(@"Нажми, чтобы остановить") action:^(UIView *v) {
            [P stopAnimation]; [ws toast:L(@"Остановлено. Оригинал — после перезапуска")]; [ws reload];
        }]] : @[]
                          footer:L(@"Открой «🖼 Текстуры», выбери фон стола и нажми «🎞 Анимация»: подойдут GIF или несколько фото по порядку.")]];
}

- (void)runTheme:(NSInteger)filter {
    __weak typeof(self) ws = self;
    [[FlidePacks shared] applyTheme:filter progress:^(NSUInteger done, NSUInteger total) {
        ws.status = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)done, (unsigned long)total];
        if (done == total) { ws.status = nil; [ws toast:L(@"Тема применена ✦")]; }
        if (done % 10 == 0 || done == total) [ws reload];
    }];
    [self reload];
}

- (void)importPack {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder, UTTypePNG] asCopy:NO];
    p.allowsMultipleSelection = YES;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.filesHandler) { void (^h)(NSArray *) = self.filesHandler; self.filesHandler = nil; h(urls); return; }
    __weak typeof(self) ws = self;
    NSString *guess = urls.count == 1 && urls.firstObject.hasDirectoryPath ? urls.firstObject.lastPathComponent : L(@"Мой пак");
    [self ask:L(@"Название пака") placeholder:guess done:^(NSString *t) {
        NSUInteger n = [[FlidePacks shared] importFromURLs:urls asPack:t];
        [ws toast:[NSString stringWithFormat:L(@"Импортировано PNG: %lu"), (unsigned long)n]];
        [ws reload];
    }];
}

#pragma mark Стрим и скрины

- (void)buildTools:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FlideTools *T = [FlideTools shared];
    NSMutableArray *stream = [NSMutableArray arrayWithObject:[FRow toggle:L(@"🕶 Режим стримера") sub:L(@"Выбранные ники → «Игрок 1/2/3»") key:kStreamer]];
    for (NSString *p in [FDefaults() arrayForKey:kStreamerPaths]) {
        [stream addObject:[FRow title:p.lastPathComponent sub:friendlyPath(p) action:^(UIView *v) {
            NSMutableArray *a = [[FDefaults() arrayForKey:kStreamerPaths] mutableCopy];
            [a removeObject:p];
            [FDefaults() setObject:a forKey:kStreamerPaths];
            [ws reload];
        }]];
    }
    [S addObject:[FSection title:L(@"Стрим") rows:stream footer:L(@"Добавить ник: «🔤 Тексты» → нажми на ник → «Скрыть как ник». Тут нажми, чтобы убрать.")]];

    UIView *overlay = [FlideMenu overlayRoot];
    [S addObject:[FSection title:L(@"Скрины и клипы") rows:@[
        [FRow title:L(@"📸 Чистый скриншот") sub:L(@"Кадр игры без окон FLIDE") action:^(UIView *v) {
            UIImage *img = [T cleanScreenshot];
            if (img) [ws share:@[img] source:v]; else [ws toast:L(@"Не получилось")];
        }],
        [FRow title:T.clipBuffering ? L(@"⏺ Буфер клипов: включён") : L(@"⏺ Включить буфер клипов") sub:L(@"Пишет последние 30 секунд") action:^(UIView *v) {
            [T setClipBuffering:!T.clipBuffering completion:^(NSError *e) {
                [ws toast:e ? e.localizedDescription : (T.clipBuffering ? L(@"Буфер включён") : L(@"Буфер выключен"))];
                [ws reload];
            }];
        }],
        [FRow title:L(@"🎬 Сохранить последние 30 сек") sub:nil action:^(UIView *v) {
            if (!T.clipBuffering) { [ws toast:L(@"Сначала включи буфер")]; return; }
            [T exportClip:^(NSURL *url, NSError *e) {
                if (url) [ws share:@[url] source:v]; else [ws toast:e.localizedDescription ?: L(@"Ошибка")];
            }];
        }],
    ] footer:L(@"Файлы также лежат в FLIDE/shots и FLIDE/clips.")]];

    [S addObject:[FSection title:L(@"Рисование и стикеры") rows:@[
        [FRow title:L(@"🖍 Рисовать поверх экрана") sub:L(@"✓ — закончить, рисунок останется") action:^(UIView *v) { [T toggleDrawingIn:overlay]; }],
        [FRow title:L(@"😀 Стикер-эмодзи") sub:nil action:^(UIView *v) {
            NSArray *em = [[FlideEmotes shared] builtinEmotes];
            [ws choose:L(@"Стикер") options:em source:v done:^(NSInteger i) {
                UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(160, 160)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
                    NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:130]};
                    CGSize s = [em[i] sizeWithAttributes:a];
                    [em[i] drawAtPoint:CGPointMake((160 - s.width) / 2, (160 - s.height) / 2) withAttributes:a];
                }];
                [T addSticker:img in:overlay];
            }];
        }],
        [FRow title:L(@"🖼 Стикер из Фото") sub:nil action:^(UIView *v) { [ws pickPhoto:^(UIImage *img) { [T addSticker:img in:overlay]; }]; }],
        [FRow title:L(@"Убрать все стикеры") sub:nil action:^(UIView *v) { [T clearStickers]; }],
    ] footer:L(@"Стикер: тащи, щипком меняй размер, двумя пальцами крути, удержи — удалить.")]];
}

#pragma mark Настройки

- (void)buildSettings:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    NSArray *langs = @[L(@"Русский"), @"English"];
    NSInteger li = [[FDefaults() stringForKey:kLang] isEqualToString:@"en"] ? 1 : 0;
    FRow *lang = [FRow title:L(@"Язык") sub:langs[li] action:^(UIView *v) {
        [ws choose:L(@"Язык / Language") options:langs source:v done:^(NSInteger i) {
            [FDefaults() setObject:i ? @"en" : @"ru" forKey:kLang];
            [FlideMenu rebuildAll];
        }];
    }];
    lang.icon = @"globe";
    [S addObject:[FSection title:L(@"Язык") rows:@[lang] footer:nil]];

    NSArray *glass = @[L(@"Жидкое стекло"), L(@"Матовое стекло"), L(@"Тёмное (быстрее всего)")];
    NSArray *sizes = @[L(@"Компактно"), L(@"Обычно"), L(@"Крупно")];
    NSInteger gi = MIN(2, [FDefaults() integerForKey:kUIGlass]);
    NSInteger si = [FDefaults() objectForKey:kUIScale] ? MIN(2, [FDefaults() integerForKey:kUIScale]) : 1;
    FRow *g = [FRow title:L(@"Фон окон") sub:glass[gi] action:^(UIView *v) {
        [ws choose:L(@"Фон окон") options:glass source:v done:^(NSInteger i) { [FDefaults() setInteger:i forKey:kUIGlass]; [FlideMenu rebuildAll]; }];
    }];
    g.icon = @"square.on.square";
    FRow *sz = [FRow title:L(@"Размер интерфейса") sub:sizes[si] action:^(UIView *v) {
        [ws choose:L(@"Размер интерфейса") options:sizes source:v done:^(NSInteger i) { [FDefaults() setInteger:i forKey:kUIScale]; [FlideMenu rebuildAll]; }];
    }];
    sz.icon = @"textformat.size";
    FRow *acc = [FRow title:L(@"Цвет меню") sub:FlideHexFromColor(FlideAccent()) action:^(UIView *v) {
        ws.pickingAccent = YES; [ws pickColor];
    }];
    acc.swatch = FlideAccent();
    acc.icon = @"paintpalette";
    FRow *labels = [FRow toggle:L(@"Подписи в панели") sub:L(@"Названия под иконками сверху") key:kUILabels];
    labels.changed = ^{ [FlideMenu rebuildAll]; };
    labels.icon = @"text.below.photo";
    FRow *anim = [FRow toggle:L(@"Анимации меню") sub:L(@"Плавное появление окон") key:kUIAnim];
    anim.icon = @"sparkles";
    [S addObject:[FSection title:L(@"Вид") rows:@[g, sz, acc, labels, anim] footer:L(@"«Тёмное» не размывает фон — меньше нагрузка на телефон.")]];

    FRow *help = [FRow title:L(@"Показать подсказку снова") sub:nil action:^(UIView *v) {
        [FDefaults() removeObjectForKey:@"flide.help.hidden"]; [ws toast:L(@"Подсказка — в окне «Главное»")];
    }];
    help.icon = @"questionmark.circle";
    NSString *ver = [NSString stringWithFormat:L(@"FLIDE для UNO · %@"), [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"];
    [S addObject:[FSection title:L(@"О FLIDE") rows:@[help, [FRow title:ver sub:L(@"Кастомизация без рекламы. Только визуал на твоём устройстве.") action:nil]] footer:nil]];
}

#pragma mark - таблица

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t {
    // ждём, пока перестанешь печатать — не перестраиваем список на каждую букву
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.3];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.sections[s].rows.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return self.sections[s].title; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return self.sections[s].footer; }

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    FRow *r = self.sections[ip.section].rows[ip.row];
    return r.grid ? 70 : UITableViewAutomaticDimension;
}

- (UIView *)gridFor:(FRow *)r width:(CGFloat)w {
    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, 70)];
    sc.showsHorizontalScrollIndicator = NO;
    CGFloat x = 12;
    for (id thing in r.grid) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x, 8, 54, 54);
        b.layer.cornerRadius = 14;
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        if ([thing isKindOfClass:NSDictionary.class]) {
            [b setTitle:thing[@"icon"] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:30];
        } else if ([thing hasPrefix:@"/"]) {
            [b setImage:[UIImage imageWithContentsOfFile:thing] forState:UIControlStateNormal];
            b.imageView.contentMode = UIViewContentModeScaleAspectFit;
            b.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
        } else {
            [b setTitle:thing forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:30];
        }
        objc_setAssociatedObject(b, "thing", thing, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(b, "row", r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [b addTarget:self action:@selector(gridTapped:) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(gridLong:)]];
        [sc addSubview:b];
        x += 62;
    }
    sc.contentSize = CGSizeMake(x + 6, 70);
    return sc;
}

- (void)gridTapped:(UIButton *)b {
    FRow *r = objc_getAssociatedObject(b, "row");
    id thing = objc_getAssociatedObject(b, "thing");
    [UIView animateWithDuration:0.12 animations:^{ b.transform = CGAffineTransformMakeScale(0.85, 0.85); }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ b.transform = CGAffineTransformIdentity; }]; }];
    if (r.gridTap) r.gridTap(thing, b);
}

- (void)gridLong:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    FRow *r = objc_getAssociatedObject(g.view, "row");
    id thing = objc_getAssociatedObject(g.view, "thing");
    if (r.gridLong) r.gridLong(thing);
}

- (NSString *)sliderText:(FRow *)r value:(float)v {
    if ([r.sliderFormat isEqualToString:@"percent"]) return [NSString stringWithFormat:@"%.0f%%", v * 100];
    return [NSString stringWithFormat:r.sliderFormat, v];
}

// значок слева, как в Настройках iOS: эмодзи или SF Symbol на цветной плашке
static UIImage *badge(NSString *icon, UIColor *tint) {
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@|%@", icon, FlideHexFromColor(tint)];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    CGFloat S = 30;
    img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(S, S)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, S, S) cornerRadius:8];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat r, g, b, a; [tint getRed:&r green:&g blue:&b alpha:&a];
        CGFloat comps[] = { MIN(1, r + 0.18), MIN(1, g + 0.18), MIN(1, b + 0.18), 0.95,  r * 0.75, g * 0.75, b * 0.75, 0.95 };
        CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
        CGContextSaveGState(ctx.CGContext);
        [bg addClip];
        CGContextDrawLinearGradient(ctx.CGContext, grad, CGPointZero, CGPointMake(0, S), 0);
        CGContextRestoreGState(ctx.CGContext);
        CGGradientRelease(grad); CGColorSpaceRelease(cs);
        UIImage *sym = [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
        if (sym) {
            sym = [sym imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            [sym drawInRect:CGRectMake((S - sym.size.width) / 2, (S - sym.size.height) / 2, sym.size.width, sym.size.height)];
        } else {
            NSDictionary *at = @{NSFontAttributeName: [UIFont systemFontOfSize:17]};
            CGSize ts = [icon sizeWithAttributes:at];
            [icon drawAtPoint:CGPointMake((S - ts.width) / 2, (S - ts.height) / 2) withAttributes:at];
        }
    }];
    [cache setObject:img forKey:key];
    return img;
}

// эмодзи в начале заголовка → значок, а в тексте его убираем
static NSString *leadingEmoji(NSString *t, NSString **rest) {
    if (t.length < 2) return nil;
    NSRange r = [t rangeOfComposedCharacterSequenceAtIndex:0];
    NSString *first = [t substringWithRange:r];
    unichar c = [first characterAtIndex:0];
    BOOL emoji = (c >= 0xD800 && c <= 0xDBFF) || (c >= 0x2190 && c <= 0x2BFF) || c == 0x2728 || c == 0x2B50 || (c >= 0x2600 && c <= 0x27BF);
    if (!emoji || [first isEqualToString:@"✓"] || [first isEqualToString:@"↺"] || [first isEqualToString:@"←"]) return nil;
    NSString *tail = [[t substringFromIndex:NSMaxRange(r)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!tail.length) return nil;
    if (rest) *rest = tail;
    return first;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    NSString *t = self.sections[section].title;
    if (!t.length) return nil;
    UILabel *l = [UILabel new];
    l.text = [@"   " stringByAppendingString:t.uppercaseString];
    l.font = [UIFont systemFontOfSize:12 * uiScale() weight:UIFontWeightBold];
    l.textColor = [FlideAccent() colorWithAlphaComponent:0.95];
    return l;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    return self.sections[section].title.length ? 30 : 8;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    FRow *r = self.sections[ip.section].rows[ip.row];
    if (r.grid) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"grid"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"grid"];
        for (UIView *v in c.contentView.subviews) [v removeFromSuperview];
        c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *g = [self gridFor:r width:tv.bounds.size.width - 40];
        g.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [c.contentView addSubview:g];
        return c;
    }
    // ячейки переиспользуются — это сильно ускоряет длинные списки и поиск
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"row"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
    CGFloat k = uiScale();
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    UIView *sel = [UIView new]; sel.backgroundColor = [FlideAccent() colorWithAlphaComponent:0.25];
    c.selectedBackgroundView = sel;
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    c.imageView.image = nil;

    NSString *title = r.title, *rest = nil;
    NSString *icon = r.icon ?: (r.item ? nil : leadingEmoji(title, &rest));
    if (rest) title = rest;
    c.textLabel.text = title;
    c.textLabel.font = [UIFont systemFontOfSize:16 * k weight:UIFontWeightSemibold];
    c.textLabel.numberOfLines = 3;
    c.textLabel.textColor = r.destructive ? UIColor.systemRedColor : UIColor.whiteColor;
    c.detailTextLabel.text = r.subtitle;
    c.detailTextLabel.font = [UIFont systemFontOfSize:12.5 * k];
    c.detailTextLabel.numberOfLines = 2;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    if (icon) c.imageView.image = badge(icon, r.destructive ? UIColor.systemRedColor : FlideAccent());
    if (!r.action && !r.defaultsKey && !r.sliderKey) c.selectionStyle = UITableViewCellSelectionStyleNone;
    else if (r.action && !r.swatch) c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (r.defaultsKey) {
        UISwitch *sw = [UISwitch new];
        sw.on = FBool(r.defaultsKey);
        sw.onTintColor = FlideAccent();
        objc_setAssociatedObject(sw, "row", r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (r.sliderKey) {
        float v = [FDefaults() objectForKey:r.sliderKey] ? [FDefaults() floatForKey:r.sliderKey] : r.sliderDefault;
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 30)];
        sl.minimumValue = r.sliderMin; sl.maximumValue = r.sliderMax; sl.value = v;
        sl.tintColor = FlideAccent();
        objc_setAssociatedObject(sl, "row", r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(sl, "cell", c, OBJC_ASSOCIATION_ASSIGN);
        [sl addTarget:self action:@selector(slid:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sl;
        c.detailTextLabel.text = [self sliderText:r value:v];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (r.swatch) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        dot.layer.cornerRadius = 12;
        dot.backgroundColor = r.swatch;
        dot.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
        dot.layer.borderWidth = 1.5;
        c.accessoryView = dot;
    }

    if (r.item && self.tab == FTabTextures) {
        c.imageView.image = r.item.preview ?: badge(@"photo", [UIColor colorWithWhite:0.35 alpha:1]);
        if (!r.item.preview) [self queuePreview:r.item];
    }
    return c;
}

- (void)toggle:(UISwitch *)sw {
    FRow *r = objc_getAssociatedObject(sw, "row");
    [FDefaults() setBool:sw.on forKey:r.defaultsKey];
    if (r.changed) r.changed();
}

- (void)slid:(UISlider *)sl {
    FRow *r = objc_getAssociatedObject(sl, "row");
    float v = roundf(sl.value / r.sliderStep) * r.sliderStep;
    [FDefaults() setFloat:v forKey:r.sliderKey];
    UITableViewCell *c = objc_getAssociatedObject(sl, "cell");
    c.detailTextLabel.text = [self sliderText:r value:v];
    if (r.changed) r.changed();
}

// Превью: сначала с диска (мгновенно), иначе — по одному из Unity, и только
// когда список не крутится. ReadPixels заставляет GPU ждать, поэтому строго дозируем.
static NSString *previewPath(FlideItem *it) {
    return [FlideDir(@"cache") stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@_%@.png", FlideSafeName(it.name), FlideSafeName(it.detail ?: @"")]];
}

static UIImage *roundedThumb(UIImage *img) {
    UIGraphicsImageRenderer *rr = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(36, 36)];
    return [rr imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 36, 36) cornerRadius:8] addClip];
        [[UIColor colorWithWhite:1 alpha:0.08] setFill]; UIRectFill(CGRectMake(0, 0, 36, 36));
        CGSize s = img.size; CGFloat k = MIN(36 / s.width, 36 / s.height);
        [img drawInRect:CGRectMake((36 - s.width * k) / 2, (36 - s.height * k) / 2, s.width * k, s.height * k)];
    }];
}

- (void)queuePreview:(FlideItem *)it {
    NSNumber *key = @(it.instanceID);
    if ([self.previewQueue containsObject:key]) return;
    [self.previewQueue addObject:key];
    NSString *path = previewPath(it);
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *disk = [UIImage imageWithContentsOfFile:path];
        UIImage *thumb = disk ? roundedThumb(disk) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (thumb) { it.preview = thumb; [ws refreshRowFor:it]; return; }
            if (FlideGuardTripped(@"preview")) return;
            [ws.previewTodo addObject:it];
            if (!ws.previewTimer)
                ws.previewTimer = [NSTimer scheduledTimerWithTimeInterval:0.12 repeats:YES block:^(NSTimer *t) { [ws previewStep]; }];
        });
    });
}

- (void)previewStep {
    if (self.table.isDragging || self.table.isDecelerating) return; // крутишь список — ждём
    FlideItem *it = self.previewTodo.lastObject; // сначала самые свежие (видимые)
    if (!it) { [self.previewTimer invalidate]; self.previewTimer = nil; return; }
    [self.previewTodo removeLastObject];
    if (!it.handle) return;
    BOOL visible = NO;
    for (UITableViewCell *c in self.table.visibleCells) {
        NSIndexPath *ip = [self.table indexPathForCell:c];
        if (ip && ip.section < (NSInteger)self.sections.count && ip.row < (NSInteger)self.sections[ip.section].rows.count &&
            self.sections[ip.section].rows[ip.row].item == it) { visible = YES; break; }
    }
    if (!visible) { [self.previewQueue removeObject:@(it.instanceID)]; return; } // уехала с экрана — не тратим GPU
    UIImage *img = [[FlideEngine shared] imageOfTexture:it maxSide:72];
    if (!img) return;
    NSString *path = previewPath(it);
    NSData *png = UIImagePNGRepresentation(img);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{ [png writeToFile:path atomically:YES]; });
    it.preview = roundedThumb(img);
    [self refreshRowFor:it];
}

- (void)refreshRowFor:(FlideItem *)it {
    for (NSIndexPath *ip in self.table.indexPathsForVisibleRows) {
        if (ip.section >= (NSInteger)self.sections.count || ip.row >= (NSInteger)self.sections[ip.section].rows.count) continue;
        if (self.sections[ip.section].rows[ip.row].item == it) {
            [self.table cellForRowAtIndexPath:ip].imageView.image = it.preview;
            break;
        }
    }
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    FRow *r = self.sections[ip.section].rows[ip.row];
    if (r.action) r.action([tv cellForRowAtIndexPath:ip] ?: tv);
}

@end

#pragma mark - плавающее окно

@interface FlidePanel : UIView
@property (nonatomic, strong) FlidePanelVC *vc;
@property (nonatomic, strong) UIView *glass, *header, *grip;
@property (nonatomic, assign) BOOL collapsed;
@property (nonatomic, assign) CGFloat fullHeight;
- (void)toFront;
@end

@interface FlideMenu ()
+ (void)panelClosed:(FlidePanel *)p;
@end

@implementation FlidePanel

- (instancetype)initWithTab:(FTab)tab frame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.4; self.layer.shadowRadius = 24; self.layer.shadowOffset = CGSizeMake(0, 10);

        _glass = FlideGlass(26);
        _glass.frame = self.bounds;
        _glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_glass];
        UIView *c = glassContent(_glass);

        _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, 46)];
        _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [c addSubview:_header];
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(18, 0, f.size.width - 110, 46)];
        t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        t.text = L(tabTitle(tab));
        t.font = [UIFont systemFontOfSize:17 * uiScale() weight:UIFontWeightHeavy];
        UIView *accentBar = [[UIView alloc] initWithFrame:CGRectMake(18, 42, 28, 3)];
        accentBar.backgroundColor = FlideAccent();
        accentBar.layer.cornerRadius = 1.5;
        [_header addSubview:accentBar];
        t.textColor = UIColor.whiteColor;
        [_header addSubview:t];
        UIButton *min = [self headerButton:@"chevron.down.circle.fill" action:@selector(toggleCollapse) x:f.size.width - 84];
        UIButton *x = [self headerButton:@"xmark.circle.fill" action:@selector(close) x:f.size.width - 46];
        [_header addSubview:min];
        [_header addSubview:x];
        [_header addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

        _vc = [FlidePanelVC new];
        _vc.tab = tab;
        _vc.view.frame = CGRectMake(0, 46, f.size.width, f.size.height - 46);
        _vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [c addSubview:_vc.view];

        _grip = [[UIView alloc] initWithFrame:CGRectMake(f.size.width - 30, f.size.height - 30, 30, 30)];
        _grip.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        UIImageView *gi = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]];
        gi.tintColor = [UIColor colorWithWhite:1 alpha:0.45];
        gi.frame = CGRectMake(8, 8, 14, 14);
        [_grip addSubview:gi];
        [_grip addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resize:)]];
        [c addSubview:_grip];

        UITapGestureRecognizer *front = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toFront)];
        front.cancelsTouchesInView = NO;
        [self addGestureRecognizer:front];
    }
    return self;
}

- (UIButton *)headerButton:(NSString *)sym action:(SEL)sel x:(CGFloat)x {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:sym] forState:UIControlStateNormal];
    b.tintColor = [UIColor colorWithWhite:1 alpha:0.75];
    b.frame = CGRectMake(x, 5, 36, 36);
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)toFront { [self.superview bringSubviewToFront:self]; }

- (CGRect)clamp:(CGRect)f {
    CGRect b = self.superview.bounds;
    f.origin.x = MIN(MAX(f.origin.x, -f.size.width + 80), b.size.width - 80);
    f.origin.y = MIN(MAX(f.origin.y, 0), b.size.height - 46);
    return f;
}

- (void)drag:(UIPanGestureRecognizer *)g {
    [self toFront];
    CGPoint t = [g translationInView:self.superview];
    self.frame = [self clamp:CGRectOffset(self.frame, t.x, t.y)];
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)resize:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGRect f = self.frame;
    f.size.width = MAX(280, f.size.width + t.x);
    f.size.height = MAX(200, f.size.height + t.y);
    self.frame = f;
    self.fullHeight = f.size.height;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)toggleCollapse {
    self.collapsed = !self.collapsed;
    if (!self.fullHeight) self.fullHeight = self.frame.size.height;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        CGRect f = self.frame;
        f.size.height = self.collapsed ? 46 : self.fullHeight;
        self.frame = f;
        self.vc.view.alpha = self.collapsed ? 0 : 1;
        self.grip.alpha = self.collapsed ? 0 : 1;
    } completion:nil];
}

- (void)close {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL f) {
        [self removeFromSuperview];
        [FlideMenu panelClosed:self];
    }];
}

@end

#pragma mark - панель запуска и управление окнами

@implementation FlideMenu

static FlideOverlayWindow *gOverlay;
static UIView *gLauncher;
static NSMutableArray<FlidePanel *> *gPanels;

+ (BOOL)isOverlayWindow:(UIWindow *)w { return [w isKindOfClass:FlideOverlayWindow.class]; }
+ (UIView *)overlayRoot { [self ensureOverlay]; return gOverlay.rootViewController.view; }

static UIWindow *gameWindow(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if (![w isKindOfClass:FlideOverlayWindow.class] && w.userInteractionEnabled && w.rootViewController) return w;
    }
    return nil;
}

+ (void)ensureOverlay {
    if (gOverlay) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;
    gOverlay = [[FlideOverlayWindow alloc] initWithWindowScene:scene];
    gOverlay.windowLevel = UIWindowLevelStatusBar + 2;
    gOverlay.backgroundColor = UIColor.clearColor;
    gOverlay.rootViewController = [FlideOverlayRoot new];
    gOverlay.rootViewController.view.backgroundColor = UIColor.clearColor;
    gOverlay.hidden = NO;
    gPanels = [NSMutableArray new];
}

+ (void)updateKey {
    gFlideMenuVisible = gPanels.count > 0 || gLauncher != nil;
    // окна с полями ввода должны быть «ключевыми», иначе не будет клавиатуры
    if (gPanels.count) [gOverlay makeKeyWindow];
    else [gameWindow() makeKeyWindow];
}

+ (void)show {
    [self ensureOverlay];
    if (gLauncher) { [self hideLauncher]; return; }
    [self buildLauncherAnimated:YES];
}

+ (void)buildLauncherAnimated:(BOOL)animated {
    UIView *root = gOverlay.rootViewController.view;
    BOOL labels = [FDefaults() objectForKey:kUILabels] ? FBool(kUILabels) : YES;
    CGFloat itemW = labels ? 60 : 44, barH = labels ? 66 : 54;

    UIView *bar = FlideGlass(barH / 2);
    UIStackView *st = [UIStackView new];
    st.axis = UILayoutConstraintAxisHorizontal;
    st.spacing = 2;
    st.alignment = UIStackViewAlignmentCenter;

    // название слева
    UILabel *logo = [UILabel new];
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:@"✦ FLIDE"
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: UIColor.whiteColor}];
    [t addAttribute:NSForegroundColorAttributeName value:FlideAccent() range:NSMakeRange(0, 1)];
    logo.attributedText = t;
    [logo.widthAnchor constraintEqualToConstant:84].active = YES;
    logo.textAlignment = NSTextAlignmentCenter;
    [st addArrangedSubview:logo];

    for (NSInteger tab = 0; tab < FTabCount; tab++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = tab;
        [b.widthAnchor constraintEqualToConstant:itemW].active = YES;
        [b.heightAnchor constraintEqualToConstant:barH - 8].active = YES;
        UILabel *ic = [UILabel new];
        ic.text = tabIcon(tab);
        ic.font = [UIFont systemFontOfSize:labels ? 22 : 24];
        ic.textAlignment = NSTextAlignmentCenter;
        ic.frame = CGRectMake(0, labels ? 4 : 6, itemW, 28);
        ic.userInteractionEnabled = NO;
        [b addSubview:ic];
        if (labels) {
            UILabel *lb = [UILabel new];
            lb.text = L(tabShort(tab));
            lb.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
            lb.textColor = [UIColor colorWithWhite:1 alpha:0.85];
            lb.textAlignment = NSTextAlignmentCenter;
            lb.adjustsFontSizeToFitWidth = YES;
            lb.minimumScaleFactor = 0.7;
            lb.frame = CGRectMake(2, 34, itemW - 4, 14);
            lb.userInteractionEnabled = NO;
            [b addSubview:lb];
        }
        b.layer.cornerRadius = 14;
        [b addTarget:self action:@selector(launch:) forControlEvents:UIControlEventTouchUpInside];
        [b addTarget:self action:@selector(press:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(release:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [st addArrangedSubview:b];
    }
    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    x.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
    [x.widthAnchor constraintEqualToConstant:40].active = YES;
    [x addTarget:self action:@selector(hideLauncher) forControlEvents:UIControlEventTouchUpInside];
    [st addArrangedSubview:x];

    CGFloat w = 84 + FTabCount * (itemW + 2) + 40 + 20;
    CGFloat maxW = root.bounds.size.width - 24;
    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, MIN(w, maxW), barH)];
    sc.showsHorizontalScrollIndicator = NO;
    st.frame = CGRectMake(6, 0, w - 12, barH);
    [sc addSubview:st];
    sc.contentSize = CGSizeMake(w, barH);
    bar.frame = CGRectMake((root.bounds.size.width - sc.frame.size.width) / 2, root.safeAreaInsets.top + 8, sc.frame.size.width, barH);
    [glassContent(bar) addSubview:sc];
    bar.layer.shadowColor = UIColor.blackColor.CGColor;
    [bar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragLauncher:)]];
    [root addSubview:bar];
    gLauncher = bar;
    if (animated && ([FDefaults() objectForKey:kUIAnim] ? FBool(kUIAnim) : YES)) {
        bar.transform = CGAffineTransformMakeTranslation(0, -90);
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            bar.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    [self updateKey];
}

+ (void)press:(UIButton *)b {
    [UIView animateWithDuration:0.12 animations:^{
        b.transform = CGAffineTransformMakeScale(0.88, 0.88);
        b.backgroundColor = [FlideAccent() colorWithAlphaComponent:0.3];
    }];
}
+ (void)release:(UIButton *)b {
    [UIView animateWithDuration:0.2 animations:^{ b.transform = CGAffineTransformIdentity; b.backgroundColor = UIColor.clearColor; }];
}

+ (void)resetToBase {
    [[FlideEngine shared] resetEverything];
    // всё, что FLIDE добавлял сверху игры
    for (NSString *k in @[kAuras, kHD, kFPS120, kFxStyle, kFxColor, kFxRandom, kFunSpeed, kFunRainbow, kFunTrail,
                          kFunHaptic, kFunShake, kFunFPS, kFunNight, kFunConfetti, kFunParty, kFunClock, kFunShakeConfetti,
                          kVictoryStyle, kVictoryText, kMyAvatar, kBootAnim, kBootSeconds, kPackActive])
        [FDefaults() removeObjectForKey:k];
    [FlideBoot setCustomImage:nil];
    [[FlideFun shared] applySpeed];   // скорость → ×1
    [[FlideFun shared] applyNight];
    [[FlideFX shared] reloadRules];
    [[FlideTools shared] clearAll];
    if (FIL_Ready()) { int fps = -1; void *a[1] = { &fps }; FIL_Static("UnityEngine", "Application", "set_targetFrameRate", 1, a); }
}

+ (void)rebuildAll {
    // язык или вид поменялись — пересобираем окна на тех же местах
    NSMutableArray *state = [NSMutableArray new];
    for (FlidePanel *p in [gPanels copy]) {
        [state addObject:@[@(p.vc.tab), [NSValue valueWithCGRect:p.frame]]];
        [p removeFromSuperview];
        [self panelClosed:p];
    }
    BOOL hadLauncher = gLauncher != nil;
    [gLauncher removeFromSuperview];
    gLauncher = nil;
    if (hadLauncher) [self buildLauncherAnimated:NO];
    for (NSArray *st in state) [self openTab:[st[0] integerValue] frame:[st[1] CGRectValue] animated:NO];
}

+ (void)dragLauncher:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:g.view.superview];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:g.view.superview];
}

+ (void)hideLauncher {
    UIView *l = gLauncher;
    gLauncher = nil;
    [UIView animateWithDuration:0.25 animations:^{ l.alpha = 0; l.transform = CGAffineTransformMakeTranslation(0, -60); }
                     completion:^(BOOL f) { [l removeFromSuperview]; }];
    [self updateKey];
}

+ (void)launch:(UIButton *)b { [self openTab:b.tag frame:CGRectNull animated:YES]; }

+ (void)openTab:(FTab)tab frame:(CGRect)given animated:(BOOL)animated {
    for (FlidePanel *p in gPanels) {
        if (p.vc.tab != tab) continue;
        [p toFront];
        CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        a.values = @[@0, @-8, @8, @-4, @0]; a.duration = 0.3;
        [p.layer addAnimation:a forKey:nil];
        return;
    }
    UIView *root = gOverlay.rootViewController.view;
    CGRect safe = UIEdgeInsetsInsetRect(root.bounds, root.safeAreaInsets);
    CGFloat w = MIN(390, safe.size.width - 24), h = MIN(540, safe.size.height - 90);
    CGFloat off = (gPanels.count % 5) * 34;
    CGRect f = CGRectMake(safe.origin.x + 12 + off, safe.origin.y + 84 + off * 0.6, w, h);
    if (CGRectGetMaxX(f) > CGRectGetMaxX(safe)) f.origin.x = CGRectGetMaxX(safe) - w - 12;
    if (!CGRectIsNull(given)) f = given;
    FlidePanel *p = [[FlidePanel alloc] initWithTab:tab frame:f];
    [gOverlay.rootViewController addChildViewController:p.vc];
    [root addSubview:p];
    [p.vc didMoveToParentViewController:gOverlay.rootViewController];
    [gPanels addObject:p];
    if (gLauncher) [root bringSubviewToFront:gLauncher];
    if (animated && ([FDefaults() objectForKey:kUIAnim] ? FBool(kUIAnim) : YES)) {
        p.alpha = 0;
        p.transform = CGAffineTransformMakeScale(0.92, 0.92);
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
            p.alpha = 1; p.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    [self updateKey];
}

+ (void)panelClosed:(FlidePanel *)p {
    [p.vc willMoveToParentViewController:nil];
    [p.vc removeFromParentViewController];
    [gPanels removeObject:p];
    [self updateKey];
}

#pragma mark жест

+ (void)tapped:(UITapGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateRecognized) [self show];
}

+ (void)attach {
    UIWindow *w = gameWindow();
    if (!w || objc_getAssociatedObject(w, "flide")) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    tap.numberOfTapsRequired = 3;
    tap.numberOfTouchesRequired = 2;
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesEnded = NO;
    [w addGestureRecognizer:tap];
    objc_setAssociatedObject(w, "flide", tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (![FDefaults() boolForKey:@"flide.welcomed2"]) {
        [FDefaults() setBool:YES forKey:@"flide.welcomed2"];
        UILabel *l = [UILabel new];
        l.text = L(@"  ✦ FLIDE: тройной тап двумя пальцами — меню  ");
        l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        l.textColor = UIColor.whiteColor;
        l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        l.layer.cornerRadius = 16; l.clipsToBounds = YES;
        [l sizeToFit];
        l.frame = CGRectMake((w.bounds.size.width - l.bounds.size.width) / 2, 40, l.bounds.size.width, 32);
        [w addSubview:l];
        [UIView animateWithDuration:0.6 delay:4 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
    }
}

+ (void)install {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *n) {
        [self attach];
        [[FlideFX shared] start];
        [self ensureOverlay];
    }];
}

@end
