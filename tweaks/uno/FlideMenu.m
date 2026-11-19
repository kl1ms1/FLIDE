// FLIDE · меню из плавающих окон.
// Тройной тап двумя пальцами → панель запуска → открывай сколько угодно окон.
// Окна таскаются за заголовок, меняют размер за уголок, сворачиваются.
// Игра под окнами продолжает работать: касания мимо окон уходят в UNO.
#import "FlideCore.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

BOOL gFlideMenuVisible = NO;

typedef NS_ENUM(NSInteger, FTab) { FTabMain, FTabBoot, FTabTextures, FTabTexts, FTabFX, FTabFun, FTabEmotes, FTabPacks, FTabTools, FTabCount };

static NSString *tabTitle(FTab t) {
    switch (t) {
        case FTabMain:     return @"⚙️ Главное";
        case FTabBoot:     return @"🚀 Бут-лого";
        case FTabTextures: return @"🖼 Текстуры";
        case FTabTexts:    return @"🔤 Тексты";
        case FTabFX:       return @"✨ Эффекты";
        case FTabFun:      return @"🎉 Приколы";
        case FTabEmotes:   return @"😀 Эмоции и подарки";
        case FTabPacks:    return @"📦 Паки и темы";
        case FTabTools:    return @"📹 Стрим и скрины";
        default:           return @"";
    }
}
static NSString *tabIcon(FTab t) { return [tabTitle(t) componentsSeparatedByString:@" "].firstObject; }

UIView *FlideGlass(CGFloat radius) {
    UIVisualEffect *effect;
    Class glass = NSClassFromString(@"UIGlassEffect");
    effect = glass ? [glass new] : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
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
@end

@implementation FlidePanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.previewQueue = [NSMutableSet new];

    self.search = [UISearchBar new];
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.placeholder = @"Поиск";
    self.search.delegate = self;
    self.search.frame = CGRectMake(0, 0, 300, 44);

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];

    if (self.tab == FTabTexts) {
        __weak typeof(self) ws = self;
        self.refresh = [NSTimer scheduledTimerWithTimeInterval:2.5 repeats:YES block:^(NSTimer *t) { [ws autoRefresh]; }];
    }
    [self reload];
}

- (void)dealloc {
    [self.refresh invalidate];
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
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
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
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
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
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[FRow title:@"← Назад" sub:nil action:^(UIView *v) {
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
        [S addObject:[FSection title:self.pickTitle rows:rows footer:@"Нажми — элемент подсветится в игре и выберется."]];
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
    default: break;
    }
    self.sections = S;
    [self.table reloadData];
}

#pragma mark Главное

- (void)buildMain:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    [S addObject:[FSection title:@"Чистота" rows:@[
        [FRow toggle:@"Без рекламы" sub:@"Межстраничная и баннеры. Нужен перезапуск" key:kNoAds],
    ] footer:@"Реклама за награду остаётся — смотришь, только если сам хочешь бонус."]];
    if (FlideIsClone())
        [S addObject:[FSection title:@"Клон" rows:@[
            [FRow toggle:@"Маскировка Bundle ID" sub:[NSString stringWithFormat:@"%@ → com.mattel163.uno", FlideRealBundleID()] key:kSpoof],
        ] footer:@"Живёт рядом с обычным UNO. Нужен перезапуск."]];
    FRow *fps = [FRow toggle:@"Макс. FPS" sub:@"До 120 Гц на ProMotion" key:kFPS120];
    fps.changed = ^{ [[FlideEngine shared] applyQuality]; };
    [S addObject:[FSection title:@"Качество" rows:@[
        [FRow toggle:@"HD-фильтрация" sub:@"Анизотропия 16×, трилинейная, резче мипмапы" key:kHD], fps,
    ] footer:@"HD-пак текстур — в окне «📦 Паки и темы»."]];
    NSArray *disabled = [FDefaults() arrayForKey:@"flide.disabled"];
    if (disabled.count)
        [S addObject:[FSection title:@"Защита от вылетов" rows:@[
            [FRow title:@"Восстановить отключённые функции" sub:[disabled componentsJoinedByString:@", "] action:^(UIView *v) {
                FlideGuardReset(); [ws toast:@"Включено обратно"]; [ws reload];
            }],
        ] footer:@"Эти функции вызвали вылет и были отключены автоматически."]];
    FRow *reset = [FRow title:@"Сбросить все настройки FLIDE" sub:nil action:^(UIView *v) {
        for (NSString *k in @[kTexts, kAuras, kTextures, kHD, kFPS120, kFxTouch, kFxCombo, kFxStyle, kFxColor, kFunSpeed,
                              kFunRainbow, kFunTrail, kFunNight, kStreamerPaths, kMyAvatar])
            [FDefaults() removeObjectForKey:k];
        [NSFileManager.defaultManager removeItemAtPath:FlideDir(@"textures") error:nil];
        [[FlidePacks shared] stopAnimation];
        [[FlideFX shared] reloadRules];
        [ws toast:@"Сброшено. Перезапусти игру"];
        [ws reload];
    }];
    reset.destructive = YES;
    [S addObject:[FSection title:nil rows:@[reset] footer:@"FLIDE · только визуал на твоём устройстве."]];
}

#pragma mark Бут-лого

- (void)buildBoot:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    NSArray *names = [FlideBoot animationNames];
    NSInteger cur = MIN((NSInteger)names.count - 1, [FDefaults() integerForKey:kBootAnim]);
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:
        [FRow toggle:@"Бут-лого при запуске" sub:@"Заставка FLIDE при открытии игры" key:kBoot],
        [FRow title:@"Анимация" sub:names[cur] action:^(UIView *v) {
            [ws choose:@"Анимация появления" options:names source:v done:^(NSInteger i) {
                [FDefaults() setInteger:i forKey:kBootAnim]; [ws reload];
            }];
        }],
        [FRow slider:@"Длительность" key:kBootSeconds min:1 max:5 step:0.5 def:2.2 fmt:@"%.1f сек"],
        [FRow title:@"Своя картинка" sub:[FlideBoot hasCustomImage] ? @"Стоит своя ✓" : @"Сейчас стандартное ✦ FLIDE" action:^(UIView *v) {
            [ws pickPhoto:^(UIImage *img) {
                [ws toast:[FlideBoot setCustomImage:img] ? @"Бут-лого обновлено ✦" : @"Не получилось"]; [ws reload];
            }];
        }], nil];
    if ([FlideBoot hasCustomImage])
        [rows addObject:[FRow title:@"Вернуть стандартное" sub:nil action:^(UIView *v) {
            [FlideBoot setCustomImage:nil]; [ws toast:@"Стандартное лого"]; [ws reload];
        }]];
    [rows addObject:[FRow title:@"▶︎ Показать сейчас" sub:nil action:^(UIView *v) { [FlideBoot showAnimated]; }]];
    [S addObject:[FSection title:@"Бут-лого" rows:rows footer:@"«Печатная машинка» работает со стандартным лого. PNG с прозрачностью смотрится лучше всего."]];
}

#pragma mark Текстуры

- (void)buildTextures:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    self.table.tableHeaderView = self.search;
    if (!self.items) [self setItemsReleasingOld:[[FlideEngine shared] scanTextures]];
    NSDictionary *replaced = [FDefaults() dictionaryForKey:kTextures];
    NSString *anim = [[FlidePacks shared] animatedTexture];
    [S addObject:[FSection title:nil rows:@[[FRow title:@"↻ Обновить список" sub:@"Открой нужный экран игры и обнови" action:^(UIView *v) {
        [ws setItemsReleasingOld:nil]; [ws.previewQueue removeAllObjects]; [ws reload];
    }]] footer:nil]];
    NSMutableArray *rows = [NSMutableArray new];
    for (FlideItem *it in [self filtered]) {
        NSString *mark = [it.name isEqualToString:anim] ? @" · 🎞 анимация" : (replaced[it.name] ? @" · заменена ✓" : @"");
        FRow *r = [FRow title:it.name sub:[it.detail stringByAppendingString:mark] action:^(UIView *v) {
            FlideTextureEditor *e = [FlideTextureEditor editorForItem:it onChange:^{ it.preview = nil; [ws.previewQueue removeObject:@(it.instanceID)]; [ws reload]; }];
            [ws presentViewController:e animated:YES completion:nil];
        }];
        r.item = it;
        [rows addObject:r];
    }
    NSString *footer = FlideGuardTripped(@"preview")
        ? @"Превью отключены после вылета (включить: «Главное → Восстановить»). Замена работает."
        : @"Нажми на текстуру — откроется редактор с предпросмотром: фото, фильтры, перекраска, анимация.";
    [S addObject:[FSection title:[NSString stringWithFormat:@"Текстуры · %lu", (unsigned long)rows.count] rows:rows footer:footer]];
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
            [ws toast:@"Подмена убрана"];
            [ws reload];
        }]];
    }];
    if (active.count) [S addObject:[FSection title:@"✏️ Мои подмены" rows:active footer:@"Нажми, чтобы убрать."]];

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
        [S addObject:[FSection title:@"Тексты на экране" rows:@[] footer:@"Пока пусто — открой экран игры, список обновится сам."]];
    else
        ((FSection *)S.lastObject).footer = @"Список обновляется сам, когда открываешь новый экран (например, аватарку). Нажми строку — элемент подсветится в игре.";
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
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Текст в игре" message:[NSString stringWithFormat:@"%@\nМеняется вживую, пока печатаешь", friendlyPath(path)]
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = before ?: it.detail;
        tf.clearButtonMode = UITextFieldViewModeAlways;
        [tf addTarget:self action:@selector(liveText:) forControlEvents:UIControlEventEditingChanged];
        objc_setAssociatedObject(tf, "path", path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        [[FlideEngine shared] setOverride:before forPath:path];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"🕶 Скрыть как ник (стример)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[FlideEngine shared] setOverride:before forPath:path];
        NSMutableArray *p = [[FDefaults() arrayForKey:kStreamerPaths] mutableCopy] ?: [NSMutableArray new];
        if (![p containsObject:path]) [p addObject:path];
        [FDefaults() setObject:p forKey:kStreamerPaths];
        [FDefaults() setBool:YES forKey:kStreamer];
        [self toast:@"Режим стримера: этот ник скрыт"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
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
    FRow *style = [FRow title:@"Стиль" sub:FlideFxStyleName([FDefaults() integerForKey:kFxStyle]) action:^(UIView *v) {
        [ws pickStyle:^(FlideFxStyle s) { [FDefaults() setInteger:s forKey:kFxStyle]; [ws reload]; } source:v];
    }];
    FRow *col = [FRow title:@"Цвет" sub:FlideHexFromColor(color) action:^(UIView *v) { [ws pickColor]; }];
    col.swatch = color;
    [S addObject:[FSection title:@"Броски карт" rows:@[
        [FRow toggle:@"Искры при броске" sub:@"Свайп карты — вспышка частиц" key:kFxTouch],
        [FRow toggle:@"Комбо" sub:@"3+ карты подряд — ударная волна и COMBO ×N" key:kFxCombo],
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
    [auras addObject:[FRow title:@"＋ Добавить ауру к элементу" sub:nil action:^(UIView *v) {
        [ws startPicking:@"Выбери элемент для ауры" then:^(FlideItem *it) {
            NSString *path = it.name;
            [ws pickStyle:^(FlideFxStyle s) {
                NSMutableDictionary *d = [[FDefaults() dictionaryForKey:kAuras] mutableCopy] ?: [NSMutableDictionary new];
                d[path] = @{ @"style": @(s), @"color": [FDefaults() stringForKey:kFxColor] ?: @"#7CF7FF", @"radius": @46 };
                [FDefaults() setObject:d forKey:kAuras];
                [[FlideFX shared] reloadRules];
                [ws toast:@"Аура добавлена ✦"];
                [ws reload];
            } source:ws.view];
        }];
    }]];
    [S addObject:[FSection title:@"Ауры" rows:auras footer:@"Выбери подсветку хода — аура будет только у того, кто ходит. Нажми на ауру, чтобы удалить."]];
}

- (void)pickStyle:(void (^)(FlideFxStyle))done source:(UIView *)src {
    NSMutableArray *names = [NSMutableArray new];
    for (NSInteger s = 0; s < FlideFxStyleCount; s++) [names addObject:FlideFxStyleName(s)];
    [self choose:@"Стиль эффекта" options:names source:src done:^(NSInteger i) { done(i); }];
}

- (void)pickColor {
    UIColorPickerViewController *p = [UIColorPickerViewController new];
    p.selectedColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    p.supportsAlpha = NO;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    [FDefaults() setObject:FlideHexFromColor(vc.selectedColor) forKey:kFxColor];
    [self reload];
}

#pragma mark Приколы

- (void)buildFun:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FRow *speed = [FRow slider:@"Скорость игры" key:kFunSpeed min:1 max:5 step:0.5 def:1 fmt:@"×%.1f"];
    speed.changed = ^{ [[FlideFun shared] applySpeed]; };
    [S addObject:[FSection title:@"Скорость" rows:@[speed]
                          footer:@"Ускоряет анимации и меню. В онлайне сервер быстрее не станет — ход соперников всё равно ждёт сервер."]];
    FRow *night = [FRow slider:@"Ночной фильтр" key:kFunNight min:0 max:0.45 step:0.05 def:0 fmt:@"%.0f%%"];
    night.sliderFormat = @"percent";
    night.changed = ^{ [[FlideFun shared] applyNight]; };
    [S addObject:[FSection title:@"Экран" rows:@[
        [FRow toggle:@"🌈 Радужные тексты" sub:@"Все надписи переливаются" key:kFunRainbow],
        [FRow toggle:@"✨ След пальца" sub:@"Светящийся хвост за пальцем" key:kFunTrail],
        [FRow toggle:@"📳 Вибро-отклик" sub:@"Лёгкий отклик при броске, сильный при комбо" key:kFunHaptic],
        [FRow toggle:@"💥 Тряска при комбо" sub:@"Экран вздрагивает на COMBO" key:kFunShake],
        [FRow toggle:@"FPS" sub:@"Счётчик кадров в углу" key:kFunFPS],
        night,
    ] footer:nil]];
    NSArray *vs = @[@"🎊 Конфетти", @"🎆 Фейерверк", @"🎊+🎆 Всё сразу"];
    NSInteger vi = MIN(2, [FDefaults() integerForKey:kVictoryStyle]);
    NSString *vt = [FDefaults() stringForKey:kVictoryText];
    [S addObject:[FSection title:@"Победа" rows:@[
        [FRow toggle:@"Анимация победы" sub:@"Срабатывает, когда на экране появляется «победа / win»" key:kFunConfetti],
        [FRow title:@"Эффект" sub:vs[vi] action:^(UIView *v) {
            [ws choose:@"Эффект победы" options:vs source:v done:^(NSInteger i) { [FDefaults() setInteger:i forKey:kVictoryStyle]; [ws reload]; }];
        }],
        [FRow title:@"Надпись" sub:vt.length ? vt : @"нет" action:^(UIView *v) {
            [ws ask:@"Надпись при победе" placeholder:@"Например: ИЗИ 😎" done:^(NSString *t) { [FDefaults() setObject:t forKey:kVictoryText]; [ws reload]; }];
        }],
        [FRow title:@"▶︎ Показать сейчас" sub:nil action:^(UIView *v) { [[FlideFun shared] victoryNow]; }],
    ] footer:nil]];
    NSDictionary *st = [[FlideFun shared] stats];
    int secs = [st[@"seconds"] intValue];
    [S addObject:[FSection title:@"📊 Статистика FLIDE" rows:@[
        [FRow title:[NSString stringWithFormat:@"⏱ В игре: %dч %02dм", secs / 3600, (secs / 60) % 60] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:@"🃏 Бросков карт: %d", [st[@"throws"] intValue]] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:@"🔥 Рекорд комбо: ×%d", [st[@"bestCombo"] intValue]] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:@"🏆 Побед замечено: %d", [st[@"wins"] intValue]] sub:nil action:nil],
        [FRow title:[NSString stringWithFormat:@"🚀 Запусков: %d", [st[@"launches"] intValue]] sub:nil action:nil],
        [FRow title:@"Сбросить статистику" sub:nil action:^(UIView *v) { [[FlideFun shared] resetStats]; [ws reload]; }],
    ] footer:@"Считается только на этом устройстве."]];
}

#pragma mark Эмоции и подарки

- (void)buildEmotes:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FlideEmotes *E = [FlideEmotes shared];
    NSString *me = [FDefaults() stringForKey:kMyAvatar];
    [S addObject:[FSection title:nil rows:@[
        [FRow title:@"👤 Мой аватар" sub:me ? friendlyPath(me) : @"Не выбран — эмоции появятся внизу по центру" action:^(UIView *v) {
            [ws startPicking:@"Выбери свой аватар" then:^(FlideItem *it) { [FDefaults() setObject:it.name forKey:kMyAvatar]; }];
        }],
    ] footer:@"🔒 Только визуал: видишь только ты. Никому ничего не отправляется и ничего не даёт."]];

    FRow *emotes = [FRow new];
    emotes.grid = [[E builtinEmotes] arrayByAddingObjectsFromArray:[E customEmotes]];
    emotes.gridTap = ^(id thing, UIView *src) { [E sendEmote:thing]; };
    emotes.gridLong = ^(id thing) {
        if ([thing hasPrefix:@"/"]) { [E removeCustomEmote:thing]; [ws reload]; }
    };
    [S addObject:[FSection title:@"Эмоции" rows:@[emotes,
        [FRow title:@"＋ Своя эмоция из Фото" sub:nil action:^(UIView *v) {
            [ws pickPhoto:^(UIImage *img) { [E addCustomEmote:img]; [ws reload]; }];
        }],
    ] footer:@"Нажми — эмоция всплывёт над твоим аватаром. Свою — удержи, чтобы удалить."]];

    NSMutableArray *gifts = [NSMutableArray arrayWithArray:[E builtinGifts]];
    [gifts addObjectsFromArray:[E customGifts]];
    FRow *giftRow = [FRow new];
    giftRow.grid = gifts;
    giftRow.gridTap = ^(id gift, UIView *src) {
        [ws choose:@"Кому подарок (только визуал)" options:@[@"🎁 Себе", @"👆 Выбрать на экране"] source:src done:^(NSInteger i) {
            if (i == 0) { [E sendGift:gift toPoint:nil]; return; }
            [ws startPicking:@"Кому отправить подарок" then:^(FlideItem *it) {
                CGPoint p;
                BOOL ok = [[FlideEngine shared] screenPointForItem:it point:&p];
                [E sendGift:gift toPoint:ok ? [NSValue valueWithCGPoint:p] : nil];
            }];
        }];
    };
    giftRow.gridLong = ^(id thing) {
        if ([thing isKindOfClass:NSString.class] && [thing hasPrefix:@"/"]) { [E removeCustomGift:thing]; [ws reload]; }
    };
    [S addObject:[FSection title:@"Подарки" rows:@[giftRow,
        [FRow title:@"＋ Свой подарок из Фото" sub:nil action:^(UIView *v) {
            [ws pickPhoto:^(UIImage *img) { [E addCustomGift:img]; [ws reload]; }];
        }],
    ] footer:@"Наши собственные анимации — бесплатно и только у тебя на экране."]];
}

#pragma mark Паки и темы

- (void)buildPacks:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FlidePacks *P = [FlidePacks shared];
    NSArray *names = FlideFilterNames();
    NSMutableArray *themes = [NSMutableArray new];
    if (P.themeRunning)
        [themes addObject:[FRow title:@"⏹ Остановить" sub:self.status action:^(UIView *v) { [P cancelTheme]; [ws reload]; }]];
    for (NSInteger i = 1; i < (NSInteger)names.count; i++)
        [themes addObject:[FRow title:names[i] sub:nil action:^(UIView *v) { [ws runTheme:i]; }]];
    [themes addObject:[FRow title:@"↺ Вернуть всем оригинал" sub:nil action:^(UIView *v) { [ws runTheme:0]; }]];
    [S addObject:[FSection title:@"🎨 Тема в одно нажатие" rows:themes
                          footer:@"Фильтр сразу ко всем текстурам на экране. Идёт по одной, игра не зависает. Шрифты не трогаются."]];

    NSString *active = [FDefaults() stringForKey:kPackActive];
    NSMutableArray *packs = [NSMutableArray new];
    for (NSString *p in [P packs]) {
        BOOL on = [p isEqualToString:active];
        [packs addObject:[FRow title:[NSString stringWithFormat:@"%@%@", on ? @"✅ " : @"📦 ", p] sub:on ? @"Включён" : nil action:^(UIView *v) {
            [ws choose:p options:on ? @[@"Выключить", @"Поделиться (zip)", @"Удалить"] : @[@"Включить", @"Поделиться (zip)", @"Удалить"] source:v done:^(NSInteger i) {
                NSString *dir = [FlideDir(@"packs") stringByAppendingPathComponent:p];
                if (i == 0) {
                    if (on) { [P deactivatePack]; [ws toast:@"Пак выключен"]; }
                    else [ws toast:[NSString stringWithFormat:@"Подставлено текстур: %lu", (unsigned long)[P activatePack:p]]];
                } else if (i == 1) {
                    NSURL *zip = [P zipFolder:dir];
                    if (zip) [ws share:@[zip] source:v];
                } else {
                    if (on) [P deactivatePack];
                    [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
                }
                [ws reload];
            }];
        }]];
    }
    [packs addObject:[FRow title:@"📥 Импорт пака из «Файлов»" sub:@"Папка с PNG (распакуй zip в «Файлах»)" action:^(UIView *v) { [ws importPack]; }]];
    [packs addObject:[FRow title:@"💾 Сохранить мою тему как пак" sub:@"Замены + тексты + ауры + цвета" action:^(UIView *v) {
        [ws ask:@"Название пака" placeholder:@"Моя тема" done:^(NSString *t) {
            NSURL *u = [P savePresetNamed:t];
            NSURL *zip = u ? [P zipFolder:u.path] : nil;
            [ws reload];
            if (zip) [ws share:@[zip] source:v];
        }];
    }]];
    [S addObject:[FSection title:@"Паки" rows:packs footer:@"Пак можно скинуть другу — он импортирует его у себя."]];

    [S addObject:[FSection title:@"✨ HD-пак (апскейл нейросетью)" rows:@[
        [FRow title:@"1. Экспортировать все текстуры в zip" sub:@"Сохрани zip в «Файлы»" action:^(UIView *v) {
            NSUInteger n = [[FlideEngine shared] exportAllTextures];
            NSURL *zip = [P zipFolder:FlideDir(@"export")];
            [ws toast:[NSString stringWithFormat:@"Текстур: %lu", (unsigned long)n]];
            if (zip) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws share:@[zip] source:v]; });
        }],
        [FRow title:@"2. Загрузи zip в Release с тегом hd-src" sub:@"GitHub → Releases → hd-src → прикрепить export.zip" action:nil],
        [FRow title:@"3. Actions → HD texture pack → Run" sub:@"Real-ESRGAN улучшит каждую текстуру" action:nil],
        [FRow title:@"4. Скачай FLIDE-HD-pack, распакуй и импортируй" sub:@"«📥 Импорт пака» → включи пак" action:nil],
    ] footer:@"Нейросеть убирает мыло и артефакты сжатия. Размер текстур сохраняется, поэтому ничего не съезжает."]];

    NSString *anim = [P animatedTexture];
    [S addObject:[FSection title:@"🎞 Анимированный стол" rows:anim ? @[
        [FRow title:[NSString stringWithFormat:@"Анимация: %@", anim] sub:@"Нажми, чтобы остановить" action:^(UIView *v) {
            [P stopAnimation]; [ws toast:@"Остановлено. Оригинал — после перезапуска"]; [ws reload];
        }]] : @[]
                          footer:@"Открой «🖼 Текстуры», выбери фон стола и нажми «🎞 Анимация»: подойдут GIF или несколько фото по порядку."]];
}

- (void)runTheme:(NSInteger)filter {
    __weak typeof(self) ws = self;
    [[FlidePacks shared] applyTheme:filter progress:^(NSUInteger done, NSUInteger total) {
        ws.status = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)done, (unsigned long)total];
        if (done == total) { ws.status = nil; [ws toast:@"Тема применена ✦"]; }
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
    __weak typeof(self) ws = self;
    NSString *guess = urls.count == 1 && urls.firstObject.hasDirectoryPath ? urls.firstObject.lastPathComponent : @"Мой пак";
    [self ask:@"Название пака" placeholder:guess done:^(NSString *t) {
        NSUInteger n = [[FlidePacks shared] importFromURLs:urls asPack:t];
        [ws toast:[NSString stringWithFormat:@"Импортировано PNG: %lu", (unsigned long)n]];
        [ws reload];
    }];
}

#pragma mark Стрим и скрины

- (void)buildTools:(NSMutableArray *)S {
    __weak typeof(self) ws = self;
    FlideTools *T = [FlideTools shared];
    NSMutableArray *stream = [NSMutableArray arrayWithObject:[FRow toggle:@"🕶 Режим стримера" sub:@"Выбранные ники → «Игрок 1/2/3»" key:kStreamer]];
    for (NSString *p in [FDefaults() arrayForKey:kStreamerPaths]) {
        [stream addObject:[FRow title:p.lastPathComponent sub:friendlyPath(p) action:^(UIView *v) {
            NSMutableArray *a = [[FDefaults() arrayForKey:kStreamerPaths] mutableCopy];
            [a removeObject:p];
            [FDefaults() setObject:a forKey:kStreamerPaths];
            [ws reload];
        }]];
    }
    [S addObject:[FSection title:@"Стрим" rows:stream footer:@"Добавить ник: «🔤 Тексты» → нажми на ник → «Скрыть как ник». Тут нажми, чтобы убрать."]];

    UIView *overlay = [FlideMenu overlayRoot];
    [S addObject:[FSection title:@"Скрины и клипы" rows:@[
        [FRow title:@"📸 Чистый скриншот" sub:@"Кадр игры без окон FLIDE" action:^(UIView *v) {
            UIImage *img = [T cleanScreenshot];
            if (img) [ws share:@[img] source:v]; else [ws toast:@"Не получилось"];
        }],
        [FRow title:T.clipBuffering ? @"⏺ Буфер клипов: включён" : @"⏺ Включить буфер клипов" sub:@"Пишет последние 30 секунд" action:^(UIView *v) {
            [T setClipBuffering:!T.clipBuffering completion:^(NSError *e) {
                [ws toast:e ? e.localizedDescription : (T.clipBuffering ? @"Буфер включён" : @"Буфер выключен")];
                [ws reload];
            }];
        }],
        [FRow title:@"🎬 Сохранить последние 30 сек" sub:nil action:^(UIView *v) {
            if (!T.clipBuffering) { [ws toast:@"Сначала включи буфер"]; return; }
            [T exportClip:^(NSURL *url, NSError *e) {
                if (url) [ws share:@[url] source:v]; else [ws toast:e.localizedDescription ?: @"Ошибка"];
            }];
        }],
    ] footer:@"Файлы также лежат в FLIDE/shots и FLIDE/clips."]];

    [S addObject:[FSection title:@"Рисование и стикеры" rows:@[
        [FRow title:@"🖍 Рисовать поверх экрана" sub:@"✓ — закончить, рисунок останется" action:^(UIView *v) { [T toggleDrawingIn:overlay]; }],
        [FRow title:@"😀 Стикер-эмодзи" sub:nil action:^(UIView *v) {
            NSArray *em = [[FlideEmotes shared] builtinEmotes];
            [ws choose:@"Стикер" options:em source:v done:^(NSInteger i) {
                UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(160, 160)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
                    NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:130]};
                    CGSize s = [em[i] sizeWithAttributes:a];
                    [em[i] drawAtPoint:CGPointMake((160 - s.width) / 2, (160 - s.height) / 2) withAttributes:a];
                }];
                [T addSticker:img in:overlay];
            }];
        }],
        [FRow title:@"🖼 Стикер из Фото" sub:nil action:^(UIView *v) { [ws pickPhoto:^(UIImage *img) { [T addSticker:img in:overlay]; }]; }],
        [FRow title:@"Убрать все стикеры" sub:nil action:^(UIView *v) { [T clearStickers]; }],
    ] footer:@"Стикер: тащи, щипком меняй размер, двумя пальцами крути, удержи — удалить."]];
}

#pragma mark - таблица

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t { [self reload]; }
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

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    FRow *r = self.sections[ip.section].rows[ip.row];
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    if (r.grid) {
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *g = [self gridFor:r width:tv.bounds.size.width - 40];
        g.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [c.contentView addSubview:g];
        return c;
    }
    c.textLabel.text = r.title;
    c.textLabel.numberOfLines = 3;
    c.textLabel.textColor = r.destructive ? UIColor.systemRedColor : UIColor.whiteColor;
    c.detailTextLabel.text = r.subtitle;
    c.detailTextLabel.numberOfLines = 2;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    if (!r.action && !r.defaultsKey && !r.sliderKey) c.selectionStyle = UITableViewCellSelectionStyleNone;

    if (r.defaultsKey) {
        UISwitch *sw = [UISwitch new];
        sw.on = FBool(r.defaultsKey);
        objc_setAssociatedObject(sw, "row", r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (r.sliderKey) {
        float v = [FDefaults() objectForKey:r.sliderKey] ? [FDefaults() floatForKey:r.sliderKey] : r.sliderDefault;
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
        sl.minimumValue = r.sliderMin; sl.maximumValue = r.sliderMax; sl.value = v;
        sl.tintColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
        objc_setAssociatedObject(sl, "row", r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(sl, "cell", c, OBJC_ASSOCIATION_ASSIGN);
        [sl addTarget:self action:@selector(slid:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sl;
        c.detailTextLabel.text = [self sliderText:r value:v];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (r.swatch) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
        dot.layer.cornerRadius = 11;
        dot.backgroundColor = r.swatch;
        dot.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
        dot.layer.borderWidth = 1;
        c.accessoryView = dot;
    }

    if (r.item && self.tab == FTabTextures) {
        c.imageView.image = r.item.preview ?: [UIImage systemImageNamed:@"photo"];
        c.imageView.tintColor = [UIColor colorWithWhite:1 alpha:0.3];
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

// превью грузим по одному за тик, чтобы не тормозить игру
- (void)queuePreview:(FlideItem *)it {
    NSNumber *key = @(it.instanceID);
    if ([self.previewQueue containsObject:key] || FlideGuardTripped(@"preview")) return;
    [self.previewQueue addObject:key];
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * self.previewQueue.count * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!ws || !it.handle) return;
        UIImage *img = [[FlideEngine shared] imageOfTexture:it maxSide:96];
        if (!img) return;
        UIGraphicsImageRenderer *rr = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(44, 44)];
        it.preview = [rr imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 44, 44) cornerRadius:9] addClip];
            CGSize s = img.size; CGFloat k = MIN(44 / s.width, 44 / s.height);
            [img drawInRect:CGRectMake((44 - s.width * k) / 2, (44 - s.height * k) / 2, s.width * k, s.height * k)];
        }];
        for (NSIndexPath *ip in ws.table.indexPathsForVisibleRows) {
            if (ip.section >= (NSInteger)ws.sections.count || ip.row >= (NSInteger)ws.sections[ip.section].rows.count) continue;
            if (ws.sections[ip.section].rows[ip.row].item == it) {
                [ws.table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    });
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
        t.text = tabTitle(tab);
        t.font = [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy];
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
    UIView *root = gOverlay.rootViewController.view;

    UIView *bar = FlideGlass(28);
    UIStackView *st = [UIStackView new];
    st.axis = UILayoutConstraintAxisHorizontal;
    st.spacing = 4;
    UILabel *logo = [UILabel new];
    logo.text = @" ✦ ";
    logo.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
    logo.textColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    [st addArrangedSubview:logo];
    for (NSInteger t = 0; t < FTabCount; t++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:tabIcon(t) forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:24];
        b.tag = t;
        [b.widthAnchor constraintEqualToConstant:44].active = YES;
        [b addTarget:self action:@selector(launch:) forControlEvents:UIControlEventTouchUpInside];
        [st addArrangedSubview:b];
    }
    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    x.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    [x.widthAnchor constraintEqualToConstant:40].active = YES;
    [x addTarget:self action:@selector(hideLauncher) forControlEvents:UIControlEventTouchUpInside];
    [st addArrangedSubview:x];

    CGFloat w = 30 + FTabCount * 48 + 44 + 16;
    CGFloat maxW = root.bounds.size.width - 24;
    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, MIN(w, maxW), 56)];
    sc.showsHorizontalScrollIndicator = NO;
    st.frame = CGRectMake(8, 0, w - 16, 56);
    [sc addSubview:st];
    sc.contentSize = CGSizeMake(w, 56);
    bar.frame = CGRectMake((root.bounds.size.width - sc.frame.size.width) / 2, root.safeAreaInsets.top + 10, sc.frame.size.width, 56);
    [glassContent(bar) addSubview:sc];
    [bar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragLauncher:)]];
    [root addSubview:bar];
    gLauncher = bar;
    bar.transform = CGAffineTransformMakeTranslation(0, -90);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        bar.transform = CGAffineTransformIdentity;
    } completion:nil];
    [self updateKey];
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

+ (void)launch:(UIButton *)b {
    FTab tab = b.tag;
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
    CGRect f = CGRectMake(safe.origin.x + 12 + off, safe.origin.y + 76 + off * 0.6, w, h);
    if (CGRectGetMaxX(f) > CGRectGetMaxX(safe)) f.origin.x = CGRectGetMaxX(safe) - w - 12;
    FlidePanel *p = [[FlidePanel alloc] initWithTab:tab frame:f];
    [gOverlay.rootViewController addChildViewController:p.vc];
    [root addSubview:p];
    [p.vc didMoveToParentViewController:gOverlay.rootViewController];
    [gPanels addObject:p];
    if (gLauncher) [root bringSubviewToFront:gLauncher];
    p.alpha = 0;
    p.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
        p.alpha = 1; p.transform = CGAffineTransformIdentity;
    } completion:nil];
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
        l.text = @"  ✦ FLIDE: тройной тап двумя пальцами — меню  ";
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
