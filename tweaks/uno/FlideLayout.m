// FLIDE · редактор интерфейса игры и пресеты раскладки.
// Двигаем, масштабируем, крутим, прячем любые элементы UI игры — только у тебя на экране.
// Правило: путь элемента → {dx, dy, s, r, a, hide, anim}. Путь, начинающийся с «*/»,
// совпадает по концу (так пресеты работают с настоящими именами из GameDeckWnd).
#import "FlideCore.h"

static NSString *const kLayout = @"flide.layout";           // path -> rule
static NSString *const kLayoutPreset = @"flide.layout.preset";

@interface FlideLayout ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *targets; // path -> handles
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSArray<NSNumber *> *> *base;     // объект -> исходные (x, y, sx, sy, rz)
@property (nonatomic, assign) CFTimeInterval lastScan;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL animating;
@end

@implementation FlideLayout

+ (instancetype)shared {
    static FlideLayout *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideLayout new]; });
    return s;
}

- (void)start {
    self.targets = [NSMutableDictionary new];
    self.base = [NSMutableDictionary new];
    [self reschedule];
}

- (NSDictionary *)rules { return [FDefaults() dictionaryForKey:kLayout] ?: @{}; }

- (void)reschedule {
    [self.timer invalidate];
    NSDictionary *r = [self rules];
    if (!r.count) { self.timer = nil; return; }
    BOOL anim = NO;
    for (NSDictionary *x in r.allValues) if ([x[@"anim"] integerValue]) anim = YES;
    self.animating = anim;
    // с анимациями — 20 раз в секунду, без них — раз в секунду (игра могла сбросить позицию)
    __weak typeof(self) ws = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:anim ? 0.05 : 1.0 repeats:YES block:^(NSTimer *t) { [ws tick]; }];
    self.lastScan = 0;
}

static BOOL pathMatches(NSString *rule, NSString *path) {
    if ([rule hasPrefix:@"*/"]) {
        NSString *tail = [rule substringFromIndex:2];
        return [path isEqualToString:tail] || [path hasSuffix:[@"/" stringByAppendingString:tail]];
    }
    return [path isEqualToString:rule];
}

- (void)rescan {
    for (NSArray *hs in self.targets.allValues) for (NSNumber *h in hs) FIL_Unpin(h.unsignedIntValue);
    [self.targets removeAllObjects];
    NSArray *keys = [self rules].allKeys;
    if (!keys.count) return;
    for (NSValue *v in FIL_FindAll("UnityEngine", "RectTransform")) {
        NSString *p = FIL_Path(v.pointerValue);
        for (NSString *k in keys) {
            if (!pathMatches(k, p)) continue;
            NSMutableArray *hs = [self.targets[k] mutableCopy] ?: [NSMutableArray new];
            [hs addObject:@(FIL_Pin(v.pointerValue))];
            self.targets[k] = hs;
        }
    }
}

- (NSArray<NSNumber *> *)baseOf:(void *)t {
    NSValue *key = [NSValue valueWithPointer:t];
    NSArray *b = self.base[key];
    if (b) return b;
    FVec2 *pos = FIL_Unbox(FIL_Call0(t, "get_anchoredPosition"));
    FVec3 *sc = FIL_Unbox(FIL_Call0(t, "get_localScale"));
    FVec3 *rot = FIL_Unbox(FIL_Call0(t, "get_localEulerAngles"));
    if (!pos || !sc || !rot) return nil;
    b = @[@(pos->x), @(pos->y), @(sc->x), @(sc->y), @(rot->z)];
    self.base[key] = b;
    return b;
}

- (void)apply:(NSDictionary *)rule to:(void *)t phase:(double)ph {
    NSArray *b = [self baseOf:t];
    if (!b) return;
    double dx = [rule[@"dx"] doubleValue], dy = [rule[@"dy"] doubleValue];
    double s = rule[@"s"] ? [rule[@"s"] doubleValue] : 1, r = [rule[@"r"] doubleValue];
    double sx = rule[@"sx"] ? [rule[@"sx"] doubleValue] : 1;
    if ([rule[@"hide"] boolValue]) s = 0.0001;
    switch ([rule[@"anim"] integerValue]) {
        case 1: s *= 1 + 0.06 * sin(ph * 3); break;                 // пульс
        case 2: dy += 6 * sin(ph * 2.2); break;                     // покачивание
        case 3: r += 6 * sin(ph * 1.6); break;                      // маятник
        case 4: r += fmod(ph * 40, 360); break;                     // вращение
        case 5: dx += 3 * sin(ph * 25); break;                      // дрожь
        default: break;
    }
    FVec2 pos = { (float)([b[0] doubleValue] + dx), (float)([b[1] doubleValue] + dy) };
    FVec3 sc = { (float)([b[2] doubleValue] * s * sx), (float)([b[3] doubleValue] * s), 1 };
    FVec3 rot = { 0, 0, (float)([b[4] doubleValue] + r) };
    FIL_Call1(t, "set_anchoredPosition", &pos);
    FIL_Call1(t, "set_localScale", &sc);
    FIL_Call1(t, "set_localEulerAngles", &rot);
}

- (void)tick {
    if (!FIL_Ready()) return;
    NSDictionary *rules = [self rules];
    if (!rules.count) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastScan > 10) { self.lastScan = now; [self rescan]; }
    [rules enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSDictionary *rule, BOOL *stop) {
        NSUInteger i = 0;
        for (NSNumber *h in self.targets[k]) {
            void *t = FIL_Target(h.unsignedIntValue);
            if (t) [self apply:rule to:t phase:now + i++ * 0.7];
        }
    }];
}

#pragma mark - правила

- (NSDictionary *)ruleFor:(NSString *)path { return [self rules][path] ?: @{}; }

- (void)setRule:(NSDictionary *)rule forPath:(NSString *)path {
    NSMutableDictionary *d = [[self rules] mutableCopy];
    if (rule.count) d[path] = rule; else {
        [self restorePath:path];
        [d removeObjectForKey:path];
    }
    [FDefaults() setObject:d forKey:kLayout];
    if (rule.count) { // мгновенно, не дожидаясь тика
        if (!self.targets[path]) self.lastScan = 0;
        [self reschedule];
        [self tick];
    } else [self reschedule];
}

- (void)restorePath:(NSString *)path {
    for (NSNumber *h in self.targets[path]) {
        void *t = FIL_Target(h.unsignedIntValue);
        NSArray *b = t ? self.base[[NSValue valueWithPointer:t]] : nil;
        if (!b) continue;
        FVec2 pos = { [b[0] floatValue], [b[1] floatValue] };
        FVec3 sc = { [b[2] floatValue], [b[3] floatValue], 1 };
        FVec3 rot = { 0, 0, [b[4] floatValue] };
        FIL_Call1(t, "set_anchoredPosition", &pos);
        FIL_Call1(t, "set_localScale", &sc);
        FIL_Call1(t, "set_localEulerAngles", &rot);
    }
}

- (void)resetAll {
    for (NSString *k in [self rules].allKeys) [self restorePath:k];
    [FDefaults() removeObjectForKey:kLayout];
    [FDefaults() removeObjectForKey:kLayoutPreset];
    [self reschedule];
}

#pragma mark - пресеты (настоящие имена элементов игрового стола)

- (NSArray<NSDictionary *> *)presets {
    return @[
      @{@"id": @"cinema", @"title": L(@"🎬 Кино"), @"desc": L(@"Убирает всё лишнее: рейтинг, кнопки, пинг, звёзды — только стол и игроки"),
        @"rules": @{@"*/BtnRank": @{@"hide": @YES}, @"*/btnQuestion": @{@"hide": @YES}, @"*/RoundNum": @{@"hide": @YES},
                    @"*/Text_Ping": @{@"hide": @YES}, @"*/SeasonTierBar": @{@"hide": @YES}, @"*/StarGroup": @{@"hide": @YES},
                    @"*/OtherIcons": @{@"hide": @YES}, @"*/BtnSaveReplay": @{@"hide": @YES}, @"*/BtnReport": @{@"hide": @YES},
                    @"*/Network": @{@"hide": @YES}, @"*/FlowerGroup": @{@"hide": @YES}}},
      @{@"id": @"big", @"title": L(@"🔍 Крупный стол"), @"desc": L(@"Аватары, колода и кнопка UNO крупнее — удобно на маленьком экране"),
        @"rules": @{@"*/PlayerInfoNode/HeadTemplate_1": @{@"s": @1.25}, @"*/PlayerInfoNode/HeadTemplate_2": @{@"s": @1.25},
                    @"*/PlayerInfoNode/HeadTemplate_3": @{@"s": @1.25}, @"*/PlayerInfoNode/HeadTemplate_4": @{@"s": @1.25},
                    @"*/btnUNONew": @{@"s": @1.35}, @"*/CardPile": @{@"s": @1.2}, @"*/timeRemainPart": @{@"s": @1.2}}},
      @{@"id": @"alive", @"title": L(@"✨ Живой стол"), @"desc": L(@"Аватары покачиваются, кнопка UNO пульсирует, таймер дышит"),
        @"rules": @{@"*/PlayerInfoNode/HeadTemplate_1": @{@"anim": @2}, @"*/PlayerInfoNode/HeadTemplate_2": @{@"anim": @2},
                    @"*/PlayerInfoNode/HeadTemplate_3": @{@"anim": @2}, @"*/PlayerInfoNode/HeadTemplate_4": @{@"anim": @2},
                    @"*/btnUNONew": @{@"anim": @1}, @"*/timeRemainPart": @{@"anim": @1}, @"*/CardPile": @{@"anim": @3}}},
      @{@"id": @"mirror", @"title": L(@"🪞 Зеркало"), @"desc": L(@"Весь интерфейс стола отражён слева направо"),
        @"rules": @{@"*/GameDeckWnd/ContentPanel": @{@"sx": @-1}}},
      @{@"id": @"chaos", @"title": L(@"🌀 Хаос"), @"desc": L(@"Всё слегка наклонено и разного размера — безумный стол"),
        @"rules": @{@"*/PlayerInfoNode/HeadTemplate_1": @{@"r": @-8, @"s": @1.1}, @"*/PlayerInfoNode/HeadTemplate_2": @{@"r": @10, @"s": @0.9},
                    @"*/PlayerInfoNode/HeadTemplate_3": @{@"r": @-12, @"s": @1.15}, @"*/PlayerInfoNode/HeadTemplate_4": @{@"r": @7, @"s": @0.95},
                    @"*/btnUNONew": @{@"anim": @3, @"s": @1.2}, @"*/CardPile": @{@"anim": @4}, @"*/timeRemainPart": @{@"anim": @5}}},
      @{@"id": @"compact", @"title": L(@"📱 Компакт"), @"desc": L(@"Всё мельче — больше места для карт"),
        @"rules": @{@"*/PlayerInfoNode": @{@"s": @0.85}, @"*/btnUNONew": @{@"s": @0.85}, @"*/BtnSetting": @{@"s": @0.8},
                    @"*/btnOpenEmotion": @{@"s": @0.8}, @"*/timeRemainPart": @{@"s": @0.85}, @"*/SeasonTierBar": @{@"s": @0.8}}},
      @{@"id": @"upside", @"title": L(@"🙃 Вверх ногами"), @"desc": L(@"Стол перевёрнут на 180°. Для прикола"),
        @"rules": @{@"*/GameDeckWnd/ContentPanel": @{@"r": @180}}},
    ];
}

- (NSString *)activePreset { return [FDefaults() stringForKey:kLayoutPreset]; }

- (void)applyPreset:(NSString *)pid {
    [self resetAll];
    for (NSDictionary *p in [self presets]) {
        if (![p[@"id"] isEqualToString:pid]) continue;
        [FDefaults() setObject:p[@"rules"] forKey:kLayout];
        [FDefaults() setObject:pid forKey:kLayoutPreset];
    }
    [self reschedule];
    [self tick];
}

// свои пресеты раскладки
- (NSDictionary *)userPresets { return [FDefaults() dictionaryForKey:@"flide.layout.user"] ?: @{}; }
- (void)saveUserPreset:(NSString *)name {
    NSMutableDictionary *d = [[self userPresets] mutableCopy];
    d[name] = [self rules];
    [FDefaults() setObject:d forKey:@"flide.layout.user"];
}
- (void)applyUserPreset:(NSString *)name {
    NSDictionary *r = [self userPresets][name];
    [self resetAll];
    if (r) [FDefaults() setObject:r forKey:kLayout];
    [self reschedule];
    [self tick];
}
- (void)deleteUserPreset:(NSString *)name {
    NSMutableDictionary *d = [[self userPresets] mutableCopy];
    [d removeObjectForKey:name];
    [FDefaults() setObject:d forKey:@"flide.layout.user"];
}

@end
