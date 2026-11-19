// FLIDE · движок: текстуры, тексты (визуальные подмены), качество, поиск элементов.
// Всё работает только на твоём устройстве. На сервер ничего не уходит.
#import "FlideCore.h"

NSString *FlideDir(NSString *sub) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [[docs stringByAppendingPathComponent:@"FLIDE"] stringByAppendingPathComponent:sub ?: @""];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *safeFileName(NSString *s) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>| "];
    NSString *r = [[s componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    return r.length ? r : @"noname";
}

@implementation FlideItem
@end

@interface FlideEngine ()
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pinned;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *replacedIDs, *hdIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *textTargets, *elementTargets;
@property (nonatomic, assign) CFTimeInterval lastTextScan, lastElementScan;
@end

@implementation FlideEngine

+ (instancetype)shared {
    static FlideEngine *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideEngine new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pinned = [NSMutableArray new];
        _replacedIDs = [NSMutableSet new];
        _hdIDs = [NSMutableSet new];
        _textTargets = [NSMutableDictionary new];
        _elementTargets = [NSMutableDictionary new];
    }
    return self;
}

- (void)start {
    // Unity крутит свой цикл на главном потоке — там же вызываем il2cpp
    [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) { [self slowTick]; }];
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *t) { [self textTick]; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self applyQuality]; });
}

#pragma mark - текстуры

- (void)unpinAll {
    for (NSNumber *h in self.pinned) FIL_Unpin(h.unsignedIntValue);
    [self.pinned removeAllObjects];
}

- (NSArray<FlideItem *> *)scanTextures {
    if (!FIL_Ready()) return @[];
    [self unpinAll];
    NSMutableArray *out = [NSMutableArray new];
    for (NSValue *v in FIL_FindAll("UnityEngine", "Texture2D")) {
        void *tex = v.pointerValue;
        int w = FIL_Int(FIL_Call0(tex, "get_width")), h = FIL_Int(FIL_Call0(tex, "get_height"));
        if (w < 16 || h < 16) continue;
        FlideItem *it = [FlideItem new];
        NSString *n = FIL_Name(tex);
        it.name = n.length ? n : @"(без имени)";
        it.detail = [NSString stringWithFormat:@"%d×%d", w, h];
        it.instanceID = FIL_InstanceID(tex);
        it.handle = FIL_Pin(tex);
        [self.pinned addObject:@(it.handle)];
        [out addObject:it];
    }
    [out sortUsingComparator:^NSComparisonResult(FlideItem *a, FlideItem *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return out;
}

// Копия текстуры через RenderTexture → читаемый Texture2D → пиксели → UIImage
- (UIImage *)imageOfTextureObject:(void *)tex maxSide:(int)maxSide {
    if (!tex) return nil;
    int w = FIL_Int(FIL_Call0(tex, "get_width")), h = FIL_Int(FIL_Call0(tex, "get_height"));
    if (w <= 0 || h <= 0) return nil;
    float k = MIN(1.0f, (float)maxSide / MAX(w, h));
    int pw = MAX(1, (int)(w * k)), ph = MAX(1, (int)(h * k));

    Il2CppClass *RT  = FIL_Class("UnityEngine", "RenderTexture");
    Il2CppClass *GFX = FIL_Class("UnityEngine", "Graphics");
    Il2CppClass *T2D = FIL_Class("UnityEngine", "Texture2D");
    Il2CppClass *OBJ = FIL_Class("UnityEngine", "Object");
    const MethodInfo *getTmp  = FIL_MethodSig(RT, "GetTemporary", "System.Int32,System.Int32");
    const MethodInfo *relTmp  = FIL_MethodSig(RT, "ReleaseTemporary", "UnityEngine.RenderTexture");
    const MethodInfo *getAct  = FIL_MethodSig(RT, "get_active", "");
    const MethodInfo *setAct  = FIL_MethodSig(RT, "set_active", "UnityEngine.RenderTexture");
    const MethodInfo *blit    = FIL_MethodSig(GFX, "Blit", "UnityEngine.Texture,UnityEngine.RenderTexture");
    const MethodInfo *ctor    = FIL_MethodSig(T2D, ".ctor", "System.Int32,System.Int32");
    const MethodInfo *read    = FIL_MethodSig(T2D, "ReadPixels", "UnityEngine.Rect,System.Int32,System.Int32");
    const MethodInfo *apply   = FIL_MethodSig(T2D, "Apply", "");
    const MethodInfo *pixels  = FIL_MethodSig(T2D, "GetPixels32", "");
    const MethodInfo *destroy = FIL_MethodSig(OBJ, "Destroy", "UnityEngine.Object");
    if (!getTmp || !relTmp || !getAct || !setAct || !blit || !ctor || !read || !apply || !pixels) {
        FLog(@"preview: Unity API недоступно");
        return nil;
    }

    BOOL ok = NO;
    void *a2[2] = { &pw, &ph };
    void *rt = FIL_Invoke(getTmp, NULL, a2, &ok);
    if (!rt) return nil;
    void *prev = FIL_Invoke(getAct, NULL, NULL, NULL);
    void *ab[2] = { tex, rt };
    FIL_Invoke(blit, NULL, ab, &ok);
    void *as[1] = { rt };
    FIL_Invoke(setAct, NULL, as, NULL);

    UIImage *img = nil;
    void *t2 = FIL_New(T2D);
    FIL_Invoke(ctor, t2, a2, &ok);
    if (ok) {
        FRect r = { 0, 0, (float)pw, (float)ph };
        int zero = 0;
        void *ar[3] = { &r, &zero, &zero };
        FIL_Invoke(read, t2, ar, &ok);
        FIL_Invoke(apply, t2, NULL, NULL);
        void *arr = FIL_Invoke(pixels, t2, NULL, &ok);
        NSUInteger n = FIL_ArrayLength(arr);
        if (ok && n == (NSUInteger)(pw * ph)) {
            const uint8_t *src = (const uint8_t *)FIL_ArrayData(arr);
            NSMutableData *buf = [NSMutableData dataWithLength:n * 4];
            uint8_t *dst = buf.mutableBytes;
            for (int y = 0; y < ph; y++) // у Unity начало координат снизу
                memcpy(dst + (size_t)y * pw * 4, src + (size_t)(ph - 1 - y) * pw * 4, (size_t)pw * 4);
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGDataProviderRef dp = CGDataProviderCreateWithCFData((__bridge CFDataRef)buf);
            CGImageRef cg = CGImageCreate(pw, ph, 8, 32, pw * 4, cs,
                                          kCGBitmapByteOrderDefault | kCGImageAlphaLast, dp, NULL, false,
                                          kCGRenderingIntentDefault);
            if (cg) { img = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
            CGDataProviderRelease(dp);
            CGColorSpaceRelease(cs);
        }
    }
    void *ap[1] = { prev };
    FIL_Invoke(setAct, NULL, ap, NULL);
    FIL_Invoke(relTmp, NULL, as, NULL);
    if (destroy && t2) { void *ad[1] = { t2 }; FIL_Invoke(destroy, NULL, ad, NULL); }
    return img;
}

- (UIImage *)imageOfTexture:(FlideItem *)item maxSide:(int)maxSide {
    return [self imageOfTextureObject:FIL_Target(item.handle) maxSide:maxSide];
}

static NSData *pngFitted(UIImage *image, int w, int h) {
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1; f.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h) format:f];
    return [r PNGDataWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGSize s = image.size;
        CGFloat k = MAX(w / s.width, h / s.height); // заполнить без искажений
        CGSize d = CGSizeMake(s.width * k, s.height * k);
        [image drawInRect:CGRectMake((w - d.width) / 2, (h - d.height) / 2, d.width, d.height)];
    }];
}

- (BOOL)loadPNG:(NSData *)png intoTexture:(void *)tex {
    Il2CppClass *IC = FIL_Class("UnityEngine", "ImageConversion");
    const MethodInfo *load = FIL_MethodSig(IC, "LoadImage", "UnityEngine.Texture2D,System.Byte[]");
    if (!load || !tex) return NO;
    void *args[2] = { tex, FIL_NewByteArray(png) };
    BOOL ok = NO;
    void *r = FIL_Invoke(load, NULL, args, &ok);
    return ok && FIL_Bool(r);
}

- (BOOL)replaceTexture:(FlideItem *)item withImage:(UIImage *)image {
    void *tex = FIL_Target(item.handle);
    if (!tex || !image) return NO;
    int w = FIL_Int(FIL_Call0(tex, "get_width")), h = FIL_Int(FIL_Call0(tex, "get_height"));
    NSData *png = pngFitted(image, w, h); // размер как у оригинала — спрайты в атласе не съедут
    if (![self loadPNG:png intoTexture:tex]) return NO;

    NSString *file = [safeFileName(item.name) stringByAppendingPathExtension:@"png"];
    [png writeToFile:[FlideDir(@"textures") stringByAppendingPathComponent:file] atomically:YES];
    NSMutableDictionary *idx = [[FDefaults() dictionaryForKey:kTextures] mutableCopy] ?: [NSMutableDictionary new];
    idx[item.name] = file;
    [FDefaults() setObject:idx forKey:kTextures];
    [self.replacedIDs addObject:@(item.instanceID)];
    item.preview = nil;
    return YES;
}

- (void)resetTexture:(FlideItem *)item {
    NSMutableDictionary *idx = [[FDefaults() dictionaryForKey:kTextures] mutableCopy];
    NSString *file = idx[item.name];
    if (file) [NSFileManager.defaultManager removeItemAtPath:[FlideDir(@"textures") stringByAppendingPathComponent:file] error:nil];
    [idx removeObjectForKey:item.name];
    [FDefaults() setObject:idx ?: @{} forKey:kTextures];
}

- (NSURL *)exportTexture:(FlideItem *)item {
    UIImage *img = [self imageOfTexture:item maxSide:4096];
    if (!img) return nil;
    NSString *path = [FlideDir(@"export") stringByAppendingPathComponent:
                      [safeFileName(item.name) stringByAppendingPathExtension:@"png"]];
    return [UIImagePNGRepresentation(img) writeToFile:path atomically:YES] ? [NSURL fileURLWithPath:path] : nil;
}

- (NSUInteger)exportAllTextures {
    NSUInteger n = 0;
    for (FlideItem *it in [self scanTextures]) @autoreleasepool { if ([self exportTexture:it]) n++; }
    return n;
}

#pragma mark - качество

- (void)applyQuality {
    if (!FIL_Ready()) return;
    if (FBool(kFPS120)) {
        int fps = (int)UIScreen.mainScreen.maximumFramesPerSecond;
        void *a[1] = { &fps };
        FIL_Static("UnityEngine", "Application", "set_targetFrameRate", 1, a);
    }
}

- (void)hdTexture:(void *)tex {
    int aniso = 16, trilinear = 2; float bias = -0.3f;
    FIL_Call1(tex, "set_anisoLevel", &aniso);
    FIL_Call1(tex, "set_filterMode", &trilinear);
    FIL_Call1(tex, "set_mipMapBias", &bias);
}

#pragma mark - периодические задачи

- (void)slowTick {
    if (!FIL_Ready()) return;
    NSDictionary *idx = [FDefaults() dictionaryForKey:kTextures];
    BOOL hd = FBool(kHD);
    if (!idx.count && !hd) return;
    for (NSValue *v in FIL_FindAll("UnityEngine", "Texture2D")) {
        void *tex = v.pointerValue;
        NSNumber *iid = @(FIL_InstanceID(tex));
        if (hd && ![self.hdIDs containsObject:iid]) { [self hdTexture:tex]; [self.hdIDs addObject:iid]; }
        if (idx.count && ![self.replacedIDs containsObject:iid]) {
            NSString *file = idx[FIL_Name(tex)];
            if (file) {
                NSData *png = [NSData dataWithContentsOfFile:[FlideDir(@"textures") stringByAppendingPathComponent:file]];
                UIImage *img = png ? [UIImage imageWithData:png] : nil;
                int w = FIL_Int(FIL_Call0(tex, "get_width")), h = FIL_Int(FIL_Call0(tex, "get_height"));
                if (img && (img.size.width != w || img.size.height != h)) png = pngFitted(img, w, h);
                if (png) [self loadPNG:png intoTexture:tex];
            }
            [self.replacedIDs addObject:iid];
        }
    }
}

#pragma mark - тексты

static NSArray<NSValue *> *allTextObjects(void) {
    NSMutableArray *all = [NSMutableArray new];
    if (FIL_Class("TMPro", "TMP_Text")) [all addObjectsFromArray:FIL_FindAll("TMPro", "TMP_Text")];
    else {
        [all addObjectsFromArray:FIL_FindAll("TMPro", "TextMeshProUGUI")];
        [all addObjectsFromArray:FIL_FindAll("TMPro", "TextMeshPro")];
    }
    [all addObjectsFromArray:FIL_FindAll("UnityEngine.UI", "Text")];
    return all;
}

- (NSArray<FlideItem *> *)scanTexts {
    if (!FIL_Ready()) return @[];
    [self unpinAll];
    NSMutableArray *out = [NSMutableArray new];
    for (NSValue *v in allTextObjects()) {
        void *o = v.pointerValue;
        if (!FIL_ActiveInHierarchy(o)) continue;
        NSString *txt = FIL_ToNSString(FIL_Call0(o, "get_text"));
        if (!txt.length) continue;
        FlideItem *it = [FlideItem new];
        it.name = FIL_Path(o);
        it.detail = txt;
        it.handle = FIL_Pin(o);
        [self.pinned addObject:@(it.handle)];
        [out addObject:it];
    }
    return out;
}

- (void)setOverride:(NSString *)text forPath:(NSString *)path {
    NSMutableDictionary *d = [[FDefaults() dictionaryForKey:kTexts] mutableCopy] ?: [NSMutableDictionary new];
    if (text.length) d[path] = text; else [d removeObjectForKey:path];
    [FDefaults() setObject:d forKey:kTexts];
    for (NSNumber *h in self.textTargets[path]) FIL_Unpin(h.unsignedIntValue);
    [self.textTargets removeObjectForKey:path];
    self.lastTextScan = 0;
}

- (void)refreshTargets:(NSMutableDictionary *)targets forPaths:(NSArray *)paths objects:(NSArray<NSValue *> *)objs {
    for (NSArray *hs in targets.allValues) for (NSNumber *h in hs) FIL_Unpin(h.unsignedIntValue);
    [targets removeAllObjects];
    NSSet *want = [NSSet setWithArray:paths];
    for (NSValue *v in objs) {
        void *o = v.pointerValue;
        NSString *p = FIL_Path(o);
        if (![want containsObject:p]) continue;
        NSMutableArray *hs = [targets[p] mutableCopy] ?: [NSMutableArray new];
        [hs addObject:@(FIL_Pin(o))];
        targets[p] = hs;
    }
}

- (void)textTick {
    NSDictionary *rules = [FDefaults() dictionaryForKey:kTexts];
    if (!rules.count || !FIL_Ready()) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastTextScan > 2.5) {
        self.lastTextScan = now;
        [self refreshTargets:self.textTargets forPaths:rules.allKeys objects:allTextObjects()];
    }
    [rules enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSString *text, BOOL *stop) {
        for (NSNumber *h in self.textTargets[path]) {
            void *o = FIL_Target(h.unsignedIntValue);
            if (!o) continue;
            NSString *cur = FIL_ToNSString(FIL_Call0(o, "get_text"));
            if (cur && ![cur isEqualToString:text]) FIL_Call1(o, "set_text", FIL_NewString(text));
        }
    }];
}

#pragma mark - элементы для эффектов

- (NSArray<FlideItem *> *)scanElements {
    if (!FIL_Ready()) return @[];
    [self unpinAll];
    NSMutableArray *out = [NSMutableArray new];
    NSMutableSet *seen = [NSMutableSet new];
    for (NSValue *v in FIL_FindAll("UnityEngine.UI", "Graphic")) {
        void *o = v.pointerValue;
        if (!FIL_ActiveInHierarchy(o)) continue;
        NSString *p = FIL_Path(o);
        if ([seen containsObject:p]) continue;
        [seen addObject:p];
        FlideItem *it = [FlideItem new];
        it.name = p;
        it.detail = @(FIL_ClassName(FIL_ClassOf(o)));
        [out addObject:it];
    }
    [out sortUsingComparator:^NSComparisonResult(FlideItem *a, FlideItem *b) { return [a.name compare:b.name]; }];
    return out;
}

- (BOOL)screenPointForPath:(NSString *)path point:(CGPoint *)pt {
    if (!FIL_Ready()) return NO;
    for (int attempt = 0; attempt < 2; attempt++) {
        for (NSNumber *h in self.elementTargets[path]) {
            void *o = FIL_Target(h.unsignedIntValue);
            if (o && FIL_ActiveInHierarchy(o) && FIL_ScreenPoint(o, pt)) return YES;
        }
        // не нашли — сцена могла смениться; пересканируем не чаще раза в 5 сек
        CFTimeInterval now = CACurrentMediaTime();
        if (now - self.lastElementScan < 5.0) break;
        self.lastElementScan = now;
        NSArray *paths = [[FDefaults() dictionaryForKey:kAuras] allKeys] ?: @[];
        [self refreshTargets:self.elementTargets forPaths:paths objects:FIL_FindAll("UnityEngine.UI", "Graphic")];
    }
    return NO;
}

@end
