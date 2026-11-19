// FLIDE · паки текстур, пресеты тем, темы в одно нажатие, анимированный стол.
//
// Пак — папка Documents/FLIDE/packs/<имя>/ с PNG. Имя файла = имя текстуры.
// Туда же кладётся HD-пак после апскейла в GitHub Actions.
#import "FlideCore.h"

static NSString *const kPackKeys = @"flide.pack.keys";

@interface FlidePacks ()
@property (nonatomic, assign) BOOL themeRunning;
@property (nonatomic, strong) NSMutableArray<FlideItem *> *themeQueue;
@property (nonatomic, assign) NSUInteger themeTotal;
@property (nonatomic, assign) NSInteger themeFilter;
@property (nonatomic, copy) void (^themeProgress)(NSUInteger, NSUInteger);
// анимация
@property (nonatomic, strong) NSTimer *animTimer;
@property (nonatomic, strong) NSArray<NSString *> *animFrames;
@property (nonatomic, assign) NSUInteger animIndex;
@property (nonatomic, assign) uint32_t animHandle;
@property (nonatomic, assign) CFTimeInterval animLastSearch;
@end

@implementation FlidePacks

+ (instancetype)shared {
    static FlidePacks *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlidePacks new]; });
    return s;
}

- (void)start {
    NSDictionary *a = [FDefaults() dictionaryForKey:kTableAnim];
    if (a[@"texture"]) [self runAnimationFor:a[@"texture"] fps:[a[@"fps"] doubleValue]];
}

#pragma mark - паки

- (NSArray<NSString *> *)packs {
    NSArray *all = [NSFileManager.defaultManager contentsOfDirectoryAtPath:FlideDir(@"packs") error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *n in all) {
        BOOL dir = NO;
        [NSFileManager.defaultManager fileExistsAtPath:[FlideDir(@"packs") stringByAppendingPathComponent:n] isDirectory:&dir];
        if (dir && ![n hasPrefix:@"."]) [out addObject:n];
    }
    return [out sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSArray<NSString *> *pngsIn(NSString *dir) {
    NSMutableArray *out = [NSMutableArray new];
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtPath:dir];
    for (NSString *rel in e)
        if ([rel.pathExtension.lowercaseString isEqualToString:@"png"]) [out addObject:[dir stringByAppendingPathComponent:rel]];
    return out;
}

- (NSUInteger)activatePack:(NSString *)name {
    [self deactivatePack];
    NSString *dir = [FlideDir(@"packs") stringByAppendingPathComponent:name];
    NSMutableDictionary *idx = [[FDefaults() dictionaryForKey:kTextures] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableArray *keys = [NSMutableArray new];
    NSString *texDir = FlideDir(@"textures");
    for (NSString *src in pngsIn(dir)) {
        NSString *stem = src.lastPathComponent.stringByDeletingPathExtension;
        stem = [stem stringByReplacingOccurrencesOfString:@"_flide" withString:@""];
        NSString *file = [NSString stringWithFormat:@"pack_%@.png", FlideSafeName(stem)];
        NSString *dst = [texDir stringByAppendingPathComponent:file];
        [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
        if ([NSFileManager.defaultManager copyItemAtPath:src toPath:dst error:nil]) {
            idx[stem] = file;
            [keys addObject:stem];
        }
    }
    // настройки темы, если в паке есть settings.json
    NSData *json = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"settings.json"]];
    NSDictionary *cfg = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if ([cfg isKindOfClass:NSDictionary.class])
        for (NSString *k in @[kTexts, kAuras, kFxColor, kFxStyle, kBootAnim])
            if (cfg[k]) [FDefaults() setObject:cfg[k] forKey:k];

    [FDefaults() setObject:idx forKey:kTextures];
    [FDefaults() setObject:keys forKey:kPackKeys];
    [FDefaults() setObject:name forKey:kPackActive];
    [[FlideEngine shared] reapplyReplacements];
    [[FlideFX shared] reloadRules];
    return keys.count;
}

- (void)deactivatePack {
    NSArray *keys = [FDefaults() arrayForKey:kPackKeys];
    if (!keys.count) { [FDefaults() removeObjectForKey:kPackActive]; return; }
    NSMutableDictionary *idx = [[FDefaults() dictionaryForKey:kTextures] mutableCopy];
    NSSet *keySet = [NSSet setWithArray:keys];
    for (NSString *k in keys) {
        NSString *f = idx[k];
        if (f) [NSFileManager.defaultManager removeItemAtPath:[FlideDir(@"textures") stringByAppendingPathComponent:f] error:nil];
        [idx removeObjectForKey:k];
    }
    [FDefaults() setObject:idx ?: @{} forKey:kTextures];
    [FDefaults() removeObjectForKey:kPackKeys];
    [FDefaults() removeObjectForKey:kPackActive];
    // вернём сохранённые оригиналы сразу
    FlideEngine *E = [FlideEngine shared];
    NSArray *items = [E scanTextures];
    for (FlideItem *it in items)
        if ([keySet containsObject:it.name] || [keySet containsObject:FlideSafeName(it.name)]) [E resetTexture:it];
    [E releaseItems:items];
}

- (NSURL *)savePresetNamed:(NSString *)name {
    NSString *dir = [FlideDir(@"packs") stringByAppendingPathComponent:FlideSafeName(name)];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *idx = [FDefaults() dictionaryForKey:kTextures];
    [idx enumerateKeysAndObjectsUsingBlock:^(NSString *tex, NSString *file, BOOL *stop) {
        NSString *dst = [dir stringByAppendingPathComponent:[FlideSafeName(tex) stringByAppendingPathExtension:@"png"]];
        [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
        [NSFileManager.defaultManager copyItemAtPath:[FlideDir(@"textures") stringByAppendingPathComponent:file] toPath:dst error:nil];
    }];
    NSMutableDictionary *cfg = [NSMutableDictionary new];
    for (NSString *k in @[kTexts, kAuras, kFxColor, kFxStyle, kBootAnim]) {
        id v = [FDefaults() objectForKey:k];
        if (v) cfg[k] = v;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:cfg options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[dir stringByAppendingPathComponent:@"settings.json"] atomically:YES];
    return [NSURL fileURLWithPath:dir];
}

- (NSUInteger)importFromURLs:(NSArray<NSURL *> *)urls asPack:(NSString *)name {
    NSString *dir = [FlideDir(@"packs") stringByAppendingPathComponent:FlideSafeName(name)];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSUInteger n = 0;
    for (NSURL *u in urls) {
        BOOL scoped = [u startAccessingSecurityScopedResource];
        BOOL isDir = NO;
        [NSFileManager.defaultManager fileExistsAtPath:u.path isDirectory:&isDir];
        NSArray *files = isDir ? pngsIn(u.path) : @[u.path];
        if (isDir) {
            NSString *json = [u.path stringByAppendingPathComponent:@"settings.json"];
            if ([NSFileManager.defaultManager fileExistsAtPath:json])
                [NSFileManager.defaultManager copyItemAtPath:json toPath:[dir stringByAppendingPathComponent:@"settings.json"] error:nil];
        }
        for (NSString *f in files) {
            if (![f.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
            NSString *dst = [dir stringByAppendingPathComponent:f.lastPathComponent];
            [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
            if ([NSFileManager.defaultManager copyItemAtPath:f toPath:dst error:nil]) n++;
        }
        if (scoped) [u stopAccessingSecurityScopedResource];
    }
    return n;
}

- (NSURL *)zipFolder:(NSString *)path {
    __block NSURL *result = nil;
    NSError *err = nil;
    NSFileCoordinator *fc = [NSFileCoordinator new];
    [fc coordinateReadingItemAtURL:[NSURL fileURLWithPath:path] options:NSFileCoordinatorReadingForUploading error:&err
                        byAccessor:^(NSURL *zipURL) {
        NSURL *dst = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:
                      [path.lastPathComponent stringByAppendingPathExtension:@"zip"]];
        [NSFileManager.defaultManager removeItemAtURL:dst error:nil];
        if ([NSFileManager.defaultManager copyItemAtURL:zipURL toURL:dst error:nil]) result = dst;
    }];
    return result;
}

#pragma mark - темы

static BOOL skipForTheme(FlideItem *it) {
    NSString *n = it.name.lowercaseString;
    // шрифтовые атласы (TextMeshPro SDF) фильтровать нельзя — сломается текст
    return [n containsString:@"sdf"] || [n containsString:@"font"];
}

- (void)applyTheme:(NSInteger)filter progress:(void (^)(NSUInteger, NSUInteger))progress {
    [self cancelTheme];
    NSMutableArray *q = [NSMutableArray new];
    for (FlideItem *it in [[FlideEngine shared] scanTextures]) {
        if (skipForTheme(it)) { [[FlideEngine shared] releaseItems:@[it]]; continue; }
        [q addObject:it];
    }
    self.themeQueue = q;
    self.themeTotal = q.count;
    self.themeFilter = filter;
    self.themeProgress = progress;
    self.themeRunning = YES;
    [self themeStep];
}

- (void)themeStep {
    if (!self.themeRunning) return;
    FlideItem *it = self.themeQueue.firstObject;
    if (!it) {
        self.themeRunning = NO;
        if (self.themeProgress) self.themeProgress(self.themeTotal, self.themeTotal);
        return;
    }
    [self.themeQueue removeObjectAtIndex:0];
    FlideEngine *E = [FlideEngine shared];
    @autoreleasepool {
        if (self.themeFilter == 0) [E resetTexture:it];
        else {
            UIImage *orig = [E originalOfTexture:it] ?: [E imageOfTexture:it maxSide:4096];
            if (orig) [E replaceTexture:it withImage:FlideFilterImage(orig, self.themeFilter, 0, 1)];
        }
    }
    [E releaseItems:@[it]];
    if (self.themeProgress) self.themeProgress(self.themeTotal - self.themeQueue.count, self.themeTotal);
    // по одной текстуре за тик — игра не замирает
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self themeStep]; });
}

- (void)cancelTheme {
    self.themeRunning = NO;
    [[FlideEngine shared] releaseItems:self.themeQueue];
    [self.themeQueue removeAllObjects];
}

#pragma mark - анимированная текстура

- (NSString *)animDir:(NSString *)texture {
    return [FlideDir(@"anim") stringByAppendingPathComponent:FlideSafeName(texture)];
}

- (BOOL)setAnimationForTexture:(NSString *)textureName frames:(NSArray<UIImage *> *)frames fps:(double)fps size:(CGSize)size {
    [self stopAnimation];
    NSString *dir = [self animDir:textureName];
    [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1; f.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:f];
    NSUInteger i = 0;
    for (UIImage *img in frames) @autoreleasepool {
        NSData *png = [r PNGDataWithActions:^(UIGraphicsImageRendererContext *c) {
            [img drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
        [png writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%03lu.png", (unsigned long)i++]] atomically:YES];
    }
    // обычная замена этой текстуры больше не нужна
    NSMutableDictionary *idx = [[FDefaults() dictionaryForKey:kTextures] mutableCopy];
    [idx removeObjectForKey:textureName];
    [FDefaults() setObject:idx ?: @{} forKey:kTextures];
    [FDefaults() setObject:@{@"texture": textureName, @"fps": @(fps ?: 8)} forKey:kTableAnim];
    [self runAnimationFor:textureName fps:fps ?: 8];
    return i > 1;
}

- (void)runAnimationFor:(NSString *)texture fps:(double)fps {
    NSString *dir = [self animDir:texture];
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *paths = [NSMutableArray new];
    for (NSString *f in files) if ([f hasSuffix:@".png"]) [paths addObject:[dir stringByAppendingPathComponent:f]];
    if (paths.count < 2) return;
    self.animFrames = paths;
    self.animIndex = 0;
    __weak typeof(self) ws = self;
    self.animTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / MAX(1, MIN(15, fps)) repeats:YES block:^(NSTimer *t) {
        [ws animTick:texture];
    }];
}

- (void *)findTexture:(NSString *)name {
    void *t = FIL_Target(self.animHandle);
    if (t && FIL_Int(FIL_Call0(t, "get_width")) > 0) return t;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.animLastSearch < 3) return NULL;
    self.animLastSearch = now;
    FIL_Unpin(self.animHandle);
    self.animHandle = 0;
    for (NSValue *v in FIL_FindAll("UnityEngine", "Texture2D")) {
        NSString *n = FIL_Name(v.pointerValue);
        if ([n isEqualToString:name] || [FlideSafeName(n) isEqualToString:name]) {
            self.animHandle = FIL_Pin(v.pointerValue);
            return v.pointerValue;
        }
    }
    return NULL;
}

- (void)animTick:(NSString *)texture {
    if (!FIL_Ready() || !self.animFrames.count) return;
    void *tex = [self findTexture:texture];
    if (!tex) return;
    NSData *png = [NSData dataWithContentsOfFile:self.animFrames[self.animIndex % self.animFrames.count]];
    self.animIndex++;
    if (png) [[FlideEngine shared] loadPNG:png intoTexture:tex];
}

- (void)stopAnimation {
    [self.animTimer invalidate];
    self.animTimer = nil;
    self.animFrames = nil;
    FIL_Unpin(self.animHandle);
    self.animHandle = 0;
    [FDefaults() removeObjectForKey:kTableAnim];
}

- (NSString *)animatedTexture { return [FDefaults() dictionaryForKey:kTableAnim][@"texture"]; }

@end
