// FLIDE · свои звуки. Играются поверх игры только у тебя на устройстве.
// Звуки по умолчанию синтезируются кодом (без чужих сэмплов), можно подставить свой файл.
// Громкость самой игры: масштабируем UnityEngine.AudioSource.volume — только если эти
// методы есть в бинарнике; иначе функция отключена (проверка через FIL_Method).
#import "FlideCore.h"
#import <AVFoundation/AVFoundation.h>

typedef struct { double f0, f1, dur, vol, noise; } Note;

static NSData *makeWav(const Note *notes, int n) {
    const int sr = 44100;
    NSMutableData *pcm = [NSMutableData new];
    for (int i = 0; i < n; i++) {
        Note nt = notes[i];
        int frames = (int)(nt.dur * sr);
        double phase = 0;
        for (int k = 0; k < frames; k++) {
            double t = (double)k / frames;
            phase += 2 * M_PI * (nt.f0 + (nt.f1 - nt.f0) * t) / sr;
            double env = fmin(1.0, k / (0.005 * sr)) * exp(-3.5 * t);
            double s = sin(phase) + 0.3 * sin(2 * phase) + 0.1 * sin(3 * phase);
            if (nt.noise > 0) s = (1 - nt.noise) * s + nt.noise * ((arc4random() / (double)UINT32_MAX) * 2 - 1);
            double v = s * env * nt.vol * 0.5 * 32767;
            int16_t sample = (int16_t)fmax(-32767, fmin(32767, v));
            [pcm appendBytes:&sample length:2];
        }
    }
    uint32_t dataLen = (uint32_t)pcm.length, riff = 36 + dataLen, fmtLen = 16, rate = sr, byteRate = sr * 2;
    uint16_t fmt = 1, ch = 1, align = 2, bits = 16;
    NSMutableData *w = [NSMutableData new];
    [w appendBytes:"RIFF" length:4]; [w appendBytes:&riff length:4]; [w appendBytes:"WAVEfmt " length:8];
    [w appendBytes:&fmtLen length:4]; [w appendBytes:&fmt length:2]; [w appendBytes:&ch length:2];
    [w appendBytes:&rate length:4]; [w appendBytes:&byteRate length:4]; [w appendBytes:&align length:2]; [w appendBytes:&bits length:2];
    [w appendBytes:"data" length:4]; [w appendBytes:&dataLen length:4]; [w appendData:pcm];
    return w;
}

static NSData *defaultSound(NSString *event) {
    static NSMutableDictionary<NSString *, NSData *> *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSData *d = cache[event];
    if (d) return d;
    if ([event isEqualToString:@"throw"]) { Note n[] = {{500, 150, 0.12, 0.8, 0.7}}; d = makeWav(n, 1); }
    else if ([event isEqualToString:@"combo"]) { Note n[] = {{523, 523, .09, .8, 0}, {659, 659, .09, .8, 0}, {784, 784, .09, .8, 0}, {1047, 1047, .22, .8, 0}}; d = makeWav(n, 4); }
    else if ([event isEqualToString:@"uno"]) { Note n[] = {{784, 784, .10, .9, 0}, {1047, 1047, .32, .9, 0}}; d = makeWav(n, 2); }
    else if ([event isEqualToString:@"victory"]) { Note n[] = {{523, 523, .12, .8, 0}, {659, 659, .12, .8, 0}, {784, 784, .12, .8, 0}, {1047, 1047, .5, .8, 0}}; d = makeWav(n, 4); }
    else if ([event isEqualToString:@"emote"]) { Note n[] = {{500, 900, .09, .7, 0}}; d = makeWav(n, 1); }
    else if ([event isEqualToString:@"gift"]) { Note n[] = {{1568, 1568, .07, .7, 0}, {1319, 1319, .07, .7, 0}, {1047, 1047, .07, .7, 0}, {1760, 1760, .2, .7, 0}}; d = makeWav(n, 4); }
    else { Note n[] = {{1400, 1400, .03, .5, 0}}; d = makeWav(n, 1); }
    cache[event] = d;
    return d;
}

@interface FlideSound () <AVAudioPlayerDelegate>
@property (nonatomic, strong) NSMutableArray<AVAudioPlayer *> *active;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *origVol, *lastSet;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *unoHandles;
@property (nonatomic, assign) CFTimeInterval unoScanAt;
@end

@implementation FlideSound

+ (instancetype)shared {
    static FlideSound *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FlideSound new]; });
    return s;
}

- (void)start {
    self.active = [NSMutableArray new];
    self.origVol = [NSMutableDictionary new];
    self.lastSet = [NSMutableDictionary new];
    self.unoHandles = [NSMutableArray new];
    [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) { [self applyGameVolume]; }];
}

- (NSArray<NSDictionary *> *)events {
    return @[@{@"id": @"throw",   @"title": L(@"Бросок карты"),       @"sub": L(@"Свайп карты на стол")},
             @{@"id": @"combo",   @"title": L(@"Комбо"),              @"sub": L(@"3+ карты подряд")},
             @{@"id": @"uno",     @"title": L(@"Кнопка UNO"),         @"sub": L(@"Нажатие на кнопку UNO")},
             @{@"id": @"victory", @"title": L(@"Победа"),             @"sub": L(@"Экран результатов раунда")},
             @{@"id": @"emote",   @"title": L(@"Эмоция"),             @"sub": L(@"Быстрая панель эмоций FLIDE")},
             @{@"id": @"gift",    @"title": L(@"Подарок"),            @"sub": L(@"Бросок подарка FLIDE")},
             @{@"id": @"menu",    @"title": L(@"Открытие окна FLIDE"), @"sub": L(@"Щелчок при открытии окна")}];
}

#pragma mark - настройки события

// режим: 0 выключен, 1 стандартный звук FLIDE, 2 свой файл
- (NSInteger)modeFor:(NSString *)event {
    NSDictionary *m = [FDefaults() dictionaryForKey:kSndMap][event];
    if (m[@"mode"]) return [m[@"mode"] integerValue];
    // у броска и кнопки UNO в игре уже есть свои звуки — по умолчанию не дублируем
    return ([event isEqualToString:@"throw"] || [event isEqualToString:@"uno"] || [event isEqualToString:@"menu"]) ? 0 : 1;
}

- (void)setMode:(NSInteger)mode forEvent:(NSString *)event {
    NSMutableDictionary *all = [[FDefaults() dictionaryForKey:kSndMap] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *m = [all[event] mutableCopy] ?: [NSMutableDictionary new];
    m[@"mode"] = @(mode);
    all[event] = m;
    [FDefaults() setObject:all forKey:kSndMap];
}

- (NSString *)customPathFor:(NSString *)event {
    NSString *dir = FlideDir(@"sounds");
    for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil])
        if ([f.stringByDeletingPathExtension isEqualToString:event]) return [dir stringByAppendingPathComponent:f];
    return nil;
}

- (NSString *)sourceNameFor:(NSString *)event {
    switch ([self modeFor:event]) {
        case 0: return L(@"Выключен");
        case 2: { NSString *p = [self customPathFor:event]; return p ? [NSString stringWithFormat:L(@"Свой файл: %@"), p.lastPathComponent] : L(@"Выключен"); }
        default: return L(@"Стандартный FLIDE");
    }
}

- (BOOL)setCustomFile:(NSURL *)url forEvent:(NSString *)event {
    if (!url) return NO;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *old;
    while ((old = [self customPathFor:event])) [NSFileManager.defaultManager removeItemAtPath:old error:nil];
    NSString *dst = [[FlideDir(@"sounds") stringByAppendingPathComponent:event] stringByAppendingPathExtension:url.pathExtension.lowercaseString ?: @"m4a"];
    BOOL ok = [NSFileManager.defaultManager copyItemAtPath:url.path toPath:dst error:nil];
    if (scoped) [url stopAccessingSecurityScopedResource];
    // файл, который AVAudioPlayer не открывает, не принимаем
    if (ok && ![[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:dst] error:nil]) {
        [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
        return NO;
    }
    if (ok) [self setMode:2 forEvent:event];
    return ok;
}

#pragma mark - воспроизведение

- (void)startPlayer:(AVAudioPlayer *)p {
    if (!p) return;
    float vol = [FDefaults() objectForKey:kSndVol] ? [FDefaults() floatForKey:kSndVol] : 0.8f;
    p.volume = vol;
    p.delegate = self;
    [p prepareToPlay];
    if (self.active.count > 10) { [self.active.firstObject stop]; [self.active removeObjectAtIndex:0]; }
    [self.active addObject:p];
    [p play];
}

- (void)playMode:(NSInteger)mode event:(NSString *)event {
    AVAudioPlayer *p = nil;
    if (mode == 2) {
        NSString *path = [self customPathFor:event];
        if (path) p = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
    }
    if (!p && mode >= 1) p = [[AVAudioPlayer alloc] initWithData:defaultSound(event) error:nil];
    [self startPlayer:p];
}

- (void)play:(NSString *)event {
    if (!FBool(kSndOn)) return;
    NSInteger mode = [self modeFor:event];
    if (mode == 0) return;
    [self playMode:mode event:event];
}

- (void)preview:(NSString *)event {
    NSInteger mode = [self modeFor:event];
    [self playMode:mode == 0 ? 1 : mode event:event];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag { [self.active removeObject:player]; }

#pragma mark - кнопка UNO

- (void)tapAt:(CGPoint)p {
    if (!FBool(kSndOn) || [self modeFor:@"uno"] == 0 || !FIL_Ready()) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (!self.unoHandles.count && now - self.unoScanAt > 6) {
        self.unoScanAt = now;
        for (NSValue *v in FIL_FindAll("UnityEngine.UI", "Graphic"))
            if ([FIL_Path(v.pointerValue) containsString:@"/btnUNONew"]) [self.unoHandles addObject:@(FIL_Pin(v.pointerValue))];
    }
    for (NSNumber *h in self.unoHandles) {
        void *o = FIL_Target(h.unsignedIntValue);
        if (o && FIL_ActiveInHierarchy(o) && FIL_ContainsUIPoint(o, p)) { [self play:@"uno"]; return; }
    }
    if (self.unoHandles.count && now - self.unoScanAt > 20) { // сцена могла смениться
        for (NSNumber *h in self.unoHandles) FIL_Unpin(h.unsignedIntValue);
        [self.unoHandles removeAllObjects];
    }
}

#pragma mark - громкость игры

- (BOOL)gameVolumeSupported {
    if (!FIL_Ready()) return NO;
    Il2CppClass *k = FIL_Class("UnityEngine", "AudioSource");
    return k && FIL_Method(k, "set_volume", 1) && FIL_Method(k, "get_volume", 0);
}

- (void)applyGameVolume {
    float scale = [FDefaults() objectForKey:kGameVol] ? [FDefaults() floatForKey:kGameVol] : 1.0f;
    BOOL neutral = scale >= 0.999f;
    if (neutral && !self.origVol.count) return;          // ничего не трогали — ничего не делаем
    if (![self gameVolumeSupported]) return;
    NSArray<NSValue *> *all = FIL_FindAll("UnityEngine", "AudioSource");
    NSUInteger n = 0;
    for (NSValue *v in all) {
        if (n++ > 300) break;
        void *src = v.pointerValue;
        float *cp = FIL_Unbox(FIL_Call0(src, "get_volume"));
        if (!cp) continue;
        float cur = *cp;
        NSNumber *orig = self.origVol[v];
        if (neutral) {
            if (orig) { float o = orig.floatValue; FIL_Call1(src, "set_volume", &o); }
            continue;
        }
        NSNumber *last = self.lastSet[v];
        if (!orig || (last && fabsf(cur - last.floatValue) > 0.02f)) orig = @(cur); // игра сама поменяла громкость — берём её значение
        self.origVol[v] = orig;
        float target = orig.floatValue * scale;
        self.lastSet[v] = @(target);
        if (fabsf(cur - target) > 0.001f) FIL_Call1(src, "set_volume", &target);
    }
    if (neutral) { [self.origVol removeAllObjects]; [self.lastSet removeAllObjects]; }
}

@end
