// FLIDE · редактор текстуры с предпросмотром.
// Слева — как сейчас в игре, справа — что получится. «Применить» меняет текстуру
// прямо в игре, «Оригинал» возвращает как было.
#import "FlideCore.h"
#import <PhotosUI/PhotosUI.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

typedef NS_ENUM(NSInteger, FFit) { FFitFill, FFitFit, FFitStretch };

NSArray<NSString *> *FlideFilterNames(void) {
    return @[@"Без фильтра", @"Неон", @"Ч/Б", @"Инверсия", @"Тёплый", @"Холодный",
             @"Пиксели", @"Комикс", @"Постер", @"Сочный", @"Винтаж", @"Тьма",
             @"Пастель", @"Протанопия", @"Дейтеранопия", @"Тританопия"];
}

static CIContext *ciContext(void) {
    static CIContext *c;
    if (!c) c = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @NO }];
    return c;
}

// матрица цвета (строки R, G, B)
static CIImage *colorMatrix(CIImage *img, CGFloat m[9]) {
    return [img imageByApplyingFilter:@"CIColorMatrix" withInputParameters:@{
        @"inputRVector": [CIVector vectorWithX:m[0] Y:m[1] Z:m[2] W:0],
        @"inputGVector": [CIVector vectorWithX:m[3] Y:m[4] Z:m[5] W:0],
        @"inputBVector": [CIVector vectorWithX:m[6] Y:m[7] Z:m[8] W:0],
        @"inputAVector": [CIVector vectorWithX:0 Y:0 Z:0 W:1]}];
}

UIImage *FlideFilterImage(UIImage *src, NSInteger filter, float hue, float strength) {
    if (!src.CGImage) return src;
    CIImage *base = [CIImage imageWithCGImage:src.CGImage];
    CIImage *img = base;
    CGFloat scale = MAX(base.extent.size.width, base.extent.size.height) / 1024.0;
    switch (filter) {
        case 1:
            img = [img imageByApplyingFilter:@"CIColorControls" withInputParameters:@{@"inputSaturation": @2.2, @"inputContrast": @1.35, @"inputBrightness": @0.05}];
            img = [img imageByApplyingFilter:@"CIBloom" withInputParameters:@{@"inputRadius": @(6 * scale + 2), @"inputIntensity": @1.0}];
            break;
        case 2: img = [img imageByApplyingFilter:@"CIPhotoEffectNoir" withInputParameters:@{}]; break;
        case 3: img = [img imageByApplyingFilter:@"CIColorInvert" withInputParameters:@{}]; break;
        case 4: img = [img imageByApplyingFilter:@"CITemperatureAndTint" withInputParameters:@{@"inputNeutral": [CIVector vectorWithX:6500 Y:0], @"inputTargetNeutral": [CIVector vectorWithX:4200 Y:0]}]; break;
        case 5: img = [img imageByApplyingFilter:@"CITemperatureAndTint" withInputParameters:@{@"inputNeutral": [CIVector vectorWithX:6500 Y:0], @"inputTargetNeutral": [CIVector vectorWithX:11000 Y:0]}]; break;
        case 6: img = [img imageByApplyingFilter:@"CIPixellate" withInputParameters:@{@"inputScale": @(MAX(2, 10 * scale)), @"inputCenter": [CIVector vectorWithX:0 Y:0]}]; break;
        case 7: img = [img imageByApplyingFilter:@"CIComicEffect" withInputParameters:@{}]; break;
        case 8: img = [img imageByApplyingFilter:@"CIColorPosterize" withInputParameters:@{@"inputLevels": @5}]; break;
        case 9: img = [img imageByApplyingFilter:@"CIVibrance" withInputParameters:@{@"inputAmount": @1.0}];
                img = [img imageByApplyingFilter:@"CIColorControls" withInputParameters:@{@"inputSaturation": @1.5, @"inputContrast": @1.15}]; break;
        case 10: img = [img imageByApplyingFilter:@"CIPhotoEffectTransfer" withInputParameters:@{}]; break;
        case 11: img = [img imageByApplyingFilter:@"CIColorControls" withInputParameters:@{@"inputBrightness": @-0.25, @"inputContrast": @1.4, @"inputSaturation": @0.7}]; break;
        case 12: img = [img imageByApplyingFilter:@"CIColorControls" withInputParameters:@{@"inputBrightness": @0.12, @"inputContrast": @0.85, @"inputSaturation": @0.6}]; break;
        // коррекция для дальтоников (daltonize: переносим неразличимые оттенки в различимые)
        case 13: { CGFloat m[9] = {1,0,0, 0.7,1,0, 0.7,0,1}; img = colorMatrix(img, m); break; }
        case 14: { CGFloat m[9] = {1,0.7,0, 0,1,0, 0,0.7,1}; img = colorMatrix(img, m); break; }
        case 15: { CGFloat m[9] = {1,0,0.7, 0,1,0.7, 0,0,1}; img = colorMatrix(img, m); break; }
        default: break;
    }
    if (fabsf(hue) > 0.01)
        img = [img imageByApplyingFilter:@"CIHueAdjust" withInputParameters:@{@"inputAngle": @(hue)}];
    img = [img imageByCroppingToRect:base.extent];
    if (strength < 0.99) {
        CIImage *mask = [[CIImage imageWithColor:[CIColor colorWithRed:strength green:strength blue:strength]] imageByCroppingToRect:base.extent];
        img = [img imageByApplyingFilter:@"CIBlendWithMask" withInputParameters:@{@"inputBackgroundImage": base, @"inputMaskImage": mask}];
    }
    img = [img imageByApplyingFilter:@"CISourceInCompositing" withInputParameters:@{@"inputBackgroundImage": base}];
    CGImageRef cg = [ciContext() createCGImage:img fromRect:base.extent];
    UIImage *out = cg ? [UIImage imageWithCGImage:cg] : src;
    if (cg) CGImageRelease(cg);
    return out;
}

@interface FlideTextureEditor () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) FlideItem *item;
@property (nonatomic, assign) CGSize texSize;
@property (nonatomic, strong) UIImage *current, *source, *result;
@property (nonatomic, strong) UIImageView *leftView, *rightView;
@property (nonatomic, strong) UISegmentedControl *fit;
@property (nonatomic, strong) UISlider *hue, *strength;
@property (nonatomic, strong) UIScrollView *chips;
@property (nonatomic, strong) UIStackView *buttons;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, assign) NSInteger filter;
@property (nonatomic, assign) BOOL pickingFrames;
@property (nonatomic, copy) void (^onChange)(void);
@end

@implementation FlideTextureEditor

+ (instancetype)editorForItem:(FlideItem *)item onChange:(void (^)(void))onChange {
    FlideTextureEditor *e = [FlideTextureEditor new];
    e.item = item;
    e.onChange = onChange;
    e.modalPresentationStyle = UIModalPresentationOverFullScreen;
    e.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    return e;
}

- (UIView *)glassPanel {
    UIVisualEffect *effect;
    Class glass = NSClassFromString(@"UIGlassEffect");
    effect = glass ? [glass new] : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.layer.cornerRadius = 30;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    return v;
}

- (UIImageView *)previewView:(NSString *)caption {
    UIImageView *iv = [UIImageView new];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    iv.layer.cornerRadius = 16;
    iv.clipsToBounds = YES;
    // шахматка под прозрачностью
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16, 16)];
    UIImage *checker = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [[UIColor colorWithWhite:0.18 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, 16, 16));
        [[UIColor colorWithWhite:0.26 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, 8, 8)); UIRectFill(CGRectMake(8, 8, 8, 8));
    }];
    iv.backgroundColor = [UIColor colorWithPatternImage:checker];
    UILabel *l = [UILabel new];
    l.text = caption;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    l.textColor = UIColor.whiteColor;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.cornerRadius = 8; l.clipsToBounds = YES;
    l.frame = CGRectMake(8, 8, 90, 18);
    [iv addSubview:l];
    return iv;
}

- (UIButton *)button:(NSString *)title action:(SEL)sel tint:(UIColor *)tint {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.tintColor = UIColor.whiteColor;
    b.backgroundColor = tint ?: [UIColor colorWithWhite:1 alpha:0.12];
    b.layer.cornerRadius = 14;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

    self.panel = [self glassPanel];
    [self.view addSubview:self.panel];
    UIView *c = ((UIVisualEffectView *)self.panel).contentView;

    UILabel *title = [UILabel new];
    title.text = self.item.name;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.tag = 1;
    [c addSubview:title];

    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    x.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    x.tag = 2;
    [x addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:x];

    self.leftView = [self previewView:@"СЕЙЧАС"];
    self.rightView = [self previewView:@"БУДЕТ"];
    [c addSubview:self.leftView];
    [c addSubview:self.rightView];

    self.fit = [[UISegmentedControl alloc] initWithItems:@[@"Заполнить", @"Вписать", @"Растянуть"]];
    self.fit.selectedSegmentIndex = 0;
    [self.fit addTarget:self action:@selector(render) forControlEvents:UIControlEventValueChanged];
    [c addSubview:self.fit];

    self.chips = [UIScrollView new];
    self.chips.showsHorizontalScrollIndicator = NO;
    [c addSubview:self.chips];
    CGFloat x0 = 0;
    NSArray *names = FlideFilterNames();
    for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.tintColor = UIColor.whiteColor;
        b.layer.cornerRadius = 14;
        b.tag = 100 + i;
        CGFloat w = [names[i] sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font}].width + 24;
        b.frame = CGRectMake(x0, 0, w, 28);
        x0 += w + 6;
        [b addTarget:self action:@selector(chip:) forControlEvents:UIControlEventTouchUpInside];
        [self.chips addSubview:b];
    }
    self.chips.contentSize = CGSizeMake(x0, 28);

    self.hue = [UISlider new];
    self.hue.minimumValue = -M_PI; self.hue.maximumValue = M_PI; self.hue.value = 0;
    self.hue.minimumValueImage = [UIImage systemImageNamed:@"paintpalette"];
    self.hue.tintColor = FlideColorFromHex([FDefaults() stringForKey:kFxColor]);
    [self.hue addTarget:self action:@selector(render) forControlEvents:UIControlEventValueChanged];
    [c addSubview:self.hue];

    self.strength = [UISlider new];
    self.strength.minimumValue = 0; self.strength.maximumValue = 1; self.strength.value = 1;
    self.strength.minimumValueImage = [UIImage systemImageNamed:@"circle.lefthalf.filled"];
    self.strength.tintColor = self.hue.tintColor;
    [self.strength addTarget:self action:@selector(render) forControlEvents:UIControlEventValueChanged];
    [c addSubview:self.strength];

    self.buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self button:@"🖼 Фото" action:@selector(pickPhoto) tint:nil],
        [self button:@"↺ Оригинал" action:@selector(restore) tint:nil],
        [self button:@"⬇︎ PNG" action:@selector(savePNG) tint:nil],
        [self button:@"🎞 Анимация" action:@selector(pickAnimation) tint:nil],
        [self button:@"✦ Применить" action:@selector(apply) tint:self.hue.tintColor],
    ]];
    self.buttons.distribution = UIStackViewDistributionFillEqually;
    self.buttons.spacing = 8;
    [c addSubview:self.buttons];

    [self loadImages];
    [self chip:[self.chips viewWithTag:100]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat W = MIN(720, safe.size.width - 24), H = MIN(560, safe.size.height - 16);
    self.panel.frame = CGRectMake(CGRectGetMidX(safe) - W / 2, CGRectGetMidY(safe) - H / 2, W, H);
    UIView *c = ((UIVisualEffectView *)self.panel).contentView;
    [c viewWithTag:1].frame = CGRectMake(20, 12, W - 70, 26);
    [c viewWithTag:2].frame = CGRectMake(W - 46, 8, 36, 36);

    CGFloat controlsH = 32 + 8 + 28 + 8 + 30 + 30 + 8 + 44;
    CGFloat pvH = H - 48 - controlsH - 24;
    CGFloat pvW = (W - 48) / 2;
    self.leftView.frame = CGRectMake(16, 46, pvW, pvH);
    self.rightView.frame = CGRectMake(32 + pvW, 46, pvW, pvH);
    CGFloat y = 46 + pvH + 10;
    self.fit.frame = CGRectMake(16, y, W - 32, 32); y += 40;
    self.chips.frame = CGRectMake(16, y, W - 32, 28); y += 34;
    self.hue.frame = CGRectMake(16, y, (W - 40) / 2, 30);
    self.strength.frame = CGRectMake(24 + (W - 40) / 2, y, (W - 40) / 2, 30); y += 38;
    self.buttons.frame = CGRectMake(16, y, W - 32, 44);
}

- (void)close {
    if (self.onChange) self.onChange();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [a dismissViewControllerAnimated:YES completion:nil];
    });
}

#pragma mark - картинки

- (void)loadImages {
    FlideEngine *E = [FlideEngine shared];
    self.current = [E imageOfTexture:self.item maxSide:1024];
    UIImage *orig = [E originalOfTexture:self.item];
    self.source = orig ?: self.current;
    self.texSize = self.current ? CGSizeMake(self.current.size.width, self.current.size.height) : CGSizeMake(512, 512);
    // точный размер текстуры из подписи «W×H»
    NSArray *wh = [self.item.detail componentsSeparatedByString:@"×"];
    if (wh.count == 2) self.texSize = CGSizeMake([wh[0] doubleValue], [wh[1] doubleValue]);
    self.leftView.image = self.current;
    if (!self.current) [self toast:FlideGuardTripped(@"preview")
        ? @"Превью отключено после вылета. Включи в «Главное → Восстановить функции»"
        : @"Не удалось прочитать текстуру — но заменить её всё равно можно"];
}

- (UIImage *)composeAtScale:(CGFloat)scale {
    if (!self.source) return nil;
    CGSize T = CGSizeMake(MAX(1, round(self.texSize.width * scale)), MAX(1, round(self.texSize.height * scale)));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1; f.opaque = NO;
    UIImage *fitted = [[[UIGraphicsImageRenderer alloc] initWithSize:T format:f] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGSize s = self.source.size;
        CGRect r;
        switch ((FFit)self.fit.selectedSegmentIndex) {
            case FFitStretch: r = CGRectMake(0, 0, T.width, T.height); break;
            case FFitFit: {
                CGFloat k = MIN(T.width / s.width, T.height / s.height);
                r = CGRectMake((T.width - s.width * k) / 2, (T.height - s.height * k) / 2, s.width * k, s.height * k);
                break;
            }
            default: {
                CGFloat k = MAX(T.width / s.width, T.height / s.height);
                r = CGRectMake((T.width - s.width * k) / 2, (T.height - s.height * k) / 2, s.width * k, s.height * k);
            }
        }
        [self.source drawInRect:r];
    }];

    return FlideFilterImage(fitted, self.filter, self.hue.value, self.strength.value);
}

- (void)render {
    CGFloat k = MIN(1.0, 512.0 / MAX(self.texSize.width, self.texSize.height)); // превью быстрое
    self.rightView.image = [self composeAtScale:k];
}

- (void)chip:(UIButton *)b {
    self.filter = b.tag - 100;
    for (UIButton *o in self.chips.subviews)
        if ([o isKindOfClass:UIButton.class])
            o.backgroundColor = o == b ? [self.hue.tintColor colorWithAlphaComponent:0.6] : [UIColor colorWithWhite:1 alpha:0.1];
    [self render];
}

#pragma mark - действия

- (void)pickAnimation {
    self.pickingFrames = YES;
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 30;
    cfg.selection = PHPickerConfigurationSelectionOrdered;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

// GIF → кадры
static NSArray<UIImage *> *framesFromGIF(NSData *data, double *fps) {
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return @[];
    size_t n = CGImageSourceGetCount(src);
    NSMutableArray *out = [NSMutableArray new];
    double total = 0;
    size_t step = MAX((size_t)1, n / 30); // не больше 30 кадров
    for (size_t i = 0; i < n; i += step) {
        CGImageRef cg = CGImageSourceCreateImageAtIndex(src, i, NULL);
        if (cg) { [out addObject:[UIImage imageWithCGImage:cg]]; CGImageRelease(cg); }
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, i, NULL));
        NSNumber *d = props[(NSString *)kCGImagePropertyGIFDictionary][(NSString *)kCGImagePropertyGIFDelayTime];
        total += (d.doubleValue > 0 ? d.doubleValue : 0.1) * step;
    }
    CFRelease(src);
    if (fps && out.count) *fps = MIN(12, MAX(2, out.count / MAX(total, 0.1)));
    return out;
}

- (void)loadFrames:(NSArray<PHPickerResult *> *)results {
    NSMutableArray *frames = [NSMutableArray new];
    __block double fps = 8;
    dispatch_group_t g = dispatch_group_create();
    NSMutableDictionary *byIndex = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < results.count; i++) {
        NSItemProvider *p = results[i].itemProvider;
        dispatch_group_enter(g);
        if (results.count == 1 && [p hasItemConformingToTypeIdentifier:@"com.compuserve.gif"]) {
            [p loadDataRepresentationForTypeIdentifier:@"com.compuserve.gif" completionHandler:^(NSData *data, NSError *e) {
                double f = 8;
                NSArray *fr = data ? framesFromGIF(data, &f) : @[];
                @synchronized (byIndex) { for (NSUInteger k = 0; k < fr.count; k++) byIndex[@(k)] = fr[k]; fps = f; }
                dispatch_group_leave(g);
            }];
        } else {
            [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *e) {
                if ([obj isKindOfClass:UIImage.class]) @synchronized (byIndex) { byIndex[@(i)] = obj; }
                dispatch_group_leave(g);
            }];
        }
    }
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        for (NSNumber *k in [byIndex.allKeys sortedArrayUsingSelector:@selector(compare:)]) [frames addObject:byIndex[k]];
        if (frames.count < 2) { [self toast:@"Нужно минимум 2 кадра или GIF"]; return; }
        NSMutableArray *styled = [NSMutableArray new];
        UIImage *keep = self.source;
        for (UIImage *f in frames) @autoreleasepool { self.source = f; [styled addObject:[self composeAtScale:1.0] ?: f]; }
        self.source = keep;
        BOOL ok = [[FlidePacks shared] setAnimationForTexture:self.item.name frames:styled fps:fps size:self.texSize];
        [self toast:ok ? [NSString stringWithFormat:@"Анимация: %lu кадров ✦", (unsigned long)styled.count] : @"Не получилось"];
    });
}

- (void)pickPhoto {
    self.pickingFrames = NO;
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (self.pickingFrames) { self.pickingFrames = NO; if (results.count) [self loadFrames:results]; return; }
    NSItemProvider *p = results.firstObject.itemProvider;
    if (![p canLoadObjectOfClass:UIImage.class]) return;
    [p loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![obj isKindOfClass:UIImage.class]) return;
            // нормализуем ориентацию фото
            UIImage *img = (UIImage *)obj;
            UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = 1;
            self.source = [[[UIGraphicsImageRenderer alloc] initWithSize:img.size format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
                [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
            }];
            [self render];
        });
    }];
}

- (void)apply {
    UIImage *full = [self composeAtScale:1.0];
    BOOL ok = full && [[FlideEngine shared] replaceTexture:self.item withImage:full];
    if (ok) {
        self.current = [[FlideEngine shared] imageOfTexture:self.item maxSide:1024] ?: full;
        self.leftView.image = self.current;
    }
    [self toast:ok ? @"Применено в игре ✦" : @"Не получилось заменить"];
}

- (void)restore {
    BOOL instant = [[FlideEngine shared] resetTexture:self.item];
    UIImage *orig = [[FlideEngine shared] originalOfTexture:self.item];
    if (orig) { self.source = orig; [self render]; }
    self.current = [[FlideEngine shared] imageOfTexture:self.item maxSide:1024] ?: self.current;
    self.leftView.image = self.current;
    [self toast:instant ? @"Оригинал вернулся" : @"Оригинал вернётся после перезапуска"];
}

- (void)savePNG {
    UIImage *img = [self composeAtScale:1.0];
    NSString *path = [FlideDir(@"export") stringByAppendingPathComponent:
                      [[self.item.name stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByAppendingString:@"_flide.png"]];
    BOOL ok = img && [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    [self toast:ok ? @"Сохранено в FLIDE/export" : @"Не получилось"];
}

@end
