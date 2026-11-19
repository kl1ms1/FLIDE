// FLIDE · меню. Открывается тройным тапом двумя пальцами.
// iOS 26+: настоящий Liquid Glass (UIGlassEffect). Ниже — матовое стекло с бликом.
#import "FlideCore.h"
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

extern BOOL gFlideMenuVisible;

typedef NS_ENUM(NSInteger, FTab) { FTabMain, FTabTextures, FTabTexts, FTabFX };

#pragma mark - стеклянная панель

@interface FlideGlassView : UIView
@property (nonatomic, strong) UIVisualEffectView *fx;
@property (nonatomic, strong) CAGradientLayer *rim;
@property (nonatomic, strong) CAShapeLayer *rimMask;
@end

@implementation FlideGlassView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        UIVisualEffect *effect = nil;
        Class glass = NSClassFromString(@"UIGlassEffect");
        if (glass) effect = [glass new];
        else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        _fx = [[UIVisualEffectView alloc] initWithEffect:effect];
        _fx.layer.cornerRadius = 30;
        _fx.layer.cornerCurve = kCACornerCurveContinuous;
        _fx.clipsToBounds = YES;
        [self addSubview:_fx];

        // блик-обводка как у жидкого стекла
        _rim = [CAGradientLayer layer];
        _rim.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.55].CGColor,
                        (id)[UIColor colorWithWhite:1 alpha:0.05].CGColor,
                        (id)[UIColor colorWithWhite:1 alpha:0.30].CGColor];
        _rim.startPoint = CGPointMake(0, 0); _rim.endPoint = CGPointMake(1, 1);
        _rimMask = [CAShapeLayer layer];
        _rimMask.fillColor = UIColor.clearColor.CGColor;
        _rimMask.strokeColor = UIColor.blackColor.CGColor;
        _rimMask.lineWidth = 1.2;
        _rim.mask = _rimMask;
        [self.layer addSublayer:_rim];

        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 30;
        self.layer.shadowOffset = CGSizeMake(0, 12);
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.fx.frame = self.bounds;
    self.rim.frame = self.bounds;
    self.rimMask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 0.6, 0.6) cornerRadius:30].CGPath;
}
@end

#pragma mark - строки таблицы

@interface FRow : NSObject
@property (nonatomic, copy) NSString *title, *subtitle, *defaultsKey;
@property (nonatomic, copy) void (^action)(UIView *source);
@property (nonatomic, strong) FlideItem *item;
@property (nonatomic, strong) UIColor *swatch;
@property (nonatomic, assign) BOOL destructive;
@end
@implementation FRow
+ (instancetype)title:(NSString *)t sub:(NSString *)s action:(void (^)(UIView *))a {
    FRow *r = [FRow new]; r.title = t; r.subtitle = s; r.action = a; return r;
}
+ (instancetype)toggle:(NSString *)t sub:(NSString *)s key:(NSString *)k {
    FRow *r = [FRow new]; r.title = t; r.subtitle = s; r.defaultsKey = k; return r;
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

#pragma mark - контроллер меню

@interface FlideMenuVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate,
                                           PHPickerViewControllerDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) FlideGlassView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) NSArray<FSection *> *sections;
@property (nonatomic, strong) NSArray<FlideItem *> *items;
@property (nonatomic, assign) BOOL pickingElement;
@property (nonatomic, strong) FlideItem *pendingTexture;
@property (nonatomic, assign) BOOL pickingBoot;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *previewQueue;
@end

@implementation FlideMenuVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    self.previewQueue = [NSMutableSet new];

    UIButton *dim = [UIButton buttonWithType:UIButtonTypeCustom];
    dim.frame = self.view.bounds;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [dim addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:dim];

    self.panel = [FlideGlassView new];
    [self.view addSubview:self.panel];

    UILabel *title = [UILabel new];
    title.text = @"✦ FLIDE";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;
    title.tag = 1;
    [self.panel addSubview:title];

    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    x.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    x.tag = 2;
    [x addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:x];

    self.tabs = [[UISegmentedControl alloc] initWithItems:@[@"Главное", @"Текстуры", @"Тексты", @"Эффекты"]];
    self.tabs.selectedSegmentIndex = 0;
    [self.tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.tabs];

    self.search = [UISearchBar new];
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.placeholder = @"Поиск";
    self.search.delegate = self;
    self.search.frame = CGRectMake(0, 0, 300, 44);

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.panel addSubview:self.table];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat w = MIN(440, safe.size.width - 32), h = MIN(620, safe.size.height - 24);
    self.panel.frame = CGRectMake(CGRectGetMidX(safe) - w / 2, CGRectGetMidY(safe) - h / 2, w, h);
    [self.panel viewWithTag:1].frame = CGRectMake(22, 14, w - 80, 30);
    [self.panel viewWithTag:2].frame = CGRectMake(w - 50, 12, 36, 36);
    self.tabs.frame = CGRectMake(16, 52, w - 32, 32);
    self.table.frame = CGRectMake(0, 92, w, h - 96);
}

- (void)close {
    gFlideMenuVisible = NO;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)tabChanged {
    self.pickingElement = NO;
    self.items = nil;
    self.search.text = @"";
    [self reload];
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [a dismissViewControllerAnimated:YES completion:nil];
    });
}

#pragma mark - данные вкладок

- (NSArray<FlideItem *> *)filtered {
    NSString *q = self.search.text;
    if (!q.length) return self.items;
    return [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FlideItem *it, id b) {
        return [it.name localizedCaseInsensitiveContainsString:q] || [it.detail localizedCaseInsensitiveContainsString:q];
    }]];
}

- (void)reload {
    __weak typeof(self) ws = self;
    FlideEngine *E = [FlideEngine shared];
    NSMutableArray *S = [NSMutableArray new];
    self.table.tableHeaderView = nil;

    switch ((FTab)self.tabs.selectedSegmentIndex) {
    case FTabMain: {
        [S addObject:[FSection title:@"Чистота" rows:@[
            [FRow toggle:@"Без рекламы" sub:@"Межстраничная и баннеры. Нужен перезапуск" key:kNoAds],
        ] footer:@"Реклама за награду остаётся — смотришь, только если сам хочешь бонус."]];
        if (FlideIsClone())
            [S addObject:[FSection title:@"Клон" rows:@[
                [FRow toggle:@"Маскировка Bundle ID" sub:[NSString stringWithFormat:@"%@ → com.mattel163.uno", FlideRealBundleID()] key:kSpoof],
            ] footer:@"Живёт рядом с обычным UNO. Игра видит оригинальный ID — вход и сохранения работают. Нужен перезапуск."]];
        NSMutableArray *boot = [NSMutableArray arrayWithObjects:
            [FRow toggle:@"Бут-лого при запуске" sub:@"Анимированная заставка FLIDE" key:kBoot],
            [FRow title:@"Своя картинка" sub:[FlideBoot hasCustomImage] ? @"Стоит своя ✓" : @"Сейчас стандартное ✦ FLIDE"
                 action:^(UIView *v) { ws.pickingBoot = YES; [ws openPhotoPicker]; }],
            [FRow title:@"Показать сейчас" sub:nil action:^(UIView *v) {
                [ws close];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [FlideBoot showAnimated]; });
            }], nil];
        if ([FlideBoot hasCustomImage])
            [boot insertObject:[FRow title:@"Вернуть стандартное" sub:nil action:^(UIView *v) {
                [FlideBoot setCustomImage:nil]; [ws toast:@"Стандартное лого"]; [ws reload];
            }] atIndex:2];
        [S addObject:[FSection title:@"Бут-лого" rows:boot footer:@"Картинка с прозрачностью (PNG) смотрится лучше всего."]];
        [S addObject:[FSection title:@"Качество" rows:@[
            [FRow toggle:@"HD-текстуры" sub:@"Анизотропия 16×, трилинейная фильтрация, резче мипмапы" key:kHD],
            [FRow toggle:@"Макс. FPS" sub:@"До 120 Гц на ProMotion" key:kFPS120],
        ] footer:nil]];
        [S addObject:[FSection title:@"Файлы" rows:@[
            [FRow title:@"Экспортировать все текстуры" sub:@"PNG в «Файлы → UNO → FLIDE/export»" action:^(UIView *v) {
                NSUInteger n = [E exportAllTextures];
                [ws toast:[NSString stringWithFormat:@"Сохранено: %lu", (unsigned long)n]];
            }],
        ] footer:@"Экспорт нужен, чтобы улучшить текстуры (апскейл) и залить обратно."]];
        FRow *reset = [FRow title:@"Сбросить все настройки FLIDE" sub:nil action:^(UIView *v) {
            for (NSString *k in @[kTexts, kAuras, kTextures, kHD, kFPS120, kFxTouch, kFxCombo, kFxStyle, kFxColor])
                [FDefaults() removeObjectForKey:k];
            [NSFileManager.defaultManager removeItemAtPath:FlideDir(@"textures") error:nil];
            [[FlideFX shared] reloadRules];
            [ws toast:@"Сброшено. Перезапусти игру"];
            [ws reload];
        }];
        reset.destructive = YES;
        [S addObject:[FSection title:nil rows:@[reset]
                              footer:@"FLIDE · только визуал на твоём устройстве. Меню: тройной тап двумя пальцами."]];
        break;
    }
    case FTabTextures: {
        self.table.tableHeaderView = self.search;
        if (!self.items) self.items = [E scanTextures];
        NSDictionary *replaced = [FDefaults() dictionaryForKey:kTextures];
        NSMutableArray *rows = [NSMutableArray new];
        for (FlideItem *it in [self filtered]) {
            FRow *r = [FRow title:it.name sub:[NSString stringWithFormat:@"%@%@", it.detail, replaced[it.name] ? @" · заменена ✓" : @""]
                           action:^(UIView *v) { [ws textureActions:it source:v]; }];
            r.item = it;
            [rows addObject:r];
        }
        [S addObject:[FSection title:[NSString stringWithFormat:@"Текстуры на экране · %lu", (unsigned long)rows.count] rows:rows
                              footer:@"Совет: фоны обычно называются bg / background / table. Картинка подгоняется под размер оригинала."]];
        break;
    }
    case FTabTexts: {
        self.table.tableHeaderView = self.search;
        if (!self.items) self.items = [E scanTexts];
        NSDictionary *rules = [FDefaults() dictionaryForKey:kTexts];
        NSMutableArray *active = [NSMutableArray new];
        [rules enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSString *text, BOOL *stop) {
            [active addObject:[FRow title:[NSString stringWithFormat:@"«%@»", text] sub:path action:^(UIView *v) {
                [E setOverride:nil forPath:path];
                [ws toast:@"Подмена убрана"];
                [ws reload];
            }]];
        }];
        if (active.count)
            [S addObject:[FSection title:@"Активные подмены" rows:active footer:@"Нажми, чтобы убрать."]];
        NSMutableArray *rows = [NSMutableArray new];
        for (FlideItem *it in [self filtered])
            [rows addObject:[FRow title:it.detail sub:it.name action:^(UIView *v) { [ws editText:it]; }]];
        [S addObject:[FSection title:@"Тексты на экране" rows:rows
                              footer:@"Монеты: найди строку с числом монет и задай любое значение. Это только визуал — на сервере ничего не меняется."]];
        break;
    }
    case FTabFX: {
        if (self.pickingElement) {
            self.table.tableHeaderView = self.search;
            if (!self.items) self.items = [E scanElements];
            NSMutableArray *rows = [NSMutableArray new];
            [rows addObject:[FRow title:@"← Назад" sub:nil action:^(UIView *v) {
                ws.pickingElement = NO; ws.items = nil; [ws reload];
            }]];
            for (FlideItem *it in [self filtered])
                [rows addObject:[FRow title:it.name.lastPathComponent sub:[NSString stringWithFormat:@"%@ · %@", it.detail, it.name]
                                     action:^(UIView *v) { [ws chooseStyleForPath:it.name source:v]; }]];
            [S addObject:[FSection title:@"Выбери элемент" rows:rows
                                  footer:@"Аватар игрока, рамка хода, колода… Если выбрать подсветку хода — аура будет только у того, кто ходит."]];
            break;
        }
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
        NSDictionary *rules = [FDefaults() dictionaryForKey:kAuras];
        [rules enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSDictionary *cfg, BOOL *stop) {
            FRow *r = [FRow title:[NSString stringWithFormat:@"%@  %@", FlideFxStyleName([cfg[@"style"] integerValue]), path.lastPathComponent]
                              sub:path action:^(UIView *v) { [ws removeAura:path]; }];
            r.swatch = FlideColorFromHex(cfg[@"color"]);
            [auras addObject:r];
        }];
        [auras addObject:[FRow title:@"＋ Добавить ауру к элементу" sub:nil action:^(UIView *v) {
            ws.pickingElement = YES; ws.items = nil; [ws reload];
        }]];
        [S addObject:[FSection title:@"Ауры" rows:auras footer:@"Нажми на ауру, чтобы удалить. Цвет берётся из настройки выше."]];
        break;
    }
    }
    self.sections = S;
    [self.table reloadData];
}

#pragma mark - действия

- (void)textureActions:(FlideItem *)it source:(UIView *)src {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:it.name message:it.detail preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Заменить картинкой из Фото" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.pendingTexture = it;
        self.pickingBoot = NO;
        [self openPhotoPicker];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Сохранить PNG" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSURL *u = [[FlideEngine shared] exportTexture:it];
        [self toast:u ? @"Сохранено в FLIDE/export" : @"Не удалось прочитать текстуру"];
    }]];
    if ([FDefaults() dictionaryForKey:kTextures][it.name])
        [a addAction:[UIAlertAction actionWithTitle:@"Вернуть оригинал" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [[FlideEngine shared] resetTexture:it];
            [self toast:@"Оригинал вернётся после перезапуска"];
            [self reload];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openPhotoPicker {
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
    if (self.pickingBoot) {
        self.pickingBoot = NO;
        if (![p canLoadObjectOfClass:UIImage.class]) return;
        [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL ok = [obj isKindOfClass:UIImage.class] && [FlideBoot setCustomImage:(UIImage *)obj];
                [self toast:ok ? @"Бут-лого обновлено ✦" : @"Не получилось"];
                [self reload];
            });
        }];
        return;
    }
    FlideItem *target = self.pendingTexture;
    if (!p || !target || ![p canLoadObjectOfClass:UIImage.class]) return;
    [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = [obj isKindOfClass:UIImage.class] && [[FlideEngine shared] replaceTexture:target withImage:(UIImage *)obj];
            [self toast:ok ? @"Текстура заменена ✦" : @"Не получилось заменить"];
            [self reload];
        });
    }];
}

- (void)editText:(FlideItem *)it {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Заменить текст" message:it.name preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = it.detail; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Заменить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[FlideEngine shared] setOverride:a.textFields.firstObject.text forPath:it.name];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickStyle:(void (^)(FlideFxStyle))done source:(UIView *)src {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Стиль эффекта" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger s = 0; s < FlideFxStyleCount; s++)
        [a addAction:[UIAlertAction actionWithTitle:FlideFxStyleName(s) style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(s); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseStyleForPath:(NSString *)path source:(UIView *)src {
    [self pickStyle:^(FlideFxStyle s) {
        NSMutableDictionary *d = [[FDefaults() dictionaryForKey:kAuras] mutableCopy] ?: [NSMutableDictionary new];
        d[path] = @{ @"style": @(s), @"color": [FDefaults() stringForKey:kFxColor] ?: @"#7CF7FF", @"radius": @46 };
        [FDefaults() setObject:d forKey:kAuras];
        [[FlideFX shared] reloadRules];
        self.pickingElement = NO; self.items = nil;
        [self toast:@"Аура добавлена ✦"];
        [self reload];
    } source:src];
}

- (void)removeAura:(NSString *)path {
    NSMutableDictionary *d = [[FDefaults() dictionaryForKey:kAuras] mutableCopy];
    [d removeObjectForKey:path];
    [FDefaults() setObject:d ?: @{} forKey:kAuras];
    [[FlideFX shared] reloadRules];
    [self reload];
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

- (void)toggle:(UISwitch *)sw {
    FRow *r = self.sections[sw.tag >> 16].rows[sw.tag & 0xFFFF];
    [FDefaults() setBool:sw.on forKey:r.defaultsKey];
    if ([r.defaultsKey isEqualToString:kFPS120] || [r.defaultsKey isEqualToString:kHD]) [[FlideEngine shared] applyQuality];
}

#pragma mark - таблица

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t { [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.sections[s].rows.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return self.sections[s].title; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return self.sections[s].footer; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    FRow *r = self.sections[ip.section].rows[ip.row];
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    c.textLabel.text = r.title;
    c.textLabel.numberOfLines = 2;
    c.textLabel.textColor = r.destructive ? UIColor.systemRedColor : UIColor.whiteColor;
    c.detailTextLabel.text = r.subtitle;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    c.imageView.image = nil;
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (r.defaultsKey) {
        UISwitch *sw = [UISwitch new];
        sw.on = FBool(r.defaultsKey);
        sw.tag = (ip.section << 16) | ip.row;
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (r.swatch) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
        dot.layer.cornerRadius = 11;
        dot.backgroundColor = r.swatch;
        dot.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
        dot.layer.borderWidth = 1;
        c.accessoryView = dot;
    }

    if (r.item && self.tabs.selectedSegmentIndex == FTabTextures) {
        c.imageView.image = r.item.preview ?: [UIImage systemImageNamed:@"photo"];
        c.imageView.tintColor = [UIColor colorWithWhite:1 alpha:0.3];
        if (!r.item.preview) [self queuePreview:r.item];
    }
    return c;
}

// превью грузим по одному за тик, чтобы не тормозить игру
- (void)queuePreview:(FlideItem *)it {
    NSNumber *key = @(it.instanceID);
    if ([self.previewQueue containsObject:key]) return;
    [self.previewQueue addObject:key];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *img = [[FlideEngine shared] imageOfTexture:it maxSide:96];
        if (!img) return;
        UIGraphicsImageRenderer *rr = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(44, 44)];
        it.preview = [rr imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 44, 44) cornerRadius:9] addClip];
            CGSize s = img.size; CGFloat k = MIN(44 / s.width, 44 / s.height);
            [img drawInRect:CGRectMake((44 - s.width * k) / 2, (44 - s.height * k) / 2, s.width * k, s.height * k)];
        }];
        for (NSIndexPath *ip in self.table.indexPathsForVisibleRows) {
            FRow *r = self.sections[ip.section].rows[ip.row];
            if (r.item == it) { [self.table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone]; break; }
        }
    });
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    FRow *r = self.sections[ip.section].rows[ip.row];
    if (r.action) r.action([tv cellForRowAtIndexPath:ip] ?: tv);
}

@end

#pragma mark - жест и показ

@implementation FlideMenu

static UIWindow *gameWindow(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if (w.isKeyWindow && w.userInteractionEnabled) return w;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if (w.userInteractionEnabled && w.rootViewController) return w;
    }
    return nil;
}

+ (void)show {
    if (gFlideMenuVisible) return;
    UIViewController *top = gameWindow().rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return;
    FlideMenuVC *vc = [FlideMenuVC new];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    gFlideMenuVisible = YES;
    [top presentViewController:vc animated:YES completion:nil];
}

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

    if (![FDefaults() boolForKey:@"flide.welcomed"]) {
        [FDefaults() setBool:YES forKey:@"flide.welcomed"];
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
    }];
}

@end
